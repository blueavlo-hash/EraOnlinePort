#!/usr/bin/env python3
"""
Dead man's switch watchdog for laurel-gw.
Runs on era-online VPS (port 9877).

Expects a ping from laurel-gw every 5 minutes:
  GET /ping/lFrivZCyaHf6p2FOON99kpubKHPtmLLn

If no ping is received within 10 minutes, fires a Discord DOWN alert.
Fires a RECOVERED alert when pings resume.
Ignores the first 15 minutes after startup to avoid false alarms on VPS restart.
"""

import json, threading, time, urllib.request
from http.server import HTTPServer, BaseHTTPRequestHandler
from datetime import datetime, timezone

PORT       = 9877
TOKEN      = "lFrivZCyaHf6p2FOON99kpubKHPtmLLn"
PING_PATH  = f"/ping/{TOKEN}"
THRESHOLD  = 600   # 10 minutes — fire alert if no ping received
CHECK_EVERY = 60   # check every minute
GRACE      = 900   # 15 minute startup grace period (avoid false alarm on VPS restart)

DISCORD_WEBHOOK = (
    "https://discord.com/api/webhooks/1487499545511329933/"
    "AF-JXKmPzhIS3WCsByuJJvN7uejj7JIWZ7zZKHZIK2o44ZGFdetADrBS9ydDKv540ABb"
)

COLOR_DOWN      = 0xE74C3C
COLOR_RECOVERED = 0x2ECC71

start_time  = time.time()
last_ping   = time.time()   # init to now so grace period applies cleanly
is_down     = False
lock        = threading.Lock()


def ts():
    return datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")


def send_discord(firing):
    if firing:
        title  = "🚨  FIRING  ·  Gateway Unreachable  ·  laurel-gw"
        color  = COLOR_DOWN
        fields = [
            {"name": "🖥️  Host",    "value": "laurel-gw",     "inline": True},
            {"name": "🏷️  Alert",   "value": "Dead Man's Switch", "inline": True},
            {"name": "🔴  Severity","value": "Critical",       "inline": True},
            {"name": "📋  What happened",
             "value": "No watchdog ping received in over 10 minutes. "
                      "laurel-gw may be down or unreachable.", "inline": False},
            {"name": "🔧  Action",
             "value": "Check gateway power and connectivity. "
                      f"Last ping received: {ts()}", "inline": False},
            {"name": "🕐  Triggered", "value": ts(), "inline": False},
        ]
    else:
        title  = "✅  RESOLVED  ·  Gateway Unreachable  ·  laurel-gw"
        color  = COLOR_RECOVERED
        fields = [
            {"name": "🖥️  Host",   "value": "laurel-gw",          "inline": True},
            {"name": "🏷️  Alert",  "value": "Dead Man's Switch",   "inline": True},
            {"name": "✅  Resolved", "value": ts(), "inline": False},
            {"name": "📋  Note", "value": "Watchdog pings have resumed — laurel-gw is back online.", "inline": False},
        ]

    embed = {
        "title":  title,
        "color":  color,
        "fields": fields,
        "footer": {"text": "era-online · Watchdog"},
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }
    body = json.dumps({"username": "era-online", "embeds": [embed]}).encode()
    req  = urllib.request.Request(
        DISCORD_WEBHOOK, data=body,
        headers={"Content-Type": "application/json", "User-Agent": "curl/8.17.0"})
    try:
        urllib.request.urlopen(req, timeout=10)
        print(f"[discord] {'DOWN' if firing else 'RECOVERED'} alert sent")
    except Exception as e:
        print(f"[discord] error: {e}")


def checker():
    global is_down, last_ping
    time.sleep(GRACE)
    print(f"[watchdog] grace period over, monitoring active")
    while True:
        time.sleep(CHECK_EVERY)
        with lock:
            age = time.time() - last_ping
            if not is_down and age > THRESHOLD:
                is_down = True
                print(f"[watchdog] DOWN — last ping {age:.0f}s ago")
                send_discord(firing=True)
            elif is_down and age <= THRESHOLD:
                is_down = False
                print(f"[watchdog] RECOVERED")
                send_discord(firing=False)


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        global last_ping
        if self.path == PING_PATH:
            with lock:
                last_ping = time.time()
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"ok")
            print(f"[ping] received from {self.client_address[0]}")
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, fmt, *args):
        pass  # silence access log


if __name__ == "__main__":
    t = threading.Thread(target=checker, daemon=True)
    t.start()
    print(f"[watchdog] listening on 0.0.0.0:{PORT}")
    print(f"[watchdog] ping path: {PING_PATH}")
    HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
