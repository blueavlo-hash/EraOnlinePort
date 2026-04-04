#!/usr/bin/env python3
"""
suricata-exporter - Prometheus metrics from Suricata counters via suricatasc.
Serves /metrics on 0.0.0.0:9917
"""
import json
import re
import subprocess
from http.server import BaseHTTPRequestHandler, HTTPServer

LISTEN_PORT = 9917
SOCKET_PATH = "/var/run/suricata/suricata-command.socket"

# Aliases for dashboard compatibility (dashboard name -> exporter source name)
DASHBOARD_ALIASES = {
    "suricata_uptime_seconds":         "suricata_uptime",
    "suricata_packets_accepted_total": "suricata_ips_accepted",
    "suricata_packets_blocked_total":  "suricata_ips_blocked",
    "suricata_packets_rejected_total": "suricata_ips_rejected",
    "suricata_alerts_total":           "suricata_detect_alert",
    "suricata_flows_active":           "suricata_flow_active",
    "suricata_flows_total":            "suricata_flow_total",
    "suricata_drops_rules_total":      "suricata_ips_drop_reason_rules",
}


def _flatten(obj, prefix=""):
    items = {}
    for k, v in obj.items():
        key = f"{prefix}.{k}" if prefix else k
        if isinstance(v, dict):
            items.update(_flatten(v, key))
        elif isinstance(v, (int, float)):
            items[key] = v
    return items


def fetch_metrics():
    try:
        result = subprocess.run(
            ["suricatasc", "-c", "dump-counters", SOCKET_PATH],
            capture_output=True, text=True, timeout=10
        )
        data = json.loads(result.stdout)
        if data.get("return") != "OK":
            return None, f"suricatasc error: {data}"
        return _flatten(data["message"]), None
    except Exception as e:
        return None, str(e)


def render_prometheus(counters):
    lines = ["# HELP suricata_counter Suricata internal counter",
             "# TYPE suricata_counter gauge"]
    flat = {}
    for key, value in sorted(counters.items()):
        metric = "suricata_" + re.sub(r"[^a-zA-Z0-9_]", "_", key).lower()
        lines.append(f"{metric} {value}")
        flat[metric] = value

    # Append dashboard-expected aliases
    for alias, source in DASHBOARD_ALIASES.items():
        if source in flat:
            lines.append(f"{alias} {flat[source]}")

    return "\n".join(lines) + "\n"


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path not in ("/metrics", "/metrics/"):
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"suricata-exporter: GET /metrics\n")
            return
        counters, err = fetch_metrics()
        if err:
            body = f"# ERROR: {err}\n".encode()
            self.send_response(500)
        else:
            body = render_prometheus(counters).encode()
            self.send_response(200)
        self.send_header("Content-Type", "text/plain; version=0.0.4")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        pass


if __name__ == "__main__":
    print(f"[suricata-exporter] listening on :{LISTEN_PORT}", flush=True)
    HTTPServer(("", LISTEN_PORT), Handler).serve_forever()
