# Linux Monitoring Stack — Complete Reference

Everything you need to know about Node Exporter, Prometheus, Alertmanager, and Grafana.
Architecture, concepts, production, deployment, security, troubleshooting.

---

## Table of Contents

1. [The Big Picture — How Everything Connects](#1-the-big-picture)
2. [Node Exporter](#2-node-exporter)
3. [Prometheus](#3-prometheus)
4. [PromQL — The Query Language](#4-promql)
5. [Alert Rules](#5-alert-rules)
6. [Alertmanager](#6-alertmanager)
7. [Grafana](#7-grafana)
8. [Production Deployment](#8-production-deployment)
9. [Security Hardening](#9-security-hardening)
10. [Troubleshooting](#10-troubleshooting)
11. [Backup and Recovery](#11-backup-and-recovery)
12. [Common Pitfalls](#12-common-pitfalls)
13. [Quick Reference — All Commands](#13-quick-reference)

---

## 1. The Big Picture

### What problem does this stack solve?

Without monitoring you find out a server is down when a user complains. With this stack you find out within 2 minutes, automatically, before anyone notices.

### The data flow — end to end

```
Linux Server
   │
   │  Node Exporter reads /proc and /sys (the kernel's own files)
   │  and serves them as text over HTTP on port 9100
   │
   ▼
http://<server>:9100/metrics
   │
   │  Prometheus scrapes this URL every 15 seconds
   │  and stores the numbers as time-series in its database
   │
   ▼
Prometheus :9090
   │
   │  Prometheus continuously evaluates your alert rules.
   │  When a condition is true long enough, it fires an alert
   │  and sends it to Alertmanager via HTTP POST
   │
   ▼
Alertmanager :9093
   │
   │  Alertmanager groups related alerts together,
   │  deduplicates them, applies silences and inhibitions,
   │  then sends ONE notification instead of a flood
   │
   ▼
Email / Slack / Webhook
   │
   │  Grafana connects to Prometheus as a read-only data source
   │  and renders live dashboards — it does NOT store data itself
   │
   ▼
Grafana :3000  ◀──────────── reads from ──────────── Prometheus
```

### Who does what — one sentence each

| Component | One job |
|-----------|---------|
| Node Exporter | Reads the OS and serves raw numbers |
| Prometheus | Stores those numbers and fires alerts |
| Alertmanager | Decides WHO gets notified and WHEN |
| Grafana | Draws graphs from Prometheus data |

### The pull model (why Prometheus is different from most monitoring)

Most old monitoring tools push data — agents send metrics to a central server. Prometheus does the opposite: the central server **pulls** (scrapes) metrics from each target. This means:
- Targets don't need to know where Prometheus is
- You can see exactly what data Prometheus is getting (just curl the metrics URL)
- Adding a new target is one line in `prometheus.yml` — no agent config needed on the target

---

## 2. Node Exporter

### What it is

A single binary that reads Linux kernel files (`/proc`, `/sys`) and serves them as Prometheus-formatted text. Nothing more. It doesn't send data anywhere — it waits to be scraped.

### How it works

The Linux kernel exposes system state through virtual files:
- `/proc/stat` → CPU time per mode (idle, user, system, iowait...)
- `/proc/meminfo` → memory breakdown (total, free, available, buffers, cached...)
- `/proc/diskstats` → disk read/write counts and times per device
- `/proc/net/dev` → network bytes and packets per interface
- `/sys/class/net/*/carrier` → whether each network interface has a link

Node Exporter reads these files and converts them to the Prometheus text format:
```
node_cpu_seconds_total{cpu="0",mode="idle"} 12345.67
node_memory_MemAvailable_bytes 2147483648
node_filesystem_avail_bytes{device="/dev/sda1",mountpoint="/"} 10737418240
```

### The metrics you actually use

**CPU:**
```
node_cpu_seconds_total{mode="idle"}     # seconds spent idle per CPU core
node_cpu_seconds_total{mode="iowait"}   # seconds spent waiting for I/O
node_cpu_seconds_total{mode="user"}     # seconds in user-space processes
node_cpu_seconds_total{mode="system"}   # seconds in kernel
node_load1                              # 1-minute load average
node_load5                              # 5-minute load average
node_load15                             # 15-minute load average
```

**Memory:**
```
node_memory_MemTotal_bytes              # total installed RAM
node_memory_MemAvailable_bytes          # RAM available without swapping
node_memory_MemFree_bytes               # truly free (not counting cache)
node_memory_SwapTotal_bytes             # total swap
node_memory_SwapFree_bytes              # unused swap
node_vmstat_oom_kill                    # cumulative OOM kill count
```

**Disk:**
```
node_filesystem_size_bytes{mountpoint="/"}       # partition total size
node_filesystem_avail_bytes{mountpoint="/"}      # space available
node_filesystem_files{mountpoint="/"}            # total inodes
node_filesystem_files_free{mountpoint="/"}       # free inodes
node_disk_reads_completed_total{device="sda"}    # total read operations
node_disk_read_time_seconds_total{device="sda"}  # total time spent reading
node_disk_writes_completed_total                 # total write operations
node_disk_write_time_seconds_total               # total time spent writing
```

**Network:**
```
node_network_receive_bytes_total{device="eth0"}   # bytes received
node_network_transmit_bytes_total{device="eth0"}  # bytes sent
node_network_receive_errs_total                   # receive errors
node_network_transmit_errs_total                  # transmit errors
node_network_carrier{device="eth0"}               # 1=link up, 0=link down
```

**System:**
```
up                                      # 1 if Prometheus can reach this target
node_time_seconds                       # current Unix timestamp on the host
node_boot_time_seconds                  # Unix timestamp of last boot
node_procs_zombie                       # current zombie process count
node_filefd_allocated                   # open file descriptors
node_filefd_maximum                     # system fd limit
node_timex_offset_seconds               # NTP clock offset
```

### Why `MemAvailable` not `MemFree`

`MemFree` means truly unused RAM. But Linux aggressively uses free RAM for disk cache to speed up reads — this looks like "used" memory but Linux will reclaim it instantly when an application needs it.

`MemAvailable` is the kernel's own estimate of how much RAM can actually be given to new processes, counting both truly free memory AND reclaimable cache. **Always use `MemAvailable` for alerting** — `MemFree` will fire false alarms constantly.

### Installation location

```
/usr/local/bin/node_exporter          # the binary
/etc/systemd/system/node_exporter.service   # systemd unit file
```

No config file needed — it runs with defaults.

---

## 3. Prometheus

### What it is

A time-series database + scrape engine + rule evaluator + alerting engine, all in one binary. It pulls metrics from targets, stores them, evaluates your alert rules against them, and fires alerts to Alertmanager.

### Time-series data model

Every metric in Prometheus is a **time-series**: a stream of (timestamp, value) pairs identified by a name and a set of labels.

```
metric_name{label1="value1", label2="value2"}  →  value at timestamp
```

Example:
```
node_cpu_seconds_total{instance="server-1:9100", job="node", cpu="0", mode="idle"}  →  12345.67
node_cpu_seconds_total{instance="server-1:9100", job="node", cpu="0", mode="user"}  →  456.78
node_cpu_seconds_total{instance="server-1:9100", job="node", cpu="1", mode="idle"}  →  11234.56
```

The same metric name with different label combinations are different time-series. This is what makes Prometheus powerful — you can filter, aggregate, and calculate across any label dimension.

### The `instance` and `job` labels

Prometheus automatically adds two labels to every scraped metric:
- `job` — the name of the scrape job in `prometheus.yml` (e.g., `"node"`)
- `instance` — the target address (e.g., `"192.168.1.10:9100"`)

These are how you identify which server a metric came from.

### prometheus.yml structure

```yaml
global:
  scrape_interval: 15s        # how often to scrape targets
  evaluation_interval: 15s    # how often to evaluate alert rules

alerting:
  alertmanagers:              # where to send fired alerts
    - static_configs:
        - targets: ['localhost:9093']

rule_files:                   # alert rule files to load
  - "rules/*.yml"

scrape_configs:               # what to scrape
  - job_name: 'node'
    static_configs:
      - targets: ['server1:9100', 'server2:9100']
```

### Storage (TSDB)

Prometheus uses its own time-series database (TSDB) on local disk at `/var/lib/prometheus/`.

Key points:
- Data is stored in 2-hour blocks, then compacted into larger blocks
- Default retention is **15 days** (set by `--storage.tsdb.retention.time=15d`)
- Disk usage: roughly 1–3 bytes per sample. At 15s scrape interval with 500 metrics per target, expect ~100MB/day per target
- Prometheus is NOT designed for long-term storage — for that, use Thanos or Cortex

### The `up` metric

Every scrape job automatically creates an `up` metric:
- `up{job="node", instance="server:9100"} = 1` → scrape succeeded
- `up{job="node", instance="server:9100"} = 0` → scrape failed (server down, Node Exporter stopped, etc.)

This is what `InstanceDown` alerts on.

### Reloading config without restart

```bash
sudo systemctl reload prometheus        # sends SIGHUP
# OR
curl -X POST http://localhost:9090/-/reload
```

### Useful API endpoints

```bash
# Health check
curl http://localhost:9090/-/healthy

# Current config
curl http://localhost:9090/api/v1/status/config

# All targets and their state
curl http://localhost:9090/api/v1/targets | python3 -m json.tool

# All active alerts
curl http://localhost:9090/api/v1/alerts

# Run a PromQL query
curl 'http://localhost:9090/api/v1/query?query=up'
```

### File locations

```
/usr/local/bin/prometheus              # main binary
/usr/local/bin/promtool               # validation tool
/etc/prometheus/prometheus.yml        # main config
/etc/prometheus/rules/                # alert rule files
/var/lib/prometheus/                  # TSDB data directory
/etc/systemd/system/prometheus.service
```

---

## 4. PromQL

PromQL (Prometheus Query Language) is what you write in alert rules and Grafana panels. Understanding it is the key to the whole system.

### The two fundamental metric types you need to know

**Gauge** — a value that goes up and down freely. Snapshots of current state.
```
node_memory_MemAvailable_bytes    # current available memory
node_procs_zombie                 # current zombie count
node_load1                        # current load average
```
Use gauges directly: `node_load1 > 2`

**Counter** — a value that only ever increases (resets to 0 on restart). Total cumulative count.
```
node_cpu_seconds_total            # total CPU seconds ever spent in idle
node_network_receive_bytes_total  # total bytes ever received
```
Never alert on counters directly — their raw value is meaningless for thresholds.
**Always wrap counters in `rate()` or `increase()`** to get the per-second rate or total increase.

### `rate()` — the most important function

`rate(metric[5m])` gives you the per-second average rate of increase over the last 5 minutes.

```promql
# CPU usage % (rate of non-idle time)
(1 - avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m]))) * 100

# Network receive Mbps
rate(node_network_receive_bytes_total[5m]) * 8 / 1000000
```

The `[5m]` is the **range vector** — how far back to look. Common values: `[1m]`, `[5m]`, `[15m]`. Longer ranges smooth out spikes.

### `increase()` — total increase over a window

`increase(metric[5m])` gives you the total increase over the last 5 minutes (not per-second).

```promql
# Did any OOM kills happen in the last 5 minutes?
increase(node_vmstat_oom_kill[5m]) > 0

# Did scrape errors increase in the last 5 minutes?
increase(scrape_errors_total[5m]) > 0
```

### Aggregation — combining multiple time-series

```promql
# Average CPU usage across ALL instances (collapses to one number)
avg(rate(node_cpu_seconds_total{mode="idle"}[5m]))

# Average CPU usage PER instance (one result per instance)
avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m]))

# Sum of network bytes across all interfaces on each instance
sum by(instance) (rate(node_network_receive_bytes_total[5m]))

# Count how many CPU cores each instance has
count by(instance) (node_cpu_seconds_total{mode="idle"})
```

### Label filtering

```promql
# Only the idle mode
node_cpu_seconds_total{mode="idle"}

# Exclude tmpfs and devtmpfs from disk metrics
node_filesystem_size_bytes{fstype!~"tmpfs|devtmpfs"}

# Only eth0 interface
node_network_receive_bytes_total{device="eth0"}

# Only a specific instance
node_load1{instance="server-1:9100"}
```

`=` exact match, `!=` not equal, `=~` regex match, `!~` regex not match

### `predict_linear()` — forecasting

```promql
# Will this disk run out of space within 4 hours?
predict_linear(node_filesystem_avail_bytes{fstype!~"tmpfs|devtmpfs"}[1h], 4*3600) < 0
```

Fits a linear regression over the last 1 hour of data, extrapolates 4 hours (4×3600 seconds) forward. Returns the predicted future value. If negative → disk will be full.

### `abs()` — absolute value

```promql
# Clock offset more than 50ms in either direction
abs(node_timex_offset_seconds) > 0.05
```

### Binary operations between metrics

```promql
# Memory available as a percentage
node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes * 100

# Disk used percentage
(node_filesystem_size_bytes - node_filesystem_avail_bytes) / node_filesystem_size_bytes * 100

# Load average per core
node_load15 / count by(instance) (node_cpu_seconds_total{mode="idle"})
```

### The `for` clause — persistence window

In alert rules, `for: 2m` means the condition must be continuously true for 2 minutes before the alert fires. During those 2 minutes the alert is in PENDING state.

Why this matters: without `for`, a single bad scrape (network hiccup, 1-second CPU spike) fires an alert. With `for: 2m`, transient blips are ignored.

Trade-off: longer `for` = fewer false positives, but slower detection. Critical alerts should have short `for` (or none). Warnings can have longer `for`.

---

## 5. Alert Rules

### File structure

```yaml
groups:
  - name: cpu_alerts          # group name — for organization
    rules:
      - alert: HighCPUWarning   # alert name — appears in notifications
        expr: <promql>          # the condition
        for: 2m                 # how long it must be true
        labels:
          severity: warning     # custom labels attached to the alert
        annotations:
          summary: "..."        # short description
          description: "..."    # longer description with template values
```

### Alert states

```
INACTIVE → not firing, condition is false
PENDING  → condition is true, but "for" duration not yet reached
FIRING   → condition has been true for the full "for" duration
```

Prometheus sends the alert to Alertmanager only when it enters FIRING state.

When the condition becomes false, the alert goes back to INACTIVE and Alertmanager sends a "RESOLVED" notification (if `send_resolved: true`).

### Template variables in annotations

```yaml
annotations:
  summary: "High CPU on {{ $labels.instance }}"
  description: "CPU is {{ $value | printf \"%.1f\" }}%"
```

- `$labels.instance` → the instance label value (e.g., `"server-1:9100"`)
- `$labels.job` → the job label value
- `$labels.severity` → the severity label you set
- `$value` → the numeric value that triggered the alert
- `printf "%.1f"` → format to 1 decimal place
- `humanize` → convert bytes to human-readable (1.5GB)
- `humanizeDuration` → convert seconds to "5m 30s"

### Validating rule files

```bash
# Validate syntax before loading into Prometheus
promtool check rules /etc/prometheus/rules/cpu.yml
promtool check rules /etc/prometheus/rules/*.yml

# Validate the whole prometheus.yml (including rule files referenced in it)
promtool check config /etc/prometheus/prometheus.yml
```

**Always validate before reloading.** A syntax error in a rule file prevents Prometheus from loading ANY rule files.

### Loading rules into Prometheus

Rule files in `/etc/prometheus/rules/` are loaded at startup. After adding or changing rules:

```bash
# Copy new rule file
sudo cp prometheus/rules/cpu.yml /etc/prometheus/rules/
sudo chown prometheus:prometheus /etc/prometheus/rules/cpu.yml

# Validate
promtool check config /etc/prometheus/prometheus.yml

# Reload (no downtime)
sudo systemctl reload prometheus

# Verify at the UI
# http://localhost:9090/alerts — should show all your rules
```

---

## 6. Alertmanager

### What it is NOT

Alertmanager does NOT detect problems. That's Prometheus's job. Alertmanager only handles what happens AFTER Prometheus has decided an alert is firing.

### What it IS

A notification routing engine. Prometheus can fire 50 alerts for the same dead server (InstanceDown, HighCPUWarning, HighMemoryWarning, etc.) — Alertmanager groups them into ONE email saying "server-1 has 3 issues."

### Core concepts

**Routing tree** — a tree of rules that decides which receiver handles each alert. Evaluated top-to-bottom, first match wins.

**Receiver** — a notification destination: email, Slack webhook, PagerDuty, etc.

**Group** — a set of alerts that are bundled together into one notification. Controlled by `group_by`.

**Silences** — manually suppress alerts for a time window (e.g., during planned maintenance). Set in the Alertmanager UI.

**Inhibitions** — automatically suppress lower-severity alerts when a higher-severity one is firing. Example: suppress HighCPUWarning if InstanceDown is firing for the same server.

### alertmanager.yml structure explained

```yaml
global:
  resolve_timeout: 5m           # how long after an alert stops firing
                                # before sending RESOLVED notification
  smtp_smarthost: 'smtp.gmail.com:587'
  smtp_from: 'alerts@example.com'
  smtp_auth_username: 'alerts@example.com'
  smtp_auth_password: 'app-password-here'
  smtp_require_tls: true

route:
  receiver: 'team-email'        # default receiver (catches everything)
  group_by: ['alertname', 'instance']   # bundle alerts with same name+instance
  group_wait: 30s               # wait 30s after first alert before sending
                                # (collects more alerts from the same group)
  group_interval: 5m            # wait 5m before sending updates to an
                                # existing active group
  repeat_interval: 4h           # resend if alert is still firing after 4h

  routes:                       # child routes — checked first
    - matchers:
        - severity = "critical"
      receiver: 'team-email'
      group_wait: 10s           # critical alerts: send faster (10s not 30s)
      repeat_interval: 1h       # remind every hour, not every 4h

receivers:
  - name: 'team-email'
    email_configs:
      - to: 'oncall@example.com'
        send_resolved: true     # send email when alert clears
```

### group_wait vs group_interval vs repeat_interval

- **group_wait (30s):** When the FIRST alert arrives in a new group, wait 30 seconds before sending. During this window, Prometheus might fire more alerts for the same server — they get bundled into one notification instead of sending 5 separate emails.

- **group_interval (5m):** If new alerts arrive in an already-notified group, wait 5 minutes before sending an update. Prevents spam if alerts keep changing.

- **repeat_interval (4h):** If an alert has been firing unchanged for 4 hours, send it again. Reminds the on-call person who may have forgotten.

### Gmail App Password (why not your normal password)

Gmail with 2FA enabled won't accept your regular password for SMTP. You need an **App Password**:
1. Go to `myaccount.google.com` → Security → 2-Step Verification → App passwords
2. Create a new app password (16 characters, no spaces)
3. Use that in `smtp_auth_password`

### Validating alertmanager config

```bash
amtool check-config /etc/alertmanager/alertmanager.yml
```

### Reloading without restart

```bash
sudo systemctl reload alertmanager
# OR
curl -X POST http://localhost:9093/-/reload
```

### Testing without a real incident

```bash
# Fire a test alert manually
amtool alert add alertname="TestAlert" instance="test-server" severity="warning"

# Check it appears
amtool alert

# Check it in the UI
# http://localhost:9093

# Silence it (so you don't get an email)
amtool silence add alertname="TestAlert"
```

### File locations

```
/usr/local/bin/alertmanager
/usr/local/bin/amtool
/etc/alertmanager/alertmanager.yml
/var/lib/alertmanager/          # silence and nflog state (survives restart)
/etc/amtool/config.yml          # amtool default URL
/etc/systemd/system/alertmanager.service
```

---

## 7. Grafana

### What it is

A web-based visualization tool. It connects to Prometheus (and many other data sources) and renders graphs, stat panels, tables, and heatmaps. Grafana does NOT store any data — every query runs against Prometheus in real time.

### Core concepts

**Data source** — a connection to a data backend. For us: Prometheus at `http://localhost:9090`.

**Dashboard** — a collection of panels on one screen. Can be saved, exported as JSON, imported.

**Panel** — a single visualization (graph, stat, gauge, table, etc.) with one or more queries.

**Variable** — a dashboard-level dropdown that filters all panels. Example: `$instance` dropdown lets you switch between servers without editing queries.

**Provisioning** — loading data sources and dashboards automatically from YAML/JSON files, without manual UI steps. Used in our `grafana/provisioning/` folder.

### The Node Exporter Full dashboard (ID 1860)

This is a community-built dashboard with ~200 panels covering every Node Exporter metric. Import it via:
- Grafana UI → + → Import → enter `1860` → select Prometheus data source → Import

It's the fastest way to get a complete view of every server. Then customize panel titles to match your server names.

### Building the Overview Dashboard

Goal: one row per server, 4 stat panels per row — CPU, Memory, Disk, Uptime.

```
┌─────────────────────────────────────────────────────────┐
│  server-1  │  CPU: 34%  │  Mem: 72%  │  Disk: 45%  │  Up: 5d │
├─────────────────────────────────────────────────────────┤
│  server-2  │  CPU: 12%  │  Mem: 58%  │  Disk: 82%  │  Up: 12d│
└─────────────────────────────────────────────────────────┘
```

Queries for each panel (replace `$instance` with your variable):
```promql
# CPU %
(1 - avg by(instance) (rate(node_cpu_seconds_total{mode="idle",instance="$instance"}[5m]))) * 100

# Memory available %
node_memory_MemAvailable_bytes{instance="$instance"}
/ node_memory_MemTotal_bytes{instance="$instance"} * 100

# Root disk used %
(node_filesystem_size_bytes{mountpoint="/",instance="$instance"}
 - node_filesystem_avail_bytes{mountpoint="/",instance="$instance"})
/ node_filesystem_size_bytes{mountpoint="/",instance="$instance"} * 100

# Uptime in seconds (display with unit "duration (s)")
node_time_seconds{instance="$instance"} - node_boot_time_seconds{instance="$instance"}
```

**Color thresholds (matching alert severities):**
- Green: normal (CPU <80%, Mem available >15%, Disk <80%)
- Amber: warning (CPU 80–95%, Mem 5–15%, Disk 80–95%)
- Red: critical (CPU >95%, Mem <5%, Disk >95%)

### Exporting dashboards as JSON

In Grafana: Dashboard → Share → Export → Save to file

Commit to `grafana/dashboards/overview.json` and `grafana/dashboards/node_exporter.json`.

With provisioning configured (`grafana/provisioning/dashboards/dashboards.yml`), Grafana auto-loads these JSONs from `/var/lib/grafana/dashboards/` — no manual import needed on a fresh install.

### File locations

```
/usr/sbin/grafana-server
/etc/grafana/grafana.ini              # main config
/etc/grafana/provisioning/            # auto-load configs
/var/lib/grafana/                     # database, dashboards, plugins
/var/log/grafana/grafana.log          # logs
/etc/systemd/system/grafana-server.service
```

---

## 8. Production Deployment

### Pre-deployment checklist

```
[ ] All target servers reachable from monitoring VM (ping test)
[ ] Ports open: 9090, 9093, 9100, 3000 (or via nginx on 80/443)
[ ] SMTP credentials confirmed working (test with a mail client first)
[ ] Sufficient disk on monitoring VM for Prometheus data
    (estimate: targets × metrics_per_target × bytes_per_sample × retention_seconds)
[ ] NTP running on ALL servers (required for time-series accuracy)
[ ] All rule files pass promtool validation
[ ] alertmanager.yml passes amtool validation
[ ] Test alert received end-to-end before go-live
```

### Disk sizing for Prometheus

```
Rough formula:
  samples/second = (targets × metrics_per_target) / scrape_interval
  bytes/day = samples/second × 86400 × 1.5 bytes_per_sample
  total = bytes/day × retention_days

Example (1 server, ~500 metrics, 15s scrape, 15 day retention):
  samples/second = 500 / 15 = 33
  bytes/day = 33 × 86400 × 1.5 = ~4.3 MB/day
  total = 4.3 × 15 = ~65 MB

For 10 servers: ~650 MB. Add 2× buffer = allocate ~1.5 GB.
```

### Adding a new server to monitor

1. Install Node Exporter on the new server:
   ```bash
   sudo bash scripts/install_node_exporter.sh
   ```

2. Open its firewall to the monitoring server:
   ```bash
   sudo ufw allow from <monitoring-server-IP> to any port 9100
   ```

3. Add the target to `prometheus/prometheus.yml`:
   ```yaml
   scrape_configs:
     - job_name: 'node'
       static_configs:
         - targets:
             - 'existing-server:9100'
             - 'new-server:9100'     # add this line
   ```

4. Copy the updated config and reload:
   ```bash
   sudo cp prometheus/prometheus.yml /etc/prometheus/prometheus.yml
   promtool check config /etc/prometheus/prometheus.yml
   sudo systemctl reload prometheus
   ```

5. Verify the new target shows UP at `http://localhost:9090/targets`.

6. Update `docs/targets.txt`.

### Checking that Prometheus actually receives data

```bash
# Is the target UP?
curl -s 'http://localhost:9090/api/v1/targets' | python3 -m json.tool | grep -A5 '"health"'

# Does Prometheus have data for it?
curl -s 'http://localhost:9090/api/v1/query?query=up{job="node"}' | python3 -m json.tool

# Quick check from the Node Exporter directly
curl http://<target-IP>:9100/metrics | head -20
```

### Service management cheatsheet

```bash
# Status of all 4 services
systemctl status node_exporter prometheus alertmanager grafana-server

# Restart all 4 (order matters: node_exporter → prometheus → alertmanager → grafana)
sudo systemctl restart node_exporter
sudo systemctl restart alertmanager   # alertmanager before prometheus so it's ready
sudo systemctl restart prometheus
sudo systemctl restart grafana-server

# Enable autostart (should already be set by install scripts)
sudo systemctl enable node_exporter prometheus alertmanager grafana-server

# Follow logs in real time
sudo journalctl -u prometheus -f
sudo journalctl -u alertmanager -f
sudo journalctl -u node_exporter -f
sudo journalctl -u grafana-server -f
```

---

## 9. Security Hardening

### Why dedicated system users

Each component runs as its own user (`node_exporter`, `prometheus`, `alertmanager`, `grafana`). These users:
- Have no home directory (`--no-create-home`)
- Have no login shell (`/usr/sbin/nologin`)
- Cannot SSH in or run interactive commands
- Can only access the files their service needs

If an attacker exploits a vulnerability in Prometheus, they get a user that can only read `/etc/prometheus/` — not root, not the database, not the rest of the system.

### File permissions

```bash
# Config files containing credentials: owner read/write, group read, world nothing
sudo chmod 640 /etc/alertmanager/alertmanager.yml
sudo chmod 640 /etc/prometheus/prometheus.yml
sudo chmod 640 /etc/grafana/grafana.ini

# Verify
ls -la /etc/alertmanager/alertmanager.yml
# Should show: -rw-r----- 1 alertmanager alertmanager
```

### Never commit credentials

The `.gitignore` excludes `.env`. Store SMTP passwords only in:
1. The actual config file on the server (mode 640, owned by the service user)
2. A `.env` file on the server (gitignored)

Never put real passwords in files committed to git — even in private repos, even temporarily.

### Firewall rules

```bash
# On the monitoring server — allow team members to access dashboards
sudo ufw allow 9090/tcp   # Prometheus
sudo ufw allow 9093/tcp   # Alertmanager
sudo ufw allow 3000/tcp   # Grafana

# Node Exporter should ONLY be accessible from the monitoring server
# On each monitored server:
sudo ufw allow from <monitoring-server-IP> to any port 9100

# Deny all other access to port 9100
sudo ufw deny 9100/tcp
```

### nginx reverse proxy with basic auth

If you need internet access to dashboards, put nginx in front with TLS and basic auth:

```bash
# Install nginx and password tool
sudo apt-get install -y nginx apache2-utils

# Create password file
sudo htpasswd -c /etc/nginx/.htpasswd admin

# Create site config at /etc/nginx/sites-available/monitoring
server {
    listen 443 ssl;
    ssl_certificate /etc/letsencrypt/live/yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/yourdomain.com/privkey.pem;

    location /prometheus/ {
        proxy_pass http://localhost:9090/;
        auth_basic "Monitoring";
        auth_basic_user_file /etc/nginx/.htpasswd;
    }
    location /alertmanager/ {
        proxy_pass http://localhost:9093/;
        auth_basic "Monitoring";
        auth_basic_user_file /etc/nginx/.htpasswd;
    }
    location / {
        proxy_pass http://localhost:3000/;
        proxy_set_header Host $host;
    }
}
```

---

## 10. Troubleshooting

### Decision tree: alert not firing when it should

```
Is the target UP in Prometheus?
  http://localhost:9090/targets

  NO → Node Exporter is down or unreachable
       Check: systemctl status node_exporter
       Check: curl http://<target>:9100/metrics
       Check: firewall (sudo ufw status)

  YES → Is the rule loaded?
        http://localhost:9090/rules

        NO → rule file not loaded
             Check: promtool check rules /etc/prometheus/rules/*.yml
             Check: sudo systemctl reload prometheus
             Check: journalctl -u prometheus -n 50

        YES → Is the condition true right now?
              Run the expr in the expression browser at :9090/graph

              NO → condition not actually met — thresholds may be correct
                   The problem may not be as severe as expected

              YES → Is the alert in PENDING or FIRING state?
                    :9090/alerts

                    PENDING → still within the "for" window, wait it out

                    FIRING → alert is firing but notification not received
                             Check Alertmanager: http://localhost:9093
                             Check: amtool alert
                             Check: journalctl -u alertmanager -n 50
                             Check SMTP credentials
```

### Decision tree: notification not received

```
Did the alert appear in Alertmanager UI?
  http://localhost:9093

  NO → Prometheus can't reach Alertmanager
       Check: curl http://localhost:9093/-/healthy
       Check: systemctl status alertmanager
       Check: prometheus.yml alerting block has correct address

  YES → Did Alertmanager try to send?
        journalctl -u alertmanager -n 100 | grep -i "email\|smtp\|error"

        Shows error → SMTP problem
                      Test SMTP credentials with a mail client
                      Check App Password for Gmail
                      Check spam folder

        No attempt → alert is silenced or inhibited
                     Check: amtool silence query
                     Check routing tree in alertmanager.yml
```

### Common error messages and fixes

| Error | Cause | Fix |
|-------|-------|-----|
| `connection refused` on port 9090/9093/9100 | Service not running | `sudo systemctl start <service>` |
| `level=error msg="Opening storage failed"` in Prometheus | Corrupt TSDB or disk full | Check `df -h`, check `/var/lib/prometheus/` permissions |
| `yaml: line X: did not find expected key` | YAML indentation error | Validate with `promtool check config` or `amtool check-config` |
| `Error on ingesting out-of-order samples` | System clock skew | Check NTP: `timedatectl status` |
| `dial tcp: connection refused` in Alertmanager logs | Wrong Alertmanager address in prometheus.yml | Check alerting block in prometheus.yml |
| `535 Authentication Failed` | Wrong SMTP password | Use Gmail App Password, not account password |
| Grafana shows "No data" | Query returns no results | Check instance label matches exactly, check time range |

### Checking services quickly

```bash
# Are all 4 services running?
systemctl is-active node_exporter prometheus alertmanager grafana-server

# Are all 4 ports listening?
ss -tlnp | grep -E '9090|9093|9100|3000'

# Quick health check on all 4
curl -s http://localhost:9100/metrics | grep -c "^node_" && echo "Node Exporter OK"
curl -s -o /dev/null -w "%{http_code}" http://localhost:9090/-/healthy && echo " Prometheus OK"
curl -s -o /dev/null -w "%{http_code}" http://localhost:9093/-/healthy && echo " Alertmanager OK"
curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/api/health && echo " Grafana OK"
```

---

## 11. Backup and Recovery

### What needs to be backed up

| What | Where | How often | Why |
|------|-------|-----------|-----|
| prometheus.yml + rules/ | `/etc/prometheus/` | On every change (git is your backup) | Config is the hard part |
| alertmanager.yml | `/etc/alertmanager/` | On every change (git) | SMTP config, routing logic |
| Grafana dashboards | `grafana/dashboards/*.json` | After each dashboard change | Hard to recreate |
| Prometheus TSDB | `/var/lib/prometheus/` | Daily snapshot | Historical data |
| Alertmanager silences | `/var/lib/alertmanager/` | Rarely (not critical) | Active silences |

### Backing up Prometheus data

```bash
# Take a snapshot via the API (creates a consistent copy)
curl -XPOST http://localhost:9090/api/v1/admin/tsdb/snapshot

# The snapshot appears in /var/lib/prometheus/snapshots/
ls /var/lib/prometheus/snapshots/

# Compress and copy off-server
tar -czf prometheus-backup-$(date +%Y%m%d).tar.gz /var/lib/prometheus/snapshots/latest/
```

Note: For this internship project, the git repo IS the backup for all config files. The TSDB data (historical metrics) is not critical — you can lose it and just start collecting again.

### Recovering from a fresh install

```bash
# Clone the repo
git clone <repo-url>
cd LMT

# Run the install scripts
sudo bash scripts/install_node_exporter.sh
sudo bash scripts/install_prometheus.sh
sudo bash scripts/install_alertmanager.sh
sudo bash scripts/install_grafana.sh

# Everything is configured automatically from the repo files.
# Only thing to restore manually: SMTP password in alertmanager.yml
# (it's not in git — pull from your .env or password manager)
```

---

## 12. Common Pitfalls

### 1. Alerting on `MemFree` instead of `MemAvailable`

`MemFree` = truly unused RAM. Linux uses free RAM for disk cache, making `MemFree` always appear low even on a healthy system. Use `MemAvailable` — the kernel's estimate of how much can actually be given to processes.

### 2. Forgetting the `for` clause on fast-changing metrics

Without `for`, a single high CPU sample (one scrape returning >80%) fires an alert. Add `for: 2m` so transient spikes are ignored.

### 3. Division by zero in PromQL

```promql
# DANGEROUS: crashes if SwapTotal is 0 (no swap configured)
(node_memory_SwapTotal_bytes - node_memory_SwapFree_bytes) / node_memory_SwapTotal_bytes * 100 > 80

# SAFE: add a guard
... > 80 and node_memory_SwapTotal_bytes > 0
```

### 4. instance label mismatch between rules and prometheus.yml

If `prometheus.yml` sets `instance: "server-1"` but your rule uses `{instance="server1"}` (no dash) — your rule never matches. After Person A finalizes `prometheus.yml`, Person B must check all `instance` label values before writing rules.

### 5. Prometheus config error blocks ALL rules

If one rule file has a YAML syntax error, Prometheus refuses to load ANY rule files on reload. Always validate with `promtool check config` before reloading.

### 6. Not reloading after config changes

After editing `prometheus.yml` or any rule file in `/etc/prometheus/rules/`, you must reload:
```bash
sudo systemctl reload prometheus
```
The files on disk are not automatically re-read.

### 7. Prometheus scraping the wrong interface

On a multi-homed server (multiple network interfaces), Node Exporter listens on all interfaces by default. Prometheus reaches it by the address in `prometheus.yml`. If the IP in your config is wrong, the target shows as DOWN.

### 8. Grafana "No data" panels

Common causes:
- Instance label in the Grafana query doesn't match what Prometheus uses
- Time range in Grafana doesn't cover when the data was collected
- Prometheus data source URL is wrong

Fix: Run the exact query in Prometheus expression browser (`http://localhost:9090/graph`) first — if it returns data there, the issue is in Grafana. If not, the issue is in Prometheus.

### 9. Email going to spam

Gmail and other providers may spam-filter Alertmanager's automated emails. Check your spam folder during testing. Add the sender to your contacts or whitelist.

### 10. Clock drift breaking time-series

All servers need NTP synchronized. If a monitored server's clock drifts, Prometheus may reject samples as "out of order." Check: `timedatectl status` on each server.

---

## 13. Quick Reference

### All install commands

```bash
sudo bash scripts/install_node_exporter.sh   # :9100
sudo bash scripts/install_prometheus.sh      # :9090
sudo bash scripts/install_alertmanager.sh    # :9093
sudo bash scripts/install_grafana.sh         # :3000
```

### All validation commands

```bash
promtool check config /etc/prometheus/prometheus.yml
promtool check rules /etc/prometheus/rules/*.yml
amtool check-config /etc/alertmanager/alertmanager.yml
sudo bash scripts/verify_all.sh
```

### All reload commands

```bash
sudo systemctl reload prometheus
sudo systemctl reload alertmanager
sudo systemctl restart grafana-server   # grafana needs restart not reload
```

### Web UIs

| Service | URL | Default login |
|---------|-----|---------------|
| Prometheus | `http://<IP>:9090` | none |
| Prometheus targets | `http://<IP>:9090/targets` | none |
| Prometheus alerts | `http://<IP>:9090/alerts` | none |
| Alertmanager | `http://<IP>:9093` | none |
| Grafana | `http://<IP>:3000` | admin / admin |
| Node Exporter metrics | `http://<IP>:9100/metrics` | none |

### Log commands

```bash
sudo journalctl -u node_exporter -f
sudo journalctl -u prometheus -f
sudo journalctl -u alertmanager -f
sudo journalctl -u grafana-server -f
sudo journalctl -u prometheus --since "1 hour ago"   # last hour only
sudo journalctl -u prometheus -p err                 # errors only
```

### Most useful PromQL queries to run in the browser

```promql
# Which targets are down?
up == 0

# Current CPU usage per server
(1 - avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m]))) * 100

# Memory available % per server
node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes * 100

# Disk used % on / per server
(node_filesystem_size_bytes{mountpoint="/"} - node_filesystem_avail_bytes{mountpoint="/"})
/ node_filesystem_size_bytes{mountpoint="/"} * 100

# Network receive Mbps per interface
rate(node_network_receive_bytes_total[5m]) * 8 / 1000000

# Server uptime in days
(node_time_seconds - node_boot_time_seconds) / 86400

# How many metrics is Prometheus storing?
prometheus_tsdb_head_series

# How much disk is Prometheus TSDB using?
prometheus_tsdb_storage_blocks_bytes
```

---

*Document version: 1.0 | Created: 2026-06-21*
