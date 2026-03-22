// Package config loads and validates the server YAML configuration.
package config

import (
	"fmt"
	"os"
	"time"

	"gopkg.in/yaml.v3"
)

// Config is the top-level server configuration.
type Config struct {
	Server   ServerCfg   `yaml:"server"`
	TLS      TLSCfg      `yaml:"tls"`
	Database DatabaseCfg `yaml:"database"`
	Game     GameCfg     `yaml:"game"`
	Log      LogCfg      `yaml:"log"`
	Admin    AdminCfg    `yaml:"admin"`
}

// ServerCfg holds network listener settings.
type ServerCfg struct {
	// GameAddr is the TCP address for the game binary protocol (TLS).
	GameAddr string `yaml:"game_addr"`
	// HTTPAddr is the TCP address for the plain HTTP management API.
	HTTPAddr string `yaml:"http_addr"`
	// MaxPlayers is the hard cap on simultaneous connections.
	MaxPlayers int `yaml:"max_players"`
	// Secret is the server-wide HMAC secret. Must be ≥32 chars.
	Secret string `yaml:"secret"`
	// ClientIdentitySecret is shared with the official game client binary.
	// The client must prove it holds this secret during the handshake.
	// This blocks non-official clients (bots, injectors) from connecting.
	// Must be ≥16 chars. Change this if you release a new client binary.
	ClientIdentitySecret string `yaml:"client_identity_secret"`
	// ReadTimeout is the maximum time to receive a full packet.
	ReadTimeout time.Duration `yaml:"read_timeout"`
	// WriteTimeout is the maximum time to send data before disconnecting.
	WriteTimeout time.Duration `yaml:"write_timeout"`
	// IdleTimeout disconnects connections with no activity.
	IdleTimeout time.Duration `yaml:"idle_timeout"`
}

// TLSCfg holds TLS certificate paths.
type TLSCfg struct {
	// CertFile path. If both are empty, a self-signed cert is auto-generated.
	CertFile string `yaml:"cert_file"`
	KeyFile  string `yaml:"key_file"`
}

// DatabaseCfg holds SQLite settings.
type DatabaseCfg struct {
	// Path is the SQLite database file path.
	Path string `yaml:"path"`
	// MaxOpenConns controls connection pool size.
	MaxOpenConns int `yaml:"max_open_conns"`
}

// GameCfg holds gameplay tuning values.
type GameCfg struct {
	// TickRate is how often the world tick runs (ms). Default: 250ms (4 ticks/sec).
	TickRateMS int `yaml:"tick_rate_ms"`
	// CombatTickRate is the attack cooldown in ms. Default: 4000ms.
	CombatTickMS int `yaml:"combat_tick_ms"`
	// SpawnMap is the map ID new/lost characters spawn on.
	SpawnMap int `yaml:"spawn_map"`
	SpawnX   int `yaml:"spawn_x"`
	SpawnY   int `yaml:"spawn_y"`
	// GameDataDir is where JSON game data files live.
	GameDataDir string `yaml:"game_data_dir"`
	// NightBrightness is the minimum nighttime color brightness (0.0-1.0).
	NightBrightness float64 `yaml:"night_brightness"`
	// DayLengthSeconds is real-world seconds per in-game day (for day/night cycle).
	DayLengthSeconds int `yaml:"day_length_seconds"`
}

// LogCfg holds logging settings.
type LogCfg struct {
	// Level: "debug", "info", "warn", "error"
	Level string `yaml:"level"`
	// Format: "text" or "json"
	Format string `yaml:"format"`
	// File path for log output. Empty means stderr.
	File string `yaml:"file"`
}

// AdminCfg holds admin API settings.
type AdminCfg struct {
	// Addr is the TCP address for the admin API listener.
	Addr string `yaml:"addr"`
	// Token is the bearer token required for admin requests.
	Token string `yaml:"token"`
}

// Load reads and parses the YAML config file at the given path.
func Load(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("config: read %s: %w", path, err)
	}

	cfg := defaults()
	if err := yaml.Unmarshal(data, cfg); err != nil {
		return nil, fmt.Errorf("config: parse %s: %w", path, err)
	}

	if err := cfg.validate(); err != nil {
		return nil, fmt.Errorf("config: invalid: %w", err)
	}
	return cfg, nil
}

func defaults() *Config {
	return &Config{
		Server: ServerCfg{
			GameAddr:     ":6969",
			HTTPAddr:     ":6970",
			MaxPlayers:   1000,
			ReadTimeout:  30 * time.Second,
			WriteTimeout: 10 * time.Second,
			IdleTimeout:  5 * time.Minute,
		},
		Database: DatabaseCfg{
			Path:         "eraonline.db",
			MaxOpenConns: 4,
		},
		Game: GameCfg{
			TickRateMS:       250,
			CombatTickMS:     4000,
			SpawnMap:         3,
			SpawnX:           50,
			SpawnY:           50,
			GameDataDir:      "../EraOnline/data",
			NightBrightness:  0.25,
			DayLengthSeconds: 7200,
		},
		Log: LogCfg{
			Level:  "info",
			Format: "text",
		},
		Admin: AdminCfg{
			Addr: "127.0.0.1:6971",
		},
	}
}

func (c *Config) validate() error {
	if len(c.Server.Secret) < 32 {
		return fmt.Errorf("server.secret must be at least 32 characters")
	}
	if len(c.Server.ClientIdentitySecret) < 16 {
		return fmt.Errorf("server.client_identity_secret must be at least 16 characters")
	}
	if c.Server.MaxPlayers <= 0 {
		return fmt.Errorf("server.max_players must be positive")
	}
	if c.Game.TickRateMS <= 0 {
		return fmt.Errorf("game.tick_rate_ms must be positive")
	}
	if c.Game.CombatTickMS <= 0 {
		return fmt.Errorf("game.combat_tick_ms must be positive")
	}
	if c.Game.DayLengthSeconds <= 0 {
		return fmt.Errorf("game.day_length_seconds must be positive")
	}
	return nil
}
