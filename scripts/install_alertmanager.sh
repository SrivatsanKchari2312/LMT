#!/bin/bash
# ============================================================================
# Alertmanager v0.33.0 — Installation Script for Ubuntu
# ============================================================================
# Install on the central monitoring VM.
# Usage: sudo bash scripts/install_alertmanager.sh
# ============================================================================

set -euo pipefail

ALERTMANAGER_VERSION="0.33.0"

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
echo "===== Alertmanager v${ALERTMANAGER_VERSION} Installer ====="
echo ""

log_info "Step 1: Creating system user 'alertmanager'..."
if id "alertmanager" &>/dev/null; then
    log_ok "User already exists, skipping."
else
    useradd --no-create-home --shell /usr/sbin/nologin alertmanager
    log_ok "User 'alertmanager' created."
fi

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

log_info "Step 3: Installing configuration..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "${SCRIPT_DIR}")"

if [[ -f "${REPO_DIR}/alertmanager/alertmanager.yml" ]]; then
    cp "${REPO_DIR}/alertmanager/alertmanager.yml" /etc/alertmanager/alertmanager.yml
    log_ok "alertmanager.yml copied from repo."
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
  repeat_interval: 4h

receivers:
  - name: 'team-email'
    email_configs:
      - to: 'team-oncall@example.com'
        send_resolved: true
EOF
    log_ok "Default alertmanager.yml written — update SMTP values before use."
fi

chown alertmanager:alertmanager /etc/alertmanager/alertmanager.yml
chmod 640 /etc/alertmanager/alertmanager.yml

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

log_info "Step 5: Configuring amtool..."
mkdir -p /etc/amtool
tee /etc/amtool/config.yml > /dev/null <<'EOF'
alertmanager.url: http://localhost:9093
EOF
log_ok "amtool configured."

log_info "Step 6: Starting Alertmanager..."
systemctl daemon-reload
systemctl enable --now alertmanager
log_ok "Service enabled and started."

echo ""
echo "===== Verification ====="
systemctl status alertmanager --no-pager -l

echo ""
sleep 2
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:9093/-/healthy 2>/dev/null || echo "000")
if [[ "${HTTP_CODE}" == "200" ]]; then
    log_ok "Health endpoint responding (HTTP 200)."
else
    echo "WARNING: Health endpoint returned HTTP ${HTTP_CODE}. Check: journalctl -u alertmanager"
fi

echo ""
echo "===== Done ====="
echo ""
echo "  Web UI:  http://$(hostname -I | awk '{print $1}'):9093"
echo "  Config:  /etc/alertmanager/alertmanager.yml"
echo ""
echo "  IMPORTANT: Update SMTP credentials in /etc/alertmanager/alertmanager.yml"
echo "    sudo nano /etc/alertmanager/alertmanager.yml"
echo "    sudo systemctl reload alertmanager"
echo ""
echo "  Test alert: amtool alert add alertname=\"TestAlert\" instance=\"test-server\""
echo "  If firewall:  sudo ufw allow 9093/tcp"
echo ""
