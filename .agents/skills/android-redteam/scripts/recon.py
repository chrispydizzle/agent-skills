#!/usr/bin/env python3
"""
Android Device Reconnaissance Script

Runs a comprehensive device enumeration via ADB, collecting hardware info,
security posture, kernel details, accessible attack surfaces, and installed
packages. Output is a structured text report.

Usage:
    python recon.py [--adb-path ADB] [--output report.txt]

Requires: adb in PATH or specified via --adb-path
"""

import subprocess
import sys
import argparse
from datetime import datetime


def run_adb(cmd, adb="adb", timeout=10):
    """Run an ADB shell command, return stdout or error string."""
    try:
        result = subprocess.run(
            [adb, "shell"] + cmd.split(),
            capture_output=True, text=True, timeout=timeout
        )
        return result.stdout.strip()
    except subprocess.TimeoutExpired:
        return "[TIMEOUT]"
    except Exception as e:
        return f"[ERROR: {e}]"


def run_adb_raw(cmd, adb="adb", timeout=10):
    """Run a raw ADB command (not shell)."""
    try:
        result = subprocess.run(
            [adb] + cmd.split(),
            capture_output=True, text=True, timeout=timeout
        )
        return result.stdout.strip()
    except subprocess.TimeoutExpired:
        return "[TIMEOUT]"
    except Exception as e:
        return f"[ERROR: {e}]"


def section(title):
    return f"\n{'='*60}\n {title}\n{'='*60}\n"


def main():
    parser = argparse.ArgumentParser(description="Android Device Recon")
    parser.add_argument("--adb-path", default="adb", help="Path to adb binary")
    parser.add_argument("--output", default=None, help="Output file (default: stdout)")
    args = parser.parse_args()
    adb = args.adb_path

    lines = []
    def log(msg=""):
        lines.append(msg)
        print(msg)

    log(f"# Android Device Reconnaissance Report")
    log(f"# Generated: {datetime.now().isoformat()}")
    log(f"# ADB: {adb}")

    # Check device connectivity
    devices = run_adb_raw("devices", adb)
    log(section("ADB DEVICES"))
    log(devices)

    # Device identity
    log(section("DEVICE IDENTITY"))
    props = [
        "ro.product.model", "ro.product.brand", "ro.product.device",
        "ro.product.board", "ro.build.display.id", "ro.build.version.release",
        "ro.build.version.sdk", "ro.build.version.security_patch",
        "ro.build.type", "ro.build.flavor",
        "ro.hardware", "ro.bootloader",
        "ro.carrier", "ro.config.alarm_alert",
        "ro.debuggable", "ro.secure", "ro.adb.secure",
        "sys.oem_unlock_allowed", "ro.boot.verifiedbootstate",
        "persist.sys.dalvik.vm.lib.2",
    ]
    for prop in props:
        val = run_adb(f"getprop {prop}", adb)
        log(f"  {prop} = {val}")

    # Kernel info
    log(section("KERNEL INFO"))
    log(f"  uname -a: {run_adb('uname -a', adb)}")
    log(f"  uname -r: {run_adb('uname -r', adb)}")
    log(f"  cat /proc/version: {run_adb('cat /proc/version', adb)}")

    # SELinux
    log(section("SELINUX"))
    log(f"  getenforce: {run_adb('getenforce', adb)}")
    log(f"  id: {run_adb('id', adb)}")
    log(f"  cat /proc/self/attr/current: {run_adb('cat /proc/self/attr/current', adb)}")

    # Kernel security params
    log(section("KERNEL SECURITY"))
    kparams = [
        "/proc/sys/kernel/kptr_restrict",
        "/proc/sys/kernel/dmesg_restrict",
        "/proc/sys/kernel/perf_event_paranoid",
        "/proc/sys/kernel/randomize_va_space",
        "/proc/sys/vm/mmap_min_addr",
        "/proc/sys/net/ipv4/ping_group_range",
    ]
    for p in kparams:
        log(f"  {p}: {run_adb(f'cat {p}', adb)}")

    # Device nodes
    log(section("ACCESSIBLE DEVICE NODES"))
    dev_nodes = [
        "/dev/ion", "/dev/binder", "/dev/ashmem", "/dev/mali0",
        "/dev/ptmx", "/dev/alarm", "/dev/mobicore-user",
        "/dev/s5p-smem", "/dev/mem", "/dev/kmem",
        "/dev/tty", "/dev/random", "/dev/urandom",
    ]
    for dev in dev_nodes:
        ls = run_adb(f"ls -la {dev}", adb)
        log(f"  {dev}: {ls}")

    # Proc info
    log(section("PROC READABILITY"))
    proc_entries = [
        "/proc/slabinfo", "/proc/kallsyms", "/proc/modules",
        "/proc/vmallocinfo", "/proc/timer_list", "/proc/buddyinfo",
        "/proc/zoneinfo", "/proc/vmstat", "/proc/crypto",
        "/proc/interrupts", "/proc/locks", "/proc/net/arp",
        "/proc/sched_debug",
    ]
    for p in proc_entries:
        result = run_adb(f"head -1 {p}", adb)
        readable = "[ERROR" not in result and "[TIMEOUT" not in result and "denied" not in result.lower()
        log(f"  {p}: {'READABLE' if readable else 'BLOCKED'}")

    # Mount points
    log(section("MOUNT INFO"))
    log(run_adb("mount", adb, timeout=5))

    # SUID/SGID binaries
    log(section("SUID/SGID BINARIES"))
    log(run_adb("find /system -perm -4000 -o -perm -2000 2>/dev/null", adb, timeout=15))

    # Installed packages (summary)
    log(section("PACKAGE SUMMARY"))
    pkg_count = run_adb("pm list packages 2>/dev/null | wc -l", adb, timeout=15)
    log(f"  Total packages: {pkg_count}")
    sys_count = run_adb("pm list packages -s 2>/dev/null | wc -l", adb, timeout=15)
    log(f"  System packages: {sys_count}")
    third_count = run_adb("pm list packages -3 2>/dev/null | wc -l", adb, timeout=15)
    log(f"  Third-party packages: {third_count}")

    # Root indicators
    log(section("ROOT INDICATORS"))
    root_checks = [
        "ls -la /sbin/su",
        "ls -la /system/xbin/su",
        "ls -la /system/bin/su",
        "pm list packages com.topjohnwu.magisk",
        "pm list packages com.noshufou.android.su",
        "pm list packages eu.chainfire.supersu",
        "pm list packages com.z4mod.z4root",
        "ls /sdcard/com.kingroot.kinguser/",
    ]
    for cmd in root_checks:
        log(f"  {cmd}: {run_adb(cmd, adb)}")

    # Services
    log(section("BINDER SERVICES (count)"))
    svc_count = run_adb("service list 2>/dev/null | wc -l", adb, timeout=10)
    log(f"  Total services: {svc_count}")

    # Network
    log(section("NETWORK"))
    log(f"  ifconfig: {run_adb('ifconfig', adb, timeout=5)}")
    log(f"  netstat (listening): {run_adb('netstat -tlnp', adb, timeout=5)}")

    # Shell permissions
    log(section("SHELL PERMISSIONS"))
    log(run_adb("dumpsys package shell 2>/dev/null | grep granted=true", adb, timeout=15))

    log(section("END OF REPORT"))

    if args.output:
        with open(args.output, "w", encoding="utf-8") as f:
            f.write("\n".join(lines))
        print(f"\nReport saved to {args.output}")


if __name__ == "__main__":
    main()
