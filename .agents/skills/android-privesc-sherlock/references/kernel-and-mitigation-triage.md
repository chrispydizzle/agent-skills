# Android Privesc Sherlock — Kernel and Mitigation Triage

Use this reference only after you have checked for cheaper management-plane, privileged-app, OEM-provider, policy, or logging paths.

## 1. When kernel EoP should move up the list

Kernel or driver EoP deserves promotion when most of the following are true:

- the reachable surface is real from the current foothold
- the build lineage or partition drift suggests a patch gap
- the mitigation posture leaves corruption meaningfully exploitable
- logs, dumps, or copied diagnostics reduce exploit cost
- there is no cheaper privileged intermediary already in reach

If those conditions are missing, downgrade the kernel theory instead of keeping it as the dramatic default.

## 2. Patch-gap reasoning

Do not ask only, "Is this CVE old?"

Ask:

1. What exact kernel lineage or vendor component version is present?
2. Is the framework patch level newer than vendor or boot partition posture?
3. Is there evidence the fix exists upstream but may not be integrated on this device?
4. Does the target architecture actually execute the vulnerable path?

Per-partition drift matters. A newer Android patch month does not automatically mean the relevant vendor driver is fixed.

## 3. Reachable-surface triage

For each candidate kernel family, name:

- foothold: `untrusted_app`, `shell`, physical, or privileged intermediary
- reachable node or path: `/dev/*`, Binder transaction, USB path, modem path, GPU path, etc.
- required capability or blocked condition
- evidence that the code path is actually exercised on this build

Recommended buckets:

- Binder
- GPU
- ION or dma-buf style allocators
- ashmem or memory-sharing primitives
- USB or accessory paths
- modem and telephony-adjacent kernel interfaces
- OEM-specific drivers

## 4. Mitigation interpretation

Translate mitigation facts into ranking, not theater.

### High-value facts

- KASLR absent -> info leaks matter less, corruption value rises
- PXN absent -> some code-exec paths become simpler
- stack canaries absent -> stack corruption becomes more attractive
- HARDENED_USERCOPY absent -> copy-based bugs gain leverage
- SELinux enforcing -> many post-exploit actions may still need planning
- bootloader locked -> persistence paths shift away from image flashing
- integrity monitors active -> persistent kernel tampering may have extra constraints

### Common mistakes

- assuming a mitigation absence makes every bug reachable
- assuming a published bug is relevant without checking userspace / kernel split
- assuming the exploit target path exists just because the subsystem name exists on the device

## 5. Logs and diagnostics as exploit-cost reducers

Kernel exploitation ranking changes when logs provide:

- addresses or backtraces
- allocator state
- privileged side effects or timing oracles
- repeated crash artifacts from the same path
- copied diagnostics with weaker permissions than the original source

If a log artifact lowers exploit cost, call that out explicitly. It may be the real reason a chain is practical.

## 6. Dead-end checklist

Try to kill the theory with these questions:

- Is userspace handling the path before the kernel ever sees it?
- Does SELinux block the required setup step from all reachable domains?
- Does the target build lack the feature entirely?
- Did live repo evidence already show the surface is robust or non-exploitable on this device?
- Is the observed effect only a crash or DoS with no privilege-bearing object or primitive?

If yes, close the path clearly and move on.

## 7. Output language

Use explicit rankings such as:

- "kernel path is credible but still costlier than the live OEM provider path"
- "reachable driver surface, but architecture facts already kill this CVE family"
- "real kernel lead, promoted because mitigation posture and logs make it cheaper here"
- "DoS-only unless a privilege-bearing victim object is identified"
