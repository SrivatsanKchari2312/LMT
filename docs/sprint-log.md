# Sprint Log

> Owner: Person C | Updated end of each working day.

---

## Day 1

**Person A:** Inventoried target servers, documented IPs and OS versions. Verified network reachability from monitoring VM. Opened firewall ports 9090, 9100, 9093, 3000.

**Person B:** Pulled Node Exporter metric reference documentation. Reviewed PromQL expressions for all 20 rules.

**Person C:** Created repository skeleton and documentation structure. Drafted architecture diagram.

**Blockers:** None.

---

## Day 2

**Person A:** Deployed Node Exporter as systemd service on all target servers. Verified metrics endpoint responding.

**Person B:** Wrote `cpu.yml` alert rules (4 rules). Validated with `promtool check rules`. Committed to `feat/person-b`.

**Person C:** Updated documentation with 3-person team structure. Set up shared docs folder.

**Blockers:** None.

---

## Day 3

**Person A:** Installed Prometheus on monitoring VM. Wrote `prometheus.yml` with all scrape targets. Service running, all targets UP at `:9090/targets`.

**HANDOFF 1 (EOD):** Person A shared finalized instance label format and scrape target list to `docs/targets.txt`. Person B and C acknowledged receipt.

**Person B:** Wrote `memory.yml` alert rules (4 rules). Validated. Committed.

**Person C:** Studied Node Exporter Full dashboard (ID 1860). Panel design notes committed to `docs/grafana-plan.md`.

**Blockers:** None.

---

## Day 4

**Person A:** Fine-tuned Prometheus scrape config with environment and team labels. Tested PromQL queries in expression browser.

**Person B:** Wrote `disk.yml` alert rules (6 rules). Validated with promtool.

**Person C:** Identified panels needing customization in Node Exporter Full dashboard for multi-host views.

**Blockers:** None.

---

## Day 5

**Person B:** Wrote `network.yml` (4 rules) and `system.yml` (5 rules). All 5 rule files validated.

**HANDOFF 2 (EOD):** Person B opened PR with all 5 rule files. Person A reviewed label selectors against live prometheus.yml. PR merged. Rule files deployed to `/etc/prometheus/rules/`.

**Person A:** Loaded all 5 rule files into Prometheus. Confirmed zero errors at `:9090/alerts`.

**Person C:** Updated sprint week-1 review doc. Confirmed repo state matches monitoring VM.

**Blockers:** None.

---

## Day 6

**Person B:** Installed Alertmanager. Wrote `alertmanager.yml` with email receiver. Validated with amtool.

**Person A:** Updated `prometheus.yml` alerting block to point to Alertmanager. Wrote `prometheus_self.yml` (4 self-monitoring rules). Loaded and validated.

**Person C:** Installed Grafana. Added Prometheus as data source — Save & Test passed.

**Blockers:** SMTP App Password needed — Person B to confirm with supervisor.

---

## Day 7

**Person B:** End-to-end alert fire test 1 (CPU) — PASS. Test 2 (Disk) — PASS. Test 3 (InstanceDown) — PASS. Wrote runbook entries for all 6 critical alerts.

**Person A:** Configured file permissions (640 on all config files). Documented in `docs/security-notes.md`.

**Person C:** (Grafana now has >24h of data)

**Blockers:** None.

---

## Day 8

**HANDOFF 3 (SOD):** Person A shared Prometheus data source URL and metric name list. Person C connected Grafana, imported Node Exporter Full dashboard (ID 1860).

**Person C:** Built Overview Dashboard with one row per server. All stat panels showing real data.

**Blockers:** None.

---

## Day 9

**Person C:** Exported all dashboards as JSON. Committed to `grafana/dashboards/`. Added Grafana provisioning config.

**All:** Documentation sprint — updated Linux Monitoring Stack Documentation with actual values.

**Blockers:** None.

---

## Day 10

**FINAL SMOKE TEST:** Person A stopped Node Exporter. Person B confirmed alert fired in Prometheus and email arrived. Person C confirmed Grafana panel went red. Person A restarted — all resolved.

**Sprint retrospective:** What worked, what was difficult, improvements for next sprint. Repo tagged `v1.0`.

**Status: SPRINT COMPLETE**

---
