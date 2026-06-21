# Grafana Dashboard Plan

> Owner: Person C

---

## Dashboard 1: Node Exporter Full (ID 1860)

Import from Grafana dashboard registry — ID **1860**.

**Customizations after import:**
- Rename instance labels from auto-detected to match `docs/targets.txt` hostnames
- Set dashboard refresh to **30s**
- Add team name variable: `team = linux-monitoring`
- Add environment variable: `environment = production`
- Filter out irrelevant panels (e.g., hardware-specific panels not applicable to VMs)

**Key panels to verify:**
| Panel | Metric | Expected value |
|-------|--------|----------------|
| CPU Usage | `node_cpu_seconds_total` | 0–100% |
| Memory Available | `node_memory_MemAvailable_bytes` | > 0 |
| Disk Usage | `node_filesystem_avail_bytes` | > 0 |
| Network I/O | `node_network_*_bytes_total` | Bytes/s |
| System Load | `node_load1`, `node_load5`, `node_load15` | Normalized per core |

---

## Dashboard 2: Overview Dashboard (Custom)

**Layout:** One row per monitored server.

**Panels per server row:**

| Panel | Type | Metric | Thresholds |
|-------|------|--------|------------|
| CPU % | Stat | `(1 - avg(rate(node_cpu_seconds_total{mode="idle",instance="$instance"}[5m]))) * 100` | Green <80, Amber 80–95, Red >95 |
| Memory Available % | Stat | `node_memory_MemAvailable_bytes{instance="$instance"} / node_memory_MemTotal_bytes{instance="$instance"} * 100` | Red <5, Amber 5–15, Green >15 |
| Root Disk Used % | Stat | `(node_filesystem_size_bytes{mountpoint="/",instance="$instance"} - node_filesystem_avail_bytes{mountpoint="/",instance="$instance"}) / node_filesystem_size_bytes{mountpoint="/",instance="$instance"} * 100` | Green <80, Amber 80–95, Red >95 |
| Uptime | Stat | `node_time_seconds{instance="$instance"} - node_boot_time_seconds{instance="$instance"}` | No threshold |

**Variables:**
- `$instance` — multi-value variable from `label_values(up, instance)`
- `$job` — `node`

---

## Prometheus Data Source

- Name: `Prometheus`
- URL: `http://localhost:9090`
- Access: Proxy
- Default: Yes
- HTTP Method: POST
- Scrape interval: 15s

This is auto-provisioned via `grafana/provisioning/datasources/prometheus.yml`.

---

## Dashboard JSON Export

Export all dashboards as JSON to `grafana/dashboards/`:
- `grafana/dashboards/overview.json`
- `grafana/dashboards/node_exporter.json`

Dashboards are auto-loaded by Grafana via `grafana/provisioning/dashboards/dashboards.yml`.

---

*Last updated: 2026-06-21 | Owner: Person C*
