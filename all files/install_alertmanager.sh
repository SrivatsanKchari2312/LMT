#!/bin/bash
# ============================================================================
# Alertmanager v0.33.0 — Installation Script for Ubuntu
# ============================================================================
# Install on the central monitoring server.
# Usage: sudo bash install_alertmanager.sh
# ============================================================================

set -euo pipefail

# ---- Configuration ----
ALERTMANAGER_VERSION="0.33.0"

# ---- Color helpers ----
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok()   { echo -e "${GREEN}[OK]${NC} $1"; }

# ---- Pre-flight ----
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Run as root — sudo bash $0"
    exit 1
fi

echo ""
echo "===== Alertmanager v${ALERTMANAGER_VERSION} Installer ====="
echo ""

# Step 1: Create a dedicated system user
log_info "Step 1: Creating system user 'alertmanager'..."
if id "alertmanager" &>/dev/null; then
    log_ok "User already exists, skipping."
else
    useradd --no-create-home --shell /usr/sbin/nologin alertmanager
    log_ok "User 'alertmanager' created."
fi

# Step 2: Download and install binaries
log_info "Step 2: Downloading Alertmanager v${ALERTMANAGER_VERSION}..."
cd /tmp
wget -q "https://github.com/prometheus/alertmanager/releases/download/v${ALERTMANAGER_VERSION}/alertmanager-${ALERTMANAGER_VERSION}.linux-amd64.tar.gz"
tar xf "alertmanager-${ALERTMANAGER_VERSION}.linux-amd64.tar.gz"
mkdir -p /etc/alertmanager /var/lib/alertmanager
cp "alertmanager-${ALERTMANAGER_VERSION}.linux-amd64/alertmanager" /usr/local/bin/
cp "alertmanager-${ALERTMANAGER_VERSION}.linux-amd64/amtool" /usr/local/bin/
chown alertmanager:alertmanager /usr/local/bin/alertmanager /usr/local/bin/amtool /var/lib/alertmanager
rm -rf "alertmanager-${ALERTMANAGER_VERSION}.linux-amd64"*
log_ok "Binaries installed: alertmanager, amtool"

# Step 3: Write configuration file
log_info "Step 3: Writing alertmanager.yml..."

# Check if custom config exists alongside this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/alertmanager.yml" ]]; then
    cp "${SCRIPT_DIR}/alertmanager.yml" /etc/alertmanager/alertmanager.yml
    log_ok "Custom alertmanager.yml copied from ${SCRIPT_DIR}/"
else
    tee /etc/alertmanager/alertmanager.yml > /dev/null <<'EOF'
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
    log_ok "Default alertmanager.yml written."
fi

chown alertmanager:alertmanager /etc/alertmanager/alertmanager.yml

# Step 4: Create systemd service
log_info "Step 4: Creating systemd service..."
tee /etc/systemd/system/alertmanager.service > /dev/null <<'EOF'
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
log_ok "Service file created."

# Step 5: Start and enable
log_info "Step 5: Starting Alertmanager..."
systemctl daemon-reload
systemctl enable --now alertmanager
log_ok "Service enabled and started."

# Step 6: Configure amtool
mkdir -p /etc/amtool
tee /etc/amtool/config.yml > /dev/null <<'EOF'
alertmanager.url: http://localhost:9093
EOF
log_ok "amtool configured."

# Verify
echo ""
echo "===== Verification ====="
systemctl status alertmanager --no-pager -l

echo ""
sleep 2
if curl -s -o /dev/null -w "%{http_code}" http://localhost:9093/-/healthy 2>/dev/null | grep -q "200"; then
    log_ok "Health endpoint responding (HTTP 200)."
else
    echo "WARNING: Health endpoint not responding yet. Check: journalctl -u alertmanager"
fi

echo ""
echo "===== Done ====="
echo ""
echo "  Web UI:  http://$(hostname -I | awk '{print $1}'):9093"
echo "  Config:  /etc/alertmanager/alertmanager.yml"
echo ""
echo "  IMPORTANT: Edit the config with real SMTP/email values, then reload:"
echo "    sudo nano /etc/alertmanager/alertmanager.yml"
echo "    sudo systemctl reload alertmanager"
echo ""
echo "  Give your Prometheus teammate this Alertmanager address:"
echo "    targets: ['$(hostname -I | awk '{print $1}'):9093']"
echo ""
echo "  To test end-to-end without a real alert:"
echo "    amtool alert add alertname=\"TestAlert\" instance=\"test-server\""
echo ""
echo "  If firewall is active:  sudo ufw allow 9093/tcp"
echo ""
