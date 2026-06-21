#!/bin/bash
# ============================================================================
# Full Stack Verification — Node Exporter + Prometheus + Alertmanager + Grafana
# ============================================================================
# Usage: sudo bash scripts/verify_all.sh
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
echo "===== Node Exporter ====="
[[ -f /usr/local/bin/node_exporter ]] && check_pass "Binary installed" || check_fail "Binary missing"
id "node_exporter" &>/dev/null && check_pass "User exists" || check_fail "User missing"
systemctl is-active --quiet node_exporter && check_pass "Service running" || check_fail "Service NOT running"
systemctl is-enabled --quiet node_exporter 2>/dev/null && check_pass "Service enabled on boot" || check_fail "Service NOT enabled"
ss -tlnp | grep -q ":9100" && check_pass "Port 9100 listening" || check_fail "Port 9100 NOT listening"
curl -s http://localhost:9100/metrics | grep -q "node_cpu_seconds_total" && \
    check_pass "Metrics endpoint responding" || check_fail "Metrics endpoint NOT responding"

echo ""
echo "===== Prometheus ====="
[[ -f /usr/local/bin/prometheus ]] && check_pass "Binary installed" || check_fail "Binary missing"
[[ -f /usr/local/bin/promtool ]] && check_pass "promtool installed" || check_fail "promtool missing"
id "prometheus" &>/dev/null && check_pass "User exists" || check_fail "User missing"
[[ -f /etc/prometheus/prometheus.yml ]] && check_pass "Config file exists" || check_fail "Config file missing"
systemctl is-active --quiet prometheus && check_pass "Service running" || check_fail "Service NOT running"
systemctl is-enabled --quiet prometheus 2>/dev/null && check_pass "Service enabled on boot" || check_fail "Service NOT enabled"
ss -tlnp | grep -q ":9090" && check_pass "Port 9090 listening" || check_fail "Port 9090 NOT listening"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:9090/-/healthy 2>/dev/null || echo "000")
[[ "${HTTP_CODE}" == "200" ]] && check_pass "Health endpoint OK (HTTP 200)" || check_fail "Health endpoint returned HTTP ${HTTP_CODE}"

if command -v promtool &>/dev/null && [[ -f /etc/prometheus/prometheus.yml ]]; then
    promtool check config /etc/prometheus/prometheus.yml > /dev/null 2>&1 && \
        check_pass "Config syntax valid (promtool)" || check_fail "Config has syntax errors"
fi

RULE_COUNT=$(ls /etc/prometheus/rules/*.yml 2>/dev/null | wc -l || echo 0)
if [[ "${RULE_COUNT}" -gt 0 ]]; then
    check_pass "${RULE_COUNT} rule file(s) loaded in /etc/prometheus/rules/"
    promtool check rules /etc/prometheus/rules/*.yml > /dev/null 2>&1 && \
        check_pass "All rule files valid (promtool)" || check_fail "Rule files have errors"
else
    check_warn "No rule files in /etc/prometheus/rules/ — run install_prometheus.sh"
fi

echo ""
echo "===== Alertmanager ====="
[[ -f /usr/local/bin/alertmanager ]] && check_pass "Binary installed" || check_fail "Binary missing"
[[ -f /usr/local/bin/amtool ]] && check_pass "amtool installed" || check_fail "amtool missing"
id "alertmanager" &>/dev/null && check_pass "User exists" || check_fail "User missing"
[[ -f /etc/alertmanager/alertmanager.yml ]] && check_pass "Config file exists" || check_fail "Config file missing"
systemctl is-active --quiet alertmanager && check_pass "Service running" || check_fail "Service NOT running"
systemctl is-enabled --quiet alertmanager 2>/dev/null && check_pass "Service enabled on boot" || check_fail "Service NOT enabled"
ss -tlnp | grep -q ":9093" && check_pass "Port 9093 listening" || check_fail "Port 9093 NOT listening"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:9093/-/healthy 2>/dev/null || echo "000")
[[ "${HTTP_CODE}" == "200" ]] && check_pass "Health endpoint OK (HTTP 200)" || check_fail "Health endpoint returned HTTP ${HTTP_CODE}"
if command -v amtool &>/dev/null && [[ -f /etc/alertmanager/alertmanager.yml ]]; then
    amtool check-config /etc/alertmanager/alertmanager.yml > /dev/null 2>&1 && \
        check_pass "Config syntax valid (amtool)" || check_fail "Config has syntax errors"
fi

echo ""
echo "===== Grafana ====="
command -v grafana-server &>/dev/null && check_pass "Grafana installed" || check_fail "Grafana NOT installed"
systemctl is-active --quiet grafana-server && check_pass "Service running" || check_fail "Service NOT running"
systemctl is-enabled --quiet grafana-server 2>/dev/null && check_pass "Service enabled on boot" || check_fail "Service NOT enabled"
ss -tlnp | grep -q ":3000" && check_pass "Port 3000 listening" || check_fail "Port 3000 NOT listening"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/api/health 2>/dev/null || echo "000")
[[ "${HTTP_CODE}" == "200" ]] && check_pass "Health endpoint OK (HTTP 200)" || check_fail "Health endpoint returned HTTP ${HTTP_CODE}"

echo ""
echo "===== Firewall ====="
if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "active"; then
    for PORT in 9090 9100 9093 3000; do
        ufw status | grep -q "${PORT}" && \
            check_pass "Port ${PORT} allowed" || \
            check_warn "Port ${PORT} may be blocked — sudo ufw allow ${PORT}/tcp"
    done
else
    check_warn "UFW inactive — all ports accessible"
fi

echo ""
echo "===== Connectivity ====="
SERVER_IP=$(hostname -I | awk '{print $1}')
for SERVICE in "Node Exporter:9100/metrics" "Prometheus:9090/-/healthy" "Alertmanager:9093/-/healthy" "Grafana:3000/api/health"; do
    NAME="${SERVICE%%:*}"
    ENDPOINT="${SERVICE##*:}"
    CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://${SERVER_IP}:${ENDPOINT}" 2>/dev/null || echo "000")
    [[ "${CODE}" =~ ^2 ]] && check_pass "${NAME} reachable at ${SERVER_IP}" || check_warn "${NAME} at ${SERVER_IP}:${ENDPOINT%%/*} returned HTTP ${CODE}"
done

echo ""
echo "===== Results: ${PASS} passed, ${FAIL} failed ====="
if [[ ${FAIL} -eq 0 ]]; then
    echo -e "${GREEN}All checks passed! Stack is operational.${NC}"
    echo ""
    echo "  Node Exporter: http://${SERVER_IP}:9100/metrics"
    echo "  Prometheus:    http://${SERVER_IP}:9090"
    echo "  Alertmanager:  http://${SERVER_IP}:9093"
    echo "  Grafana:       http://${SERVER_IP}:3000"
else
    echo -e "${RED}${FAIL} check(s) failed. Review output above.${NC}"
fi
echo ""
