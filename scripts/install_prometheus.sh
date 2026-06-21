#!/bin/bash
# ============================================================================
# Prometheus v2.54.1 — Installation Script for Ubuntu
# ============================================================================
# Install on the central monitoring VM.
# Usage: sudo bash scripts/install_prometheus.sh
# ============================================================================

set -euo pipefail

PROMETHEUS_VERSION="2.54.1"
PROMETHEUS_USER="prometheus"
PROMETHEUS_DIR="/etc/prometheus"
PROMETHEUS_DATA_DIR="/var/lib/prometheus"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok()   { echo -e "${GREEN}[OK]${NC} $1"; }

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Run as root — sudo bash $0"
    exit 1
fi

echo ""
echo "===== Prometheus v${PROMETHEUS_VERSION} Installer ====="
echo ""

# Step 1: Create dedicated user
log_info "Step 1: Creating system user 'prometheus'..."
if id "prometheus" &>/dev/null; then
    log_ok "User already exists, skipping."
else
    useradd --no-create-home --shell /usr/sbin/nologin prometheus
    log_ok "User 'prometheus' created."
fi

# Step 2: Create directories
log_info "Step 2: Creating directories..."
mkdir -p "${PROMETHEUS_DIR}/rules" "${PROMETHEUS_DATA_DIR}"
log_ok "Directories created."

# Step 3: Download and install
log_info "Step 3: Downloading Prometheus v${PROMETHEUS_VERSION}..."
cd /tmp
wget -q "https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"
tar xf "prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"

cp "prometheus-${PROMETHEUS_VERSION}.linux-amd64/prometheus" /usr/local/bin/
cp "prometheus-${PROMETHEUS_VERSION}.linux-amd64/promtool" /usr/local/bin/
cp -r "prometheus-${PROMETHEUS_VERSION}.linux-amd64/consoles" "${PROMETHEUS_DIR}/"
cp -r "prometheus-${PROMETHEUS_VERSION}.linux-amd64/console_libraries" "${PROMETHEUS_DIR}/"

chown -R prometheus:prometheus "${PROMETHEUS_DIR}" "${PROMETHEUS_DATA_DIR}"
chown prometheus:prometheus /usr/local/bin/prometheus /usr/local/bin/promtool
rm -rf "prometheus-${PROMETHEUS_VERSION}.linux-amd64"*
log_ok "Binaries installed: prometheus, promtool"

# Step 4: Install configuration from repo
log_info "Step 4: Installing configuration files..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "${SCRIPT_DIR}")"

if [[ -f "${REPO_DIR}/prometheus/prometheus.yml" ]]; then
    cp "${REPO_DIR}/prometheus/prometheus.yml" "${PROMETHEUS_DIR}/prometheus.yml"
    log_ok "prometheus.yml copied from repo."
else
    log_info "Writing default prometheus.yml..."
    tee "${PROMETHEUS_DIR}/prometheus.yml" > /dev/null <<'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

alerting:
  alertmanagers:
    - static_configs:
        - targets: ['localhost:9093']

rule_files:
  - "rules/*.yml"

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
  - job_name: 'node'
    static_configs:
      - targets: ['localhost:9100']
EOF
    log_ok "Default prometheus.yml written."
fi

if [[ -d "${REPO_DIR}/prometheus/rules" ]]; then
    cp "${REPO_DIR}/prometheus/rules/"*.yml "${PROMETHEUS_DIR}/rules/" 2>/dev/null && \
        log_ok "Alert rule files copied to ${PROMETHEUS_DIR}/rules/" || \
        log_ok "No rule files found yet — add them later."
fi

chown -R prometheus:prometheus "${PROMETHEUS_DIR}"
chmod 640 "${PROMETHEUS_DIR}/prometheus.yml"

# Step 5: Validate config
log_info "Step 5: Validating configuration..."
if /usr/local/bin/promtool check config "${PROMETHEUS_DIR}/prometheus.yml" > /dev/null 2>&1; then
    log_ok "prometheus.yml is valid."
else
    echo "WARNING: Config validation failed. Review: promtool check config ${PROMETHEUS_DIR}/prometheus.yml"
fi

# Step 6: Create systemd service
log_info "Step 6: Creating systemd service..."
tee /etc/systemd/system/prometheus.service > /dev/null <<EOF
[Unit]
Description=Prometheus
After=network.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \\
  --config.file=${PROMETHEUS_DIR}/prometheus.yml \\
  --storage.tsdb.path=${PROMETHEUS_DATA_DIR} \\
  --storage.tsdb.retention.time=15d \\
  --web.console.templates=${PROMETHEUS_DIR}/consoles \\
  --web.console.libraries=${PROMETHEUS_DIR}/console_libraries
ExecReload=/bin/kill -HUP \$MAINPID

[Install]
WantedBy=multi-user.target
EOF
log_ok "Service file created."

# Step 7: Start and enable
log_info "Step 7: Starting Prometheus..."
systemctl daemon-reload
systemctl enable --now prometheus
log_ok "Service enabled and started."

echo ""
echo "===== Verification ====="
systemctl status prometheus --no-pager -l

echo ""
sleep 3
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:9090/-/healthy 2>/dev/null || echo "000")
if [[ "${HTTP_CODE}" == "200" ]]; then
    log_ok "Prometheus health endpoint OK (HTTP 200)."
else
    echo "INFO: Health endpoint returned HTTP ${HTTP_CODE} — may still be starting."
    echo "      Check: journalctl -u prometheus -f"
fi

echo ""
echo "===== Done ====="
echo ""
echo "  Web UI:     http://$(hostname -I | awk '{print $1}'):9090"
echo "  Targets:    http://$(hostname -I | awk '{print $1}'):9090/targets"
echo "  Alerts:     http://$(hostname -I | awk '{print $1}'):9090/alerts"
echo "  Config dir: ${PROMETHEUS_DIR}"
echo ""
echo "  Validate config: promtool check config ${PROMETHEUS_DIR}/prometheus.yml"
echo "  Validate rules:  promtool check rules ${PROMETHEUS_DIR}/rules/*.yml"
echo "  Reload:          sudo systemctl reload prometheus"
echo ""
echo "  If firewall is active: sudo ufw allow 9090/tcp"
echo ""
