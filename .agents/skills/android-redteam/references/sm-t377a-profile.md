# Samsung SM-T377A Device Profile

## Table of Contents
- Device Specifications
- Known Kernel Addresses
- Kernel Mitigations Status
- Attack Surface Map
- CVE Test Results
- ION UAF Analysis
- Service Enumeration Results
- Shell Capabilities
- Fuzzing Campaign Results

## Device Specifications

| Property | Value |
|----------|-------|
| Model | Samsung SM-T377A (Galaxy Tab E 8.0) |
| Carrier | AT&T |
| SoC | Exynos 3475 (ARMv7 Cortex-A7, 4 cores) |
| Android | 6.0.1 (Marshmallow) |
| Build | MMB29K.T377AUCU2AQGF |
| Kernel | 3.10.9-11788437 (compiled 2017-07-05) |
| Security Patch | 2017-07-01 |
| SELinux | Enforcing (u:r:shell:s0) |
| Shell UID | 2000 (groups: input, log, adb, sdcard_rw, sdcard_r, net_bt_admin, net_bt, inet, net_bw_stats) |
| Knox Fuse | 0 (intact) |
| Platform Key | Samsung Corp cert (SHA1: 9CA5170F381919DF), NOT AOSP test key |

## Known Kernel Addresses (Firmware T377AUCU2AQGF)

```
commit_creds       = 0xc0054328
prepare_kernel_cred = 0xc00548e0
selinux_enforcing  = ~0xc0b7ad54  (inferred from sel_write_enforce disasm)
PHYS_OFFSET        = 0x20000000
PAGE_OFFSET        = 0xC0000000
kernel_vaddr       = phys_addr + 0xA0000000
task_struct->cred  = offset 0x164
thread_info->addr_limit = offset 8
KERNEL_DS          = 0xFFFFFFFF
```

**Symbol extraction**: Firmware symbol table in decompressed kernel has +12 index offset vs running /proc/kallsyms (12 extra unnamed entries at start). Token table located by searching for 256 consecutive null-terminated ASCII strings.

**Data symbol note**: Firmware kallsyms only exports T/t/r/R symbol types. Data/BSS symbols (selinux_enforcing, init_cred, modprobe_path) must be found by disassembling referencing functions.

## Kernel Mitigations Status

| Mitigation | Status | Exploitation Impact |
|------------|--------|-------------------|
| KASLR | ABSENT | Kernel addresses predictable |
| PXN | ABSENT | Can execute userspace code from kernel context |
| Stack canaries | ABSENT | Stack overflows directly exploitable |
| HARDENED_USERCOPY | ABSENT | Heap overflow copy primitives available |
| RKP (Samsung) | ABSENT | No runtime kernel integrity checks |
| kptr_restrict | ACTIVE | /proc/kallsyms addresses zeroed (use firmware instead) |
| SELinux | ENFORCING | Blocks msgsnd, mobicore, /cache, security.* xattr |
| mmap_min_addr | ~0x00200000 | Cannot map NULL page, but low addresses OK |
| dm-verity | ACTIVE | /system integrity verified at boot |
| PIE enforcement | ACTIVE | Non-PIE binaries rejected |
| /dev/mem | DOES NOT EXIST | No direct physical memory access |
| /dev/kmem | DOES NOT EXIST | No direct kernel memory access |

## Attack Surface Map

### Accessible Kernel Drivers
| Device | Perms | SELinux | Fuzzing Result |
|--------|-------|---------|---------------|
| /dev/ion | world-RW | Allowed | CRASH on heap bit 2 (DoS) |
| /dev/binder | world-RW | Allowed | DoS via handle 0 refcount |
| /dev/ashmem | world-RW | Allowed | Robust (151K ops) |
| /dev/mali0 | world-RW | Allowed | Robust (29K ops) |
| /dev/ptmx | world-RW | Allowed | Robust |
| /dev/alarm | readable | Allowed | Robust |
| /dev/mobicore-user | world-RW on disk | BLOCKED | SELinux denies shell |
| /dev/s5p-smem | restricted | DAC denied | Permission denied |

### Information Disclosure Sources
- `/proc/slabinfo`: full heap layout
- `dmesg`: 979+ kernel log lines
- `/sys/kernel/debug/`: binder nodes, ION clients, Mali state
- ftrace: sched_switch (process enumeration), writable trace_marker
- `/proc/vmallocinfo`: kernel function names
- `/proc/1/status`: init capabilities
- dumpsys wifi: 8 saved SSIDs, BSSIDs, device MAC, WPA handshake logs
- IMEI/ICCID/IMSI via binder service calls

### Blocked Surfaces
- `/dev/mobicore-user` (SELinux)
- `/data/data/*` (DAC + SELinux)
- `/proc/<root_pid>/maps` (DAC)
- `/proc/self/pagemap` (CAP_SYS_ADMIN)
- Block devices (root-only)
- All /proc/sys writes (18 entries tested)

## CVE Test Results

| CVE | Name | Result | Details |
|-----|------|--------|---------|
| CVE-2016-5195 | Dirty COW | PATCHED | MAP_PRIVATE not modified after race |
| CVE-2015-1805 | pipe iov | PATCHED | readv returns EFAULT correctly |
| CVE-2014-3153 | Towelroot | PARTIAL | 2/3 patches missing but race window too narrow (8000+ iterations) |
| CVE-2015-3636 | ping UAF | PATCHED | LIST_POISON2 page not written |
| CVE-2013-2094 | perf OOB | PATCHED | OOB config returns ENOENT |
| CVE-2014-0196 | n_tty race | LIKELY PATCHED | Hung but no crash |
| CVE-2017-7533 | inotify race | PATCHED | 644K events, no crash |
| CVE-2017-11176 | mq_notify | N/A | CONFIG_POSIX_MQUEUE not compiled |
| CVE-2016-4557 | eBPF UAF | N/A | No bpf() syscall |

## ION UAF Analysis

### What Works
- Free/Share race: 91% win rate (ion_handle freed, SHARE on stale handle succeeds)
- Dangling fd: mmap+write on fd from SHARE after FREE works
- Target slab: kmalloc-64 (ion_handle = 52 bytes)

### What Does NOT Work
- seq_operations is static .rodata, NOT heap-allocated (earlier analysis was wrong)
- msgsnd spray: blocked by SELinux (EPERM on msgget)
- add_key spray: blocked after 198 keys
- No victim object with callable function pointers found in kmalloc-64

### Spray Effectiveness
| Technique | kmalloc-64 delta | Notes |
|-----------|-----------------|-------|
| socketpair | +1169/200ops | Best spray, persistent |
| ptmx | +706 | Also fills kmalloc-512, kmalloc-1024 |
| setxattr user.* | 41,616/sec | Temporary (freed at syscall return) |
| pipe | moderate | Targets kmalloc-1024 mainly |

### Key Technical Detail
The dma_buf from ION_IOC_SHARE holds a reference to the ion_buffer. Even after ion_handle is freed, the buffer stays alive via this dma_buf reference. mmap on the dangling fd accesses VALID buffer pages, not the freed kmalloc-64 slot. The exploit must target the handle lookup or the initial share operation, not subsequent buffer access.

## Service Enumeration Results

- 165+ services enumerated via binder
- 75+ respond to method calls from shell
- All Knox/enterprise services properly check UID/permissions
- Samsung service mode apps: all activities unexported from UID 2000

### Root Tools Found (Inactive)
| Tool | Package | Status |
|------|---------|--------|
| Magisk v30.6 | com.topjohnwu.magisk | Installed, daemon NOT running |
| z4root v1.3.0 | com.z4mod.z4root | Installed |
| Superuser v3.0.7 | com.noshufou.android.su | Installed |
| /sbin/su | N/A | Exists, SELinux blocked |
| KingRoot | com.kingroot.kinguser | Directory on /sdcard |

## Shell Capabilities (Non-Root)

Despite not achieving root, shell UID 2000 has extensive capabilities:

| Capability | Command/Method |
|------------|---------------|
| Grant permissions to any app | `pm grant <pkg> <perm>` |
| Create persistent user accounts | `pm create-user <name>` |
| Uninstall system packages | `pm uninstall <pkg>` |
| Kill any process | `am force-stop <pkg>` |
| Input injection | `input tap/swipe/keyevent` |
| Hardware keylogging | Read /dev/input/event* |
| Screen capture | `screencap` |
| Control init services | `ctl.start`/`ctl.stop` |
| Modify system settings | `settings put global/secure` |
| Read contacts | `content://contacts/people` |
| Write contacts | `content insert` |
| Read WiFi/IMEI/ICCID | `dumpsys wifi`, `service call iphonesubinfo` |
| Kernel DoS (ION) | ION_IOC_ALLOC with heap_id_mask=0x0004 |
| System DoS (Binder) | Refcount ops on handle 0 |

## Fuzzing Campaign Results

| Driver | Ops | Crashes | Key Finding |
|--------|-----|---------|-------------|
| ION | 57,936 | 1 | Heap bit 2 kernel crash (DoS) |
| Binder | 110,199 | 2 | Handle 0 refcount kills servicemanager |
| Ashmem | 151,187 | 0 | Robust |
| Mali | 29,744 | 0 | Robust (24 vendor functions tested) |
| Netlink | 10,000 | 0 | Robust |
| Alarm | 3,000 | 0 | Robust |
| ICMP/UDP | 6,000 | 0 | Robust |
| **Total** | **368,066** | **3** | **2 unique vulnerabilities** |

## Build System

```
.\qemu\build-arm.bat src\file.c output_name
```
Uses WSL Ubuntu-22.04 + arm-linux-gnueabi-gcc. Produces static PIE ARM binaries. Auto-pushes to /data/local/tmp/ via ADB.

## WARNINGS
- DO NOT run `/data/local/tmp/adbd_root` - hangs then crashes device
- DO NOT run `su-v1`, `su-v2`, `rageagainstthecage` - non-PIE, rejected by kernel
- This is a PHYSICAL device - fork-bombs and aggressive races require physical reboot
- Use conservative testing: fork in child processes, use timeouts
