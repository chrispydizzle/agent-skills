# Android Privesc Sherlock — Samsung Device Playbook

Use this reference for Samsung devices, especially Knox-era consumer devices and legacy Exynos tablets similar to the SM-T377A in this repository.

## Samsung-specific priorities

Samsung changes the privilege landscape in four big ways:

1. **Knox and TrustZone layers** add extra policy, integrity, and management behavior
2. **OEM services and providers** create custom privileged surfaces beyond AOSP
3. **carrier and bootloader policy** can kill persistence paths even when Android settings suggest otherwise
4. **OEM logging and service-mode tooling** can leak or proxy privileged behavior in ways stock Android does not

## First questions to answer

1. Is the bootloader truly unlockable, or is the toggle cosmetic under carrier lock?
2. Is the platform signed with Samsung keys or test keys?
3. Are Knox, TIMA, or related integrity layers active?
4. Which Samsung-only services, receivers, secret-code handlers, parsers, or management apps are present?
5. Do Samsung logs, DropBox copies, or sysdump artifacts expose privileged state, addresses, or system behavior?

## High-value Samsung outputs

### Service and Binder behavior

Samsung-specific errors are valuable clues:

- `-1300` often means a Samsung authorization gate, not a dead path
- "not authorized" or structured negative returns often prove the service is live and doing meaningful gatekeeping
- custom service names with `eng`, `device`, `root`, `key`, `persistence`, `clipboard`, `parser`, or `diag` deserve ranking attention

### Logging and diagnostics

Treat Samsung diagnostics as possible exploit enablers:

- copied log files
- sysdump artifacts
- service-mode logs
- kernel backtraces reflected into readable locations
- telemetry that mirrors privileged process behavior more weakly protected than the source
- Samsung log collectors such as `com.samsung.android.securitylogagent`, especially when `samsung.intent.action.knox.DENIAL_NOTIFICATION` causes `/data/misc/audit/audit.old` to be zipped or re-exported by a system-UID app

What to ask:

- is this a weaker-protected copy of a more privileged diagnostic?
- does this output lower exploit cost by leaking addresses, boot state, or privileged workflow details?
- is the Samsung log acting as an oracle even if it is not the primary bug?
- did an OEM collector preserve SELinux denial or audit state that is more actionable than the original protected source?

### OEM framework and middleware

Prioritize:

- carrier or Samsung frameworks preinstalled as privileged apps
- parsers, secret-code handlers, configuration importers, or XML loaders
- device management and anti-theft services
- telephony and modem-facing daemons with unusual capabilities

Also prioritize:

- Samsung-only Binder services that return structured authorization codes
- secret-code flows, XML importers, and parser assets inside privileged APKs
- carrier-added frameworks that sit above stock AOSP privilege boundaries

## SM-T377A-like device guidance

For devices similar to this repository's target, start from `STATUS.md` and treat these facts as ranking inputs:

- bootloader is carrier-locked; the OEM unlock toggle is cosmetic
- Samsung proprietary platform signing kills trivial test-key app installation fantasies
- SELinux is enforcing and fully analyzed; no easy transition path from `shell` or `untrusted_app`
- TIMA is active and must be considered when reasoning about persistent kernel tampering
- no KASLR, no stack canaries, no PXN, and no HARDENED_USERCOPY make real kernel bugs more valuable when present

## Current high-value path families on this device class

### 1. OEM confused deputy and privileged framework surfaces

Ask:

- can an OEM service perform file, secret-code, package, or telephony actions for the caller?
- can a parser or config importer load attacker-controlled material?
- can a diagnostic or management component be turned into a privileged intermediary?

### 2. Logs or dumps that lower exploit cost

Ask:

- does a Samsung log mirror kernel or privileged state into a weaker file?
- do sysdump or service-mode artifacts leak addresses, secrets, or policy state?
- does telephony or OEM middleware reflect sensitive boot or diagnostic state into readable logs?

### 2.5. Management and anti-theft planes

Ask:

- does Samsung or carrier management logic create a Device Owner-like control plane?
- are anti-theft or persistence services reachable enough to expose a gated but real path?
- do bugreport, logging, package, or certificate controls sit behind an OEM gate that is worth mapping?

### 3. Kernel / driver surfaces that remain reachable

On this device family, reachable surfaces worth ranking include:

- Binder
- ION
- Mali GPU
- ashmem
- modem / DM tooling

But do not carry forward paths already disproved by the actual architecture or live tests.

## Dead-end discipline for this repository

Kill these quickly when they reappear:

- BlueBorne kernel L2CAP fantasies when the handling stayed in userspace Bluedroid
- easy SELinux bypass stories when policy analysis already proves no useful transition
- unsigned-image boot fantasies on AT&T carrier-locked Samsung hardware
- stale address or mitigation assumptions contradicted by current `STATUS.md`
- generic "Samsung service exists therefore exploitable" claims without a reachable intermediary and privileged effect

## Samsung clue-to-path map

| Clue | What it usually means |
|---|---|
| Samsung-specific negative code on Binder call | live OEM gate worth mapping further |
| readable copied diagnostic with backtrace or addresses | mitigation-defeat or oracle lead |
| secret-code or parser asset inside privileged APK | potential privileged-app trampoline or confused deputy |
| `system_server` or privileged process mediating file operations | OEM provider / service confused deputy candidate |
| telephony or modem daemon with large capability set | high-value boundary, even if direct entry is not yet proven |
| strict carrier lock + intact fuse | persistence should focus on runtime or management-plane paths, not flashing |

## Best-practice report language for Samsung cases

Prefer:

- "Samsung-specific privileged intermediary"
- "OEM-only logging enabler"
- "carrier-lock kills boot-chain persistence here"
- "policy-gated but reachable service"
- "promising Samsung customization path"
- "Samsung-specific management-plane lead"

Do not bury Samsung-specific constraints under generic Android advice; they often decide the path ranking outright.
