# Linux Monitoring Tool — Node Exporter & Alertmanager

Setup and configuration files for **Node Exporter** and **Alertmanager** on Ubuntu Linux, as part of a team monitoring project using Prometheus and Grafana.

## Project Structure

```
├── documentation/
│   └── Node_Exporter_Alertmanager_Setup_Ubuntu.md   # Full setup guide with inputs & outputs
├── all files/
│   ├── install_node_exporter.sh        # Node Exporter v1.11.1 installer
│   ├── install_alertmanager.sh         # Alertmanager v0.33.0 installer
│   ├── alertmanager.yml                # Alertmanager configuration
│   ├── node_exporter_alerts.yml        # Prometheus alert rules
│   ├── prometheus_config_snippet.yml   # Config snippet for Prometheus teammate
│   ├── verify_setup.sh                 # Verification script
│   ├── uninstall.sh                    # Clean removal script
│   └── validate_all.py                 # Windows validation script
```

## Components

| Component | Version | Port | Purpose |
|-----------|---------|------|---------|
| **Node Exporter** | 1.11.1 | 9100 | Exposes hardware and OS metrics from Linux servers |
| **Alertmanager** | 0.33.0 | 9093 | Routes, groups, and delivers alert notifications |

## Quick Start (on Ubuntu)

```bash
# Install Node Exporter
sudo bash install_node_exporter.sh

# Install Alertmanager
sudo bash install_alertmanager.sh

# Verify both
sudo bash verify_setup.sh
```

## Documentation

See [Node_Exporter_Alertmanager_Setup_Ubuntu.md](documentation/Node_Exporter_Alertmanager_Setup_Ubuntu.md) for the complete step-by-step guide with all commands and expected outputs.
