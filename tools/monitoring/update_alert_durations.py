"""
Update all alert rules in the laurel-alerts group to longer 'for' durations.
Prevents false alarms from brief service blips.

Run on laurel-gw: python3 update_alert_durations.py
"""
import json, base64, urllib.request

BASE = "http://127.0.0.1:3000"
AUTH = base64.b64encode(b"admin:L@ur3l-Gr4f-2026!").decode()
H = {"Authorization": f"Basic {AUTH}", "Content-Type": "application/json"}

# New durations by severity
# critical → 5m, warning → 10m
# Override specific rules that need different values
OVERRIDES = {
    "Policy Enforcement Breach": "5m",   # security — keep responsive
    "Internet Outage (Canary)":  "5m",   # canary should be fairly quick
    "High External Latency":     "10m",  # latency spikes are normal briefly
}

DEFAULT_BY_SEVERITY = {
    "critical": "5m",
    "warning":  "10m",
}
FALLBACK = "5m"

def api(method, path, body=None):
    req = urllib.request.Request(f"{BASE}{path}",
        data=json.dumps(body).encode() if body else None,
        headers=H, method=method)
    try:
        resp = urllib.request.urlopen(req)
        return resp.status, json.loads(resp.read())
    except urllib.request.HTTPError as e:
        return e.code, e.read().decode()[:600]

s, rules = api("GET", "/api/v1/provisioning/alert-rules")
if s != 200:
    print(f"Failed to fetch rules: {s} {rules}")
    exit(1)

print(f"Found {len(rules)} alert rules\n── Updating durations ──")

for rule in rules:
    title    = rule["title"]
    severity = rule.get("labels", {}).get("severity", "critical")
    old_for  = rule.get("for", "?")

    new_for = OVERRIDES.get(title) or DEFAULT_BY_SEVERITY.get(severity, FALLBACK)

    if old_for == new_for:
        print(f"  SKIP (already {new_for}): {title}")
        continue

    rule["for"] = new_for
    uid = rule["uid"]
    s, r = api("PUT", f"/api/v1/provisioning/alert-rules/{uid}", rule)
    status = "OK" if s in (200, 201) else r
    print(f"  {old_for} → {new_for}  [{s}] {title}  {status}")

print("\nDone.")
