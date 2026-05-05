# Android Kernel Fuzzing Methodology

## Table of Contents
- Fuzzing Strategy Overview
- Target Identification
- Fuzzer Design Patterns
- ADB Shell Fuzzing Constraints
- Driver-Specific Approaches
- Crash Collection and Triage
- Safety Considerations for Physical Devices

## Fuzzing Strategy Overview

Android kernel fuzzing from ADB shell (UID 2000) follows this workflow:

1. **Enumerate attack surface**: Probe accessible /dev nodes, /proc, /sys, sockets
2. **Identify target drivers**: Determine which devices are world-readable/writable AND allowed by SELinux
3. **Research driver interface**: Use vendor GPL kernel source (Samsung provides this) to understand ioctl commands and struct layouts
4. **Build targeted fuzzers**: Write C fuzzers compiled as static PIE ARM binaries
5. **Run with monitoring**: Watch dmesg, logcat, and device responsiveness
6. **Collect and triage crashes**: Capture kernel logs, debugfs state, crash artifacts

## Target Identification

### Device Node Probing
```c
// Probe accessibility of /dev nodes
const char *devices[] = {
    "/dev/ion", "/dev/binder", "/dev/ashmem",
    "/dev/mali0", "/dev/ptmx", "/dev/alarm",
    "/dev/mobicore-user", "/dev/s5p-smem", NULL
};
for (int i = 0; devices[i]; i++) {
    int fd = open(devices[i], O_RDWR);
    if (fd >= 0) printf("ACCESSIBLE: %s\n", devices[i]);
    else printf("BLOCKED: %s (%s)\n", devices[i], strerror(errno));
    close(fd);
}
```

### Socket Probing
```c
// Test which socket types are allowed
int families[] = {AF_INET, AF_INET6, AF_NETLINK, AF_UNIX, AF_PACKET};
int types[] = {SOCK_STREAM, SOCK_DGRAM, SOCK_RAW, SOCK_SEQPACKET};
// Try each combination, note which succeed
```

### Procfs/Sysfs Probing
```bash
# Find readable /proc entries
for f in /proc/*; do cat "$f" 2>/dev/null | head -1 && echo "READABLE: $f"; done
# Find writable sysfs entries
find /sys -writable -type f 2>/dev/null
```

## Fuzzer Design Patterns

### Basic Ioctl Fuzzer
```c
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <unistd.h>
#include <string.h>
#include <time.h>

int main(int argc, char *argv[]) {
    int fd = open("/dev/TARGET", O_RDWR);
    if (fd < 0) { perror("open"); return 1; }

    srand(time(NULL) ^ getpid());
    unsigned char buf[4096];
    int ops = 0;

    for (int i = 0; i < 10000; i++) {
        // Generate random ioctl command
        unsigned int cmd = rand();
        // Fill buffer with random data
        for (int j = 0; j < sizeof(buf); j++) buf[j] = rand();
        // Random buffer size
        int size = rand() % sizeof(buf);

        ioctl(fd, cmd, buf);
        ops++;

        if (ops % 1000 == 0)
            printf("[%d] ops completed\n", ops);
    }

    close(fd);
    return 0;
}
```

### Struct-Aware Fuzzer (Recommended)
Use kernel source to define correct struct layouts, then mutate specific fields:

```c
// Example: ION struct-aware fuzzing
struct ion_allocation_data {
    size_t len;
    size_t align;
    unsigned int heap_id_mask;
    unsigned int flags;
    int handle;
};

void fuzz_ion_alloc(int fd) {
    struct ion_allocation_data data;
    // Start with valid values
    data.len = 4096;
    data.align = 4096;
    data.heap_id_mask = 1;  // system heap
    data.flags = 0;

    // Mutate one field at a time
    // Test boundary values, powers of 2, max values
    size_t lengths[] = {0, 1, 4095, 4096, 4097, 0x1000, 0x10000,
                        0x100000, 0x1000000, 0x7FFFFFFF, 0xFFFFFFFF};
    for (int i = 0; i < sizeof(lengths)/sizeof(lengths[0]); i++) {
        data.len = lengths[i];
        ioctl(fd, ION_IOC_ALLOC, &data);
    }
}
```

### Race Condition Fuzzer
```c
// Template for testing race conditions between two operations
#include <pthread.h>

volatile int go = 0;
volatile int target_handle;

void *thread_free(void *arg) {
    int fd = *(int *)arg;
    while (!go) {} // spin until synchronized
    ioctl(fd, ION_IOC_FREE, &target_handle);
    return NULL;
}

void *thread_share(void *arg) {
    int fd = *(int *)arg;
    while (!go) {} // spin until synchronized
    struct ion_fd_data data = { .handle = target_handle };
    ioctl(fd, ION_IOC_SHARE, &data);
    return NULL;
}

// Launch both threads, set go=1, check results
```

## ADB Shell Fuzzing Constraints

### What You Can Do
- Open world-RW /dev nodes
- Create sockets (TCP, UDP, ICMP, NETLINK_ROUTE, NETLINK_SELINUX)
- Fork/exec child processes
- Read /proc/slabinfo, dmesg, debugfs
- Write to /data/local/tmp/ (nosuid, nodev, noexec)
- Allocate memory (mmap, brk)
- Use pthreads for race conditions

### What You Cannot Do
- Load kernel modules
- Access /dev/mem or /dev/kmem (don't exist)
- Use System V IPC (msgsnd/msgrcv blocked by SELinux)
- Create more than 198 keys (add_key quota)
- Access /dev/mobicore-user (SELinux)
- Write to /proc/sys/* (permission denied)
- Create SOCK_RAW/AF_PACKET (some types blocked)

### Binary Compilation
Must produce static PIE ARM32 binaries:
```bash
arm-linux-gnueabi-gcc -static -pie -fPIE -o output source.c -lpthread
```
Non-PIE binaries are rejected by kernel with SIGKILL.

## Driver-Specific Approaches

### ION Memory Allocator
- Safe heaps: bit 0 (system), bit 1 (noncontig), bit 4 (exynos contig)
- DANGEROUS: bit 2 (CMA) causes kernel crash - avoid in production testing
- Ioctl commands: ION_IOC_ALLOC, ION_IOC_FREE, ION_IOC_SHARE, ION_IOC_IMPORT, ION_IOC_SYNC, ION_IOC_CUSTOM
- UAF testing: race ION_IOC_FREE against ION_IOC_SHARE on same handle
- Key insight: PROTECTED flag (bit 31) triggers WARN() but no crash

### Binder IPC
- Commands: BC_TRANSACTION, BC_REPLY, BC_INCREFS, BC_ACQUIRE, BC_RELEASE, BC_DECREFS
- DANGEROUS: handle 0 refcount operations kill servicemanager
- Safe: handle 1+ operations, all tested to 37K+ ops without issue
- Approach: fuzz transaction data to various services, fuzz refcount on handles > 0

### Mali GPU
- 24 Samsung vendor function IDs (KBASE_FUNC_*)
- All struct sizes verified against Samsung GPL source
- Approach: iterate all function IDs with valid-looking structs, mutate fields
- Result on SM-T377A: extremely robust, no crashes after 29K ops

### Ashmem
- 10 ioctl types: set_name, set_size, set_prot, pin, unpin, mmap, purge
- Path traversal in names accepted but not exploitable
- Integer overflow in pin ranges handled correctly
- Very robust driver

## Crash Collection and Triage

### Monitoring During Fuzzing
```bash
# Terminal 1: Run fuzzer
adb shell /data/local/tmp/fuzzer

# Terminal 2: Watch kernel log
adb shell dmesg -w

# Terminal 3: Watch logcat
adb logcat -v time

# Terminal 4: Periodic health check
while true; do adb shell echo ok && sleep 5; done
```

### Post-Crash Collection
```bash
# After device reboots from crash
adb shell dmesg > crash_dmesg.txt
adb shell logcat -d > crash_logcat.txt
adb shell cat /sys/kernel/debug/binder/state > binder_state.txt
adb shell cat /sys/kernel/debug/ion/clients > ion_clients.txt
```

### Triage Priority
1. Kernel panic/oops with PC in exploitable code path -> HIGH (potential code exec)
2. Use-after-free detected (KASAN or manual) -> HIGH (potential code exec)
3. NULL deref in privileged context -> MEDIUM (DoS, maybe escalation)
4. WARN() without crash -> LOW (information only)
5. Driver returns error code -> INFORMATIONAL

## Safety Considerations for Physical Devices

- **Always fork into child process** for dangerous operations
- **Set alarm()/timer for timeouts** - kill fuzzer if hung
- **Start with small iteration counts** (100-1000) before scaling up
- **Monitor device responsiveness** with parallel health check
- **Never run adbd_root or non-PIE binaries** - they crash/hang the device
- **Avoid aggressive races** with very tight loops - use usleep() between iterations
- **Test one thing at a time** - don't combine multiple risky operations
- **Save state frequently** - copy logs off device periodically
- **Know the dangerous operations**: ION heap bit 2, binder handle 0 refcount
