#!/bin/bash
# ============================================================================
# Grafana OSS — Installation Script for Ubuntu
# ============================================================================
# Install on the central monitoring VM.
# Usage: sudo bash scripts/install_grafana.sh
# ============================================================================

set -euo pipefail

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
echo "===== Grafana OSS Installer ====="
echo ""

# Step 1: Prerequisites
log_info "Step 1: Installing prerequisites..."
apt-get update -q
apt-get install -y -q apt-transport-https software-properties-common wget curl gnupg
log_ok "Prerequisites installed."

# Step 2: Add Grafana APT repository
log_info "Step 2: Adding Grafana APT repository..."
mkdir -p /usr/share/keyrings
wget -q -O /usr/share/keyrings/grafana.key https://apt.grafana.com/gpg.key
echo "deb [signed-by=/usr/share/keyrings/grafana.key] https://apt.grafana.com stable main" \
    | tee /etc/apt/sources.list.d/grafana.list > /dev/null
apt-get update -q
log_ok "Repository added."

# Step 3: Install Grafana
log_info "Step 3: Installing Grafana..."
apt-get install -y -q grafana
log_ok "Grafana installed: $(grafana-server -v 2>&1 | head -1)"

# Step 4: Copy provisioning configs from repo
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "${SCRIPT_DIR}")"

if [[ -d "${REPO_DIR}/grafana/provisioning" ]]; then
    log_info "Step 4: Installing provisioning configs..."
    mkdir -p /var/lib/grafana/dashboards

    if [[ -d "${REPO_DIR}/grafana/provisioning/datasources" ]]; then
        cp "${REPO_DIR}/grafana/provisioning/datasources/"*.yml \
            /etc/grafana/provisioning/datasources/ 2>/dev/null || true
        log_ok "Data source provisioning copied."
    fi

    if [[ -d "${REPO_DIR}/grafana/provisioning/dashboards" ]]; then
        cp "${REPO_DIR}/grafana/provisioning/dashboards/"*.yml \
            /etc/grafana/provisioning/dashboards/ 2>/dev/null || true
        log_ok "Dashboard provisioning copied."
    fi

    if [[ -d "${REPO_DIR}/grafana/dashboards" ]]; then
        cp "${REPO_DIR}/grafana/dashboards/"*.json \
            /var/lib/grafana/dashboards/ 2>/dev/null && \
            log_ok "Dashboard JSON files copied." || \
            log_ok "No dashboard JSONs yet — import from UI or commit to grafana/dashboards/."
    fi

    chown -R grafana:grafana /etc/grafana/provisioning /var/lib/grafana/dashboards
else
    log_info "No provisioning configs found in repo — configure via UI."
fi

# Step 5: Open firewall port
log_info "Step 5: Configuring firewall..."
if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "active"; then
    ufw allow 3000/tcp
    log_ok "Port 3000 opened in UFW."
else
    log_ok "UFW inactive — port 3000 accessible without rule."
fi

# Step 6: Start and enable
log_info "Step 6: Starting Grafana..."
systemctl daemon-reload
systemctl enable --now grafana-server
log_ok "Service enabled and started."

echo ""
echo "===== Verification ====="
systemctl status grafana-server --no-pager -l

echo ""
sleep 5
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/api/health 2>/dev/null || echo "000")
if [[ "${HTTP_CODE}" == "200" ]]; then
    log_ok "Grafana health endpoint OK (HTTP 200)."
else
    echo "INFO: Grafana may still be starting (HTTP ${HTTP_CODE}). Check: journalctl -u grafana-server -f"
fi

echo ""
echo "===== Done ====="
echo ""
echo "  Web UI:  http://$(hostname -I | awk '{print $1}'):3000"
echo "  Login:   admin / admin  (change on first login!)"
echo ""
echo "  Prometheus data source is auto-configured via provisioning."
echo ""
echo "  To import Node Exporter Full dashboard:"
echo "    1. Go to + → Import"
echo "    2. Enter Dashboard ID: 1860"
echo "    3. Select Prometheus data source → Import"
echo ""
