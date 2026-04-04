"""
Append a Service Probes overview row to the Home Overview dashboard.
Run on laurel-gw: python3 update_home_overview.py
"""
import json, base64, urllib.request

BASE = "http://127.0.0.1:3000"
AUTH = base64.b64encode(b"admin:L@ur3l-Gr4f-2026!").decode()
H = {"Authorization": "Basic " + AUTH, "Content-Type": "application/json"}
DS = "cfbkwe3f0oydce"

def api(method, path, body=None):
    req = urllib.request.Request(f"{BASE}{path}",
        data=json.dumps(body).encode() if body else None,
        headers=H, method=method)
    try:
        resp = urllib.request.urlopen(req)
        return resp.status, json.loads(resp.read())
    except urllib.request.HTTPError as e:
        return e.code, e.read().decode()[:600]

# Fetch current dashboard
s, r = api("GET", "/api/dashboards/uid/home-overview")
dash = r["dashboard"]

# Find the next available y position
max_y = max(
    p["gridPos"]["y"] + p["gridPos"]["h"]
    for p in dash["panels"]
)
y = max_y

# Find a safe starting panel id above existing ones
max_id = max(p.get("id", 0) for p in dash["panels"])
next_id = max_id + 1

def stat(pid, title, expr, x, row_y, color, unit="short", graph="none", decimals=0, mappings=None, thresholds=None):
    p = {
        "id": pid, "type": "stat", "title": title,
        "gridPos": {"x": x, "y": row_y, "w": 4, "h": 4},
        "fieldConfig": {"defaults": {
            "decimals": decimals, "unit": unit,
            "color": {"fixedColor": color, "mode": "fixed" if not thresholds else "thresholds"},
        }},
        "options": {"colorMode": "background", "graphMode": graph,
                    "reduceOptions": {"calcs": ["lastNotNull"]}},
        "targets": [{"datasource": {"uid": DS}, "expr": expr, "legendFormat": " ", "refId": "A"}]
    }
    if thresholds:
        p["fieldConfig"]["defaults"]["thresholds"] = thresholds
        p["fieldConfig"]["defaults"]["color"] = {"mode": "thresholds"}
    if mappings:
        p["fieldConfig"]["defaults"]["mappings"] = mappings
    return p

new_panels = [
    # Row header
    {
        "id": next_id, "type": "row", "title": "🔍  Service Probes",
        "collapsed": False,
        "gridPos": {"x": 0, "y": y, "w": 24, "h": 1}
    },
]
y += 1

updown_mappings = [{"type": "value", "options": {
    "0": {"text": "DOWN", "color": "red", "index": 0},
    "1": {"text": "UP",   "color": "green", "index": 1}
}}]

new_panels += [
    # Services Up — green when all 36 non-policy probes are up
    stat(next_id+1, "Services Up",
         'count(probe_success{job!="blackbox_policy"} == 1)',
         x=0, row_y=y, color=None, unit="short",
         thresholds={"mode": "absolute", "steps": [
             {"color": "#8a3d3d", "value": None},
             {"color": "#7a6a2a", "value": 30},
             {"color": "#3a6b4a", "value": 36},
         ]}),

    # Services Down — green at 0, red at 2+
    stat(next_id+2, "Services Down",
         'count(probe_success{job!="blackbox_policy"} == 0) or vector(0)',
         x=4, row_y=y, color=None, unit="short",
         thresholds={"mode": "absolute", "steps": [
             {"color": "#3a6b4a", "value": None},
             {"color": "#7a6a2a", "value": 1},
             {"color": "#8a3d3d", "value": 2},
         ]}),

    # Policy Blocked — green when all 3 blocked (policy enforced)
    stat(next_id+3, "Policy Blocked",
         'count(probe_success{job="blackbox_policy"} == 0) or vector(0)',
         x=8, row_y=y, color=None, unit="short",
         thresholds={"mode": "absolute", "steps": [
             {"color": "#8a3d3d", "value": None},
             {"color": "#7a6a2a", "value": 1},
             {"color": "#3a6b4a", "value": 3},
         ]}),

    # Internet (canary) — min of cloudflare/google/amazon
    stat(next_id+4, "Internet",
         'min(probe_success{job="blackbox_external"})',
         x=12, row_y=y, color=None, unit="short",
         mappings=updown_mappings,
         thresholds={"mode": "absolute", "steps": [
             {"color": "#8a3d3d", "value": None},
             {"color": "#3a6b4a", "value": 1},
         ]}),

    # VPN — min of VPN probes
    stat(next_id+5, "VPN",
         'min(probe_success{job="blackbox_vpn"})',
         x=16, row_y=y, color=None, unit="short",
         mappings=updown_mappings,
         thresholds={"mode": "absolute", "steps": [
             {"color": "#8a3d3d", "value": None},
             {"color": "#3a6b4a", "value": 1},
         ]}),

    # Certs expiring < 1d
    stat(next_id+6, "Certs Expiring <1d",
         'count((probe_ssl_earliest_cert_expiry{job="blackbox_https"} - time()) / 86400 < 1) or vector(0)',
         x=20, row_y=y, color=None, unit="short",
         thresholds={"mode": "absolute", "steps": [
             {"color": "#3a6b4a", "value": None},
             {"color": "#7a6a2a", "value": 1},
             {"color": "#8a3d3d", "value": 3},
         ]}),
]

dash["panels"].extend(new_panels)

s, r = api("POST", "/api/dashboards/db", {
    "dashboard": dash,
    "overwrite": True,
    "folderId": 0,
    "message": "add service probes overview row"
})
print(f"status: {s}")
if isinstance(r, dict):
    print(f"url: {r.get('url')}")
    print(f"version: {r.get('version')}")
else:
    print(r)
