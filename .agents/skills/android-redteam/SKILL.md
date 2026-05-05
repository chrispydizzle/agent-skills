---
name: android-redteam
description: Deep Android device security assessment and reverse engineering expertise, specializing in carrier-locked Samsung tablets. Use when the user needs help with kernel vulnerability research, fuzzing Android drivers, analyzing SELinux policies, understanding bootloader/carrier locks, exploiting ION/binder/ashmem/mali drivers, Samsung Knox bypass research, service enumeration via binder, heap spray techniques from ADB shell, or any Android privilege escalation task. Represents 10+ years of Android RE experience with specific knowledge of the Samsung SM-T377A (AT&T, firmware T377AUCU2AQGF).
---

# Android Red Team

Expert-level Android device security assessment and kernel exploitation skill. Covers the full attack lifecycle: reconnaissance, vulnerability discovery, exploitation, and privilege escalation on carrier-locked Android devices.

## ⚠ CRITICAL DEVICE SAFETY

- **Physical device** — fork-bombs, aggressive races, and `adbd_root` CRASH it
- **DO NOT run**: `/data/local/tmp/adbd_root` (hangs+crash), `su-v1`/`su-v2` (non-PIE), `rageagainstthecage` (non-PIE)
- **DO NOT broadcast**: `android.intent.action.MASTER_CLEAR` (reboots/wipes device)
- **DO NOT send AT**: `AT$ARMEE=1` (enters download mode), `*2767*2878#` (potential wipe)
- **ION heap bits 2 (0x0004) and 12 (0x1000)** cause kernel panic (DoS only — avoid!)
- **ARM32 ION struct uses uint32_t** — using uint64_t causes heap_id_mask misalignment → secure heap → kernel crash
- Always **check `/src` and `/findings` before new work** to avoid duplicating effort
- Always **read STATUS.md** for current assessment state

## Workflow

### Prior-findings preflight

Before new recon, vulnerability research, fuzzing, or exploit work, read the
current evidence base. At minimum check `STATUS.md`, progress logs, `/findings`,
and relevant `/src` notes. List:

- confirmed facts and current foothold
- tried vectors and dead ends
- artifacts or evidence that changed since the last attempt
- paths that are blocked by SELinux, patch state, signing, boot state, or
  device safety
- the specific privilege target for this loop

Do not retry a dead path unless new evidence changes the decision. When the goal
is privilege escalation, map each lead to actual upward impact; non-privesc bugs,
DoS-only crashes, and decoys should not dominate the plan.

Assessment follows this sequence:

1. **Recon** - Enumerate device, kernel, SELinux, accessible surfaces
2. **Surface mapping** - Identify accessible drivers, services, proc/sys entries
3. **Vulnerability research** - Test known CVEs, fuzz drivers, analyze services
4. **Exploitation** - Develop PoCs for discovered vulnerabilities
5. **Privilege escalation** - Chain primitives toward root or demonstrate impact

Determine which phase the user is in. If unclear, start with recon. Read `STATUS.md` for current state.

## Device Recon

Key data points to collect:

- **Device identity**: model, SoC, Android version, build ID, security patch level
- **Kernel**: version, compile date, CONFIG options (infer from /proc availability)
- **SELinux**: enforcing/permissive, current domain, policy version
- **Mitigations**: KASLR, stack canaries, PXN, kptr_restrict, mmap_min_addr
- **Accessible /dev nodes**: which are world-RW and SELinux-allowed
- **Root indicators**: su binaries, Magisk, SuperSU, KingRoot remnants

For Samsung devices specifically check:
- Knox warranty fuse status
- OEM unlock toggle vs actual carrier lock
- Platform signing key (AOSP test key = trivial system-app installation)
- Samsung service mode apps and secret dial codes

## Samsung SM-T377A — Complete Device Profile

### Identity
| Property | Value |
|----------|-------|
| Model | SM-T377A (Galaxy Tab E 8.0, AT&T) |
| SoC | Exynos 3475, ARMv7 Cortex-A7, 4 cores |
| Android | 6.0.1, Build MMB29K.T377AUCU2AQGF |
| Kernel | 3.10.9-11788437, compiled 2017-07-05 |
| Security patch | 2017-07-01 |
| SELinux | Enforcing (u:r:shell:s0) |
| Shell UID | 2000 |
| Encryption | Unencrypted (ro.crypto.state=unencrypted) |
| Build type | user (NOT debug/eng) |
| Platform key | Samsung proprietary (NOT AOSP test key) |
| Knox warranty | Fuse intact (warranty_bit=0) |
| Modem | Shannon 308 |
| BT chip | BCM43454, firmware V0100.0131 |

### Confirmed Kernel Addresses (NO KASLR)

| Symbol | Address | Source |
|--------|---------|--------|
| commit_creds | 0xC0054328 | Firmware symbol table |
| prepare_kernel_cred | 0xC00548E0 | Firmware symbol table |
| **selinux_enforcing** | **0xC0B7AD18** | TIMA paddr leak (0x20B7AD18) |
| selinux_enabled | 0xC0AB00A8 | TIMA paddr leak (0x20AB00A8) |
| TIMA write_ptr | 0xC7403580 | TIMA paddr leak (0x27403580) |
| PAGE_OFFSET | 0xC0000000 | Standard ARM32 |
| PHYS_OFFSET | 0x20000000 | Confirmed |
| Conversion | vaddr = paddr + 0xA0000000 | |
| task_struct->cred | offset 0x164 | |
| thread_info->addr_limit | offset 8, **KERNEL_DS=0x00000000** | Kernel source verified |

> ⚠ Previous selinux_enforcing estimate 0xC0B7AD54 was WRONG. Use 0xC0B7AD18.
> ⚠ **KERNEL_DS = 0x00000000 (NOT 0xFFFFFFFF)**. Samsung `set_fs(0)` sets `DOMAIN_MANAGER` (full access). Exploit must write 0 to addr_limit, not 0xFFFFFFFF. Verified from `arch/arm/include/asm/uaccess.h` in Samsung GPL release.

### Kernel Mitigations

| Mitigation | Status |
|-----------|--------|
| KASLR | ❌ NOT present |
| PXN | ❌ NOT present |
| Stack canaries | ❌ NOT present |
| HARDENED_USERCOPY | ❌ NOT present |
| kptr_restrict | ✅ ACTIVE |
| SELinux | ✅ ENFORCING |
| mmap_min_addr | ✅ 32768 (0x8000) |
| TIMA | ✅ ACTIVE (TrustZone, checks every 5 min) |
| /dev/mem, /dev/kmem | DO NOT EXIST |

### CVE Status (17+ Tested)

| CVE | Status | Notes |
|-----|--------|-------|
| CVE-2016-5195 (Dirty COW) | ❌ PATCHED | Do not retry |
| CVE-2015-1805 (pipe iov) | ❌ PATCHED | Do not retry |
| CVE-2014-3153 (Towelroot) | ❌ PATCHED | Samsung blanket-patched requeue_pi. 11 variants all EINVAL. Do not retry |
| CVE-2015-3636 (ping UAF) | ❌ PATCHED | Do not retry |
| CVE-2013-2094 (perf OOB) | ❌ PATCHED | Do not retry |
| CVE-2014-0196 (n_tty) | ❌ LIKELY PATCHED | Process hung, no crash |
| CVE-2016-0728 (keyring) | ❌ NOT VIABLE | Too slow, EDQUOT at 198 |
| CVE-2017-7533 (inotify) | ❌ SURVIVED | 558K events, 0 crashes |
| CVE-2017-11176 (mq_notify) | ❌ N/A | ENOSYS |
| CVE-2016-4557 (eBPF) | ❌ N/A | Not compiled |
| CVE-2019-2215 (binder UAF) | ⚠ UNPATCHED/UNEXPLOITABLE | Samsung patched binder_free_thread, UIO_FASTIOV=32 blocks iovec |
| **CVE-2017-1000251 (BlueBorne L2CAP)** | **⚠ UNPATCHED — EXPLOIT READY** | L2CAP channel confirmed OPEN. EFS amplification: 60 bytes in → 270 out. Probe sent, device survived (no crash). Needs investigation. |
| CVE-2017-0781/0782 (BlueBorne BNEP) | ❌ BLOCKED | Samsung backported UUID validation, ctrl type checks, packet length checks |
| CVE-2016-6786 (perf SET_OUTPUT) | ❌ PATCHED | 7000 iterations clean |
| CVE-2017-6001 (perf move_group) | ❌ PATCHED | 10K+ iterations clean |
| CVE-2017-8890 (DCCP) | ❌ BLOCKED | SELinux blocks from ALL reachable contexts |
| CVE-2017-10661 (timerfd) | ⚠ SURFACE REACHABLE | Needs clock_settime (CAP_SYS_TIME). No workaround found. |
| CVE-2017-8824 (DCCP UAF) | ❌ BLOCKED | Kernel compiled with DCCP but SELinux blocks socket from all contexts |

### Slab Cache Layout

| Cache | Contents |
|-------|----------|
| kmalloc-64 | ION handles, pipe_buffer[2] |
| kmalloc-128 | Binder metadata |
| kmalloc-192 | ION buffers, binder_thread (via epoll_ctl without BC_ENTER_LOOPER) |
| kmalloc-256 | binder_thread (252 bytes via normal path), BPF sk_filter (26 insns) |
| kmalloc-512 | readv iov array (iovcnt 33-64) |

### ION Struct (ARM32 — CRITICAL BUG AVOIDANCE)

```c
// CORRECT for ARM32 (size_t = 4 bytes):
struct ion_allocation_data {
    uint32_t len, align, heap_id_mask, flags, handle;
};  // 20 bytes, use ION_IOC_SHARE to get fd

// WRONG — causes kernel crash:
struct { uint64_t len; uint64_t align; ... };  // misaligns heap_id_mask
```

### Confirmed UAFs (Non-Exploitable)

**ION UAF (kmalloc-64)**: 91% race win (FREE vs SHARE). No code exec — no fn-ptr victim in k64.

**CVE-2019-2215 (kmalloc-256)**: Samsung nullifies eppoll_entry->whead before kfree. UIO_FASTIOV=32 blocks iovec spray. 48 offsets × 6 triggers = 288 combos → 0 crashes.

**tee() ABBA deadlock**: Zero-day DoS only. Pipe refcounting correct, no memory corruption.

### TIMA Integrity Monitor

- TrustZone-based, checks every 5 min via MobiCore (PID 2182)
- Verifies kernel code + SELinux enforcement
- Leaks physical addresses in dmesg (readable from shell and app)
- Must be neutralized BEFORE/simultaneously with SELinux disable for persistent root

### Accessible Attack Surfaces

**Device nodes**: /dev/binder, /dev/ashmem, /dev/ion, /dev/mali0, /dev/ptmx, /dev/input/event0-5 (all RW)

**Sockets**: dnsproxyd (root netd, connected), logd (connected), fwmarkd (accessible), property_service (world-RW)

**Blocked sockets**: All abstract sockets (SELinux), netd (root:system), rild, all @Factory* sockets

**Key services**: SmartcomRoot (15 methods, features disabled), DLP (3 methods), EngineeringMode (7 methods, -1300 auth), DeviceRootKeyService (5 methods), ABTPersistenceService (25 methods, auth-checked), execute (2 methods, returns app list)

**DM port (COM11)**: 180 AT commands, Shannon 308 modem, no auth. Port number changes on USB disruption.

### Critical Processes

| Process | UID | Key Capabilities |
|---------|-----|-----------------|
| netd | root | ALL (0x1fffffffff) |
| diagexe | 1000 | DAC_OVERRIDE, NET_ADMIN, NET_RAW, SYS_ADMIN, SYS_BOOT; has setuid/capset imports |
| at_distributor | 1001 | CHOWN, DAC_OVERRIDE, NET_ADMIN, NET_RAW, SYS_ADMIN, SYS_BOOT, SYS_TIME |

### dnsproxyd Protocol (netd = root)

- Socket: /dev/socket/dnsproxyd (SOCK_STREAM)
- Protocol: FrameworkListener, null-terminated, NO sequence numbers
- `getaddrinfo host service family socktype proto flags netid\0` (8 args, `^`=NULL service)
- `gethostbyname netid host af\0` (4 args)
- `gethostbyaddr netid addr addrlen af\0` (5 args)
- Format strings NOT exploitable. No crash on 256-byte hostname, negatives, INT_MAX.

### DRParser (com.sec.android.app.parser) — Post-Root Goldmine

- UID 1000 with AT_COMMAND, QCOM_DIAG, INSTALL_PACKAGES, MASTER_CLEAR, MODIFY_IPTABLES
- SecretCodeIME: "normal" protection level (any app can request)
- RSA private key in APK assets (keystring encryption reversible)
- Keystring XML loadable from /sdcard/keystrings_EFS.xml

### Blocked Paths (Do Not Retry)

- Bootloader flash: AT&T carrier lock
- Platform key forgery: Samsung proprietary
- SmartcomRoot command injection: Runtime.exec(String[]) array form
- Abstract sockets: SELinux blocks from both shell and untrusted_app
- JDWP system debugging: ro.debuggable=0
- /dev/mem, /dev/kmem: don't exist
- User namespaces, AF_PACKET, eBPF, POSIX MQ, userfaultfd: not compiled/blocked
- Factory services: KEYSTRING permission (signature|privileged)
- ftrace function tracing: only `nop` tracer compiled
- ABTPersistenceService M5: enforces auth with proper Parcelable
- **BlueBorne CVE-2017-1000251 (kernel L2CAP)**: Android 6.0.1 uses Bluedroid userspace L2CAP, kernel l2cap_parse_conf_rsp() never reached
- **BlueBorne CVE-2017-0781/0782 (BNEP userspace)**: Samsung backported UUID/ctrl/length validation
- ION UAF (kmalloc-64): No fn-ptr victim objects in k64 slab (pipe_buffer NOT in k64 on this device)
- DCCP CVE-2017-8824: SELinux blocks socket creation from ALL reachable contexts
- SELinux policy transitions: No transitions from shell/untrusted_app. su/rd_shell domains DON'T EXIST. diagexe has only 8 rules (SELinux-jailed)
- /data/log symlinks: Permission denied (files OK, symlinks blocked)
- Mali debugfs writes: SELinux blocks despite rw file permissions

### Remaining Vectors (Revised Priority)

1. **Mali T72x alias TOCTOU** — Safest exploit: shrink NATIVE after alias → GPU R/W freed pages. No SMMU. Has PoC (`src/mali/mali_alias_toctou.c`). GPU fault ≠ kernel panic.
2. **Binder proc->files UAF race** — files_struct freed while binder references it. preemption window. Has PoC (`src/binder/binder_files_race.c`). Independent of Samsung CVE-2019-2215 patch.
3. **DRParser keystring injection** — Inject custom keystring XML at /sdcard/keystrings_EFS.xml → DRParser broadcasts SECRET_CODE as UID 1000. Needs RSA encryption of XML (512-bit key, trivially factored). Format reversed.
4. **DM port HDLC binary protocol** — AT surface exhausted but HDLC binary protocol to diagexe unexplored. COM port changes on USB disruption (currently COM9).
5. **Accessibility UI automation** — APK working (uses `cmd` key). 30+ commands including sysdump_attack, secretcode_attack, click_text, set_text.

### ⚠ BlueBorne Status: KERNEL L2CAP UNREACHABLE

**CVE-2017-1000251 (kernel L2CAP stack overflow) is NOT exploitable on this device.**

Android 6.0.1 uses **Bluedroid (userspace L2CAP)**, NOT the kernel's BlueZ L2CAP stack. L2CAP signaling (CONF_REQ/CONF_RSP) is processed entirely by `com.android.bluetooth` (PID 3691) in userspace. The vulnerable kernel function `l2cap_parse_conf_rsp()` is **never called**.

**Evidence** (live test 2026-03-06):
- L2CAP channel opened on first attempt (DCID=0x0041, full CONN_RSP + CONF exchange)
- EFS overflow CONF_RSP sent (70 bytes, UNACCEPT path) — **device survived, uptime unchanged**
- Logcat shows: `bt_l2cap: L2CAP - rcvd cfg rsp for unknown CID: 0x0040` — **userspace** Bluedroid processed and rejected it
- Subsequent runs: raw HCI socket stopped receiving ACL data (local kernel L2CAP consumes packets)
- btmon captures confirm: local kernel processes L2CAP signaling (INFO_REQ/RSP), CONN_RSP returns PENDING (auth required), then local kernel disconnects before exploit can proceed
- **Root cause**: `hci_open_dev(0)` raw socket cannot exclusively receive ACL data when kernel L2CAP module is active. Need `HCI_CHANNEL_USER` or patched BlueZ for exclusive access.

**Additional blocker**: Even with exclusive HCI access, the overflow targets the kernel's `l2cap_parse_conf_rsp()` which is never invoked because Android's Bluedroid handles L2CAP in userspace (com.android.bluetooth PID 3691).

**BNEP (CVE-2017-0781/0782) also BLOCKED**: Samsung backported UUID validation, ctrl type checks, packet length checks.

**BlueBorne is a DEAD END on this device.** Move to Mali TOCTOU or binder proc->files race.

### Capabilities Achieved

**From shell**: install APKs, grant dev permissions (WRITE_SECURE_SETTINGS, READ_LOGS, DUMP), modify settings, input injection, dmesg/debugfs read, ftrace partial control

**From APK (device owner)**: enableSystemApp, silent PackageInstaller sessions, 31 permissions, accessibility service active, connect to dnsproxyd/logd, read /data/system world-readable files

## Kernel Vulnerability Research

### CVE Testing Strategy
For each candidate CVE, write a *minimal detection PoC* that tests the patch condition, not the full exploit. This quickly eliminates patched CVEs without risking device stability.

### Kernel Fuzzing
Targeted struct-aware fuzzing is far more effective than random ioctl fuzzing. Use vendor GPL kernel source for exact struct layouts.

### Key Rule for Physical Devices
**Conservative testing only.** Fork dangerous operations into child processes with alarm() timeouts. Never run aggressive tight-loop races without usleep(). Monitor device with parallel health check thread.
