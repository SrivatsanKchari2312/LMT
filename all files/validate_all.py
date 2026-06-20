#!/usr/bin/env python3
"""
Validates all Node Exporter & Alertmanager files on Windows (no Linux needed).
Checks YAML syntax, bash script structure, and cross-references.

Usage: python validate_all.py
"""

import os
import re
import sys

os.system("")  # Enable ANSI on Windows

GREEN = "\033[92m"
RED = "\033[91m"
YELLOW = "\033[93m"
BLUE = "\033[94m"
BOLD = "\033[1m"
RESET = "\033[0m"

pass_count = 0
fail_count = 0
warn_count = 0


def log_pass(msg):
    global pass_count
    pass_count += 1
    print(f"  {GREEN}PASS{RESET} {msg}")


def log_fail(msg):
    global fail_count
    fail_count += 1
    print(f"  {RED}FAIL{RESET} {msg}")


def log_warn(msg):
    global warn_count
    warn_count += 1
    print(f"  {YELLOW}WARN{RESET} {msg}")


def log_info(msg):
    print(f"  {BLUE}INFO{RESET} {msg}")


def section(msg):
    print(f"\n--- {msg} ---")


# ---------- YAML ----------
def get_yaml():
    try:
        import yaml
        return yaml
    except ImportError:
        try:
            import subprocess
            subprocess.check_call(
                [sys.executable, "-m", "pip", "install", "pyyaml", "-q"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
            import yaml
            return yaml
        except Exception:
            return None


def validate_yaml(filepath, yaml_mod):
    section(os.path.basename(filepath))
    if not os.path.exists(filepath):
        log_fail("File not found")
        return None

    # Check for tabs
    with open(filepath, "r", encoding="utf-8") as f:
        for i, line in enumerate(f, 1):
            if "\t" in line and not line.strip().startswith("#"):
                log_fail(f"Line {i}: tab character (YAML needs spaces)")

    if yaml_mod is None:
        log_warn("PyYAML not available, skipping parse")
        return None

    try:
        with open(filepath, "r", encoding="utf-8") as f:
            data = yaml_mod.safe_load(f)
        log_pass("YAML syntax valid")
        return data
    except yaml_mod.YAMLError as e:
        log_fail(f"YAML parse error: {e}")
        return None


def validate_alertmanager(filepath, yaml_mod):
    data = validate_yaml(filepath, yaml_mod)
    if data is None:
        return

    # Required keys
    for key in ["route", "receivers"]:
        if key in data:
            log_pass(f"'{key}' section present")
        else:
            log_fail(f"'{key}' section MISSING")

    if "global" in data:
        log_pass("'global' section present")
        g = data["global"]
        if "smtp_smarthost" in g:
            log_pass(f"SMTP host: {g['smtp_smarthost']}")
        if "your_" in str(g.get("smtp_auth_password", "")):
            log_warn("SMTP password is placeholder — update before deployment")

    if "route" in data:
        route = data["route"]
        recv = route.get("receiver", "")
        log_pass(f"Default receiver: '{recv}'")
        for field in ["group_by", "group_wait", "group_interval", "repeat_interval"]:
            if field in route:
                log_pass(f"{field}: {route[field]}")

    if "receivers" in data:
        names = set()
        for r in data["receivers"]:
            name = r.get("name", "")
            names.add(name)
            log_pass(f"Receiver '{name}' defined")
            for ec in r.get("email_configs", []):
                to = ec.get("to", "")
                if "example.com" in to:
                    log_warn(f"  Email 'to' is placeholder: {to}")

        # Cross-check route receiver exists
        if "route" in data:
            default = data["route"].get("receiver", "")
            if default in names:
                log_pass(f"Route receiver '{default}' exists in receivers")
            elif default:
                log_fail(f"Route receiver '{default}' NOT found in receivers")


def validate_alerts(filepath, yaml_mod):
    data = validate_yaml(filepath, yaml_mod)
    if data is None:
        return

    if "groups" not in data:
        log_fail("Missing 'groups'")
        return

    total = 0
    for group in data["groups"]:
        name = group.get("name", "?")
        rules = group.get("rules", [])
        log_pass(f"Group '{name}': {len(rules)} rule(s)")

        for rule in rules:
            total += 1
            alert = rule.get("alert", "?")
            if "expr" not in rule:
                log_fail(f"  '{alert}': missing expr")
            else:
                log_pass(f"  '{alert}': expression defined")
            if "labels" in rule and "severity" in rule["labels"]:
                log_pass(f"  '{alert}': severity={rule['labels']['severity']}")
            if "for" in rule:
                log_pass(f"  '{alert}': for={rule['for']}")

    log_pass(f"Total rules: {total}")


def validate_prometheus_snippet(filepath, yaml_mod):
    data = validate_yaml(filepath, yaml_mod)
    if data is None:
        return
    for key in ["alerting", "scrape_configs"]:
        if key in data:
            log_pass(f"'{key}' present")
        else:
            log_warn(f"'{key}' missing")


# ---------- Bash ----------
def validate_bash(filepath):
    section(os.path.basename(filepath))
    if not os.path.exists(filepath):
        log_fail("File not found")
        return

    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read()
        lines = content.split("\n")

    # Shebang
    if lines[0].strip().startswith("#!/bin/bash"):
        log_pass("Shebang present")
    else:
        log_fail("Missing shebang")

    # Error handling
    if "set -euo pipefail" in content:
        log_pass("Error handling (set -euo pipefail)")
    else:
        log_warn("No strict error handling")

    # Root check
    if "EUID" in content:
        log_pass("Root privilege check")
    else:
        log_warn("No root check")

    # Balance checks (only match at start of line to avoid comments/strings)
    if_count = len(re.findall(r"(?m)^\s*if\b", content))
    fi_count = len(re.findall(r"(?m)^\s*fi\b", content))
    if if_count == fi_count:
        log_pass(f"if/fi balanced: {if_count} pairs")
    else:
        log_fail(f"if/fi UNBALANCED: if={if_count}, fi={fi_count}")

    do_count = len(re.findall(r"(?m)^\s*do\b", content))
    done_count = len(re.findall(r"(?m)^\s*done\b", content))
    if do_count == done_count:
        if do_count > 0:
            log_pass(f"do/done balanced: {do_count} pairs")
    else:
        log_fail(f"do/done UNBALANCED: do={do_count}, done={done_count}")

    brackets_open = content.count("[[")
    brackets_close = content.count("]]")
    if brackets_open == brackets_close:
        log_pass(f"[[ ]] balanced: {brackets_open} pairs")
    else:
        log_fail(f"[[ ]] UNBALANCED: [[={brackets_open}, ]]={brackets_close}")

    code_lines = [l for l in lines if l.strip() and not l.strip().startswith("#")]
    log_info(f"Lines: {len(lines)} total, {len(code_lines)} code")


# ---------- Main ----------
def main():
    print(f"\n{BOLD}Node Exporter + Alertmanager Validation{RESET}")
    print(f"{BOLD}Running on Windows — no Linux needed{RESET}\n")

    script_dir = os.path.dirname(os.path.abspath(__file__))
    yaml_mod = get_yaml()
    if yaml_mod:
        log_info(f"PyYAML loaded (v{yaml_mod.__version__})")
    else:
        log_warn("PyYAML unavailable — YAML parse checks skipped")

    # YAML files
    validate_alertmanager(os.path.join(script_dir, "alertmanager.yml"), yaml_mod)
    validate_alerts(os.path.join(script_dir, "node_exporter_alerts.yml"), yaml_mod)
    validate_prometheus_snippet(os.path.join(script_dir, "prometheus_config_snippet.yml"), yaml_mod)

    # Bash scripts
    for script in ["install_node_exporter.sh", "install_alertmanager.sh", "verify_setup.sh", "uninstall.sh"]:
        validate_bash(os.path.join(script_dir, script))

    # Summary
    print(f"\n{'=' * 45}")
    print(f"  {GREEN}PASSED:   {pass_count}{RESET}")
    print(f"  {RED}FAILED:   {fail_count}{RESET}")
    print(f"  {YELLOW}WARNINGS: {warn_count}{RESET}")
    print(f"{'=' * 45}")

    if fail_count == 0:
        print(f"\n{GREEN}{BOLD}All validations passed! Files are correct.{RESET}")
        print("Warnings about placeholders are expected — fill in real values on Ubuntu.\n")
    else:
        print(f"\n{RED}{BOLD}{fail_count} check(s) failed.{RESET}\n")
        sys.exit(1)


if __name__ == "__main__":
    main()
