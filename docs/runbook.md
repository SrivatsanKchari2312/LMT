# Alert Runbooks — Critical Severity

> Owner: Person B | Shared with Person C for dashboard cross-referencing.
> Each entry: meaning, first diagnostic commands, escalation path.

---

## InstanceDown

**Meaning:** A monitored server (Node Exporter target) has been unreachable for more than 2 minutes. Prometheus received no scrape response.

**Trigger:** `up == 0` for `2m`

**First steps:**
```bash
# From the monitoring server:
ping <instance-IP>
ssh <instance-IP>

# Check if Node Exporter is still running on the target:
systemctl status node_exporter
journalctl -u node_exporter -n 50

# Check firewall:
sudo ufw status
ss -tlnp | grep 9100
```

**Escalation:** If the server is unreachable via SSH, escalate to infrastructure lead. If Node Exporter is down but server is up, restart it: `sudo systemctl restart node_exporter`.

---

## LowMemoryCritical

**Meaning:** Available memory has dropped below 5% of total. OOM kills are imminent.

**Trigger:** `node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes * 100 < 5` for `1m`

**First steps:**
```bash
# Identify top memory consumers:
ps aux --sort=-%mem | head -15
free -h

# Check for memory leaks in recent logs:
journalctl -p err --since "10 minutes ago"

# If safe, restart the offending process. Last resort:
# sudo sync && sudo echo 3 > /proc/sys/vm/drop_caches
```

**Escalation:** If memory does not recover within 5 minutes after killing processes, escalate to on-call engineer for potential reboot.

---

## LowDiskCritical

**Meaning:** A filesystem has exceeded 95% usage. Writes will fail imminently.

**Trigger:** `(size - avail) / size * 100 > 95` for `5m` (fstype not tmpfs/devtmpfs)

**First steps:**
```bash
# Identify which filesystem:
df -h

# Find large files:
du -sh /* 2>/dev/null | sort -rh | head -20
find /var/log -name "*.log" -size +100M

# Clear log files safely:
sudo journalctl --vacuum-size=500M
sudo find /tmp -type f -mtime +7 -delete
```

**Escalation:** If disk cannot be cleared below 90% within 15 minutes, escalate. Consider expanding the filesystem or adding storage.

---

## NetworkInterfaceDown

**Meaning:** A non-loopback network interface has lost carrier signal (cable pulled, NIC failure, or VM network issue).

**Trigger:** `node_network_carrier{device!="lo"} == 0` (immediate)

**First steps:**
```bash
# Check interface status:
ip link show
ip -s link

# Check system logs for NIC errors:
journalctl -k --since "5 minutes ago" | grep -i eth
dmesg | grep -i "link\|carrier\|nic" | tail -20
```

**Escalation:** If this is a physical machine, check cable and switch port. If a VM, check hypervisor network config. Immediate escalation to infrastructure lead if primary interface is down.

---

## OOMKillDetected

**Meaning:** The Linux OOM killer has terminated one or more processes due to memory exhaustion.

**Trigger:** `increase(node_vmstat_oom_kill[5m]) > 0` (immediate, critical)

**First steps:**
```bash
# Find what was killed:
journalctl -k --since "10 minutes ago" | grep -i "oom\|kill"
dmesg | grep -i "oom\|killed process"

# Check current memory state:
free -h
cat /proc/meminfo | head -10
```

**Escalation:** Identify the killed process and the memory consumer. If the same process keeps getting OOM-killed, escalate to application owner to fix memory leak or increase server RAM.

---

## AlertmanagerNotReachable

**Meaning:** Prometheus cannot reach any Alertmanager. Alert notifications will not be delivered while this condition persists.

**Trigger:** `prometheus_notifications_alertmanagers_discovered < 1` (immediate, critical)

**First steps:**
```bash
# Check Alertmanager service:
systemctl status alertmanager
journalctl -u alertmanager -n 50

# Verify port:
ss -tlnp | grep 9093
curl http://localhost:9093/-/healthy

# Check Prometheus config for correct address:
grep -A5 "alertmanagers" /etc/prometheus/prometheus.yml

# Reload Prometheus after fixing:
sudo systemctl reload prometheus
```

**Escalation:** If Alertmanager cannot be restarted within 5 minutes, escalate. All alerts fired during the outage will be re-sent once Alertmanager recovers.

---

*Last updated: 2026-06-21 | Owner: Person B*
