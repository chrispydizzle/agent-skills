# Samsung Knox & SELinux Reference

## Table of Contents
- Samsung Knox Architecture
- Knox Protection Layers
- SELinux on Android (Shell Perspective)
- SELinux Policy Gaps and Bypasses
- Samsung Service Security Model
- Binder Service Enumeration
- Knox Enterprise Services

## Samsung Knox Architecture

Knox is Samsung's multi-layered security platform:

```
Layer 5: Knox Container (MDM workspace separation)
Layer 4: SE for Android (SELinux + Samsung extensions)
Layer 3: TIMA / RKP (Real-time Kernel Protection)
Layer 2: Secure Boot (verified boot chain)
Layer 1: ARM TrustZone (hardware TEE)
Layer 0: Knox Warranty Fuse (hardware, one-time blow)
```

### Knox Warranty Fuse
- Physical eFuse in SoC, irreversibly blown if unauthorized boot detected
- Check: `cat /proc/sys/kernel/kn0x` or check KNOX field in download mode
- Value 0 = intact (never tripped), 0x1 = blown
- Once blown: Samsung Pay, some banking apps refuse to run
- On carrier-locked devices: even with fuse intact, flash of unsigned images is blocked

### TIMA / RKP (Real-time Kernel Protection)
- Present on Galaxy S5+ flagships, NOT on budget tablets like Tab E
- Monitors kernel code integrity at runtime via TrustZone
- Prevents: kernel code modification, credential struct tampering
- On devices WITHOUT RKP: kernel code/data is modifiable if you achieve write primitive

### Secure Boot
- Bootloader verifies each stage: BL1 -> BL2 -> ABOOT -> kernel -> system
- Carrier-locked devices add an ADDITIONAL signature check beyond Samsung's
- AT&T devices: `OEM unlock` toggle is cosmetic; bootloader still rejects unsigned images
- Verification is in the bootloader ROM, not software-bypassable

## SELinux on Android

### Domain Model
Android SELinux uses type enforcement. Key domains:
- `u:r:shell:s0` - ADB shell (UID 2000)
- `u:r:untrusted_app:s0` - Third-party apps
- `u:r:system_app:s0` - System apps
- `u:r:system_server:s0` - system_server process
- `u:r:init:s0` - Init process (PID 1)
- `u:r:kernel:s0` - Kernel threads
- `u:r:su:s0` - Superuser domain (if in policy)

### Shell Domain Restrictions
From `u:r:shell:s0`, SELinux typically blocks:
- `msgget`/`msgsnd`/`msgrcv` (System V IPC)
- Access to `/dev/mobicore-user` (TrustZone client)
- Writing to `/cache` partition
- Reading `/data/data/<pkg>` (app private data)
- `security.*` extended attributes
- `BINDER_SET_CONTEXT_MGR` ioctl
- Creating files in `/data/tombstones`
- Accessing dalvik-cache

### Shell Domain Permissions (What DOES Work)
- Open and ioctl: `/dev/ion`, `/dev/binder`, `/dev/ashmem`, `/dev/mali0`, `/dev/ptmx`
- Read: `/sys/kernel/debug/` (debugfs), `/proc/slabinfo`, dmesg
- Write: ftrace events (limited), `/dev/input/event*`
- Binder transactions to most system services
- Network sockets (TCP, UDP, ICMP, NETLINK_ROUTE, NETLINK_SELINUX)

### SELinux Policy Analysis
Extract policy for offline analysis:
```
adb pull /sys/fs/selinux/policy ./sepolicy
# Use sesearch, seinfo tools from setools package
sesearch --allow -s shell -t ion_device sepolicy
```

### Attempted SELinux Bypasses
- `setenforce 0`: requires CAP_MAC_ADMIN, denied from shell
- `runcon u:r:su:s0 id`: fails if su domain not in policy ("Invalid argument")
- `runcon u:r:system_server:s0 id`: context changes but UID stays 2000 (DAC still enforced)
- Writing to `/sys/fs/selinux/enforce`: permission denied
- Kernel-level: write 0 to `selinux_enforcing` variable (requires kernel write primitive)

## Samsung Service Security Model
Samsung services use multiple protection layers:

### Permission Checks
1. **Android permissions** (manifest-declared, signature-level for sensitive ops)
2. **UID checks** (direct comparison: `Binder.getCallingUid()`)
3. **SELinux MAC** (binder_call between domains)
4. **Samsung MDM checks** (Knox-specific authorization)

### High-Value Samsung Services

**EngineeringModeService** (7 methods)
- Method 1: returns success (0)
- Methods 6-7: return error (-1, -1300)
- Likely wraps a few critical diagnostic commands

**DeviceRootKeyService** (5 methods)
- Method 5 returns -19 (ENODEV)
- Suggests hardware/TrustZone interaction
- All useful operations require signature-level permissions

**ABTPersistenceService** (Absolute Persistence)
- Transaction 1: "Not authorized" (UID check)
- Transaction 2: state validation + auth required
- Transaction 3: "Not authorized"
- Anti-theft persistence layer

**SatsService**
- Samsung account/token service
- Responds to shell but returns empty/error for useful operations

**com.smartcom.root.APNWidgetRootService** (15 methods)
- Despite "root" in name: only APN-related methods
- Many return void/null (0x0)
- No shell execution capability found

### Service Enumeration Methodology
```bash
# List all services
service list
# Probe method count (binary search for UNKNOWN_TRANSACTION)
service call <name> 1
service call <name> 100  # if error, binary search down
# Dump service interface
dumpsys <name>
```

## Knox Enterprise Services

All Knox enterprise services check authorization before acting:

| Service | Protection | Shell Result |
|---------|-----------|--------------|
| device_policy | Active admin check | "No active admin owned by uid 2000" |
| edm_proxy | Returns empty | No useful action |
| remoteinjection | sec.MDM_REMOTE_CONTROL | Signature permission required |
| knox_security_policy | MDM enrollment | Not enrolled |
| dpm set-device-owner | MDM_PROXY_ADMIN_INTERNAL | Samsung-specific check blocks |
| dpm set-profile-owner | Same Samsung MDM check | Blocked |

**Key insight**: Samsung Knox services are properly secured even on older firmware. The MDM_PROXY_ADMIN_INTERNAL check is a Samsung addition not present in AOSP, preventing shell from becoming device admin.
