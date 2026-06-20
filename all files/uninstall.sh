#!/bin/bash
# ============================================================================
# Uninstall — Cleanly removes Node Exporter and/or Alertmanager
# ============================================================================
# Usage: sudo bash uninstall.sh [node_exporter|alertmanager|all]
# ============================================================================

set -euo pipefail

GREEN='\033[0;32m'
NC='\033[0m'
log_ok() { echo -e "  ${GREEN}✓${NC} $1"; }

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Run as root — sudo bash $0"
    exit 1
fi

COMPONENT="${1:-all}"

uninstall_node_exporter() {
    echo ""
    echo "--- Removing Node Exporter ---"
    systemctl stop node_exporter 2>/dev/null && log_ok "Stopped" || true
    systemctl disable node_exporter 2>/dev/null && log_ok "Disabled" || true
    rm -f /etc/systemd/system/node_exporter.service
    systemctl daemon-reload
    log_ok "Service file removed"
    rm -f /usr/local/bin/node_exporter
    log_ok "Binary removed"
    id "node_exporter" &>/dev/null && userdel node_exporter && log_ok "User removed" || true
    echo "  Done."
}

uninstall_alertmanager() {
    echo ""
    echo "--- Removing Alertmanager ---"
    systemctl stop alertmanager 2>/dev/null && log_ok "Stopped" || true
    systemctl disable alertmanager 2>/dev/null && log_ok "Disabled" || true
    rm -f /etc/systemd/system/alertmanager.service
    systemctl daemon-reload
    log_ok "Service file removed"
    rm -f /usr/local/bin/alertmanager /usr/local/bin/amtool
    log_ok "Binaries removed"
    rm -rf /var/lib/alertmanager /etc/amtool
    log_ok "Data directories removed"
    echo "  NOTE: /etc/alertmanager/ kept as backup. Remove manually if needed."
    id "alertmanager" &>/dev/null && userdel alertmanager && log_ok "User removed" || true
    echo "  Done."
}

case "${COMPONENT}" in
    node_exporter)  uninstall_node_exporter ;;
    alertmanager)   uninstall_alertmanager ;;
    all)            uninstall_node_exporter; uninstall_alertmanager ;;
    *)              echo "Usage: sudo bash $0 [node_exporter|alertmanager|all]"; exit 1 ;;
esac

echo ""
