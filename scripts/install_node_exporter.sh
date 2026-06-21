#!/bin/bash
# ============================================================================
# Node Exporter v1.11.1 — Installation Script for Ubuntu
# ============================================================================
# Install on every Linux server that needs to be monitored.
# Usage: sudo bash scripts/install_node_exporter.sh
# ============================================================================

set -euo pipefail

NODE_EXPORTER_VERSION="1.11.1"

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
echo "===== Node Exporter v${NODE_EXPORTER_VERSION} Installer ====="
echo ""

log_info "Step 1: Creating system user 'node_exporter'..."
if id "node_exporter" &>/dev/null; then
    log_ok "User already exists, skipping."
else
    useradd --no-create-home --shell /usr/sbin/nologin node_exporter
    log_ok "User 'node_exporter' created."
fi

log_info "Step 2: Downloading Node Exporter v${NODE_EXPORTER_VERSION}..."
cd /tmp
wget -q "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
tar xf "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
cp "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter" /usr/local/bin/
chown node_exporter:node_exporter /usr/local/bin/node_exporter
rm -rf "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64"*
log_ok "Binary installed to /usr/local/bin/node_exporter"

log_info "Step 3: Creating systemd service..."
tee /etc/systemd/system/node_exporter.service > /dev/null <<'EOF'
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
log_ok "Service file created."

log_info "Step 4: Starting Node Exporter..."
systemctl daemon-reload
systemctl enable --now node_exporter
log_ok "Service enabled and started."

echo ""
echo "===== Verification ====="
systemctl status node_exporter --no-pager -l

echo ""
sleep 2
if curl -s http://localhost:9100/metrics | grep -q "node_cpu_seconds_total"; then
    log_ok "Metrics endpoint responding on port 9100."
    echo ""
    echo "Sample metrics:"
    curl -s http://localhost:9100/metrics | grep -E "^node_cpu_seconds_total|^node_memory_MemTotal|^node_filesystem_avail" | head -5
else
    echo "WARNING: Metrics endpoint not responding. Check: journalctl -u node_exporter"
fi

echo ""
echo "===== Done ====="
echo ""
echo "  Metrics URL: http://$(hostname -I | awk '{print $1}'):9100/metrics"
echo "  Give your Prometheus teammate: targets: ['$(hostname -I | awk '{print $1}'):9100']"
echo ""
echo "  If firewall is active: sudo ufw allow 9100/tcp"
echo ""
