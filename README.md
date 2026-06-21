# Linux Monitoring Stack

Production-ready Linux server monitoring stack built with **Prometheus + Node Exporter + Alertmanager + Grafana**. Internship project — 3-person sprint, 2 weeks.

## Stack Architecture

```
┌──────────────────────┐
│  Monitored Servers   │
│  Node Exporter :9100 │
└──────────┬───────────┘
           │ scrape (15s)
           ▼
┌──────────────────────────────────────┐
│         Monitoring VM                │
│                                      │
│  Prometheus :9090  ──────────────▶  Grafana :3000
│       │                              │
│       │ fires alerts                 │ (dashboards)
│       ▼                              │
│  Alertmanager :9093                  │
│       │                              │
└───────┼──────────────────────────────┘
        │
        ▼
   Email / Webhook
```

## Repository Structure

```
├── prometheus/
│   ├── prometheus.yml              # Main Prometheus config
│   └── rules/
│       ├── cpu.yml                 # 4 CPU alert rules
│       ├── memory.yml              # 4 memory alert rules
│       ├── disk.yml                # 6 disk alert rules
│       ├── network.yml             # 4 network alert rules
│       ├── system.yml              # 5 system health rules
│       └── prometheus_self.yml     # 4 self-monitoring rules
├── alertmanager/
│   └── alertmanager.yml            # Routing + email receiver
├── grafana/
│   ├── dashboards/                 # Exported dashboard JSONs
│   └── provisioning/               # Auto-load data source + dashboards
│       ├── datasources/prometheus.yml
│       └── dashboards/dashboards.yml
├── scripts/
│   ├── install_node_exporter.sh    # Node Exporter v1.11.1
│   ├── install_prometheus.sh       # Prometheus v2.54.1
│   ├── install_alertmanager.sh     # Alertmanager v0.33.0
│   ├── install_grafana.sh          # Grafana OSS (latest stable)
│   ├── verify_all.sh               # Full stack health check
│   └── uninstall_all.sh            # Clean removal
├── docs/
│   ├── targets.txt                 # Scrape target inventory (Handoff 1)
│   ├── runbook.md                  # Runbooks for 6 critical alerts
│   ├── grafana-plan.md             # Dashboard design notes
│   ├── security-notes.md           # File permissions, nginx proxy
│   ├── sprint-log.md               # Daily standup log
│   └── alert-test-report.md        # End-to-end test results
├── documentation/
│   └── Node_Exporter_Alertmanager_Setup_Ubuntu.md
├── .env.example                    # Credential template (copy to .env)
└── .gitignore
```

## Quick Start

```bash
# 1. Install all components (on monitoring VM)
sudo bash scripts/install_node_exporter.sh
sudo bash scripts/install_prometheus.sh
sudo bash scripts/install_alertmanager.sh
sudo bash scripts/install_grafana.sh

# 2. Verify the full stack
sudo bash scripts/verify_all.sh

# 3. Open Grafana
# http://<server-IP>:3000  (admin / admin)
```

## Component Summary

| Component | Version | Port | Purpose |
|-----------|---------|------|---------|
| Node Exporter | 1.11.1 | 9100 | Exposes OS/hardware metrics |
| Prometheus | 2.54.1 | 9090 | Scrapes and evaluates alert rules |
| Alertmanager | 0.33.0 | 9093 | Routes and delivers alert notifications |
| Grafana | latest | 3000 | Dashboards and visualization |

## Alert Rules (20 total)

| File | Rules | Categories |
|------|-------|-----------|
| `cpu.yml` | 4 | HighCPUWarning, HighCPUCritical, HighIOWait, HighLoadAverage |
| `memory.yml` | 4 | LowMemoryWarning, LowMemoryCritical, SwapUsageHigh, OOMKillDetected |
| `disk.yml` | 6 | LowDiskWarning, LowDiskCritical, DiskFillingFast, InodeExhaustionWarning, HighDiskReadLatency, HighDiskWriteLatency |
| `network.yml` | 4 | HighRXBandwidth, HighTXBandwidth, HighNetworkErrorRate, NetworkInterfaceDown |
| `system.yml` | 5 | InstanceDown, UnexpectedReboot, HighZombieProcesses, HighFileDescriptors, ClockSkewDetected |
| `prometheus_self.yml` | 4 | ConfigReloadFailure, ScrapeErrorsIncreasing, AlertmanagerNotReachable, TSDBCompactionFailures |

## Common Commands

| Task | Command |
|------|---------|
| Check all services | `sudo bash scripts/verify_all.sh` |
| Reload Prometheus config | `sudo systemctl reload prometheus` |
| Validate prometheus.yml | `promtool check config /etc/prometheus/prometheus.yml` |
| Validate rule files | `promtool check rules /etc/prometheus/rules/*.yml` |
| Validate alertmanager.yml | `amtool check-config /etc/alertmanager/alertmanager.yml` |
| Fire test alert | `amtool alert add alertname="TestAlert" instance="test"` |
| View Prometheus logs | `sudo journalctl -u prometheus -f` |
| View Alertmanager logs | `sudo journalctl -u alertmanager -f` |

## Alertmanager Setup

Edit `/etc/alertmanager/alertmanager.yml` with real SMTP credentials, then reload:

```bash
sudo nano /etc/alertmanager/alertmanager.yml
sudo systemctl reload alertmanager
amtool check-config /etc/alertmanager/alertmanager.yml
```

For Gmail: enable 2FA, then create an App Password at `myaccount.google.com/apppasswords`.

## Grafana Dashboards

1. **Node Exporter Full** — Import ID `1860` from Grafana's dashboard registry
2. **Overview Dashboard** — Custom dashboard (see `docs/grafana-plan.md`)

Both dashboards are exported as JSON in `grafana/dashboards/` and auto-loaded via provisioning.

## Documentation

See `documentation/Node_Exporter_Alertmanager_Setup_Ubuntu.md` for the full step-by-step setup guide with expected command outputs.

See `docs/runbook.md` for critical alert runbooks.
