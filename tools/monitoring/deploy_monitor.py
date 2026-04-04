#!/usr/bin/env python3
import paramiko, sys

host = "89.167.94.75"
port = 22
user = "root"
password = "xK9#mP2$vL7@nQ4!wR8"

fixed_script = r"""#!/usr/bin/env python3
import os, sys, json, ssl, subprocess, urllib.request, time, threading
from datetime import datetime, timezone

RELAY_BASE           = "https://5.78.207.11:6971"
CERT_PATH            = "/etc/vl-relay-cert.pem"
BOOTSTRAP_TOKEN_FILE = "/etc/vl-bootstrap.token"
ADMIN_IPS            = {"23.234.111.81", "23.234.70.152"}
DEDUP_WINDOW = 30

PATH_RULES = [
    ("/root/.secure/",              0xE74C3C, "CRITICAL", True,
     "Someone accessed the encrypted credentials vault. This is the prize."),
    ("/root/.ssh/authorized_keys",  0xE74C3C, "CRITICAL", True,
     "SSH authorized_keys modified — attacker adding backdoor key for persistent access."),
    ("/etc/shadow",                 0xE74C3C, "CRITICAL", True,
     "Shadow password file WRITTEN — attacker changing root password or adding backdoor user."),
    ("/etc/passwd",                 0xE74C3C, "CRITICAL", True,
     "Passwd file WRITTEN — attacker creating a privileged backdoor account."),
    ("/etc/sudoers",                0xE74C3C, "CRITICAL", True,
     "Sudoers file modified — attacker granting passwordless sudo to backdoor account."),
    ("/etc/cron.d/",                0xE74C3C, "CRITICAL", True,
     "Cron directory modified — attacker establishing persistent scheduled execution."),
    ("/etc/crontab",                0xE74C3C, "CRITICAL", True,
     "System crontab modified — attacker establishing persistent scheduled execution."),
    ("/root/",                      0xE67E22, "HIGH",     False,
     "Root home directory accessed. Attacker exploring for credentials or config files."),
    ("/var/backups/vaultledger/",   0xE67E22, "HIGH",     False,
     "Encrypted backup files accessed. Attacker examining lure files."),
]

_sent = {}
_sent_lock = threading.Lock()

def _ssl_ctx():
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_REQUIRED
    ctx.load_verify_locations(CERT_PATH)
    return ctx

def _fetch_relay_key():
    token = open(BOOTSTRAP_TOKEN_FILE).read().strip()
    payload = json.dumps({"token": token}).encode()
    req = urllib.request.Request(f"{RELAY_BASE}/bootstrap", data=payload,
        headers={"Content-Type": "application/json"})
    resp = urllib.request.urlopen(req, context=_ssl_ctx(), timeout=10)
    return json.loads(resp.read())["relay_key"]

def get_ssh_sessions():
    try:
        out = subprocess.check_output(["ss", "-tnp"], text=True, timeout=3)
        all_ips, external = [], []
        for line in out.splitlines():
            if "ESTAB" in line and ":22 " in line:
                parts = line.split()
                if len(parts) >= 5:
                    peer = parts[4]
                    ip = peer.rsplit(":", 1)[0].strip("[]")
                    if ip not in ("", "127.0.0.1", "::1"):
                        all_ips.append(ip)
                        if ip not in ADMIN_IPS:
                            external.append(ip)
        if not all_ips:
            return ["(no active SSH)"], False
        if not external:
            return [], True
        return list(dict.fromkeys(external)), False
    except Exception:
        return ["(unknown)"], False

def classify(path):
    for prefix, color, severity, ping, explanation in PATH_RULES:
        if path.startswith(prefix):
            return color, severity, ping, explanation
    return 0x95A5A6, "LOW", False, "File system activity in a monitored path."

def should_send(path, event):
    key = f"{path}|{event}"
    now = time.time()
    with _sent_lock:
        if key in _sent and now - _sent[key] < DEDUP_WINDOW:
            return False
        _sent[key] = now
    return True

def get_file_info(path):
    size_str = "?"
    try:
        st = os.stat(path)
        sz = st.st_size
        size_str = f"{sz:,} B" if sz < 1024 else f"{sz/1024:.1f} KB" if sz < 1048576 else f"{sz/1048576:.1f} MB"
    except Exception:
        pass
    proc_str = "(unknown)"
    try:
        out = subprocess.check_output(["fuser", "-u", path],
            stderr=subprocess.STDOUT, text=True, timeout=3).strip()
        parts = out.split(":", 1)
        if len(parts) == 2 and parts[1].strip():
            proc_str = parts[1].strip()
    except subprocess.CalledProcessError:
        proc_str = "(no process)"
    except Exception:
        pass
    return size_str, proc_str

def send_alert(relay_key, path, event, ts):
    color, severity, ping, explanation = classify(path)
    sessions, admin_only = get_ssh_sessions()
    if admin_only:
        return
    size_str, proc_str = get_file_info(path)
    icon = "\U0001f534" if severity == "CRITICAL" else "\U0001f7e0" if severity == "HIGH" else "\U0001f7e1"
    embed = {
        "title": f"{icon} [{severity}] File Event",
        "color": color,
        "fields": [
            {"name": "Host",         "value": "vl-internal-01",      "inline": True},
            {"name": "Severity",     "value": severity,               "inline": True},
            {"name": "Time",         "value": ts,                     "inline": True},
            {"name": "Event",        "value": event,                  "inline": True},
            {"name": "File Size",    "value": size_str,               "inline": True},
            {"name": "SSH Sessions", "value": "\n".join(sessions),    "inline": True},
            {"name": "Path",         "value": f"`{path}`",            "inline": False},
            {"name": "Process",      "value": f"`{proc_str}`",        "inline": False},
            {"name": "What this means", "value": explanation,         "inline": False},
        ],
        "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "footer": {"text": "vl-internal-01 file monitor"}
    }
    payload = json.dumps({"content": "@here" if ping else "", "embeds": [embed]}).encode()
    try:
        req = urllib.request.Request(f"{RELAY_BASE}/alert", data=payload,
            headers={"Content-Type": "application/json", "X-Relay-Key": relay_key})
        urllib.request.urlopen(req, context=_ssl_ctx(), timeout=5)
    except Exception as e:
        print(f"[monitor] alert error: {e}", file=sys.stderr)

RELAY_KEY = _fetch_relay_key()
print("[monitor] bootstrapped, watching sensitive paths")

# Lure paths: fire on any read or write — we want to know if attacker even looks
LURE_PATHS = ["/root/", "/root/.secure/", "/var/backups/vaultledger/"]

# System config: WRITES ONLY — /etc/passwd and /etc/shadow are read by PAM on
# every single SSH auth attempt, firing on ACCESS would spam thousands of alerts/day
SYSTEM_PATHS = ["/etc/passwd", "/etc/shadow", "/etc/sudoers", "/etc/crontab", "/etc/cron.d/"]

def watch(paths, events):
    proc = subprocess.Popen(
        ["inotifywait", "-m", "-r"] + paths +
        ["--format", "%T|%w%f|%e", "--timefmt", "%Y-%m-%dT%H:%M:%S", "-e", events],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL
    )
    for raw in proc.stdout:
        line = raw.decode("utf-8", errors="replace").strip()
        parts = line.split("|", 2)
        if len(parts) == 3:
            ts, path, event = parts
            if "ISDIR" in event:
                continue
            if should_send(path, event):
                send_alert(RELAY_KEY, path, event, ts)

threading.Thread(target=watch, args=(SYSTEM_PATHS, "modify,create,delete,moved_to"), daemon=True).start()
watch(LURE_PATHS, "access,open,modify,create,delete")
"""

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect(host, port=port, username=user, password=password,
               allow_agent=False, look_for_keys=False, timeout=15)
print("[+] Connected")

sftp = client.open_sftp()
with sftp.open("/usr/local/bin/vl-file-monitor.py", "w") as f:
    f.write(fixed_script)
sftp.close()
sys.stdout.buffer.write(b"[+] File uploaded\n")

cmds = (
    "chmod 700 /usr/local/bin/vl-file-monitor.py && "
    "systemctl restart vl-file-monitor && "
    "sleep 3 && "
    "systemctl status vl-file-monitor --no-pager"
)
stdin, stdout, stderr = client.exec_command(cmds, timeout=30)
out = stdout.read().decode()
err = stderr.read().decode()
sys.stdout.buffer.write(out.encode("utf-8", errors="replace"))
if err:
    sys.stdout.buffer.write(("STDERR: " + err).encode("utf-8", errors="replace"))

client.close()
