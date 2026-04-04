"""
Update Grafana Discord contact point with a professional alert template.
Run on laurel-gw: python3 update_discord_template.py
"""
import json, urllib.request, base64

BASE = "http://127.0.0.1:3000"
auth = base64.b64encode(b"admin:L@ur3l-Gr4f-2026!").decode()
H = {"Content-Type": "application/json", "Authorization": f"Basic {auth}"}

DISCORD_CP_UID = "afhecz3fnt1j4a"
DISCORD_URL = "https://discord.com/api/webhooks/1487499545511329933/AF-JXKmPzhIS3WCsByuJJvN7uejj7JIWZ7zZKHZIK2o44ZGFdetADrBS9ydDKv540ABb"

def api(method, path, body=None):
    req = urllib.request.Request(f"{BASE}{path}",
        data=json.dumps(body).encode() if body else None,
        headers=H, method=method)
    try:
        resp = urllib.request.urlopen(req)
        raw = resp.read()
        return resp.status, json.loads(raw) if raw else {}
    except urllib.request.HTTPError as e:
        return e.code, e.read().decode()[:1000]

# ── 1. Create the notification template ──────────────────────────────────────
TEMPLATE_BODY = r"""{{ define "laurel.discord.message" -}}
{{ if eq .Status "firing" -}}
## 🚨  ALERT FIRING  ·  {{ len .Alerts }} alert(s)  ·  laurel-gw
{{ else -}}
## ✅  ALERT RESOLVED  ·  {{ len .Alerts }} alert(s)  ·  laurel-gw
{{ end -}}
{{ range .Alerts -}}
━━━━━━━━━━━━━━━━━━━━━━━━
**{{ .Labels.alertname }}**{{ if .Labels.instance }}  ·  `{{ .Labels.instance }}`{{ end }}
{{ if .Annotations.summary }}> 📋 {{ .Annotations.summary }}{{ end }}
**Status:** {{ if eq .Status "firing" }}🔴 Firing{{ else }}✅ Resolved{{ end }}{{ if .Labels.severity }}  ·  **Severity:** {{ .Labels.severity | title }}{{ end }}
**Triggered:** {{ .StartsAt.UTC.Format "2006-01-02 15:04:05 UTC" }}{{ if eq .Status "resolved" }}
**Resolved:** {{ .EndsAt.UTC.Format "2006-01-02 15:04:05 UTC" }}{{ end }}
{{ end -}}
{{- end }}
"""

status, r = api("PUT", "/api/v1/provisioning/templates/laurel-discord", {
    "template": TEMPLATE_BODY
})
print(f"template PUT: {status} — {r}")

# ── 2. Update contact point with message template + preserved URL ─────────────
updated_cp = {
    "name": "discord-webhook",
    "type": "discord",
    "disableResolveMessage": False,
    "settings": {
        "url": DISCORD_URL,
        "message": '{{ template "laurel.discord.message" . }}',
        "title": '{{ if eq .Status "firing" }}🔴 FIRING ({{ len .Alerts }}){{ else }}✅ RESOLVED ({{ len .Alerts }}){{ end }} — laurel-gw',
        "avatar_url": "https://grafana.com/static/assets/img/fav32.png",
        "use_discord_username": False,
    },
}

status, r = api("PUT", f"/api/v1/provisioning/contact-points/{DISCORD_CP_UID}", updated_cp)
print(f"contact point PUT: {status} — {r}")

# ── 3. Update alert rule annotations for richer context ───────────────────────
# Give each alert rule a more descriptive summary and add description annotations
rules_update = [
    {
        "uid": "bfheczy6qsykge",
        "description": "One or more blackbox probes reporting probe_success == 0",
        "summary": "Service unreachable — blackbox probe failed",
    },
    {
        "uid": "bfheczy98pb0gd",
        "description": "System RAM utilisation above 85% for 5+ minutes",
        "summary": "High memory usage on laurel-gw",
    },
    {
        "uid": "dfheczybvlg5cf",
        "description": "Root filesystem used above 80%",
        "summary": "Disk space running low on laurel-gw",
    },
    {
        "uid": "ffheczyeihla8d",
        "description": "CPU utilisation above 85% sustained for 5 minutes",
        "summary": "High CPU usage on laurel-gw",
    },
    {
        "uid": "cfheczygve51cc",
        "description": "Suricata EVE log showing >50 IDS alerts in a 5 min window — possible attack",
        "summary": "Suricata IDS alert surge detected",
    },
    {
        "uid": "bfheczyjasl4wa",
        "description": "CrowdSec bouncer Prometheus metrics have stopped reporting",
        "summary": "CrowdSec bouncer appears to be down — enforcement may be inactive",
    },
]

# Fetch and update each rule's annotations
for r_update in rules_update:
    status, rule = api("GET", f"/api/v1/provisioning/alert-rules/{r_update['uid']}")
    if status != 200:
        print(f"  SKIP {r_update['uid']}: {status}")
        continue
    rule.setdefault("annotations", {})
    rule["annotations"]["summary"] = r_update["summary"]
    rule["annotations"]["description"] = r_update["description"]
    status2, resp2 = api("PUT", f"/api/v1/provisioning/alert-rules/{r_update['uid']}", rule)
    print(f"  rule {rule.get('title')}: {status2}")

print("\nDone. Test with: Grafana → Alerting → Contact points → discord-webhook → Test")
