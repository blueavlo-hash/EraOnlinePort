"""
Add alert rules for the 6 new blackbox dashboard rows.
Run on laurel-gw: python3 add_blackbox_alerts.py
"""
import json, base64, urllib.request

BASE = "http://127.0.0.1:3000"
AUTH = base64.b64encode(b"admin:L@ur3l-Gr4f-2026!").decode()
H = {"Authorization": f"Basic {AUTH}", "Content-Type": "application/json"}
FOLDER_UID = "cfhecyr5is268c"
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

def make_rule(title, expr, for_dur, summary, description="", severity="critical"):
    return {
        "title": title,
        "ruleGroup": "laurel-alerts",
        "folderUID": FOLDER_UID,
        "condition": "A",
        "for": for_dur,
        "noDataState": "NoData",
        "execErrState": "Error",
        "annotations": {"summary": summary, "description": description},
        "labels": {"severity": severity},
        "data": [{
            "refId": "A",
            "queryType": "",
            "relativeTimeRange": {"from": 600, "to": 0},
            "datasourceUid": DS,
            "model": {"expr": expr, "intervalMs": 1000, "maxDataPoints": 43200, "refId": "A"}
        }]
    }

new_rules = [
    # VPN Integrity
    make_rule(
        "VPN Integrity Down",
        'min(probe_success{job="blackbox_vpn"}) == 0',
        "2m",
        "VPN connectivity check failed — external IP probes unreachable",
        "Check VPN tunnel status and routing. Targets: cf-trace, ifconfig-me"
    ),

    # Policy Enforcement Breach
    make_rule(
        "Policy Enforcement Breach",
        'max(probe_success{job="blackbox_policy"}) == 1',
        "2m",
        "Blocked domain is now accessible — Pi-hole policy enforcement may be broken",
        "A domain that should be blocked (facebook-graph, doubleclick, ads-google) is responding. Check Pi-hole blocklists.",
        severity="critical"
    ),

    # Network Stability
    make_rule(
        "External Network Unstable",
        'min(probe_success{job="blackbox_stability"}) == 0',
        "3m",
        "ICMP probes to external DNS resolvers failing — possible upstream network issue",
        "Targets: 1.1.1.1, 8.8.8.8, 9.9.9.9. Check ISP/WAN connectivity.",
        severity="warning"
    ),
    make_rule(
        "High External Latency",
        'avg(probe_duration_seconds{job="blackbox_stability"}) * 1000 > 200',
        "5m",
        "Average ICMP latency to external resolvers exceeds 200ms",
        "Possible network congestion or routing issue. Check WAN/VPN path.",
        severity="warning"
    ),

    # DNS Integrity
    make_rule(
        "DNS Resolution Failure",
        'probe_success{job="blackbox_dns_integrity",instance="dns-google-com"} == 0',
        "2m",
        "DNS resolution for google.com is failing — DNS may be broken",
        "Check Pi-hole and upstream DNS resolver configuration."
    ),
    make_rule(
        "Pi-hole Block Failure",
        'probe_success{job="blackbox_dns_integrity",instance="dns-block-check"} == 0',
        "2m",
        "Pi-hole is no longer blocking doubleclick.net — ad/tracker blocking may be down",
        "Check Pi-hole service status: doas rc-service pihole-FTL status",
        severity="warning"
    ),

    # External Reality / Canary
    make_rule(
        "Internet Outage (Canary)",
        'min(probe_success{job="blackbox_external"}) == 0',
        "3m",
        "All external canary targets unreachable — possible full internet outage",
        "Targets: cloudflare.com, google.com, amazon.com. Check WAN uplink and routing."
    ),
]

# Fetch existing to skip duplicates
s, existing = api("GET", "/api/v1/provisioning/alert-rules")
existing_titles = {r["title"] for r in existing}

print("── Adding alert rules ──")
for rule in new_rules:
    if rule["title"] in existing_titles:
        print(f"  SKIP (exists): {rule['title']}")
        continue
    s, r = api("POST", "/api/v1/provisioning/alert-rules", rule)
    print(f"  {s} {rule['title']}", "OK" if s in (200, 201) else r)

print("\nDone.")
