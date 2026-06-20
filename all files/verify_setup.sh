#!/bin/bash
# ============================================================================
# Quick Verification — Run after installing both components
# ============================================================================
# Usage: sudo bash verify_setup.sh
# ============================================================================

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0; FAIL=0

check_pass() { echo -e "  ${GREEN}✓${NC} $1"; ((PASS++)); }
check_fail() { echo -e "  ${RED}✗${NC} $1"; ((FAIL++)); }
check_warn() { echo -e "  ${YELLOW}!${NC} $1"; }

echo ""
echo "===== Node Exporter Checks ====="

# Binary
[[ -f /usr/local/bin/node_exporter ]] && check_pass "Binary installed" || check_fail "Binary missing"

# User
id "node_exporter" &>/dev/null && check_pass "User exists" || check_fail "User missing"

# Service running
systemctl is-active --quiet node_exporter && check_pass "Service running" || check_fail "Service NOT running"

# Service enabled
systemctl is-enabled --quiet node_exporter 2>/dev/null && check_pass "Service enabled on boot" || check_fail "Service NOT enabled"

# Port listening
ss -tlnp | grep -q ":9100" && check_pass "Port 9100 listening" || check_fail "Port 9100 NOT listening"

# Metrics endpoint
if curl -s http://localhost:9100/metrics | grep -q "node_cpu_seconds_total"; then
    check_pass "Metrics endpoint responding"
else
    check_fail "Metrics endpoint NOT responding"
fi

echo ""
echo "===== Alertmanager Checks ====="

# Binary
[[ -f /usr/local/bin/alertmanager ]] && check_pass "Binary installed" || check_fail "Binary missing"

# amtool
[[ -f /usr/local/bin/amtool ]] && check_pass "amtool installed" || check_fail "amtool missing"

# User
id "alertmanager" &>/dev/null && check_pass "User exists" || check_fail "User missing"

# Config file
[[ -f /etc/alertmanager/alertmanager.yml ]] && check_pass "Config file exists" || check_fail "Config file missing"

# Service running
systemctl is-active --quiet alertmanager && check_pass "Service running" || check_fail "Service NOT running"

# Service enabled
systemctl is-enabled --quiet alertmanager 2>/dev/null && check_pass "Service enabled on boot" || check_fail "Service NOT enabled"

# Port listening
ss -tlnp | grep -q ":9093" && check_pass "Port 9093 listening" || check_fail "Port 9093 NOT listening"

# Health endpoint
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:9093/-/healthy 2>/dev/null || echo "000")
[[ "${HTTP_CODE}" == "200" ]] && check_pass "Health endpoint OK (HTTP 200)" || check_fail "Health endpoint returned HTTP ${HTTP_CODE}"

# Config validation
if command -v amtool &>/dev/null; then
    amtool check-config /etc/alertmanager/alertmanager.yml > /dev/null 2>&1 && check_pass "Config syntax valid" || check_fail "Config syntax errors"
fi

echo ""
echo "===== Firewall ====="
if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "active"; then
    ufw status | grep -q "9100" && check_pass "Port 9100 allowed" || check_warn "Port 9100 may be blocked — sudo ufw allow 9100/tcp"
    ufw status | grep -q "9093" && check_pass "Port 9093 allowed" || check_warn "Port 9093 may be blocked — sudo ufw allow 9093/tcp"
else
    check_warn "UFW inactive or not installed (ports are accessible)"
fi

echo ""
echo "===== Results: ${PASS} passed, ${FAIL} failed ====="
if [[ ${FAIL} -eq 0 ]]; then
    echo -e "${GREEN}All checks passed!${NC}"
    echo ""
    echo "  Node Exporter: http://$(hostname -I | awk '{print $1}'):9100/metrics"
    echo "  Alertmanager:  http://$(hostname -I | awk '{print $1}'):9093"
else
    echo -e "${RED}${FAIL} check(s) failed. Review output above.${NC}"
fi
echo ""
