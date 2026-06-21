#!/bin/bash
# ============================================================================
# Add a new monitoring target to Prometheus
# ============================================================================
# Usage: sudo bash scripts/add_target.sh <IP> <friendly-name> [team] [env]
#
# Example:
#   sudo bash scripts/add_target.sh 192.168.1.101 web-server-1 backend production
# ============================================================================

set -euo pipefail

IP="${1:-}"
NAME="${2:-}"
TEAM="${3:-default}"
ENV="${4:-production}"

if [[ -z "$IP" || -z "$NAME" ]]; then
    echo "Usage: sudo bash $0 <IP> <friendly-name> [team] [env]"
    echo "Example: sudo bash $0 192.168.1.101 web-server-1 backend production"
    exit 1
fi

GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; }

echo ""
echo "===== Adding target: ${NAME} (${IP}:9100) ====="
echo ""

# Step 1: Verify Node Exporter is reachable
log_info "Step 1: Checking ${IP}:9100 is reachable..."
if curl -s --max-time 5 "http://${IP}:9100/metrics" | grep -q "node_cpu_seconds_total"; then
    log_ok "Node Exporter at ${IP}:9100 is responding."
else
    log_fail "Cannot reach ${IP}:9100 — make sure Node Exporter is installed and port is open."
    echo ""
    echo "  On the target server, run:"
    echo "    sudo bash scripts/install_node_exporter.sh"
    echo "    sudo ufw allow from $(hostname -I | awk '{print $1}') to any port 9100"
    exit 1
fi

# Step 2: Add to prometheus.yml
PROMETHEUS_CONFIG="/etc/prometheus/prometheus.yml"
log_info "Step 2: Adding to ${PROMETHEUS_CONFIG}..."

# Check if already exists
if grep -q "${IP}:9100" "${PROMETHEUS_CONFIG}"; then
    log_ok "Target ${IP}:9100 already in config — skipping."
else
    # Insert the new target before the closing of the node job
    # Append after the last target block
    python3 - <<PYEOF
import re

with open('${PROMETHEUS_CONFIG}', 'r') as f:
    content = f.read()

new_target = """
      - targets: ['${IP}:9100']
        labels:
          instance: '${NAME}'
          team: '${TEAM}'
          env: '${ENV}'"""

# Find the last targets entry under job_name: 'node' and append after it
# Simple approach: append before the comment block at end of node job
if 'Add company servers below' in content:
    content = content.replace(
        '      # ---------------------------------------------------------------\n      # Add company servers below',
        new_target + '\n\n      # ---------------------------------------------------------------\n      # Add company servers below'
    )
else:
    # Fallback: append to end of file
    content = content.rstrip() + new_target + '\n'

with open('${PROMETHEUS_CONFIG}', 'w') as f:
    f.write(content)

print("  Target added to config file.")
PYEOF
    log_ok "Target added to ${PROMETHEUS_CONFIG}."
fi

# Step 3: Validate config
log_info "Step 3: Validating config..."
if promtool check config "${PROMETHEUS_CONFIG}" > /dev/null 2>&1; then
    log_ok "Config valid."
else
    log_fail "Config validation failed — reverting is needed."
    promtool check config "${PROMETHEUS_CONFIG}"
    exit 1
fi

# Step 4: Reload Prometheus
log_info "Step 4: Reloading Prometheus..."
systemctl reload prometheus
sleep 2
log_ok "Prometheus reloaded."

# Step 5: Verify target shows as UP
log_info "Step 5: Checking target state in Prometheus (waiting up to 30s)..."
for i in $(seq 1 6); do
    STATE=$(curl -s "http://localhost:9090/api/v1/targets" | \
        python3 -c "
import json,sys
data = json.load(sys.stdin)
for t in data['data']['activeTargets']:
    if '${IP}:9100' in t['scrapeUrl']:
        print(t['health'])
        break
" 2>/dev/null || echo "pending")

    if [[ "${STATE}" == "up" ]]; then
        log_ok "Target ${NAME} (${IP}:9100) is UP in Prometheus."
        break
    else
        echo "  Waiting... (${i}/6) state=${STATE}"
        sleep 5
    fi
done

echo ""
echo "===== Done ====="
echo ""
echo "  Target: ${NAME} at ${IP}:9100"
echo "  View at: http://$(hostname -I | awk '{print $1}'):9090/targets"
echo ""
echo "  Update docs/targets.txt with this entry:"
echo "  ${NAME} | ${IP} | 9100 | ${NAME} | Ubuntu"
echo ""
