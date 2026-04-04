"""
Update laurel-gw Grafana:
  - Discord alert template (cleaner embed-style formatting)
  - Contact point title template
  - New alert rules: Cert Expiry, Suricata Down
Run on laurel-gw: python3 update_laurel_alerts.py
"""
import json, base64, urllib.request

BASE = "http://127.0.0.1:3000"
AUTH = base64.b64encode(b"admin:L@ur3l-Gr4f-2026!").decode()
H = {"Authorization": f"Basic {AUTH}", "Content-Type": "application/json"}
FOLDER_UID = "cfhecyr5is268c"

def api(method, path, body=None):
    req = urllib.request.Request(f"{BASE}{path}",
        data=json.dumps(body).encode() if body else None,
        headers=H, method=method)
    try:
        resp = urllib.request.urlopen(req)
        return resp.status, json.loads(resp.read())
    except urllib.request.HTTPError as e:
        return e.code, e.read().decode()[:600]

# ── 1. Notification template ──────────────────────────────────────────────────
# Blockquote-style fields, matches honeypot visual language
TEMPLATE_BODY = (
    '{{ define "laurel.discord.message" -}}\n'
    '{{ range .Alerts -}}\n'
    '> 🖥️  **Host** · laurel-gw\n'
    '{{ if .Labels.instance -}}'
    '> 📡  **Instance** · `{{ .Labels.instance }}`\n'
    '{{ end -}}'
    '{{ if .Labels.severity -}}'
    '> ⚡  **Severity** · {{ .Labels.severity | title }}\n'
    '{{ end -}}'
    '> 🕐  **{{ if eq .Status "firing" }}Triggered{{ else }}Resolved{{ end }}**'
    ' · {{ if eq .Status "firing" }}'
    '{{ .StartsAt.UTC.Format "2006-01-02 15:04:05 UTC" }}'
    '{{ else }}'
    '{{ .EndsAt.UTC.Format "2006-01-02 15:04:05 UTC" }}'
    '{{ end }}\n'
    '{{ if .Annotations.summary }}\n'
    '📋  {{ .Annotations.summary }}\n'
    '{{ end -}}'
    '{{ end -}}'
    '{{- end }}'
)

TITLE_TMPL = (
    '{{ if eq .Status "firing" -}}'
    '🚨  {{ if eq (len .Alerts) 1 }}{{ (index .Alerts 0).Labels.alertname }} · {{ end }}'
    'FIRING{{ if gt (len .Alerts) 1 }} ({{ len .Alerts }} alerts){{ end }} · laurel-gw'
    '{{- else -}}'
    '✅  {{ if eq (len .Alerts) 1 }}{{ (index .Alerts 0).Labels.alertname }} · {{ end }}'
    'RESOLVED{{ if gt (len .Alerts) 1 }} ({{ len .Alerts }} alerts){{ end }} · laurel-gw'
    '{{- end }}'
)

print("── Template ──")
s, r = api("PUT", "/api/v1/provisioning/templates/laurel-discord",
    {"name": "laurel-discord", "template": TEMPLATE_BODY})
print(f"  {s}", "OK" if s in (200, 202) else r)

# ── 2. Contact point – update title template ──────────────────────────────────
print("── Contact point ──")
s, cp_list = api("GET", "/api/v1/provisioning/contact-points")
cp = next((c for c in cp_list if c["name"] == "discord-webhook"), None)
if not cp:
    print("  ERROR: discord-webhook contact point not found"); exit(1)

cp["settings"]["title"]   = TITLE_TMPL
cp["settings"]["message"] = '{{ template "laurel.discord.message" . }}'
s, r = api("PUT", f"/api/v1/provisioning/contact-points/{cp['uid']}", cp)
print(f"  {s}", "OK" if s in (200, 202) else r)

# ── 3. Alert rules ────────────────────────────────────────────────────────────
def make_rule(title, expr, for_dur, summary, description=""):
    return {
        "title": title,
        "ruleGroup": "laurel-alerts",
        "folderUID": FOLDER_UID,
        "condition": "A",
        "for": for_dur,
        "noDataState": "NoData",
        "execErrState": "Error",
        "annotations": {"summary": summary, "description": description},
        "labels": {},
        "data": [{
            "refId": "A",
            "queryType": "",
            "relativeTimeRange": {"from": 600, "to": 0},
            "datasourceUid": "cfbkwe3f0oydce",
            "model": {"expr": expr, "intervalMs": 1000, "maxDataPoints": 43200, "refId": "A"}
        }]
    }

new_rules = [
    make_rule(
        "Cert Expiry Warning",
        "(probe_ssl_earliest_cert_expiry{job=\"blackbox_https\"} - time()) < 21600",
        "5m",
        "TLS certificate expiring within 6 hours — {{ $labels.instance }}",
        "Hourly renewal should have caught this. Check laurel-cert-renew logs."
    ),
    make_rule(
        "Suricata Down",
        "up{job=\"suricata\"} == 0",
        "2m",
        "Suricata IDS is not responding — IDS rules engine may be down",
        "Check: doas rc-service suricata status"
    ),
]

print("── Alert rules ──")
# Fetch existing to avoid duplicates
s, existing = api("GET", "/api/v1/provisioning/alert-rules")
existing_titles = {r["title"] for r in existing}

for rule in new_rules:
    if rule["title"] in existing_titles:
        print(f"  SKIP (exists): {rule['title']}")
        continue
    s, r = api("POST", "/api/v1/provisioning/alert-rules", rule)
    print(f"  {s} {rule['title']}", "OK" if s in (200, 201) else r)

print("\nDone.")
