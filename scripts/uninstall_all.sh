#!/bin/bash
# ============================================================================
# Full Stack Uninstall — Removes all 4 components
# ============================================================================
# Usage: sudo bash scripts/uninstall_all.sh
# ============================================================================

set -euo pipefail

RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_done() { echo -e "${RED}[REMOVED]${NC} $1"; }

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Run as root — sudo bash $0"
    exit 1
fi

echo ""
echo "===== Full Stack Uninstall ====="
echo "This will remove Node Exporter, Prometheus, Alertmanager, and Grafana."
read -rp "Continue? [y/N] " confirm
[[ "${confirm}" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
echo ""

# Node Exporter
log_info "Removing Node Exporter..."
systemctl stop node_exporter 2>/dev/null || true
systemctl disable node_exporter 2>/dev/null || true
rm -f /etc/systemd/system/node_exporter.service
rm -f /usr/local/bin/node_exporter
userdel node_exporter 2>/dev/null || true
log_done "Node Exporter removed."

# Prometheus
log_info "Removing Prometheus..."
systemctl stop prometheus 2>/dev/null || true
systemctl disable prometheus 2>/dev/null || true
rm -f /etc/systemd/system/prometheus.service
rm -f /usr/local/bin/prometheus /usr/local/bin/promtool
rm -rf /etc/prometheus /var/lib/prometheus
userdel prometheus 2>/dev/null || true
log_done "Prometheus removed."

# Alertmanager
log_info "Removing Alertmanager..."
systemctl stop alertmanager 2>/dev/null || true
systemctl disable alertmanager 2>/dev/null || true
rm -f /etc/systemd/system/alertmanager.service
rm -f /usr/local/bin/alertmanager /usr/local/bin/amtool
rm -rf /var/lib/alertmanager /etc/amtool /etc/alertmanager
userdel alertmanager 2>/dev/null || true
log_done "Alertmanager removed."

# Grafana
log_info "Removing Grafana..."
systemctl stop grafana-server 2>/dev/null || true
systemctl disable grafana-server 2>/dev/null || true
apt-get remove -y grafana 2>/dev/null || true
rm -f /etc/apt/sources.list.d/grafana.list
log_done "Grafana removed."

systemctl daemon-reload

echo ""
echo "===== Uninstall Complete ====="
echo "All config files in /etc/ have been removed."
echo "Repository files are untouched."
echo ""
