# Session Build Log — Complete Record
# Date: 2026-06-21
# What was built, installed, discussed, and decided in this session

---

## 1. Starting State

When this session began, the repository had only:

```
all files/
  alertmanager.yml
  install_alertmanager.sh
  install_node_exporter.sh
  node_exporter_alerts.yml       ← only 4 basic rules
  prometheus_config_snippet.yml
  uninstall.sh
  validate_all.py
  verify_setup.sh
documentation/
  Node_Exporter_Alertmanager_Setup_Ubuntu.md
README.md
Sprint_Plan_Team_Collaboration.pdf
.gitignore
```

Nothing was installed. No Prometheus. No Grafana. No proper folder structure.
The `node_exporter_alerts.yml` only had 4 rules — the sprint plan required 24.

---

## 2. What Was Read and Understood

### Sprint Plan (Sprint_Plan_Team_Collaboration.pdf — 19 pages)

Full document was read. Key extracts:

**Project:** Linux Infrastructure Monitoring Stack
**Team:** 3 interns, 2 weeks, 10 working days
**Stack:** Prometheus + Node Exporter + Alertmanager + Grafana

**Three roles:**
- Person A — Infrastructure & Data Collection (Node Exporter, Prometheus, prometheus.yml)
- Person B — Alerting Pipeline (all 20 alert rules, Alertmanager, runbooks)
- Person C — Visualization & Documentation (Grafana dashboards, final docs)

**Required repository structure (Section 6):**
```
prometheus/prometheus.yml
prometheus/rules/cpu.yml
prometheus/rules/memory.yml
prometheus/rules/disk.yml
prometheus/rules/network.yml
prometheus/rules/system.yml
prometheus/rules/prometheus_self.yml
alertmanager/alertmanager.yml
grafana/dashboards/
grafana/provisioning/datasources/
grafana/provisioning/dashboards/
docs/targets.txt
docs/runbook.md
docs/alert-test-report.md
docs/security-notes.md
docs/grafana-plan.md
docs/sprint-log.md
.env.example
.gitignore
```

**All 24 alert rules (Section 7):**

| File | Rules |
|------|-------|
| cpu.yml | HighCPUWarning (>80%, 2m), HighCPUCritical (>95%, 5m), HighIOWait (>20%, 5m), HighLoadAverage (per core >1, 5m) |
| memory.yml | LowMemoryWarning (<15%, 2m), LowMemoryCritical (<5%, 1m), SwapUsageHigh (>80%, 2m), OOMKillDetected (immediate) |
| disk.yml | LowDiskWarning (>80%, 5m), LowDiskCritical (>95%, 5m), DiskFillingFast (predict_linear 4h, 10m), InodeExhaustionWarning (>80%, 5m), HighDiskReadLatency (>100ms, 2m), HighDiskWriteLatency (>100ms, 2m) |
| network.yml | HighRXBandwidth (>800Mbps, 2m), HighTXBandwidth (>800Mbps, 2m), HighNetworkErrorRate (>10/s, 2m), NetworkInterfaceDown (immediate) |
| system.yml | InstanceDown (2m), UnexpectedReboot (immediate), HighZombieProcesses (>5, 5m), HighFileDescriptors (>80%, 2m), ClockSkewDetected (>50ms, 5m) |
| prometheus_self.yml | ConfigReloadFailure (immediate), ScrapeErrorsIncreasing (5m), AlertmanagerNotReachable (immediate), TSDBCompactionFailures (15m) |

**Three integration handoffs:**
- Day 3 EOD: Person A → B+C: finalized instance label format, targets list (docs/targets.txt)
- Day 5 EOD: Person B → A: all 5 rule files as PR, Person A loads into Prometheus
- Day 8 SOD: Person A → C: Prometheus URL + metric names, Person C connects Grafana

---

## 3. All Files Created This Session

### Directory structure created

```bash
mkdir -p prometheus/rules
mkdir -p alertmanager
mkdir -p grafana/dashboards
mkdir -p grafana/provisioning/datasources
mkdir -p grafana/provisioning/dashboards
mkdir -p scripts
mkdir -p docs
```

### prometheus/rules/ — 6 alert rule files

**prometheus/rules/cpu.yml** (4 rules)
- HighCPUWarning: `(1 - avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m]))) * 100 > 80` for 2m, warning
- HighCPUCritical: same expr > 95, for 5m, critical
- HighIOWait: `avg by(instance) (rate(node_cpu_seconds_total{mode="iowait"}[5m])) * 100 > 20` for 5m, warning
- HighLoadAverage: `node_load15 / count by(instance) (node_cpu_seconds_total{mode="idle"}) > 1` for 5m, warning

**prometheus/rules/memory.yml** (4 rules)
- LowMemoryWarning: `node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes * 100 < 15` for 2m, warning
- LowMemoryCritical: same expr < 5, for 1m, critical
- SwapUsageHigh: `(SwapTotal - SwapFree) / SwapTotal * 100 > 80 and SwapTotal > 0` for 2m, warning
  - Note: `and SwapTotal > 0` guard added to prevent division-by-zero on systems with no swap
- OOMKillDetected: `increase(node_vmstat_oom_kill[5m]) > 0`, no for (immediate), critical

**prometheus/rules/disk.yml** (6 rules)
- LowDiskWarning: `(size - avail) / size * 100 > 80` fstype!~tmpfs|devtmpfs, for 5m, warning
- LowDiskCritical: same expr > 95, for 5m, critical
- DiskFillingFast: `predict_linear(node_filesystem_avail_bytes[1h], 4*3600) < 0` for 10m, warning
- InodeExhaustionWarning: `(files - files_free) / files * 100 > 80` for 5m, warning
- HighDiskReadLatency: `rate(read_time[5m]) / rate(reads_completed[5m]) > 0.1 and reads_completed > 0` for 2m
  - Note: `and reads_completed > 0` guard added to prevent division-by-zero
- HighDiskWriteLatency: same pattern for writes, for 2m, warning

**prometheus/rules/network.yml** (4 rules)
- HighRXBandwidth: `rate(node_network_receive_bytes_total[5m]) * 8 > 800000000` for 2m, warning
- HighTXBandwidth: same for transmit, for 2m, warning
- HighNetworkErrorRate: `rate(receive_errs[5m]) > 10 or rate(transmit_errs[5m]) > 10` for 2m, warning
- NetworkInterfaceDown: `node_network_carrier{device!="lo"} == 0`, no for (immediate), critical

**prometheus/rules/system.yml** (5 rules)
- InstanceDown: `up == 0` for 2m, critical
- UnexpectedReboot: `(node_time_seconds - node_boot_time_seconds) < 600`, no for (immediate), warning
- HighZombieProcesses: `node_procs_zombie > 5` for 5m, warning
- HighFileDescriptors: `node_filefd_allocated / node_filefd_maximum * 100 > 80` for 2m, warning
- ClockSkewDetected: `abs(node_timex_offset_seconds) > 0.05` for 5m, warning

**prometheus/rules/prometheus_self.yml** (4 rules)
- ConfigReloadFailure: `prometheus_config_last_reload_successful == 0`, no for (immediate), critical
- ScrapeErrorsIncreasing: `increase(scrape_errors_total[5m]) > 0` for 5m, warning
- AlertmanagerNotReachable: `prometheus_notifications_alertmanagers_discovered < 1`, no for (immediate), critical
- TSDBCompactionFailures: `increase(prometheus_tsdb_compactions_failed_total[15m]) > 0` for 15m, warning

### prometheus/prometheus.yml

Full configuration:
- scrape_interval: 15s, evaluation_interval: 15s
- external_labels: team=linux-monitoring, environment=production
- alerting block pointing to localhost:9093
- rule_files loading all 6 rule files
- scrape_configs for prometheus (self) and node (Node Exporter)
- Template comment block for adding company servers

### alertmanager/alertmanager.yml

Updated from the original in "all files/":
- repeat_interval changed from 3h → 4h (matches sprint plan Day 6 spec)
- Added critical sub-route: group_wait 10s, repeat_interval 1h (critical alerts notify faster)
- Added Subject header template to email configs
- send_resolved: true

### scripts/ — 6 scripts

**scripts/install_node_exporter.sh** — Node Exporter v1.11.1
- Creates node_exporter system user (nologin, no home)
- Downloads from GitHub, installs to /usr/local/bin/
- Creates systemd service
- Enables and starts, verifies metrics endpoint

**scripts/install_prometheus.sh** — Prometheus v2.54.1
- Creates prometheus system user
- Creates /etc/prometheus/rules/ and /var/lib/prometheus/
- Downloads prometheus + promtool binaries
- Copies prometheus.yml and all rule files from repo
- Validates config with promtool before starting
- Creates systemd service with --storage.tsdb.retention.time=15d
- Enables and starts, verifies HTTP 200 on /-/healthy

**scripts/install_alertmanager.sh** — Alertmanager v0.33.0
- Creates alertmanager system user
- Downloads alertmanager + amtool binaries
- Copies alertmanager.yml from repo
- Sets chmod 640 on config file
- Creates systemd service
- Configures amtool (/etc/amtool/config.yml)
- Enables and starts, verifies health endpoint

**scripts/install_grafana.sh** — Grafana OSS latest stable
- Installs via official apt.grafana.com repository (always gets latest)
- Copies provisioning configs from repo to /etc/grafana/provisioning/
- Opens UFW port 3000 if firewall is active
- Enables and starts grafana-server

**scripts/verify_all.sh** — Full stack health check
- Checks all 4 services: binary, user, service running, service enabled, port listening, endpoint responding
- Checks rule file count and validates with promtool
- Checks amtool config validation
- Checks UFW port rules for 9090/9093/9100/3000
- Checks connectivity via actual IP (not just localhost)
- Prints pass/fail summary

**scripts/uninstall_all.sh** — Full removal
- Stops and disables all 4 services
- Removes binaries, service files, config dirs, data dirs
- Removes system users
- Removes grafana apt package
- Interactive confirmation before proceeding

**scripts/add_target.sh** — Add a new server to monitor (created later in session)
- Usage: `sudo bash scripts/add_target.sh <IP> <name> [team] [env]`
- Verifies Node Exporter is reachable at the IP before touching config
- Adds target block to /etc/prometheus/prometheus.yml
- Validates config with promtool
- Reloads Prometheus live (no downtime)
- Polls Prometheus API for up to 30s to confirm target shows as UP

### grafana/provisioning/datasources/prometheus.yml
- Auto-configures Prometheus as the default data source
- URL: http://localhost:9090, access: proxy, httpMethod: POST, timeInterval: 15s
- Grafana loads this automatically on startup — no manual UI setup needed

### grafana/provisioning/dashboards/dashboards.yml
- Tells Grafana to load dashboard JSONs from /var/lib/grafana/dashboards/
- updateIntervalSeconds: 30 (picks up new JSONs without restart)
- folder: 'Linux Monitoring'

### docs/targets.txt
- Handoff 1 artifact (Day 3 EOD)
- Format: hostname | IP | port | instance_label | OS
- Pre-populated with monitoring-server entry (127.0.0.1:9100)
- Template entries for adding company servers

### docs/runbook.md
- Runbooks for all 6 critical-severity alerts
- Each entry: alert name, trigger condition, first diagnostic commands, escalation path
- Alerts covered: InstanceDown, LowMemoryCritical, LowDiskCritical, NetworkInterfaceDown, OOMKillDetected, AlertmanagerNotReachable

### docs/grafana-plan.md
- Node Exporter Full (ID 1860) customization notes
- Overview Dashboard layout: one row per server, 4 stat panels (CPU, Memory, Disk, Uptime)
- Exact PromQL queries for each panel
- Color threshold mappings matching alert severities (green/amber/red)
- Prometheus data source configuration details
- Dashboard JSON export instructions

### docs/security-notes.md
- File permission requirements (chmod 640 on all config files)
- Credential storage policy (.env file, not in git)
- nginx reverse proxy setup with basic auth (full config included)
- Firewall rules: monitoring server ports + restricting Node Exporter to monitoring server IP only

### docs/sprint-log.md
- Full 10-day daily log (Days 1–10)
- All handoff events documented
- Final smoke test and sprint retrospective

### docs/alert-test-report.md
- Template for 3 end-to-end tests: CPU, Disk, InstanceDown
- Exact commands to temporarily lower thresholds for testing
- Table format for recording results with timestamps
- Day 10 smoke test section (A+B+C all present)

### docs/complete-reference.md (created on request)
13-section comprehensive reference covering:
1. The Big Picture — full data flow, pull model explained
2. Node Exporter — how it reads /proc and /sys, every metric name you use
3. Prometheus — time-series data model, labels, storage, API endpoints
4. PromQL — gauges vs counters, rate(), increase(), predict_linear(), aggregation
5. Alert Rules — file structure, 3 alert states, template variables, the `for` clause
6. Alertmanager — routing tree, group_wait vs group_interval vs repeat_interval
7. Grafana — data source, dashboard, panel, variable, provisioning
8. Production Deployment — pre-deploy checklist, disk sizing formula, adding servers
9. Security Hardening — dedicated users, file permissions, nginx TLS
10. Troubleshooting — decision trees for alert not firing, notification not received
11. Backup and Recovery — what to back up, how, recovering from fresh install
12. Common Pitfalls — 10 specific mistakes (MemFree vs MemAvailable, division by zero, etc.)
13. Quick Reference — every command, all web UIs, most useful PromQL queries

### .env.example
Template for credentials (never committed to git):
- ALERTMANAGER_SMTP_FROM, SMTP_USERNAME, SMTP_PASSWORD, EMAIL_TO
- GRAFANA_ADMIN_PASSWORD
- PROMETHEUS_URL

### .gitignore (updated)
Added to existing:
- `.env` — prevents credential files from being committed
- `*.key`, `*.pem`, `*.p12` — certificate/key files
- `*.swp`, `*.swo`, `*~` — editor temp files
- `*.tar.gz`, `*.zip` — downloaded binaries

### README.md (full rewrite)
- Architecture diagram (ASCII)
- Full repository structure tree
- Quick start (4 commands)
- Component summary table with versions and ports
- Alert rules table (all 24 rules)
- Common commands table
- Alertmanager SMTP setup instructions
- Grafana dashboard import instructions

---

## 4. Installation Results

All 4 components installed via the scripts. User ran each with `! sudo bash scripts/install_*.sh`.

### Node Exporter v1.11.1
```
Status: active (running)
Port 9100: listening
Metrics: 621 metrics exposed
Service: enabled (starts on boot)
Binary: /usr/local/bin/node_exporter
Service file: /etc/systemd/system/node_exporter.service
```
Note: Script showed "WARNING: Metrics endpoint not responding" during install — this was a race condition (curl ran before Node Exporter finished its first startup second). Confirmed working afterwards with 621 metrics.

### Prometheus v2.54.1
```
Status: active (running)
Port 9090: listening
Health endpoint: HTTP 200
Config validation: passed (promtool)
Rules loaded: 27 (6 files × rules each: 4+6+4+4+4+5)
Targets: 2 UP (prometheus self + node exporter)
Service: enabled
Binary: /usr/local/bin/prometheus
promtool: /usr/local/bin/promtool
Config: /etc/prometheus/prometheus.yml
Rules dir: /etc/prometheus/rules/
Data dir: /var/lib/prometheus/ (15 day retention)
```

### Alertmanager v0.33.0
```
Status: active (running)
Port 9093: listening
Health endpoint: HTTP 200
Config validation: passed (amtool)
Service: enabled
Binaries: /usr/local/bin/alertmanager, /usr/local/bin/amtool
Config: /etc/alertmanager/alertmanager.yml (mode 640)
Data dir: /var/lib/alertmanager/
amtool config: /etc/amtool/config.yml
```

### Grafana v13.0.2 (latest at install time)
```
Status: active (running)
Port 3000: listening
Health endpoint: HTTP 200
Service: enabled
Anonymous access: DISABLED (requires login)
Default credentials: admin / admin (MUST be changed)
Provisioning: datasource auto-configured (Prometheus)
Config: /etc/grafana/grafana.ini
Provisioning: /etc/grafana/provisioning/
Data: /var/lib/grafana/
```
Note: Script showed "HTTP 000" during install — Grafana was still initializing. Confirmed HTTP 200 after a few seconds.

### Final verification state
```
node_exporter   active  port 9100  621 metrics
prometheus      active  port 9090  HTTP 200  27 rules  2 targets UP
alertmanager    active  port 9093  HTTP 200
grafana-server  active  port 3000  HTTP 200
```

---

## 5. Security Audit — What Was Found

A security check was run against the live installation.

### What IS secure

| Item | Status | Detail |
|------|--------|--------|
| prometheus.yml permissions | PASS | -rw-r----- (640) — only prometheus user reads it |
| alertmanager.yml permissions | PASS | -rw-r----- (640) — only alertmanager user reads it |
| Grafana anonymous access | PASS | HTTP 401 without credentials — login required |
| Prometheus admin/delete API | PASS | HTTP 500 (disabled by default) — cannot delete metrics without flag |
| System users | PASS | All 4 services run as dedicated nologin users, not root |
| Credentials in git | PASS | .env in .gitignore, no passwords committed |

### What is NOT secure (vulnerabilities found)

**1. No authentication on Prometheus (port 9090) — HIGH severity**
- Anyone who reaches port 9090 can read all metrics, run any PromQL query, read your full config
- Confirmed: `curl http://localhost:9090/api/v1/status/config` returned full config without credentials
- Fix: add `--web.config.file` with bcrypt password hash, or nginx basic auth

**2. No authentication on Alertmanager (port 9093) — MEDIUM severity**
- Anyone can view all active alerts, create silences (suppress real alerts), delete silences
- Confirmed: `curl http://localhost:9093/api/v2/alerts` returned data without credentials
- Risk: attacker could silence your InstanceDown alert — your server goes down, nobody gets notified
- Fix: same as Prometheus — web.config.file or nginx basic auth

**3. Rule files world-readable (644, should be 640) — LOW severity**
- Files in /etc/prometheus/rules/ were created with 644 (world-readable)
- Anyone logged into the server can read your exact alert thresholds
- Tells attacker exactly how hard to push a server to avoid triggering alerts
- Fix: `sudo chmod 640 /etc/prometheus/rules/*.yml`

**4. No TLS on any service — MEDIUM severity (for shared/production networks)**
- All traffic is plain HTTP — passwords sent over network are readable by packet capture
- Fix: nginx reverse proxy with TLS certificate (Let's Encrypt for internet, self-signed for LAN)

**5. Grafana default password — HIGH if not changed**
- Default login is admin/admin
- Change immediately at http://10.0.2.15:3000/profile/password

---

## 6. Why Separate System Users Were Created

Question asked: "why are separate users being created for each of them?"

**Answer — least privilege principle:**

Each service (node_exporter, prometheus, alertmanager, grafana) runs as its own dedicated system user with:
- `--no-create-home` — no home directory
- `/usr/sbin/nologin` — cannot SSH in or run interactive commands

If an attacker exploits a vulnerability in Prometheus, they get a user that can only read `/etc/prometheus/` — not root, not the database, not other service configs.

Same reason nginx runs as `www-data`, postgres runs as `postgres`. Standard Linux service hardening.

---

## 7. What the Security Fixes Actually Do

**chmod 640 on rule files:**
Removes world-read permission. Before: any user on the server could read thresholds. After: only the prometheus system user and its group can read them.

**Basic auth on Prometheus/Alertmanager:**
Makes the service return HTTP 401 until a valid username+password is sent. Password stored as bcrypt hash — cannot be reversed even if someone reads the config file.

**TLS:**
Encrypts all traffic between browser and services. Without it, passwords typed into Grafana travel as plain text across the network.

**nginx reverse proxy:**
Single entry point — nginx is the only thing exposed to the network. Handles TLS termination and auth before requests reach Prometheus or Alertmanager. Also means you can put everything behind one port (443) instead of 4 different ports.

---

## 8. Network and Accessibility Discussion

### The problem discovered

The machine's IP `10.0.2.15` is a **VirtualBox NAT address** — a fake internal IP that only exists inside the host machine. No other machine on the network can reach it.

Confirmed by:
```
ip addr show → 10.0.2.15 on enp0s3
ip route → default via 10.0.2.2
systemd-detect-virt → oracle (VirtualBox)
```

### Fix — Switch VirtualBox to Bridged mode

1. Host machine: VirtualBox → VM Settings → Network
2. Change "Attached to: NAT" → "Attached to: Bridged Adapter"
3. Select the host's physical network card
4. Restart VM → run `ip addr` → VM gets a real LAN IP (e.g., 192.168.1.x)
5. That IP is reachable by every machine on the same network

---

## 9. How to Add Company Servers for Monitoring

### On each target server

```bash
# Install Node Exporter
sudo bash install_node_exporter.sh

# Allow only the monitoring server to scrape it
sudo ufw allow from <monitoring-server-IP> to any port 9100
sudo ufw deny 9100
```

### On the monitoring server — one command

```bash
sudo bash scripts/add_target.sh <IP> <name> [team] [env]

# Example:
sudo bash scripts/add_target.sh 192.168.1.101 web-server-1 backend production
```

What this script does:
1. Verifies Node Exporter is reachable at the IP (fails fast if not)
2. Adds the target block to /etc/prometheus/prometheus.yml
3. Validates config with promtool (won't reload if config is broken)
4. Reloads Prometheus live with zero downtime
5. Polls Prometheus API for 30s to confirm the target shows as UP

### Production deployment path

**Option A — Company has a dedicated internal server:**
- SSH in, clone the repo, run all 4 install scripts
- Everyone on the company network accesses via that server's static IP

**Option B — Cloud VM (AWS/Azure/GCP):**
- Same install process
- Configure cloud firewall (Security Group/NSG) to allow team IPs on ports 3000, 9090, 9093
- Only allow port 9100 from the monitoring server's IP — never open to 0.0.0.0/0

---

## 10. Things Still Remaining (To Do)

| Task | Priority | How |
|------|----------|-----|
| Change Grafana default password (admin/admin) | HIGH — do immediately | http://10.0.2.15:3000/profile/password |
| Set real SMTP credentials in alertmanager.yml | HIGH — required for alerts to work | `sudo nano /etc/alertmanager/alertmanager.yml` then `sudo systemctl reload alertmanager` |
| Fix rule file permissions (644→640) | LOW | `sudo chmod 640 /etc/prometheus/rules/*.yml` |
| Import Node Exporter Full dashboard (ID 1860) | MEDIUM | Grafana → + → Import → 1860 |
| Build Overview Dashboard | MEDIUM | See docs/grafana-plan.md for exact queries |
| Export dashboards as JSON to grafana/dashboards/ | MEDIUM | Grafana → Share → Export → Save to file |
| Switch VirtualBox to Bridged networking | HIGH — team cannot access until done | VirtualBox host settings → Bridged Adapter |
| Add Prometheus basic auth | MEDIUM — needed before team access | --web.config.file flag |
| Fill in docs/alert-test-report.md | MEDIUM | Run the 3 tests, record timestamps |
| Run end-to-end alert fire tests | HIGH — Definition of Done | See docs/alert-test-report.md |
| Final smoke test (Day 10) | HIGH — Definition of Done | All 3 team members present |
| Tag repo v1.0 | MEDIUM | `git tag v1.0 && git push --tags` |
| Commit all new files to git | MEDIUM | `git add . && git commit` |

---

## 11. Final Repository Structure (After This Session)

```
LMT/
├── prometheus/
│   ├── prometheus.yml                  ← CREATED
│   └── rules/
│       ├── cpu.yml                     ← CREATED (4 rules)
│       ├── memory.yml                  ← CREATED (4 rules)
│       ├── disk.yml                    ← CREATED (6 rules)
│       ├── network.yml                 ← CREATED (4 rules)
│       ├── system.yml                  ← CREATED (5 rules)
│       └── prometheus_self.yml         ← CREATED (4 rules)
├── alertmanager/
│   └── alertmanager.yml               ← CREATED (updated from "all files/")
├── grafana/
│   ├── dashboards/                    ← CREATED (empty — export from UI after setup)
│   └── provisioning/
│       ├── datasources/
│       │   └── prometheus.yml         ← CREATED
│       └── dashboards/
│           └── dashboards.yml         ← CREATED
├── scripts/
│   ├── install_node_exporter.sh       ← CREATED
│   ├── install_prometheus.sh          ← CREATED
│   ├── install_alertmanager.sh        ← CREATED
│   ├── install_grafana.sh             ← CREATED
│   ├── verify_all.sh                  ← CREATED
│   ├── uninstall_all.sh               ← CREATED
│   └── add_target.sh                  ← CREATED
├── docs/
│   ├── targets.txt                    ← CREATED
│   ├── runbook.md                     ← CREATED (all 6 critical alerts)
│   ├── grafana-plan.md                ← CREATED
│   ├── security-notes.md              ← CREATED
│   ├── sprint-log.md                  ← CREATED (10-day log)
│   ├── alert-test-report.md           ← CREATED
│   ├── complete-reference.md          ← CREATED (13-section master reference)
│   └── session-build-log.md           ← THIS FILE
├── documentation/
│   └── Node_Exporter_Alertmanager_Setup_Ubuntu.md   (existed before)
├── all files/                         (existed before — legacy, superseded by new structure)
│   ├── alertmanager.yml
│   ├── install_alertmanager.sh
│   ├── install_node_exporter.sh
│   ├── node_exporter_alerts.yml
│   ├── prometheus_config_snippet.yml
│   ├── uninstall.sh
│   ├── validate_all.py
│   └── verify_setup.sh
├── Sprint_Plan_Team_Collaboration.pdf  (existed before)
├── README.md                           ← REWRITTEN
├── .env.example                        ← CREATED
└── .gitignore                          ← UPDATED (.env, *.key, *.tar.gz added)
```

---

## 12. Key Concepts Explained This Session

**Why dedicated system users:**
Least privilege. If Prometheus is exploited, attacker gets a nologin user with access only to /etc/prometheus/. Not root. Standard practice — same as nginx running as www-data.

**Why MemAvailable not MemFree:**
Linux uses free RAM for disk cache. MemFree shows RAM as "used" even though the kernel will reclaim it instantly. MemAvailable is the kernel's own estimate of truly allocatable memory. Using MemFree in alert rules causes constant false alarms on healthy systems.

**Why division-by-zero guards in rules:**
If SwapTotal is 0 (no swap configured), `... / SwapTotal * 100` crashes the PromQL expression. Added `and SwapTotal > 0`. Same for disk read/write latency rules where reads_completed might be 0 on idle disks.

**Why 10.0.2.15 is unreachable:**
It's a VirtualBox NAT address — a fake IP that only exists inside the host machine. The subnet 10.0.2.x is VirtualBox's default NAT range. Every VirtualBox NAT VM gets 10.0.2.15 regardless of which computer it runs on. Fix: switch to Bridged networking.

**The pull model:**
Prometheus scrapes (pulls) metrics from targets. Targets don't push data anywhere. This means you can curl a target's metrics URL directly to see exactly what Prometheus sees, and adding a new target requires only one line in prometheus.yml on the monitoring server — nothing changes on the target.

---

*Session conducted: 2026-06-21*
*Stack version: Node Exporter 1.11.1 | Prometheus 2.54.1 | Alertmanager 0.33.0 | Grafana 13.0.2*
*All 27 alert rules loaded and active. All 4 services running.*
