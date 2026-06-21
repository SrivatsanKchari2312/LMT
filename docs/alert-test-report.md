# Alert Fire Test Report

> Owner: Person B | Tests run on Days 7 and 10.

---

## Test Environment

| Item | Value |
|------|-------|
| Monitoring Server | localhost (Ubuntu 24.04) |
| Prometheus | http://localhost:9090 |
| Alertmanager | http://localhost:9093 |
| Test Date | 2026-06-21 |
| Tester | Person B |

---

## Test 1: HighCPUWarning (End-to-End)

**Method:** Temporarily lower `HighCPUWarning` threshold to 1%, run `stress-ng`.

```bash
# Lower threshold temporarily in /etc/prometheus/rules/cpu.yml
# Change: > 80  →  > 1
sudo systemctl reload prometheus

# Generate CPU load:
stress-ng --cpu 4 --timeout 180
```

**Expected pipeline:**
1. Prometheus detects CPU > 1% within 15s
2. Alert enters PENDING state
3. After `for: 2m` → FIRING
4. Prometheus sends to Alertmanager within 30s
5. Email arrives within `group_wait: 30s`

| Step | Result | Timestamp | Notes |
|------|--------|-----------|-------|
| Alert PENDING | PASS | - | Prometheus Alerts tab |
| Alert FIRING | PASS | - | After 2m |
| Email received | PASS | - | Within 3 minutes |
| Alert RESOLVED | PASS | - | After threshold restored |

**Restore:** Revert threshold to `> 80`, reload Prometheus.

---

## Test 2: LowDiskWarning (End-to-End)

**Method:** Create a large temp file to push disk usage above 80% (or lower threshold to 10% on a low-usage VM).

```bash
# Lower threshold temporarily in /etc/prometheus/rules/disk.yml
# Change: > 80  →  > 10

# Create temp file to trigger:
dd if=/dev/zero of=/tmp/testfile bs=1M count=5000

# Or use fallocate:
fallocate -l 5G /tmp/bigfile
```

| Step | Result | Timestamp | Notes |
|------|--------|-----------|-------|
| Alert PENDING | - | - | |
| Alert FIRING | - | - | |
| Email received | - | - | |
| Alert RESOLVED (file deleted) | - | - | |

**Restore:** `rm /tmp/bigfile`, revert threshold.

---

## Test 3: InstanceDown (End-to-End)

**Method:** Stop Node Exporter on one target to simulate a downed server.

```bash
sudo systemctl stop node_exporter
```

**Expected:** `InstanceDown` fires after 2 minutes, email arrives within ~3 minutes total.

| Step | Result | Timestamp | Notes |
|------|--------|-----------|-------|
| Target shows DOWN in :9090/targets | - | - | |
| Alert PENDING | - | - | |
| Alert FIRING (after 2m) | - | - | |
| Email received | - | - | |
| Alert RESOLVED (after restart) | - | - | |

**Restore:** `sudo systemctl start node_exporter`

---

## Day 10 Smoke Test

**Participants:** Person A (stops Node Exporter), Person B (watches Prometheus + email), Person C (watches Grafana)

| Observer | What they saw | Pass/Fail |
|----------|--------------|-----------|
| Person A | Node Exporter stopped, then restarted | - |
| Person B | InstanceDown fired in 2m, email received | - |
| Person C | Server row went red in Grafana, resolved on restart | - |

**Overall result:** -

---

*Last updated: 2026-06-21 | Owner: Person B*
