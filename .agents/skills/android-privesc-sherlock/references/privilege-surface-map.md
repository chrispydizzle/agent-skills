# Android Privesc Sherlock — Privilege Surface Map

This reference is for the middle of the investigation: after you know the foothold, but before you decide the kernel is the answer.

## 1. Management-plane abuse

Treat the management plane as a first-class escalation target.

Why it matters:

- Device Owner or DPC control can be operationally "worse than root"
- provisioning flaws can produce broad policy, logging, certificate, and persistence control without a kernel bug

Look for:

- current Device Owner or profile owner identity
- signs the device became managed after provisioning
- enterprise logging, remote bugreport, or delegated certificate activity
- OEM management equivalents outside stock DevicePolicyManager

High-signal outputs:

- `dumpsys device_policy`
- provisioning and enterprise-policy logs
- unexpected DPC package names or recent owner changes

If the question is incident-response flavored, answer these before anything destructive:

1. is the Device Owner expected for this fleet or user?
2. did management appear only after provisioning?
3. are certificate, bugreport, or enterprise logging powers being exercised unexpectedly?
4. does the boot state reduce trust in OS integrity as well?

## 2. Privileged apps and permission allowlists

Privileged apps are often a cheaper trampoline than kernel exploitation.

Map:

- packages installed under `system`, `product`, `vendor`, or `priv-app`
- allowlisted privileged permissions
- exported components, BROWSABLE activities, deep links, receivers, parsers, WebView bridges, and local IPC surfaces

Questions to answer:

1. Which privileged apps are reachable from the current foothold?
2. Which granted permissions materially change control if inherited?
3. Which component types are historically fragile: parsers, importers, bridges, deserializers, content providers, intent relays?

Treat privileged app exported components as "internet-facing" even when the origin is local IPC or an intent chain.

## 2.5 Content provider triage

Content providers look attractive because they sit in privileged processes and expose structured data. In practice, **most OEM providers on production Samsung firmware are not reachable from shell or untrusted_app**. Rapid elimination is more valuable than deep-dive speculation.

### Triage discipline

1. **Check `dumpsys activity providers`** first — it shows every currently-published provider, its UID, and whether it is singleton. Providers not listed here are not bound and cannot be reached at all.
2. **Probe live with `content query --uri`** — the error tells you the exact gate:
   - `not exported from uid NNNN` → dead end from your foothold, period
   - `requires <custom.permission>` → exported but gated; check whether the custom permission is signature-level (almost always is on Samsung)
   - empty cursor or rows → **open and reachable** — this is the rare exception worth investigating
3. **Compare cost** against service and kernel paths before investing more time. An exported-but-gated provider is *less useful* than a Binder service that returns structured errors, because the provider gate is all-or-nothing while the service may have per-transaction permission checks with exploitable inconsistencies.

### Real-device calibration (Samsung SM-T377A class)

On production Samsung Tab E firmware, the top provider candidates from package dumps are all gated:

| Provider | Authority | Gate | Verdict |
|---|---|---|---|
| MTContentProvider (MobileTracker) | `com.android.settings.mt.provider.MTContentProvider` | not exported, uid 1000 | dead end |
| SoContentProvider (SOAgent) | `com.sec.android.soagent.provider.contentprovider` | not exported, uid 1000 | dead end |
| ExternalOEMControlProvider (SCloud) | `com.samsung.android.scloud.sync.vendor` | custom READ/WRITE perms, uid 5009 | gated |
| OpenContentProvider | `com.msc.openprovider.openContentProvider` | custom READ + PROHIBIT perm, obfuscated naming | gated |

Observation: soagent also registers `MasterLogProvider` under the obfuscated authority `com.sec.android.log.gnj0zk4j42` — also uid 1000 and not exported.

### When providers *do* matter

Providers become interesting when:
- one is genuinely exported without custom permissions (rare on Samsung production builds)
- an intermediary app that *can* reach a gated provider is itself reachable from your foothold (confused-deputy chain)
- the provider's backing database file has weaker filesystem permissions than the provider enforcement suggests
- a race condition or path-traversal bug in the provider's `openFile()` or `call()` methods bypasses the permission gate

If your provider triage finds everything gated, **say so explicitly and pivot**. A common failure mode is spending paragraphs on provider possibilities without stating that all candidates are blocked and that the next cheapest path is a Binder service or kernel surface.

## 3. OEM `system_server` providers and Binder services

OEM-added providers and services are high-value because they already sit on the privileged side of the boundary.

Why they matter:

- they can hand out file descriptors
- they can proxy file operations
- they can invoke privileged APIs for an unprivileged caller
- they often embed OEM assumptions that are easier to get wrong than stock AOSP code

Look for:

- custom provider authorities
- custom Binder services
- path-validation or permission-check failures
- file-oriented operations performed in system processes
- structured permission failures that prove the path is live

When a service returns a Samsung- or OEM-specific error code, do not treat it as noise. It often proves you found a real gate.

## 4. SELinux mistakes as force multipliers

SELinux alone may not be the exploit, but it changes which bugs matter.

High-value policy clues:

- permissive domains
- broad vendor allow rules
- mislabeled files, sockets, or providers
- denials clustered around a specific vendor component

Interpretation rules:

- "denied" means reachable but blocked
- "permissive" means a small bug can become a chain
- no useful transition path should kill trivial domain-hop fantasies

## 5. Logs, dumps, and copied diagnostics as enablers

Logs matter because they change exploit cost.

Look for:

- readable backtraces, addresses, or kernel symbols
- copied diagnostics in weaker-protected locations
- privileged log collectors that mirror denials or audit trails into app-managed zips or reports
- bugreport or dumpstate paths controlled by Device Owner or OEM tooling
- crash loops that repeatedly emit useful state
- wording drift that reveals a more privileged code path than the obvious one

Common mistake:

- treating a vendor log copy as "just debugging output" when it is really a mitigation-defeat oracle
- missing OEM collectors like Samsung `SecurityLogAgent`, where `samsung.intent.action.knox.DENIAL_NOTIFICATION` drives zipping of `/data/misc/audit/audit.old` from a system-UID app into a more reusable artifact flow

## 6. Debug, build-type, and boot-integrity pivots

Starting position changes everything.

Elevate immediately if you see:

- ADB already authorized or persistently available
- `userdebug` or `eng` build characteristics
- `android:debuggable=true`
- unlocked bootloader or warning-state Verified Boot
- per-partition patch drift that keeps vendor code older than framework code

These do not finish the chain by themselves, but they radically change path cost.

## 6.5 Quick comparative ranking

Use this rough ranking when multiple paths are live:

| Path family | Typical start | Typical lift | Usual cost |
|---|---|---|---|
| Device Owner / DPC abuse | untrusted app or local foothold | management-plane control | medium |
| Privileged app trampoline | app foothold | signature / privileged permissions | medium |
| OEM confused deputy (Binder) | untrusted app | `system_server`-mediated capability | medium |
| Content provider intermediary | app or shell | data/file ops in privileged process | low if exported; dead if gated |
| SELinux / policy mistake | any foothold | lateral movement / policy bypass | medium |
| Log or dump enabler | app or privileged intermediary | mitigation defeat / oracle | medium |
| Kernel / driver EoP | untrusted app | root / kernel primitives | high |
| Boot / rollback weakness | physical or staging access | persistent OS control | medium-high |

The point is not the exact labels. The point is to stop treating kernel EoP as the automatic first-place answer.

## 7. Init, service, and filesystem mistakes

These are often OEM-specific and easy to miss.

Map:

- world-writable files and directories
- capabilities granted to services
- privileged components consuming attacker-controlled files
- crash handlers, tombstone paths, or dump pipelines operating on shared storage

Clues that matter:

- ownership or mode changes on sensitive files
- symlink or path confusion opportunities
- privileged service failures that reference attacker-controlled paths
- init or service definitions that over-grant capabilities relative to their job

## 8. Ranking rules

Prefer language like:

- "reachable but permission-gated"
- "high-value confused-deputy candidate"
- "management-plane escalation path"
- "log artifact that lowers exploit cost"
- "kernel lead, but not cheapest next step"

Avoid:

- "probably exploitable" without naming the intermediary, privileged effect, and blocking condition
- "kernel bug" when a cheaper privileged app or OEM service path is still live

## Security-control audit prompts

If the user wants remediation-minded output, prioritize checks for:

- patch velocity across framework, vendor, and boot-facing components
- locked bootloader plus Verified Boot and rollback protection
- debug-surface elimination on production devices
- zero permissive domains and tight vendor SELinux policy
- privileged-app allowlist minimization
- Device Owner / DPC monitoring
- log and dump hygiene, especially OEM pipelines
