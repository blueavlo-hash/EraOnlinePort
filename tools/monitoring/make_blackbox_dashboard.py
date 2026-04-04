import json, urllib.request, base64

BASE = "http://127.0.0.1:3000"
auth = base64.b64encode(b"admin:L@ur3l-Gr4f-2026!").decode()
H = {"Content-Type": "application/json", "Authorization": f"Basic {auth}"}

def api(method, path, body=None):
    req = urllib.request.Request(f"{BASE}{path}",
        data=json.dumps(body).encode() if body else None,
        headers=H, method=method)
    try:
        resp = urllib.request.urlopen(req)
        return resp.status, json.loads(resp.read())
    except urllib.request.HTTPError as e:
        return e.code, e.read().decode()[:500]

DS = "cfbkwe3f0oydce"

def ts_panel(title, expr, y=0, x=0, w=24, h=8, unit="s", legend=True, min_val=0):
    defaults = {"unit": unit}
    if min_val is not None:
        defaults["min"] = min_val
    return {
        "type": "timeseries", "title": title,
        "gridPos": {"x": x, "y": y, "w": w, "h": h},
        "fieldConfig": {"defaults": defaults, "overrides": []},
        "options": {
            "legend": {"displayMode": "table" if legend else "hidden", "placement": "bottom"},
            "tooltip": {"mode": "multi"}
        },
        "targets": [{"datasource": {"uid": DS}, "expr": expr, "legendFormat": "{{instance}}", "refId": "A"}]
    }

def stat_panel(title, expr, y=0, x=0, w=4, h=4, unit="short", mappings=None, thresholds=None):
    th = thresholds or {"mode": "absolute", "steps": [{"color": "red", "value": None}, {"color": "green", "value": 1}]}
    return {
        "type": "stat", "title": title,
        "gridPos": {"x": x, "y": y, "w": w, "h": h},
        "fieldConfig": {"defaults": {"unit": unit, "thresholds": th, "mappings": mappings or []}},
        "options": {"reduceOptions": {"calcs": ["lastNotNull"]}, "colorMode": "background", "graphMode": "none", "textMode": "value"},
        "targets": [{"datasource": {"uid": DS}, "expr": expr, "legendFormat": " ", "refId": "A"}]
    }

def updown_mappings():
    return [{"type": "value", "options": {"0": {"text": "DOWN", "color": "red", "index": 0}, "1": {"text": "UP", "color": "green", "index": 1}}}]

def row_panel(title, y=0):
    return {"type": "row", "title": title, "gridPos": {"x": 0, "y": y, "w": 24, "h": 1}, "collapsed": False, "panels": []}

y = 0
panels = []

# ── Service Status Overview (collapsed) ──────────────────────────────────────
# All monitored services in a single collapsed row for at-a-glance health check

def collapsed_row(title, row_panels, y=0):
    return {
        "type": "row",
        "title": title,
        "gridPos": {"x": 0, "y": y, "w": 24, "h": 1},
        "collapsed": True,
        "panels": row_panels,
    }

_ov_panels = []
_oy = 0   # y within the collapsed row (relative positions)

# --- HTTP services block ---
for i, svc in enumerate(["authelia", "grafana", "searxng", "librespeed",
                          "filebrowser", "vaultwarden", "pihole-ftl", "loki"]):
    _ov_panels.append({
        "type": "stat", "title": svc,
        "gridPos": {"x": (i % 8) * 3, "y": _oy + (i // 8) * 4, "w": 3, "h": 4},
        "fieldConfig": {"defaults": {"unit": "short", "color": {"mode": "thresholds"},
            "thresholds": {"mode": "absolute", "steps": [{"color": "red", "value": None}, {"color": "green", "value": 1}]},
            "mappings": [{"type": "value", "options": {
                "0": {"text": "DOWN", "color": "red", "index": 0},
                "1": {"text": "UP", "color": "green", "index": 1}}}]}},
        "options": {"reduceOptions": {"calcs": ["lastNotNull"]}, "colorMode": "background",
                    "graphMode": "none", "textMode": "value"},
        "targets": [{"datasource": {"uid": DS},
                     "expr": f'max by() (probe_success{{job="blackbox_http",instance="{svc}"}})', "legendFormat": " ", "refId": "A"}]
    })
_oy += 4

# --- HTTPS vhosts ---
for i, (inst, label) in enumerate([
        ("grafana.home.lan", "grafana HTTPS"), ("auth.home.lan", "authelia HTTPS"),
        ("vault.home.lan", "vaultwarden HTTPS"), ("search.home.lan", "searxng HTTPS")]):
    _ov_panels.append({
        "type": "stat", "title": label,
        "gridPos": {"x": i * 6, "y": _oy, "w": 6, "h": 4},
        "fieldConfig": {"defaults": {"unit": "short", "color": {"mode": "thresholds"},
            "thresholds": {"mode": "absolute", "steps": [{"color": "red", "value": None}, {"color": "green", "value": 1}]},
            "mappings": [{"type": "value", "options": {
                "0": {"text": "DOWN", "color": "red", "index": 0},
                "1": {"text": "UP", "color": "green", "index": 1}}}]}},
        "options": {"reduceOptions": {"calcs": ["lastNotNull"]}, "colorMode": "background",
                    "graphMode": "none", "textMode": "value"},
        "targets": [{"datasource": {"uid": DS},
                     "expr": f'probe_success{{job="blackbox_https",instance="{inst}"}}', "legendFormat": " ", "refId": "A"}]
    })
_oy += 4

# --- TCP ports ---
for i, svc in enumerate(["ssh", "step-ca", "crowdsec-lapi", "nginx-https", "nginx-http"]):
    _ov_panels.append({
        "type": "stat", "title": f"TCP:{svc}",
        "gridPos": {"x": i * 4, "y": _oy, "w": 4, "h": 4},
        "fieldConfig": {"defaults": {"unit": "short", "color": {"mode": "thresholds"},
            "thresholds": {"mode": "absolute", "steps": [{"color": "red", "value": None}, {"color": "green", "value": 1}]},
            "mappings": [{"type": "value", "options": {
                "0": {"text": "CLOSED", "color": "red", "index": 0},
                "1": {"text": "OPEN", "color": "green", "index": 1}}}]}},
        "options": {"reduceOptions": {"calcs": ["lastNotNull"]}, "colorMode": "background",
                    "graphMode": "none", "textMode": "value"},
        "targets": [{"datasource": {"uid": DS},
                     "expr": f'probe_success{{job="blackbox_tcp",instance="{svc}"}}', "legendFormat": " ", "refId": "A"}]
    })
# CrowdSec bouncer health (uses crowdsec metrics if available)
_ov_panels.append({
    "type": "stat", "title": "CrowdSec Bouncer",
    "gridPos": {"x": 20, "y": _oy, "w": 4, "h": 4},
    "fieldConfig": {"defaults": {"unit": "short", "color": {"mode": "thresholds"},
        "thresholds": {"mode": "absolute", "steps": [{"color": "red", "value": None}, {"color": "green", "value": 1}]},
        "mappings": [{"type": "value", "options": {
            "0": {"text": "DOWN", "color": "red", "index": 0},
            "1": {"text": "UP", "color": "green", "index": 1}}}]}},
    "options": {"reduceOptions": {"calcs": ["lastNotNull"]}, "colorMode": "background",
                "graphMode": "none", "textMode": "value"},
    "targets": [{"datasource": {"uid": DS},
                 "expr": 'min(probe_success{job="blackbox_tcp",instance="crowdsec-lapi"})', "legendFormat": " ", "refId": "A"}]
})
_oy += 4

# --- DNS + Ping status ---
_ov_panels.append({
    "type": "stat", "title": "DNS (local)",
    "gridPos": {"x": 0, "y": _oy, "w": 4, "h": 4},
    "fieldConfig": {"defaults": {"unit": "short", "color": {"mode": "thresholds"},
        "thresholds": {"mode": "absolute", "steps": [{"color": "red", "value": None}, {"color": "green", "value": 1}]},
        "mappings": [{"type": "value", "options": {"0": {"text": "FAIL", "color": "red", "index": 0}, "1": {"text": "OK", "color": "green", "index": 1}}}]}},
    "options": {"reduceOptions": {"calcs": ["lastNotNull"]}, "colorMode": "background", "graphMode": "none"},
    "targets": [{"datasource": {"uid": DS}, "expr": 'probe_success{job="blackbox_dns",instance="pihole-dns-local"}', "legendFormat": " ", "refId": "A"}]
})
_ov_panels.append({
    "type": "stat", "title": "DNS (external)",
    "gridPos": {"x": 4, "y": _oy, "w": 4, "h": 4},
    "fieldConfig": {"defaults": {"unit": "short", "color": {"mode": "thresholds"},
        "thresholds": {"mode": "absolute", "steps": [{"color": "red", "value": None}, {"color": "green", "value": 1}]},
        "mappings": [{"type": "value", "options": {"0": {"text": "FAIL", "color": "red", "index": 0}, "1": {"text": "OK", "color": "green", "index": 1}}}]}},
    "options": {"reduceOptions": {"calcs": ["lastNotNull"]}, "colorMode": "background", "graphMode": "none"},
    "targets": [{"datasource": {"uid": DS}, "expr": 'probe_success{job="blackbox_dns",instance="pihole-dns-external"}', "legendFormat": " ", "refId": "A"}]
})
_ov_panels.append({
    "type": "stat", "title": "Ping GW1",
    "gridPos": {"x": 8, "y": _oy, "w": 4, "h": 4},
    "fieldConfig": {"defaults": {"unit": "short", "color": {"mode": "thresholds"},
        "thresholds": {"mode": "absolute", "steps": [{"color": "red", "value": None}, {"color": "green", "value": 1}]},
        "mappings": [{"type": "value", "options": {"0": {"text": "DOWN", "color": "red", "index": 0}, "1": {"text": "UP", "color": "green", "index": 1}}}]}},
    "options": {"reduceOptions": {"calcs": ["lastNotNull"]}, "colorMode": "background", "graphMode": "none"},
    "targets": [{"datasource": {"uid": DS}, "expr": 'probe_success{job="blackbox_icmp",instance="gateway-primary"}', "legendFormat": " ", "refId": "A"}]
})
_ov_panels.append({
    "type": "stat", "title": "Ping GW2",
    "gridPos": {"x": 12, "y": _oy, "w": 4, "h": 4},
    "fieldConfig": {"defaults": {"unit": "short", "color": {"mode": "thresholds"},
        "thresholds": {"mode": "absolute", "steps": [{"color": "red", "value": None}, {"color": "green", "value": 1}]},
        "mappings": [{"type": "value", "options": {"0": {"text": "DOWN", "color": "red", "index": 0}, "1": {"text": "UP", "color": "green", "index": 1}}}]}},
    "options": {"reduceOptions": {"calcs": ["lastNotNull"]}, "colorMode": "background", "graphMode": "none"},
    "targets": [{"datasource": {"uid": DS}, "expr": 'probe_success{job="blackbox_icmp",instance="gateway-services"}', "legendFormat": " ", "refId": "A"}]
})
_oy += 4

panels.append(collapsed_row("📊 Service Status Overview", _ov_panels, y))
y += 1

# ── Summary row (39 probes total; policy targets excluded from up/down counts) ─
# 8 panels × w=3 = 24
_summary = [
    {
        "type": "stat", "title": "Services Up",
        "gridPos": {"x": 0, "y": y, "w": 3, "h": 4},
        "fieldConfig": {"defaults": {"unit": "short", "color": {"mode": "thresholds"},
            "thresholds": {"mode": "absolute", "steps": [{"color": "red", "value": None}, {"color": "orange", "value": 1}, {"color": "green", "value": 36}]}}},
        "options": {"reduceOptions": {"calcs": ["lastNotNull"]}, "colorMode": "background", "graphMode": "none"},
        # 36 non-policy probes total (39 - 3 policy which are expected DOWN)
        "targets": [{"datasource": {"uid": DS}, "expr": 'count(probe_success{job!="blackbox_policy"} == 1)', "legendFormat": " ", "refId": "A"}]
    },
    {
        "type": "stat", "title": "Services Down",
        "gridPos": {"x": 3, "y": y, "w": 3, "h": 4},
        "fieldConfig": {"defaults": {"unit": "short", "color": {"mode": "thresholds"},
            "thresholds": {"mode": "absolute", "steps": [{"color": "green", "value": None}, {"color": "orange", "value": 1}, {"color": "red", "value": 2}]}}},
        "options": {"reduceOptions": {"calcs": ["lastNotNull"]}, "colorMode": "background", "graphMode": "none"},
        "targets": [{"datasource": {"uid": DS}, "expr": 'count(probe_success{job!="blackbox_policy"} == 0) or vector(0)', "legendFormat": " ", "refId": "A"}]
    },
    {
        "type": "stat", "title": "Policy Blocked",
        "gridPos": {"x": 6, "y": y, "w": 3, "h": 4},
        "fieldConfig": {"defaults": {"unit": "short", "color": {"mode": "thresholds"},
            # All 3 blocked = green; any accessible = red
            "thresholds": {"mode": "absolute", "steps": [{"color": "red", "value": None}, {"color": "orange", "value": 1}, {"color": "green", "value": 3}]}}},
        "options": {"reduceOptions": {"calcs": ["lastNotNull"]}, "colorMode": "background", "graphMode": "none"},
        "targets": [{"datasource": {"uid": DS}, "expr": 'count(probe_success{job="blackbox_policy"} == 0) or vector(0)', "legendFormat": " ", "refId": "A"}]
    },
    {
        "type": "stat", "title": "VPN",
        "gridPos": {"x": 9, "y": y, "w": 3, "h": 4},
        "fieldConfig": {"defaults": {"unit": "short", "color": {"mode": "thresholds"},
            "thresholds": {"mode": "absolute", "steps": [{"color": "red", "value": None}, {"color": "green", "value": 1}]},
            "mappings": [{"type": "value", "options": {"0": {"text": "DOWN", "color": "red"}, "1": {"text": "UP", "color": "green"}}}]}},
        "options": {"reduceOptions": {"calcs": ["lastNotNull"]}, "colorMode": "background", "graphMode": "none"},
        "targets": [{"datasource": {"uid": DS}, "expr": 'min(probe_success{job="blackbox_vpn"})', "legendFormat": " ", "refId": "A"}]
    },
    {
        "type": "gauge", "title": "Avg HTTP Response",
        "gridPos": {"x": 12, "y": y, "w": 3, "h": 4},
        "fieldConfig": {"defaults": {"unit": "ms", "min": 0, "max": 2000,
            "thresholds": {"mode": "absolute", "steps": [
                {"color": "green", "value": None},
                {"color": "orange", "value": 500},
                {"color": "red", "value": 1500}
            ]}}},
        "options": {"reduceOptions": {"calcs": ["lastNotNull"]}, "orientation": "auto",
                    "showThresholdLabels": False, "showThresholdMarkers": True},
        "targets": [{"datasource": {"uid": DS}, "expr": 'avg(probe_duration_seconds{job="blackbox_http"}) * 1000', "legendFormat": " ", "refId": "A"}]
    },
    {
        "type": "stat", "title": "Certs Expiring < 1d",
        "gridPos": {"x": 15, "y": y, "w": 3, "h": 4},
        "fieldConfig": {"defaults": {"unit": "short", "color": {"mode": "thresholds"},
            "thresholds": {"mode": "absolute", "steps": [{"color": "green", "value": None}, {"color": "orange", "value": 1}, {"color": "red", "value": 3}]}}},
        "options": {"reduceOptions": {"calcs": ["lastNotNull"]}, "colorMode": "background", "graphMode": "none"},
        "targets": [{"datasource": {"uid": DS}, "expr": 'count((probe_ssl_earliest_cert_expiry{job="blackbox_https"} - time()) / 86400 < 1) or vector(0)', "legendFormat": " ", "refId": "A"}]
    },
    {
        "type": "stat", "title": "DNS",
        "gridPos": {"x": 18, "y": y, "w": 3, "h": 4},
        "fieldConfig": {"defaults": {"unit": "short", "color": {"mode": "thresholds"},
            "thresholds": {"mode": "absolute", "steps": [{"color": "red", "value": None}, {"color": "green", "value": 1}]},
            "mappings": [{"type": "value", "options": {"0": {"text": "FAIL", "color": "red"}, "1": {"text": "OK", "color": "green"}}}]}},
        "options": {"reduceOptions": {"calcs": ["lastNotNull"]}, "colorMode": "background", "graphMode": "none"},
        "targets": [{"datasource": {"uid": DS}, "expr": 'min(probe_success{job="blackbox_dns"})', "legendFormat": " ", "refId": "A"}]
    },
    {
        "type": "stat", "title": "Ping",
        "gridPos": {"x": 21, "y": y, "w": 3, "h": 4},
        "fieldConfig": {"defaults": {"unit": "short", "color": {"mode": "thresholds"},
            "thresholds": {"mode": "absolute", "steps": [{"color": "red", "value": None}, {"color": "green", "value": 1}]},
            "mappings": [{"type": "value", "options": {"0": {"text": "FAIL", "color": "red"}, "1": {"text": "OK", "color": "green"}}}]}},
        "options": {"reduceOptions": {"calcs": ["lastNotNull"]}, "colorMode": "background", "graphMode": "none"},
        "targets": [{"datasource": {"uid": DS}, "expr": 'min(probe_success{job="blackbox_icmp"})', "legendFormat": " ", "refId": "A"}]
    },
]
panels.extend(_summary)
y += 4

# ── Security Services ────────────────────────────────────────────────────────
panels.append(row_panel("Security Services", y)); y += 1

panels.append({
    "type": "stat", "title": "Suricata IDS",
    "gridPos": {"x": 0, "y": y, "w": 6, "h": 4},
    "fieldConfig": {"defaults": {"unit": "short", "color": {"mode": "thresholds"},
        "thresholds": {"mode": "absolute", "steps": [{"color": "red", "value": None}, {"color": "green", "value": 1}]},
        "mappings": [{"type": "value", "options": {
            "0": {"text": "DOWN", "color": "red", "index": 0},
            "1": {"text": "UP", "color": "green", "index": 1}}}]}},
    "options": {"reduceOptions": {"calcs": ["lastNotNull"]}, "colorMode": "background", "graphMode": "none", "textMode": "value"},
    "targets": [{"datasource": {"uid": DS}, "expr": 'up{job="suricata"}', "legendFormat": " ", "refId": "A"}]
})
panels.append({
    "type": "stat", "title": "CrowdSec Bouncer",
    "gridPos": {"x": 6, "y": y, "w": 6, "h": 4},
    "fieldConfig": {"defaults": {"unit": "short", "color": {"mode": "thresholds"},
        "thresholds": {"mode": "absolute", "steps": [{"color": "red", "value": None}, {"color": "green", "value": 1}]},
        "mappings": [{"type": "value", "options": {
            "0": {"text": "DOWN", "color": "red", "index": 0},
            "1": {"text": "UP", "color": "green", "index": 1}}}]}},
    "options": {"reduceOptions": {"calcs": ["lastNotNull"]}, "colorMode": "background", "graphMode": "none", "textMode": "value"},
    "targets": [{"datasource": {"uid": DS}, "expr": 'min(probe_success{job="blackbox_tcp",instance="crowdsec-lapi"})', "legendFormat": " ", "refId": "A"}]
})
panels.append({
    "type": "timeseries", "title": "Security Service Uptime",
    "gridPos": {"x": 12, "y": y, "w": 12, "h": 4},
    "fieldConfig": {"defaults": {"unit": "short", "min": 0, "max": 1}, "overrides": []},
    "options": {"legend": {"displayMode": "table", "placement": "right"}, "tooltip": {"mode": "multi"}},
    "targets": [
        {"datasource": {"uid": DS}, "expr": 'up{job="suricata"}', "legendFormat": "Suricata", "refId": "A"},
        {"datasource": {"uid": DS}, "expr": 'probe_success{job="blackbox_tcp",instance="crowdsec-lapi"}', "legendFormat": "CrowdSec", "refId": "B"},
    ]
})
y += 4

# ── HTTP Services (collapsed) ─────────────────────────────────────────────────
_http = []
_hy = 0
for i, svc in enumerate(["authelia", "grafana", "searxng", "librespeed", "filebrowser", "vaultwarden", "pihole-ftl", "loki"]):
    _http.append({
        "type": "stat", "title": svc,
        "gridPos": {"x": (i % 8) * 3, "y": _hy + (i // 8) * 4, "w": 3, "h": 4},
        "fieldConfig": {"defaults": {"unit": "short", "color": {"mode": "thresholds"},
            "thresholds": {"mode": "absolute", "steps": [{"color": "red", "value": None}, {"color": "green", "value": 1}]},
            "mappings": updown_mappings()}},
        "options": {"reduceOptions": {"calcs": ["lastNotNull"]}, "colorMode": "background", "graphMode": "none", "textMode": "value"},
        "targets": [{"datasource": {"uid": DS}, "expr": f'max by() (probe_success{{job="blackbox_http",instance="{svc}"}})', "legendFormat": " ", "refId": "A"}]
    })
_hy += 4
_http.append(ts_panel("HTTP Response Time (ms)", 'probe_duration_seconds{job="blackbox_http"} * 1000', y=_hy, unit="ms"))
_hy += 8
_http.append(ts_panel("HTTP Service Availability", 'probe_success{job="blackbox_http"}', y=_hy, unit="short", h=6))
panels.append(collapsed_row("🌍 HTTP Services", _http, y)); y += 1

# ── TLS Certs (collapsed) ─────────────────────────────────────────────────────
_tls = []
_ty = 0
_tls.append({
    "type": "bargauge", "title": "Days Until Certificate Expiry",
    "gridPos": {"x": 0, "y": _ty, "w": 24, "h": 10},
    "fieldConfig": {"defaults": {"unit": "d", "min": 0, "max": 90,
        "thresholds": {"mode": "absolute", "steps": [
            {"color": "red", "value": None}, {"color": "orange", "value": 14},
            {"color": "yellow", "value": 30}, {"color": "green", "value": 60}
        ]}}},
    "options": {"reduceOptions": {"calcs": ["lastNotNull"]}, "orientation": "horizontal",
                "displayMode": "gradient", "valueMode": "color", "showUnfilled": True,
                "minVizWidth": 0, "minVizHeight": 10},
    "targets": [{"datasource": {"uid": DS},
        "expr": '(probe_ssl_earliest_cert_expiry{job="blackbox_https"} - time()) / 86400',
        "legendFormat": "{{instance}}", "refId": "A", "instant": True}]
})
_ty += 10
_tls.append(ts_panel("Cert Expiry Trend (days)", '(probe_ssl_earliest_cert_expiry{job="blackbox_https"} - time()) / 86400', y=_ty, unit="d", h=6))
_ty += 6
_tls.append(ts_panel("HTTPS Vhost Availability", 'probe_success{job="blackbox_https"}', y=_ty, unit="short", h=5))
panels.append(collapsed_row("🔐 TLS Certificate Expiry", _tls, y)); y += 1

# ── TCP (collapsed) ───────────────────────────────────────────────────────────
_tcp = []
_tpy = 0
for i, svc in enumerate(["ssh", "step-ca", "crowdsec-lapi", "nginx-https", "nginx-http"]):
    _tcp.append({
        "type": "stat", "title": svc,
        "gridPos": {"x": i * 4, "y": _tpy, "w": 4, "h": 4},
        "fieldConfig": {"defaults": {"unit": "short", "color": {"mode": "thresholds"},
            "thresholds": {"mode": "absolute", "steps": [{"color": "red", "value": None}, {"color": "green", "value": 1}]},
            "mappings": [{"type": "value", "options": {"0": {"text": "CLOSED", "color": "red"}, "1": {"text": "OPEN", "color": "green"}}}]}},
        "options": {"reduceOptions": {"calcs": ["lastNotNull"]}, "colorMode": "background", "graphMode": "none", "textMode": "value"},
        "targets": [{"datasource": {"uid": DS}, "expr": f'probe_success{{job="blackbox_tcp",instance="{svc}"}}', "legendFormat": " ", "refId": "A"}]
    })
_tpy += 4
_tcp.append(ts_panel("TCP Response Time (ms)", 'probe_duration_seconds{job="blackbox_tcp"} * 1000', y=_tpy, unit="ms", h=6))
panels.append(collapsed_row("🔌 TCP Port Checks", _tcp, y)); y += 1

# ── DNS Health (collapsed) ────────────────────────────────────────────────────
_dns_h = []
_dhy = 0
_dns_h.append({
    "type": "stat", "title": "Local DNS (.home.lan)",
    "gridPos": {"x": 0, "y": _dhy, "w": 6, "h": 4},
    "fieldConfig": {"defaults": {"unit": "short", "color": {"mode": "thresholds"},
        "thresholds": {"mode": "absolute", "steps": [{"color": "red", "value": None}, {"color": "green", "value": 1}]},
        "mappings": [{"type": "value", "options": {"0": {"text": "FAIL", "color": "red"}, "1": {"text": "OK", "color": "green"}}}]}},
    "options": {"reduceOptions": {"calcs": ["lastNotNull"]}, "colorMode": "background", "graphMode": "none"},
    "targets": [{"datasource": {"uid": DS}, "expr": 'probe_success{job="blackbox_dns",instance="pihole-dns-local"}', "legendFormat": " ", "refId": "A"}]
})
_dns_h.append({
    "type": "stat", "title": "External DNS (internet)",
    "gridPos": {"x": 6, "y": _dhy, "w": 6, "h": 4},
    "fieldConfig": {"defaults": {"unit": "short", "color": {"mode": "thresholds"},
        "thresholds": {"mode": "absolute", "steps": [{"color": "red", "value": None}, {"color": "green", "value": 1}]},
        "mappings": [{"type": "value", "options": {"0": {"text": "FAIL", "color": "red"}, "1": {"text": "OK", "color": "green"}}}]}},
    "options": {"reduceOptions": {"calcs": ["lastNotNull"]}, "colorMode": "background", "graphMode": "none"},
    "targets": [{"datasource": {"uid": DS}, "expr": 'probe_success{job="blackbox_dns",instance="pihole-dns-external"}', "legendFormat": " ", "refId": "A"}]
})
_dns_h.append(ts_panel("DNS Response Time (µs)", 'probe_duration_seconds{job="blackbox_dns"} * 1000000', y=_dhy, x=12, w=12, unit="µs", h=4, legend=False, min_val=None))
panels.append(collapsed_row("🌐 DNS Health", _dns_h, y)); y += 1

# ── ICMP (collapsed) ─────────────────────────────────────────────────────────
_icmp = []
_iy = 0
for i, (inst, label) in enumerate([("gateway-primary", "192.168.100.1"), ("gateway-services", "192.168.100.2")]):
    _icmp.append({
        "type": "gauge", "title": f"ping: {label}",
        "gridPos": {"x": i * 6, "y": _iy, "w": 6, "h": 6},
        "fieldConfig": {"defaults": {"unit": "µs", "min": 0, "max": 5000,
            "thresholds": {"mode": "absolute", "steps": [
                {"color": "green", "value": None},
                {"color": "orange", "value": 2000},
                {"color": "red", "value": 4000}
            ]}}},
        "options": {"reduceOptions": {"calcs": ["lastNotNull"]}, "orientation": "auto",
                    "showThresholdLabels": False, "showThresholdMarkers": True},
        "targets": [{"datasource": {"uid": DS}, "expr": f'probe_duration_seconds{{job="blackbox_icmp",instance="{inst}"}} * 1000000', "legendFormat": " ", "refId": "A"}]
    })
_icmp.append(ts_panel("Round-Trip Time (µs)", 'probe_duration_seconds{job="blackbox_icmp"} * 1000000', y=_iy, x=12, w=12, unit="µs", h=6, legend=False, min_val=None))
panels.append(collapsed_row("📡 ICMP / Ping", _icmp, y)); y += 1

# ── VPN Integrity ─────────────────────────────────────────────────────────────
_vpn = []
_vy = 0
for i, inst in enumerate(["cf-trace", "ifconfig-me"]):
    _vpn.append({
        "type": "stat", "title": inst,
        "gridPos": {"x": i * 6, "y": _vy, "w": 6, "h": 4},
        "fieldConfig": {"defaults": {"unit": "short", "color": {"mode": "thresholds"},
            "thresholds": {"mode": "absolute", "steps": [{"color": "red", "value": None}, {"color": "green", "value": 1}]},
            "mappings": [{"type": "value", "options": {"0": {"text": "DOWN", "color": "red", "index": 0}, "1": {"text": "UP", "color": "green", "index": 1}}}]}},
        "options": {"reduceOptions": {"calcs": ["lastNotNull"]}, "colorMode": "background", "graphMode": "none", "textMode": "value"},
        "targets": [{"datasource": {"uid": DS}, "expr": f'probe_success{{job="blackbox_vpn",instance="{inst}"}}', "legendFormat": " ", "refId": "A"}]
    })
_vpn.append({
    "type": "gauge", "title": "Avg Response",
    "gridPos": {"x": 12, "y": _vy, "w": 6, "h": 4},
    "fieldConfig": {"defaults": {"unit": "ms", "min": 0, "max": 3000,
        "thresholds": {"mode": "absolute", "steps": [
            {"color": "green", "value": None},
            {"color": "orange", "value": 800},
            {"color": "red", "value": 2000}
        ]}}},
    "options": {"reduceOptions": {"calcs": ["lastNotNull"]}, "orientation": "auto",
                "showThresholdLabels": False, "showThresholdMarkers": True},
    "targets": [{"datasource": {"uid": DS}, "expr": 'avg(probe_duration_seconds{job="blackbox_vpn"}) * 1000', "legendFormat": " ", "refId": "A"}]
})
_vy += 4
_vpn.append({
    "type": "timeseries", "title": "VPN Probe Latency",
    "gridPos": {"x": 0, "y": _vy, "w": 24, "h": 8},
    "fieldConfig": {"defaults": {"unit": "s", "min": 0}, "overrides": []},
    "options": {"legend": {"displayMode": "table", "placement": "bottom"}, "tooltip": {"mode": "multi"}},
    "targets": [{"datasource": {"uid": DS}, "expr": 'probe_duration_seconds{job="blackbox_vpn"}', "legendFormat": "{{instance}}", "refId": "A"}]
})
panels.append(collapsed_row("🔒 VPN Integrity", _vpn, y)); y += 1

# ── Policy Enforcement (Expected Failures) ────────────────────────────────────
_pol = []
_py = 0
for i, inst in enumerate(["facebook-graph", "doubleclick", "ads-google"]):
    _pol.append({
        "type": "stat", "title": inst,
        "gridPos": {"x": i * 8, "y": _py, "w": 8, "h": 4},
        "fieldConfig": {"defaults": {"unit": "short", "color": {"mode": "thresholds"},
            "thresholds": {"mode": "absolute", "steps": [{"color": "green", "value": None}, {"color": "red", "value": 1}]},
            "mappings": [{"type": "value", "options": {
                "0": {"text": "BLOCKED ✓", "color": "green", "index": 0},
                "1": {"text": "ACCESSIBLE ✗", "color": "red", "index": 1}}}]}},
        "options": {"reduceOptions": {"calcs": ["lastNotNull"]}, "colorMode": "background", "graphMode": "none", "textMode": "value"},
        "targets": [{"datasource": {"uid": DS}, "expr": f'probe_success{{job="blackbox_policy",instance="{inst}"}}', "legendFormat": " ", "refId": "A"}]
    })
_py += 4
_pol.append({
    "type": "timeseries", "title": "Policy Targets — Probe Success Over Time (expect 0)",
    "gridPos": {"x": 0, "y": _py, "w": 24, "h": 8},
    "fieldConfig": {"defaults": {"unit": "short", "min": 0, "max": 1}, "overrides": []},
    "options": {"legend": {"displayMode": "table", "placement": "bottom"}, "tooltip": {"mode": "multi"}},
    "targets": [{"datasource": {"uid": DS}, "expr": 'probe_success{job="blackbox_policy"}', "legendFormat": "{{instance}}", "refId": "A"}]
})
panels.append(collapsed_row("🛡️ Policy Enforcement (Expected Failures)", _pol, y)); y += 1

# ── Network Stability ─────────────────────────────────────────────────────────
_stab = []
_sy = 0
for i, (inst, label) in enumerate([("cloudflare-dns", "1.1.1.1"), ("google-dns", "8.8.8.8"), ("quad9", "9.9.9.9")]):
    _stab.append({
        "type": "stat", "title": label,
        "gridPos": {"x": i * 8, "y": _sy, "w": 8, "h": 4},
        "fieldConfig": {"defaults": {"unit": "short", "color": {"mode": "thresholds"},
            "thresholds": {"mode": "absolute", "steps": [{"color": "red", "value": None}, {"color": "green", "value": 1}]},
            "mappings": [{"type": "value", "options": {"0": {"text": "DOWN", "color": "red", "index": 0}, "1": {"text": "UP", "color": "green", "index": 1}}}]}},
        "options": {"reduceOptions": {"calcs": ["lastNotNull"]}, "colorMode": "background", "graphMode": "none", "textMode": "value"},
        "targets": [{"datasource": {"uid": DS}, "expr": f'probe_success{{job="blackbox_stability",instance="{inst}"}}', "legendFormat": " ", "refId": "A"}]
    })
_sy += 4
_stab.append({
    "type": "timeseries", "title": "ICMP Latency (ms) — Jitter & Spikes",
    "gridPos": {"x": 0, "y": _sy, "w": 24, "h": 8},
    "fieldConfig": {"defaults": {"unit": "ms", "min": 0}, "overrides": []},
    "options": {"legend": {"displayMode": "table", "placement": "bottom"}, "tooltip": {"mode": "multi"}},
    "targets": [{"datasource": {"uid": DS}, "expr": 'probe_duration_seconds{job="blackbox_stability"} * 1000', "legendFormat": "{{instance}}", "refId": "A"}]
})
panels.append(collapsed_row("📶 Network Stability", _stab, y)); y += 1

# ── DNS Integrity ─────────────────────────────────────────────────────────────
_dns = []
_dy = 0
dns_targets = [
    ("dns-google-com", "google.com (resolve)", False),
    ("dns-nxdomain",   "nonexistentdomain.test (NXDOMAIN)", False),
    ("dns-block-check","doubleclick.net (Pi-hole block)", False),
]
for i, (inst, label, invert) in enumerate(dns_targets):
    # invert=False: green=1(success). For nxdomain a DNS response is still success=1.
    _dns.append({
        "type": "stat", "title": label,
        "gridPos": {"x": i * 8, "y": _dy, "w": 8, "h": 4},
        "fieldConfig": {"defaults": {"unit": "short", "color": {"mode": "thresholds"},
            "thresholds": {"mode": "absolute", "steps": [{"color": "red", "value": None}, {"color": "green", "value": 1}]},
            "mappings": [{"type": "value", "options": {"0": {"text": "FAIL", "color": "red", "index": 0}, "1": {"text": "OK", "color": "green", "index": 1}}}]}},
        "options": {"reduceOptions": {"calcs": ["lastNotNull"]}, "colorMode": "background", "graphMode": "none", "textMode": "value"},
        "targets": [{"datasource": {"uid": DS}, "expr": f'probe_success{{job="blackbox_dns_integrity",instance="{inst}"}}', "legendFormat": " ", "refId": "A"}]
    })
_dy += 4
_dns.append({
    "type": "timeseries", "title": "DNS Response Time (ms)",
    "gridPos": {"x": 0, "y": _dy, "w": 24, "h": 8},
    "fieldConfig": {"defaults": {"unit": "ms", "min": 0}, "overrides": []},
    "options": {"legend": {"displayMode": "table", "placement": "bottom"}, "tooltip": {"mode": "multi"}},
    "targets": [{"datasource": {"uid": DS}, "expr": 'probe_duration_seconds{job="blackbox_dns_integrity"} * 1000', "legendFormat": "{{instance}}", "refId": "A"}]
})
panels.append(collapsed_row("🔍 DNS Integrity", _dns, y)); y += 1

# ── External Reality (Canary Checks) ─────────────────────────────────────────
_ext = []
_ey = 0
for i, (inst, label) in enumerate([("cloudflare", "cloudflare.com"), ("google", "google.com"), ("amazon", "amazon.com")]):
    _ext.append({
        "type": "stat", "title": label,
        "gridPos": {"x": i * 8, "y": _ey, "w": 8, "h": 4},
        "fieldConfig": {"defaults": {"unit": "short", "color": {"mode": "thresholds"},
            "thresholds": {"mode": "absolute", "steps": [{"color": "red", "value": None}, {"color": "green", "value": 1}]},
            "mappings": [{"type": "value", "options": {"0": {"text": "DOWN", "color": "red", "index": 0}, "1": {"text": "UP", "color": "green", "index": 1}}}]}},
        "options": {"reduceOptions": {"calcs": ["lastNotNull"]}, "colorMode": "background", "graphMode": "none", "textMode": "value"},
        "targets": [{"datasource": {"uid": DS}, "expr": f'probe_success{{job="blackbox_external",instance="{inst}"}}', "legendFormat": " ", "refId": "A"}]
    })
_ey += 4
_ext.append({
    "type": "timeseries", "title": "Canary Latency Comparison (ms)",
    "gridPos": {"x": 0, "y": _ey, "w": 24, "h": 8},
    "fieldConfig": {"defaults": {"unit": "ms", "min": 0}, "overrides": []},
    "options": {"legend": {"displayMode": "table", "placement": "bottom"}, "tooltip": {"mode": "multi"}},
    "targets": [{"datasource": {"uid": DS}, "expr": 'probe_duration_seconds{job="blackbox_external"} * 1000', "legendFormat": "{{instance}}", "refId": "A"}]
})
panels.append(collapsed_row("🌐 External Reality (Canary Checks)", _ext, y)); y += 1

# ── Advanced Routing / Path Validation ───────────────────────────────────────
_rte = []
_ry = 0
_rte.append({
    "type": "stat", "title": "Internal Gateway",
    "gridPos": {"x": 0, "y": _ry, "w": 6, "h": 4},
    "fieldConfig": {"defaults": {"unit": "short", "color": {"mode": "thresholds"},
        "thresholds": {"mode": "absolute", "steps": [{"color": "red", "value": None}, {"color": "green", "value": 1}]},
        "mappings": [{"type": "value", "options": {"0": {"text": "DOWN", "color": "red", "index": 0}, "1": {"text": "UP", "color": "green", "index": 1}}}]}},
    "options": {"reduceOptions": {"calcs": ["lastNotNull"]}, "colorMode": "background", "graphMode": "none", "textMode": "value"},
    "targets": [{"datasource": {"uid": DS}, "expr": 'probe_success{job="blackbox_icmp"}', "legendFormat": " ", "refId": "A"}]
})
_rte.append({
    "type": "stat", "title": "External (via VPN)",
    "gridPos": {"x": 6, "y": _ry, "w": 6, "h": 4},
    "fieldConfig": {"defaults": {"unit": "short", "color": {"mode": "thresholds"},
        "thresholds": {"mode": "absolute", "steps": [{"color": "red", "value": None}, {"color": "green", "value": 1}]},
        "mappings": [{"type": "value", "options": {"0": {"text": "DOWN", "color": "red", "index": 0}, "1": {"text": "UP", "color": "green", "index": 1}}}]}},
    "options": {"reduceOptions": {"calcs": ["lastNotNull"]}, "colorMode": "background", "graphMode": "none", "textMode": "value"},
    "targets": [{"datasource": {"uid": DS}, "expr": 'min(probe_success{job="blackbox_stability"})', "legendFormat": " ", "refId": "A"}]
})
_ry += 4
_rte.append({
    "type": "timeseries", "title": "Latency Comparison: Internal vs External Path (ms)",
    "gridPos": {"x": 0, "y": _ry, "w": 24, "h": 8},
    "fieldConfig": {"defaults": {"unit": "ms", "min": 0}, "overrides": []},
    "options": {"legend": {"displayMode": "table", "placement": "bottom"}, "tooltip": {"mode": "multi"}},
    "targets": [
        {"datasource": {"uid": DS}, "expr": 'probe_duration_seconds{job="blackbox_icmp"} * 1000', "legendFormat": "internal: {{instance}}", "refId": "A"},
        {"datasource": {"uid": DS}, "expr": 'probe_duration_seconds{job="blackbox_stability"} * 1000', "legendFormat": "external: {{instance}}", "refId": "B"},
    ]
})
panels.append(collapsed_row("🗺️ Advanced Routing / Path Validation", _rte, y)); y += 1

# ── Push to Grafana ───────────────────────────────────────────────────────────
dashboard = {
    "uid": "service-probes",
    "title": "Service Probes",
    "tags": ["blackbox", "probes", "uptime", "ssl"],
    "timezone": "browser",
    "schemaVersion": 39,
    "refresh": "30s",
    "time": {"from": "now-3h", "to": "now"},
    "panels": panels
}

status, r = api("POST", "/api/dashboards/db", {
    "dashboard": dashboard,
    "overwrite": True,
    "folderId": 0,
    "message": "full blackbox dashboard"
})
print(f"status: {status}")
if isinstance(r, dict):
    print(f"url: {r.get('url', 'n/a')}")
    print(f"version: {r.get('version', 'n/a')}")
else:
    print(r)
