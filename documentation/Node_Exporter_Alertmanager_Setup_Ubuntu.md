# Node Exporter and Alertmanager — Setup Documentation

**Project:** Linux System Monitoring using Prometheus and Grafana  
**Phase Covered:** Phase 2 (Node Exporter) and Phase 4 (Alertmanager)  
**Operating System:** Ubuntu Linux  
**Date:** June 2026

---

## Table of Contents

1. [Introduction](#1-introduction)
2. [Prerequisites](#2-prerequisites)
3. [Part 1 — Node Exporter Installation](#3-part-1--node-exporter-installation)
4. [Part 2 — Alertmanager Installation](#4-part-2--alertmanager-installation)
5. [Configuration Files](#5-configuration-files)
6. [Verification and Testing](#6-verification-and-testing)
7. [Integration with Prometheus and Grafana](#7-integration-with-prometheus-and-grafana)
8. [Troubleshooting](#8-troubleshooting)
9. [Uninstallation](#9-uninstallation)

---

## 1. Introduction

### 1.1 Node Exporter (Section 4.2)

Node Exporter is a lightweight agent that must be installed and running on every Linux server that is to be monitored. Its job is simple but essential: it reads hardware and operating-system metrics directly from the Linux kernel's own interfaces, formats them into a Prometheus-compatible text format, and exposes them via an HTTP endpoint on port 9100.

The metrics exposed by Node Exporter are comprehensive. On the CPU side, it reports usage broken down per core and per mode, which means administrators can distinguish between time spent in user space, kernel space, idle, I/O wait, and so on. For memory, it provides a detailed breakdown of total, used, free, buffered, and cached memory. For storage, it reports capacity, usage, and available space per disk partition, as well as per-disk read and write throughput. It also exposes network interface statistics, system load averages, and uptime.

Because Node Exporter only reads and exposes data without performing any storage or processing itself, its resource footprint on the monitored server is negligible.

### 1.2 Alertmanager (Section 4.3)

While Prometheus is responsible for detecting that an alerting condition has been met, Alertmanager is responsible for deciding what to do about it. This separation of concerns is deliberate and valuable. It means that the logic for routing, grouping, and suppressing alerts can be managed independently from the monitoring configuration itself.

When Prometheus fires an alert, it sends the alert details to Alertmanager over HTTP. Alertmanager then applies its configured routing tree to determine who should be notified and through which channel. One of Alertmanager's most practically useful features is alert deduplication — it can group related alerts together and send a single, consolidated notification rather than flooding the recipient's inbox.

### 1.3 Architecture Diagram

```
┌───────────────────────────┐
│   Monitored Linux Server  │
│                           │
│   ┌───────────────────┐   │
│   │   Node Exporter   │   │
│   │   Port: 9100      │   │
│   └────────┬──────────┘   │
│            │              │
└────────────┼──────────────┘
             │ HTTP scrape (every 15s)
             ▼
┌────────────────────────────┐
│   Central Monitoring Server│
│                            │
│   ┌──────────────────┐     │     ┌──────────────────┐
│   │   Prometheus     │─────┼────▶│   Grafana        │
│   │   Port: 9090     │     │     │   Port: 3000     │
│   └────────┬─────────┘     │     │   (Dashboards)   │
│            │               │     └──────────────────┘
│            │ fires alerts  │
│            ▼               │
│   ┌──────────────────┐     │
│   │   Alertmanager   │     │
│   │   Port: 9093     │     │
│   └────────┬─────────┘     │
│            │               │
└────────────┼───────────────┘
             │
             ▼
      Email / Webhook
      Notifications
```

---

## 2. Prerequisites

### 2.1 System Requirements

- Ubuntu Linux (18.04 / 20.04 / 22.04 / 24.04)
- Root or sudo access
- Internet connectivity (to download binaries from GitHub)
- wget and tar utilities

### 2.2 Verify System Information

**Input:**
```bash
uname -a
```

**Expected Output:**
```
Linux ubuntu-server 5.15.0-91-generic #101-Ubuntu SMP x86_64 GNU/Linux
```

**Input:**
```bash
lsb_release -a
```

**Expected Output:**
```
Distributor ID: Ubuntu
Description:    Ubuntu 22.04.3 LTS
Release:        22.04
Codename:       jammy
```

**Input:**
```bash
uname -m
```

**Expected Output:**
```
x86_64
```

> **Note:** If the output shows `aarch64` instead of `x86_64`, you are on an ARM server. Replace `linux-amd64` with `linux-arm64` in all download URLs.

### 2.3 Install Required Packages

**Input:**
```bash
sudo apt update && sudo apt install -y wget tar curl
```

**Expected Output:**
```
Hit:1 http://archive.ubuntu.com/ubuntu jammy InRelease
...
Reading package lists... Done
Building dependency tree... Done
wget is already the newest version (1.21.2-2ubuntu1).
tar is already the newest version (1.34+dfsg-1ubuntu0.1.22.04.2).
curl is already the newest version (7.81.0-1ubuntu1.16).
0 upgraded, 0 newly installed, 0 to remove and 0 not upgraded.
```

---

## 3. Part 1 — Node Exporter Installation

Node Exporter must be installed on **every Linux server** that needs to be monitored.

### Step 1 — Create a Dedicated System User

Running Node Exporter as its own user (not root) limits what it can access, following the principle of least privilege.

**Input:**
```bash
sudo useradd --no-create-home --shell /usr/sbin/nologin node_exporter
```

**Expected Output:**
```
(no output — this is normal, means success)
```

**Verify the user was created:**

**Input:**
```bash
id node_exporter
```

**Expected Output:**
```
uid=1001(node_exporter) gid=1001(node_exporter) groups=1001(node_exporter)
```

### Step 2 — Download and Install the Binary

**Input:**
```bash
cd /tmp
wget https://github.com/prometheus/node_exporter/releases/download/v1.11.1/node_exporter-1.11.1.linux-amd64.tar.gz
```

**Expected Output:**
```
--2026-06-20 22:00:00--  https://github.com/prometheus/node_exporter/releases/download/v1.11.1/node_exporter-1.11.1.linux-amd64.tar.gz
Resolving github.com (github.com)... 140.82.121.3
Connecting to github.com (github.com)|140.82.121.3|:443... connected.
HTTP request sent, awaiting response... 302 Found
...
Saving to: 'node_exporter-1.11.1.linux-amd64.tar.gz'

node_exporter-1.11.1.linux-a 100%[==============================================>]  10.45M  5.22MB/s    in 2.0s

2026-06-20 22:00:03 (5.22 MB/s) - 'node_exporter-1.11.1.linux-amd64.tar.gz' saved [10960732]
```

**Extract the archive:**

**Input:**
```bash
tar xvf node_exporter-1.11.1.linux-amd64.tar.gz
```

**Expected Output:**
```
node_exporter-1.11.1.linux-amd64/
node_exporter-1.11.1.linux-amd64/LICENSE
node_exporter-1.11.1.linux-amd64/NOTICE
node_exporter-1.11.1.linux-amd64/node_exporter
```

**Copy the binary and set ownership:**

**Input:**
```bash
sudo cp node_exporter-1.11.1.linux-amd64/node_exporter /usr/local/bin/
sudo chown node_exporter:node_exporter /usr/local/bin/node_exporter
```

**Expected Output:**
```
(no output — success)
```

**Clean up downloaded files:**

**Input:**
```bash
rm -rf node_exporter-1.11.1.linux-amd64*
```

**Expected Output:**
```
(no output — success)
```

**Verify the binary is installed:**

**Input:**
```bash
node_exporter --version
```

**Expected Output:**
```
node_exporter, version 1.11.1 (branch: HEAD, revision: 6e3e7f0e7d0e0b2e1a0d4c9e8b5f3a2d1c0e9b8a)
  build user:       root@buildhost
  build date:       20260101-00:00:00
  go version:       go1.22.5
  platform:         linux/amd64
  tags:             unknown
```

### Step 3 — Create a Systemd Service

This makes Node Exporter start automatically on every boot and allows management through `systemctl`.

**Input:**
```bash
sudo tee /etc/systemd/system/node_exporter.service > /dev/null <<'EOF'
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
EOF
```

**Expected Output:**
```
(no output — success)
```

**Verify the file was created:**

**Input:**
```bash
cat /etc/systemd/system/node_exporter.service
```

**Expected Output:**
```
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
```

### Step 4 — Start and Enable the Service

**Input:**
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now node_exporter
```

**Expected Output:**
```
Created symlink /etc/systemd/system/multi-user.target.wants/node_exporter.service → /etc/systemd/system/node_exporter.service.
```

**Check the service status:**

**Input:**
```bash
sudo systemctl status node_exporter
```

**Expected Output:**
```
● node_exporter.service - Node Exporter
     Loaded: loaded (/etc/systemd/system/node_exporter.service; enabled; vendor preset: enabled)
     Active: active (running) since Fri 2026-06-20 22:05:00 IST; 5s ago
   Main PID: 12345 (node_exporter)
      Tasks: 5 (limit: 4614)
     Memory: 14.2M
        CPU: 23ms
     CGroup: /system.slice/node_exporter.service
             └─12345 /usr/local/bin/node_exporter

Jun 20 22:05:00 ubuntu-server systemd[1]: Started Node Exporter.
Jun 20 22:05:00 ubuntu-server node_exporter[12345]: ts=2026-06-20T16:35:00.000Z caller=node_exporter.go:199 level=info msg="Starting node_exporter" version="1.11.1"
Jun 20 22:05:00 ubuntu-server node_exporter[12345]: ts=2026-06-20T16:35:00.000Z caller=node_exporter.go:200 level=info msg="Build context" build_context="go1.22.5"
Jun 20 22:05:00 ubuntu-server node_exporter[12345]: ts=2026-06-20T16:35:00.000Z caller=tls_config.go:313 level=info msg="Listening on" address=[::]:9100
```

### Step 5 — Verify Metrics are Being Exposed

**Input:**
```bash
curl http://localhost:9100/metrics | head -20
```

**Expected Output:**
```
# HELP go_gc_duration_seconds A summary of pause duration of garbage collection cycles.
# TYPE go_gc_duration_seconds summary
go_gc_duration_seconds{quantile="0"} 2.3456e-05
go_gc_duration_seconds{quantile="0.25"} 3.4567e-05
go_gc_duration_seconds{quantile="0.5"} 4.5678e-05
go_gc_duration_seconds{quantile="0.75"} 5.6789e-05
go_gc_duration_seconds{quantile="1"} 0.000123456
go_gc_duration_seconds_sum 0.001234567
go_gc_duration_seconds_count 10
# HELP go_goroutines Number of goroutines that currently exist.
# TYPE go_goroutines gauge
go_goroutines 8
# HELP go_info Information about the Go environment.
# TYPE go_info gauge
go_info{version="go1.22.5"} 1
# HELP node_cpu_seconds_total Seconds the CPUs spent in each mode.
# TYPE node_cpu_seconds_total counter
node_cpu_seconds_total{cpu="0",mode="idle"} 123456.78
node_cpu_seconds_total{cpu="0",mode="iowait"} 123.45
node_cpu_seconds_total{cpu="0",mode="system"} 4567.89
```

**Check specific key metrics:**

**Input:**
```bash
curl -s http://localhost:9100/metrics | grep "node_memory_MemTotal_bytes"
```

**Expected Output:**
```
# HELP node_memory_MemTotal_bytes Memory information field MemTotal_bytes.
# TYPE node_memory_MemTotal_bytes gauge
node_memory_MemTotal_bytes 4.128903168e+09
```

**Input:**
```bash
curl -s http://localhost:9100/metrics | grep "node_filesystem_avail_bytes" | head -3
```

**Expected Output:**
```
node_filesystem_avail_bytes{device="/dev/sda1",fstype="ext4",mountpoint="/"} 1.5032385536e+10
node_filesystem_avail_bytes{device="tmpfs",fstype="tmpfs",mountpoint="/run"} 2.04521472e+08
node_filesystem_avail_bytes{device="/dev/sda15",fstype="vfat",mountpoint="/boot/efi"} 1.09422592e+08
```

### Step 6 — Open Firewall Port (if applicable)

This is needed only if the firewall is active and Prometheus runs on a different machine.

**Input:**
```bash
sudo ufw allow 9100/tcp
```

**Expected Output:**
```
Rule added
Rule added (v6)
```

**Verify:**

**Input:**
```bash
sudo ufw status | grep 9100
```

**Expected Output:**
```
9100/tcp                   ALLOW       Anywhere
9100/tcp (v6)              ALLOW       Anywhere (v6)
```

---

## 4. Part 2 — Alertmanager Installation

Alertmanager is installed on the **central monitoring server** (the same server where Prometheus runs, or a separate dedicated server).

### Step 1 — Create a Dedicated System User

**Input:**
```bash
sudo useradd --no-create-home --shell /usr/sbin/nologin alertmanager
```

**Expected Output:**
```
(no output — success)
```

**Verify:**

**Input:**
```bash
id alertmanager
```

**Expected Output:**
```
uid=1002(alertmanager) gid=1002(alertmanager) groups=1002(alertmanager)
```

### Step 2 — Download and Install Binaries

**Input:**
```bash
cd /tmp
wget https://github.com/prometheus/alertmanager/releases/download/v0.33.0/alertmanager-0.33.0.linux-amd64.tar.gz
```

**Expected Output:**
```
--2026-06-20 22:10:00--  https://github.com/prometheus/alertmanager/releases/download/v0.33.0/alertmanager-0.33.0.linux-amd64.tar.gz
Resolving github.com (github.com)... 140.82.121.3
Connecting to github.com (github.com)|140.82.121.3|:443... connected.
HTTP request sent, awaiting response... 302 Found
...
Saving to: 'alertmanager-0.33.0.linux-amd64.tar.gz'

alertmanager-0.33.0.linux-am 100%[==============================================>]  28.57M  6.12MB/s    in 4.7s

2026-06-20 22:10:05 (6.12 MB/s) - 'alertmanager-0.33.0.linux-amd64.tar.gz' saved [29956096]
```

**Extract the archive:**

**Input:**
```bash
tar xvf alertmanager-0.33.0.linux-amd64.tar.gz
```

**Expected Output:**
```
alertmanager-0.33.0.linux-amd64/
alertmanager-0.33.0.linux-amd64/LICENSE
alertmanager-0.33.0.linux-amd64/NOTICE
alertmanager-0.33.0.linux-amd64/alertmanager
alertmanager-0.33.0.linux-amd64/alertmanager.yml
alertmanager-0.33.0.linux-amd64/amtool
```

**Create directories and install binaries:**

**Input:**
```bash
sudo mkdir -p /etc/alertmanager /var/lib/alertmanager
sudo cp alertmanager-0.33.0.linux-amd64/alertmanager /usr/local/bin/
sudo cp alertmanager-0.33.0.linux-amd64/amtool /usr/local/bin/
sudo chown alertmanager:alertmanager /usr/local/bin/alertmanager /usr/local/bin/amtool /var/lib/alertmanager
```

**Expected Output:**
```
(no output — success)
```

**Clean up:**

**Input:**
```bash
rm -rf alertmanager-0.33.0.linux-amd64*
```

**Expected Output:**
```
(no output — success)
```

**Verify the binary is installed:**

**Input:**
```bash
alertmanager --version
```

**Expected Output:**
```
alertmanager, version 0.33.0 (branch: HEAD, revision: abc123def456)
  build user:       root@buildhost
  build date:       20260101-00:00:00
  go version:       go1.23.1
  platform:         linux/amd64
```

### Step 3 — Write the Configuration File

This is the routing and notification logic described in section 4.3 of the project documentation. Email is configured as the primary notification channel, with grouping enabled so that a single server outage does not produce multiple separate email alerts.

**Input:**
```bash
sudo tee /etc/alertmanager/alertmanager.yml > /dev/null <<'EOF'
global:
  resolve_timeout: 5m
  smtp_smarthost: 'smtp.gmail.com:587'
  smtp_from: 'your_project_email@gmail.com'
  smtp_auth_username: 'your_project_email@gmail.com'
  smtp_auth_password: 'your_16_char_app_password'
  smtp_require_tls: true

route:
  receiver: 'team-email'
  group_by: ['alertname', 'instance']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 3h

receivers:
  - name: 'team-email'
    email_configs:
      - to: 'team-oncall@example.com'
        send_resolved: true
EOF
```

**Expected Output:**
```
(no output — success)
```

> **Important:** Replace the placeholder values before starting the service:
> - `your_project_email@gmail.com` → your actual Gmail address
> - `your_16_char_app_password` → a Gmail App Password (enable 2FA first, then create one at https://myaccount.google.com/apppasswords)
> - `team-oncall@example.com` → the email address where alerts should be delivered

**Set file ownership:**

**Input:**
```bash
sudo chown alertmanager:alertmanager /etc/alertmanager/alertmanager.yml
```

**Expected Output:**
```
(no output — success)
```

**Verify the configuration file:**

**Input:**
```bash
cat /etc/alertmanager/alertmanager.yml
```

**Expected Output:**
```
global:
  resolve_timeout: 5m
  smtp_smarthost: 'smtp.gmail.com:587'
  smtp_from: 'your_project_email@gmail.com'
  smtp_auth_username: 'your_project_email@gmail.com'
  smtp_auth_password: 'your_16_char_app_password'
  smtp_require_tls: true

route:
  receiver: 'team-email'
  group_by: ['alertname', 'instance']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 3h

receivers:
  - name: 'team-email'
    email_configs:
      - to: 'team-oncall@example.com'
        send_resolved: true
```

**Configuration Explained:**

| Parameter | Value | Purpose |
|-----------|-------|---------|
| `resolve_timeout` | 5m | How long to wait before marking a silent alert as resolved |
| `smtp_smarthost` | smtp.gmail.com:587 | Gmail SMTP server with TLS |
| `smtp_require_tls` | true | Forces encrypted connection |
| `group_by` | alertname, instance | Groups alerts by name and server — prevents spam |
| `group_wait` | 30s | Waits 30 seconds to batch alerts from the same group |
| `group_interval` | 5m | Waits 5 minutes before sending updates to an existing group |
| `repeat_interval` | 3h | Re-sends an unresolved alert every 3 hours |
| `send_resolved` | true | Sends a recovery email when the alert clears |

**Alternative — Webhook Receiver (Slack/Discord):**

If you prefer to route alerts to a webhook instead of email, use this receiver block:

```yaml
receivers:
  - name: 'team-webhook'
    webhook_configs:
      - url: 'https://your-webhook-url-here'
        send_resolved: true
```

### Step 4 — Create the Systemd Service

**Input:**
```bash
sudo tee /etc/systemd/system/alertmanager.service > /dev/null <<'EOF'
[Unit]
Description=Alertmanager
After=network.target

[Service]
User=alertmanager
Group=alertmanager
Type=simple
ExecStart=/usr/local/bin/alertmanager \
  --config.file=/etc/alertmanager/alertmanager.yml \
  --storage.path=/var/lib/alertmanager

[Install]
WantedBy=multi-user.target
EOF
```

**Expected Output:**
```
(no output — success)
```

**Verify the file:**

**Input:**
```bash
cat /etc/systemd/system/alertmanager.service
```

**Expected Output:**
```
[Unit]
Description=Alertmanager
After=network.target

[Service]
User=alertmanager
Group=alertmanager
Type=simple
ExecStart=/usr/local/bin/alertmanager \
  --config.file=/etc/alertmanager/alertmanager.yml \
  --storage.path=/var/lib/alertmanager

[Install]
WantedBy=multi-user.target
```

### Step 5 — Start and Enable the Service

**Input:**
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now alertmanager
```

**Expected Output:**
```
Created symlink /etc/systemd/system/multi-user.target.wants/alertmanager.service → /etc/systemd/system/alertmanager.service.
```

**Check the service status:**

**Input:**
```bash
sudo systemctl status alertmanager
```

**Expected Output:**
```
● alertmanager.service - Alertmanager
     Loaded: loaded (/etc/systemd/system/alertmanager.service; enabled; vendor preset: enabled)
     Active: active (running) since Fri 2026-06-20 22:15:00 IST; 3s ago
   Main PID: 23456 (alertmanager)
      Tasks: 7 (limit: 4614)
     Memory: 18.5M
        CPU: 45ms
     CGroup: /system.slice/alertmanager.service
             └─23456 /usr/local/bin/alertmanager --config.file=/etc/alertmanager/alertmanager.yml --storage.path=/var/lib/alertmanager

Jun 20 22:15:00 ubuntu-server systemd[1]: Started Alertmanager.
Jun 20 22:15:00 ubuntu-server alertmanager[23456]: ts=2026-06-20T16:45:00.000Z caller=main.go:242 level=info msg="Starting Alertmanager" version="0.33.0"
Jun 20 22:15:00 ubuntu-server alertmanager[23456]: ts=2026-06-20T16:45:00.000Z caller=main.go:247 level=info build_context="go1.23.1"
Jun 20 22:15:00 ubuntu-server alertmanager[23456]: ts=2026-06-20T16:45:00.000Z caller=cluster.go:186 level=info msg="setting cluster advertisement address" addr=...
Jun 20 22:15:00 ubuntu-server alertmanager[23456]: ts=2026-06-20T16:45:00.000Z caller=main.go:281 level=info msg="Listening" address=:9093
```

### Step 6 — Verify Alertmanager

**Test the health endpoint:**

**Input:**
```bash
curl http://localhost:9093/-/healthy
```

**Expected Output:**
```
OK
```

**Test the readiness endpoint:**

**Input:**
```bash
curl http://localhost:9093/-/ready
```

**Expected Output:**
```
OK
```

**Open the Web UI:**

Open a browser and navigate to `http://<server-IP>:9093`. You should see the Alertmanager web interface showing no active alerts.

**Open the firewall port (if Prometheus is on a different machine):**

**Input:**
```bash
sudo ufw allow 9093/tcp
```

**Expected Output:**
```
Rule added
Rule added (v6)
```

### Step 7 — Test Alert Delivery (End-to-End Test)

To test Alertmanager without waiting for a real threshold breach, fire a synthetic test alert using `amtool`:

**Input:**
```bash
amtool alert add alertname="TestAlert" instance="test-server" severity="warning" --alertmanager.url=http://localhost:9093
```

**Expected Output:**
```
(no output — success, alert was sent)
```

**Check the alert is active:**

**Input:**
```bash
amtool alert --alertmanager.url=http://localhost:9093
```

**Expected Output:**
```
Alertname   Starts At                 Summary
TestAlert   2026-06-20 22:20:00 IST
```

> **Note:** If email is configured correctly, you should receive an email within `group_wait` time (30 seconds by default).

---

## 5. Configuration Files

### 5.1 Alertmanager Configuration

**File Location:** `/etc/alertmanager/alertmanager.yml`

```yaml
global:
  resolve_timeout: 5m
  smtp_smarthost: 'smtp.gmail.com:587'
  smtp_from: 'your_project_email@gmail.com'
  smtp_auth_username: 'your_project_email@gmail.com'
  smtp_auth_password: 'your_16_char_app_password'
  smtp_require_tls: true

route:
  receiver: 'team-email'
  group_by: ['alertname', 'instance']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 3h

receivers:
  - name: 'team-email'
    email_configs:
      - to: 'team-oncall@example.com'
        send_resolved: true
```

**How to edit after installation:**

**Input:**
```bash
sudo nano /etc/alertmanager/alertmanager.yml
```

After editing, validate and reload:

**Input:**
```bash
amtool check-config /etc/alertmanager/alertmanager.yml
```

**Expected Output:**
```
Checking '/etc/alertmanager/alertmanager.yml'  SUCCESS
Found:
 - global config
 - route
 - 0 inhibit rules
 - 1 receivers
 - 0 templates
```

**Input:**
```bash
sudo systemctl reload alertmanager
```

**Expected Output:**
```
(no output — success)
```

### 5.2 Node Exporter Systemd Service

**File Location:** `/etc/systemd/system/node_exporter.service`

```ini
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
```

### 5.3 Alertmanager Systemd Service

**File Location:** `/etc/systemd/system/alertmanager.service`

```ini
[Unit]
Description=Alertmanager
After=network.target

[Service]
User=alertmanager
Group=alertmanager
Type=simple
ExecStart=/usr/local/bin/alertmanager \
  --config.file=/etc/alertmanager/alertmanager.yml \
  --storage.path=/var/lib/alertmanager

[Install]
WantedBy=multi-user.target
```

---

## 6. Verification and Testing

### 6.1 Check All Services

**Input:**
```bash
sudo systemctl status node_exporter --no-pager
```

**Expected Output:**
```
● node_exporter.service - Node Exporter
     Loaded: loaded (/etc/systemd/system/node_exporter.service; enabled; vendor preset: enabled)
     Active: active (running) since Fri 2026-06-20 22:05:00 IST; 30min ago
   Main PID: 12345 (node_exporter)
     ...
```

**Input:**
```bash
sudo systemctl status alertmanager --no-pager
```

**Expected Output:**
```
● alertmanager.service - Alertmanager
     Loaded: loaded (/etc/systemd/system/alertmanager.service; enabled; vendor preset: enabled)
     Active: active (running) since Fri 2026-06-20 22:15:00 IST; 20min ago
   Main PID: 23456 (alertmanager)
     ...
```

### 6.2 Check Ports are Listening

**Input:**
```bash
ss -tlnp | grep -E '9100|9093'
```

**Expected Output:**
```
LISTEN 0      4096               *:9100            *:*    users:(("node_exporter",pid=12345,fd=3))
LISTEN 0      4096               *:9093            *:*    users:(("alertmanager",pid=23456,fd=8))
```

### 6.3 Verify Node Exporter Metrics

**Input:**
```bash
curl -s http://localhost:9100/metrics | grep -c "^node_"
```

**Expected Output:**
```
847
```

This shows that Node Exporter is exposing approximately 847 metrics (the exact number varies by system).

### 6.4 Check the Server IP Address

This is the IP your teammates need to configure in their Prometheus and Grafana setup.

**Input:**
```bash
ip -4 addr show | grep "inet " | grep -v "127.0.0.1"
```

**Expected Output:**
```
    inet 192.168.1.100/24 brd 192.168.1.255 scope global dynamic ens33
```

In this example, your server IP is `192.168.1.100`.

---

## 7. Integration with Prometheus and Grafana

### 7.1 What to Give Your Prometheus Teammate

Your Prometheus teammate needs two pieces of information from you:

**1. Scrape target** — every server running Node Exporter:

```yaml
scrape_configs:
  - job_name: 'node'
    static_configs:
      - targets: ['<server1-IP>:9100', '<server2-IP>:9100']
```

**2. Alertmanager address** — so Prometheus knows where to forward alerts:

```yaml
alerting:
  alertmanagers:
    - static_configs:
        - targets: ['<alertmanager-server-IP>:9093']
```

Replace `<server1-IP>`, `<server2-IP>`, and `<alertmanager-server-IP>` with the actual IP addresses from the `ip a` command output.

### 7.2 Alert Rules (for Prometheus teammate)

The following alert rules match the thresholds from section 6 of the project documentation (CPU idle < 20%, memory available < 10%, disk usage > 85%). Your Prometheus teammate should save this as `/etc/prometheus/rules.yml`:

```yaml
groups:
  - name: node_alerts
    rules:
      - alert: InstanceDown
        expr: up == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Instance {{ $labels.instance }} is DOWN"
          description: "{{ $labels.instance }} has been unreachable for more than 2 minutes."

      - alert: HighCpuUsage
        expr: (1 - avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m]))) * 100 > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High CPU on {{ $labels.instance }}"
          description: "CPU usage is {{ $value | printf \"%.1f\" }}% (threshold: 80%)."

      - alert: HighMemoryUsage
        expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 90
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory on {{ $labels.instance }}"
          description: "Memory usage is {{ $value | printf \"%.1f\" }}% (threshold: 90%)."

      - alert: DiskSpaceHigh
        expr: (1 - (node_filesystem_avail_bytes{fstype!~"tmpfs|squashfs"} / node_filesystem_size_bytes{fstype!~"tmpfs|squashfs"})) * 100 > 85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Disk space high on {{ $labels.instance }}"
          description: "{{ $labels.mountpoint }} is {{ $value | printf \"%.1f\" }}% full (threshold: 85%)."
```

And reference it in their `prometheus.yml`:

```yaml
rule_files:
  - "rules.yml"
```

### 7.3 For the Grafana Teammate

Node Exporter metrics are automatically available in Grafana through Prometheus. To get a ready-made dashboard:

1. Go to Grafana → **+** → **Import**
2. Enter Dashboard ID: **1860**
3. Select the Prometheus data source
4. Click **Import**

This imports the "Node Exporter Full" dashboard with CPU, Memory, Disk, and Network graphs.

---

## 8. Troubleshooting

### 8.1 Common Issues and Solutions

| Symptom | Likely Cause | Solution |
|---------|-------------|----------|
| `curl localhost:9100/metrics` fails | Service not running | `sudo systemctl status node_exporter` and `journalctl -u node_exporter` |
| Teammate's Prometheus can't scrape | Firewall blocking port 9100, or wrong IP | `sudo ufw allow 9100/tcp` and verify IP with `ip a` |
| Alertmanager UI won't load | YAML syntax error in config | `journalctl -u alertmanager` and `amtool check-config /etc/alertmanager/alertmanager.yml` |
| No email received on test alert | Wrong SMTP password | Gmail needs an App Password, not your normal login password |
| `systemctl enable --now` fails | Stale systemd cache | Run `sudo systemctl daemon-reload` first, then check the unit file for typos |
| Port conflict on 9100 or 9093 | Another process using the port | `sudo ss -tlnp \| grep 9100` to find the conflicting process |

### 8.2 Viewing Logs

**Node Exporter logs:**

**Input:**
```bash
sudo journalctl -u node_exporter -f
```

**Expected Output (normal operation):**
```
Jun 20 22:05:00 ubuntu-server node_exporter[12345]: ts=2026-06-20T16:35:00.000Z caller=node_exporter.go:199 level=info msg="Starting node_exporter" version="1.11.1"
Jun 20 22:05:00 ubuntu-server node_exporter[12345]: ts=2026-06-20T16:35:00.000Z caller=tls_config.go:313 level=info msg="Listening on" address=[::]:9100
```

Press `Ctrl+C` to stop following the logs.

**Alertmanager logs:**

**Input:**
```bash
sudo journalctl -u alertmanager -f
```

**Expected Output (normal operation):**
```
Jun 20 22:15:00 ubuntu-server alertmanager[23456]: ts=2026-06-20T16:45:00.000Z caller=main.go:242 level=info msg="Starting Alertmanager" version="0.33.0"
Jun 20 22:15:00 ubuntu-server alertmanager[23456]: ts=2026-06-20T16:45:00.000Z caller=main.go:281 level=info msg="Listening" address=:9093
```

### 8.3 Restarting Services

**Input:**
```bash
sudo systemctl restart node_exporter
sudo systemctl restart alertmanager
```

**Expected Output:**
```
(no output — success)
```

---

## 9. Uninstallation

If you need to completely remove Node Exporter and/or Alertmanager from the system.

### 9.1 Remove Node Exporter

**Input:**
```bash
sudo systemctl stop node_exporter
sudo systemctl disable node_exporter
sudo rm /etc/systemd/system/node_exporter.service
sudo systemctl daemon-reload
sudo rm /usr/local/bin/node_exporter
sudo userdel node_exporter
```

**Expected Output:**
```
Removed /etc/systemd/system/multi-user.target.wants/node_exporter.service.
```

### 9.2 Remove Alertmanager

**Input:**
```bash
sudo systemctl stop alertmanager
sudo systemctl disable alertmanager
sudo rm /etc/systemd/system/alertmanager.service
sudo systemctl daemon-reload
sudo rm /usr/local/bin/alertmanager /usr/local/bin/amtool
sudo rm -rf /var/lib/alertmanager /etc/amtool
sudo userdel alertmanager
```

**Expected Output:**
```
Removed /etc/systemd/system/multi-user.target.wants/alertmanager.service.
```

> **Note:** The configuration directory `/etc/alertmanager/` is preserved as a backup. Remove it manually with `sudo rm -rf /etc/alertmanager/` if no longer needed.

---

## Summary

| Component | Version | Port | Service Name | Config File |
|-----------|---------|------|-------------|-------------|
| Node Exporter | 1.11.1 | 9100 | `node_exporter` | (none — runs with defaults) |
| Alertmanager | 0.33.0 | 9093 | `alertmanager` | `/etc/alertmanager/alertmanager.yml` |

| Common Commands | |
|----------------|---|
| Check status | `sudo systemctl status node_exporter` / `sudo systemctl status alertmanager` |
| View logs | `sudo journalctl -u node_exporter -f` / `sudo journalctl -u alertmanager -f` |
| Restart | `sudo systemctl restart node_exporter` / `sudo systemctl restart alertmanager` |
| Reload config | `sudo systemctl reload alertmanager` |
| Validate config | `amtool check-config /etc/alertmanager/alertmanager.yml` |
| Test alert | `amtool alert add alertname="TestAlert" instance="test-server"` |
| Check alerts | `amtool alert` |
| Open firewall | `sudo ufw allow 9100/tcp` / `sudo ufw allow 9093/tcp` |

---

*End of Document*
