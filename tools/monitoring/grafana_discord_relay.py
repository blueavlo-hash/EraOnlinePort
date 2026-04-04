#!/usr/bin/env python3
"""
Local Grafana → Discord embed transformer.
Listens on 127.0.0.1:9876, receives Grafana webhook payloads,
posts rich embeds to Discord matching the honeypot embed style.

OpenRC service: grafana-discord
"""
import json, ssl, urllib.request
from http.server import HTTPServer, BaseHTTPRequestHandler
from datetime import datetime, timezone

DISCORD_WEBHOOK = (
    "https://discord.com/api/webhooks/1487499545511329933/"
    "AF-JXKmPzhIS3WCsByuJJvN7uejj7JIWZ7zZKHZIK2o44ZGFdetADrBS9ydDKv540ABb"
)

# Colours matching the honeypot palette
COLOR_FIRING   = 0xE74C3C   # red
COLOR_RESOLVED = 0x2ECC71   # green
COLOR_WARNING  = 0xE67E22   # orange (cert expiry etc.)

WARNING_ALERTS = {"Cert Expiry Warning"}

def severity_emoji(sev):
    return {"critical": "🔴", "warning": "🟡", "info": "🔵"}.get((sev or "").lower(), "🔴")

def build_embeds(payload):
    status  = payload.get("status", "firing")
    alerts  = payload.get("alerts", [])
    embeds  = []

    for alert in alerts:
        labels      = alert.get("labels", {})
        annotations = alert.get("annotations", {})
        alert_name  = labels.get("alertname", "Alert")
        instance    = labels.get("instance", "")
        severity    = labels.get("severity", "")
        summary     = annotations.get("summary", "")
        description = annotations.get("description", "")
        starts_at   = alert.get("startsAt", "")
        ends_at     = alert.get("endsAt", "")

        firing = (alert.get("status", status) == "firing")

        if alert_name in WARNING_ALERTS:
            color = COLOR_WARNING
        else:
            color = COLOR_FIRING if firing else COLOR_RESOLVED

        title = (
            f"{'🚨' if firing else '✅'}  "
            f"{'FIRING' if firing else 'RESOLVED'}  ·  {alert_name}  ·  laurel-gw"
        )

        # ── Inline fields (3-column grid like the honeypot) ──────────────────
        fields = [
            {"name": "🖥️  Host",    "value": "laurel-gw",  "inline": True},
            {"name": "🏷️  Alert",   "value": alert_name,   "inline": True},
        ]

        if instance:
            fields.append({"name": "📡  Instance", "value": f"`{instance}`", "inline": True})
        if severity:
            fields.append({"name": f"{severity_emoji(severity)}  Severity",
                           "value": severity.title(), "inline": True})

        # ── Full-width fields ─────────────────────────────────────────────────
        if summary:
            fields.append({"name": "📋  What happened", "value": summary, "inline": False})
        if description:
            fields.append({"name": "🔧  Action", "value": description, "inline": False})

        # Triggered / resolved timestamp as full-width field
        if firing and starts_at:
            try:
                dt = datetime.fromisoformat(starts_at.replace("Z", "+00:00"))
                ts_str = dt.strftime("%Y-%m-%d %H:%M:%S UTC")
            except Exception:
                ts_str = starts_at
            fields.append({"name": "🕐  Triggered", "value": ts_str, "inline": False})
        elif not firing and ends_at:
            try:
                dt = datetime.fromisoformat(ends_at.replace("Z", "+00:00"))
                ts_str = dt.strftime("%Y-%m-%d %H:%M:%S UTC")
            except Exception:
                ts_str = ends_at
            fields.append({"name": "✅  Resolved", "value": ts_str, "inline": False})

        embed = {
            "title":  title,
            "color":  color,
            "fields": fields,
            "footer": {"text": "laurel-gw · Grafana Alerting"},
            "timestamp": starts_at if starts_at else datetime.now(timezone.utc).isoformat(),
        }
        embeds.append(embed)

    return embeds


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length  = int(self.headers.get("Content-Length", 0))
        payload = json.loads(self.rfile.read(length))

        embeds = build_embeds(payload)
        if embeds:
            body = json.dumps({"username": "laurel-gw", "embeds": embeds}).encode()
            req  = urllib.request.Request(
                DISCORD_WEBHOOK, data=body,
                headers={"Content-Type": "application/json", "User-Agent": "curl/8.17.0"})
            try:
                urllib.request.urlopen(req, timeout=10)
            except Exception as e:
                print(f"[discord] error: {e}")

        self.send_response(200)
        self.end_headers()

    def log_message(self, fmt, *args):
        pass   # silence access log


if __name__ == "__main__":
    print("grafana-discord listening on 127.0.0.1:9876")
    HTTPServer(("127.0.0.1", 9876), Handler).serve_forever()
