using System.Diagnostics;
using System.IO.Compression;
using System.Net.Http;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Windows.Forms;

namespace EraOnlineLauncher;

public sealed class MainForm : Form
{
    private readonly Label _titleLabel;
    private readonly Label _statusLabel;
    private readonly ProgressBar _progressBar;
    private readonly Button _launchButton;
    private readonly Button _checkButton;
    private readonly HttpClient _httpClient = new();

    private LauncherConfig? _config;
    private LauncherState? _state;
    private string? _installedExePath;
    private bool _busy;

    public MainForm()
    {
        Text = "Era Online Launcher";
        Width = 520;
        Height = 220;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;

        _titleLabel = new Label
        {
            Left = 20,
            Top = 20,
            Width = 460,
            Height = 32,
            Text = "Era Online",
            Font = new Font("Segoe UI", 18, FontStyle.Bold)
        };

        _statusLabel = new Label
        {
            Left = 20,
            Top = 70,
            Width = 460,
            Height = 40,
            Text = "Starting launcher...",
            Font = new Font("Segoe UI", 10)
        };

        _progressBar = new ProgressBar
        {
            Left = 20,
            Top = 118,
            Width = 460,
            Height = 20,
            Style = ProgressBarStyle.Continuous
        };

        _launchButton = new Button
        {
            Left = 360,
            Top = 150,
            Width = 120,
            Height = 32,
            Text = "Launch",
            Enabled = false
        };
        _launchButton.Click += (_, _) => LaunchInstalledGame();

        _checkButton = new Button
        {
            Left = 220,
            Top = 150,
            Width = 120,
            Height = 32,
            Text = "Check Updates"
        };
        _checkButton.Click += async (_, _) => await CheckForUpdatesAsync();

        Controls.AddRange([_titleLabel, _statusLabel, _progressBar, _checkButton, _launchButton]);
        Shown += async (_, _) => await InitializeAsync();
    }

    private string LauncherRoot => AppContext.BaseDirectory;
    private string StatePath => Path.Combine(LauncherRoot, "state.json");
    private string ConfigPath => Path.Combine(LauncherRoot, "launcher-config.json");

    private async Task InitializeAsync()
    {
        try
        {
            _config = await LoadConfigAsync();
            _state = await LoadStateAsync();
            _installedExePath = FindInstalledExecutable();
            UpdateLaunchButton();
            await CheckForUpdatesAsync();
        }
        catch (Exception ex)
        {
            SetStatus($"Launcher error: {ex.Message}");
        }
    }

    private async Task CheckForUpdatesAsync()
    {
        if (_busy || _config is null)
        {
            return;
        }

        try
        {
            _busy = true;
            UpdateControls();
            SetStatus("Checking for updates...");
            _progressBar.Style = ProgressBarStyle.Marquee;

            var release = await FetchManifestAsync(_config.ManifestUrl);
            if (_state?.InstalledTag == release.Version && File.Exists(FindInstalledExecutable() ?? string.Empty))
            {
                SetStatus($"Up to date: {release.Version}");
                _installedExePath = FindInstalledExecutable();
                UpdateLaunchButton();
                return;
            }

            await DownloadAndInstallReleaseAsync(release);
            SetStatus($"Ready: {release.Version}");
        }
        catch (Exception ex)
        {
            SetStatus($"Update failed: {ex.Message}");
        }
        finally
        {
            _busy = false;
            _progressBar.Style = ProgressBarStyle.Continuous;
            UpdateControls();
        }
    }

    private async Task DownloadAndInstallReleaseAsync(ReleaseManifest release)
    {
        var downloadsDir = Path.Combine(LauncherRoot, "downloads");
        var installedDir = Path.Combine(LauncherRoot, "installed");
        var currentDir = Path.Combine(installedDir, "current");
        var stagingDir = Path.Combine(installedDir, "staging-" + Guid.NewGuid().ToString("N"));
        var zipPath = Path.Combine(downloadsDir, release.AssetName ?? "package.zip");

        Directory.CreateDirectory(downloadsDir);
        Directory.CreateDirectory(installedDir);
        Directory.CreateDirectory(stagingDir);

        if (File.Exists(zipPath))
        {
            File.Delete(zipPath);
        }

        if (release.DownloadParts is { Count: > 0 })
        {
            await DownloadMultipartAsync(release.DownloadParts, zipPath);
        }
        else if (!string.IsNullOrWhiteSpace(release.DownloadUrl))
        {
            await DownloadFileAsync(release.DownloadUrl, zipPath, "Downloading update");
        }
        else
        {
            throw new InvalidOperationException("Manifest does not contain a downloadable package.");
        }

        SetStatus("Extracting update...");
        _progressBar.Style = ProgressBarStyle.Marquee;
        ZipFile.ExtractToDirectory(zipPath, stagingDir, true);

        var exePath = Directory.GetFiles(stagingDir, _config!.ExeName, SearchOption.AllDirectories).FirstOrDefault();
        if (exePath is null)
        {
            throw new FileNotFoundException($"Could not find {_config.ExeName} in the downloaded package.");
        }

        if (Directory.Exists(currentDir))
        {
            Directory.Delete(currentDir, true);
        }

        Directory.Move(stagingDir, currentDir);
        var relativeExe = Path.GetRelativePath(currentDir, Path.Combine(currentDir, Path.GetRelativePath(stagingDir, exePath)));
        _state = new LauncherState
        {
            InstalledTag = release.Version,
            InstalledName = release.Name,
            AssetName = release.AssetName,
            InstalledAt = DateTimeOffset.UtcNow.ToString("O"),
            ExeRelativePath = relativeExe
        };

        await SaveStateAsync(_state);
        _installedExePath = FindInstalledExecutable();
        UpdateLaunchButton();
    }

    private async Task DownloadMultipartAsync(IReadOnlyList<string> parts, string outputPath)
    {
        var tempDir = Path.Combine(Path.GetDirectoryName(outputPath)!, "parts");
        Directory.CreateDirectory(tempDir);
        using var output = File.Create(outputPath);
        var buffer = new byte[1024 * 1024];
        var totalParts = parts.Count;

        for (var i = 0; i < totalParts; i++)
        {
            var partUrl = parts[i];
            SetStatus($"Downloading part {i + 1} of {totalParts}...");
            _progressBar.Style = ProgressBarStyle.Continuous;
            _progressBar.Value = (int)Math.Round(((i + 1d) / totalParts) * 100d);

            using var response = await _httpClient.GetAsync(partUrl, HttpCompletionOption.ResponseHeadersRead);
            response.EnsureSuccessStatusCode();
            await using var stream = await response.Content.ReadAsStreamAsync();

            int read;
            while ((read = await stream.ReadAsync(buffer, 0, buffer.Length)) > 0)
            {
                await output.WriteAsync(buffer, 0, read);
            }
        }

        _progressBar.Value = 100;
    }

    private async Task DownloadFileAsync(string url, string outputPath, string status)
    {
        SetStatus(status + "...");
        _progressBar.Style = ProgressBarStyle.Marquee;
        using var response = await _httpClient.GetAsync(url, HttpCompletionOption.ResponseHeadersRead);
        response.EnsureSuccessStatusCode();
        await using var input = await response.Content.ReadAsStreamAsync();
        await using var output = File.Create(outputPath);
        await input.CopyToAsync(output);
    }

    private void LaunchInstalledGame()
    {
        if (_installedExePath is null || !File.Exists(_installedExePath))
        {
            SetStatus("Game is not installed yet.");
            return;
        }

        var startInfo = new ProcessStartInfo
        {
            FileName = _installedExePath,
            WorkingDirectory = Path.GetDirectoryName(_installedExePath)!
        };

        if (_config?.LaunchArgs is { Length: > 0 })
        {
            foreach (var arg in _config.LaunchArgs)
            {
                startInfo.ArgumentList.Add(arg);
            }
        }

        var process = Process.Start(startInfo);
        if (process is null)
        {
            SetStatus("Failed to launch game.");
            return;
        }

        Close();
    }

    private async Task<LauncherConfig> LoadConfigAsync()
    {
        if (!File.Exists(ConfigPath))
        {
            throw new FileNotFoundException("launcher-config.json is missing.");
        }

        await using var stream = File.OpenRead(ConfigPath);
        var config = await JsonSerializer.DeserializeAsync<LauncherConfig>(stream, JsonOptions())
            ?? throw new InvalidOperationException("Could not read launcher-config.json.");

        if (string.IsNullOrWhiteSpace(config.ManifestUrl))
        {
            throw new InvalidOperationException("manifest_url is missing from launcher-config.json.");
        }

        return config;
    }

    private async Task<LauncherState?> LoadStateAsync()
    {
        if (!File.Exists(StatePath))
        {
            return null;
        }

        await using var stream = File.OpenRead(StatePath);
        return await JsonSerializer.DeserializeAsync<LauncherState>(stream, JsonOptions());
    }

    private async Task SaveStateAsync(LauncherState state)
    {
        await using var stream = File.Create(StatePath);
        await JsonSerializer.SerializeAsync(stream, state, JsonOptions());
    }

    private async Task<ReleaseManifest> FetchManifestAsync(string manifestUrl)
    {
        await using var stream = await _httpClient.GetStreamAsync(manifestUrl);
        var manifest = await JsonSerializer.DeserializeAsync<ReleaseManifest>(stream, JsonOptions())
            ?? throw new InvalidOperationException("Could not read release manifest.");

        if (string.IsNullOrWhiteSpace(manifest.Version))
        {
            throw new InvalidOperationException("Release manifest is missing version.");
        }

        return manifest;
    }

    private string? FindInstalledExecutable()
    {
        var currentDir = Path.Combine(LauncherRoot, "installed", "current");
        if (!Directory.Exists(currentDir) || _config is null)
        {
            return null;
        }

        if (!string.IsNullOrWhiteSpace(_state?.ExeRelativePath))
        {
            var candidate = Path.Combine(currentDir, _state.ExeRelativePath);
            if (File.Exists(candidate))
            {
                return candidate;
            }
        }

        return Directory.GetFiles(currentDir, _config.ExeName, SearchOption.AllDirectories).FirstOrDefault();
    }

    private void SetStatus(string text)
    {
        _statusLabel.Text = text;
    }

    private void UpdateControls()
    {
        _checkButton.Enabled = !_busy;
        _launchButton.Enabled = !_busy && _installedExePath is not null && File.Exists(_installedExePath);
    }

    private void UpdateLaunchButton()
    {
        _launchButton.Enabled = _installedExePath is not null && File.Exists(_installedExePath) && !_busy;
    }

    private static JsonSerializerOptions JsonOptions() => new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
    };

    private sealed class LauncherConfig
    {
        public string ManifestUrl { get; set; } = string.Empty;
        public string ExeName { get; set; } = "EraOnline.exe";
        public string[] LaunchArgs { get; set; } = [];
    }

    private sealed class LauncherState
    {
        public string? InstalledTag { get; set; }
        public string? InstalledName { get; set; }
        public string? AssetName { get; set; }
        public string? InstalledAt { get; set; }
        public string? ExeRelativePath { get; set; }
    }

    private sealed class ReleaseManifest
    {
        public string Version { get; set; } = string.Empty;
        public string? Name { get; set; }
        public string? PublishedAt { get; set; }
        public string? AssetName { get; set; }
        public string? DownloadUrl { get; set; }
        public List<string>? DownloadParts { get; set; }
    }
}
