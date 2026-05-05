# Android Privesc Sherlock — Core Methodology

## High-level discovery workflow

Use this as the default investigation flow:

1. collect device identity and patch context
2. enumerate the privileged attack surface
3. find weakness signals
4. select the cheapest credible privesc path
5. validate the chain in a lab or artifact-backed way
6. only then think about persistence, stealth, or operationalization

That order matters. Agents often waste time by jumping from "weird kernel thing" straight to exploitation without first exhausting management-plane, privileged-app, OEM-provider, or log-enabled paths.

## Source inventory template

Build an inventory before judging paths.

| Artifact | What it proves well | Typical blind spots | High-value joins |
|---|---|---|---|
| `getprop`, build fingerprint, patch level | build lineage, security posture, partition drift | says nothing about exported app entrypoints or OEM logic bugs | build ID, device codename, patch month |
| package inventory + `priv-app` placement | privileged app trust boundaries | placement alone does not prove exported or reachable components | package name, signing lineage, permission grants |
| permission allowlists (`privapp-permissions*.xml`) | which packages hold dangerous privileged permissions | allowlist presence does not prove reachable code path | package name, permission name |
| `service list`, `dumpsys`, binder responses | live system services and access behavior | negative replies can be permission gates, not proof of no value | service name, transaction code, UID |
| `content query` probes, `dumpsys activity providers` | which providers are actually reachable vs gated vs not-exported | provider registration alone does not prove reachability; must live-probe | authority, uid, exported state, permission gate |
| SELinux policy + AVC denials | domain boundaries, blocked-but-reachable surfaces, policy mistakes | denials alone do not prove a bypass | domain, type, class, perm |
| logcat, bugreports, DropBox, tombstones | runtime behavior, copied diagnostics, crash or ANR pivots | noisy and often observer-side rather than cause-side | PID/TID, package, timestamp |
| `/dev`, `/proc`, `/sys`, debugfs | kernel and driver exposure | many nodes exist but are blocked by DAC or SELinux | node name, major/minor, ioctl family |
| firmware / decompiled APKs / vendor source | hidden services, signing assumptions, struct layouts | static reachability can differ from runtime policy | package, symbol, service string |

## Ranking discipline

Always score a candidate path on three axes:

1. **Reachability** — can the current foothold actually touch it?
2. **Privilege lift** — what new authority would it grant?
3. **Chain cost** — how much exploit engineering is still needed?

If two paths have similar impact, prefer the one with:

- the stronger artifact trail
- the cheaper validation step
- the more stable privileged intermediary
- the fewer speculative assumptions about hidden state

Example decision rules:

- If a privileged app has an exported bridge and already holds dangerous privileged permissions, that often outranks a speculative driver UAF.
- If an OEM provider runs in `system_server` and returns permission-shaped failures, treat it as a high-value confused-deputy candidate.
- If bootloader state, platform signing, or architecture facts already kill a path, close it and move on.

## What system output means

### Patch and build output

- Old patch level + old kernel + OEM lag = patch-gap hunting becomes worthwhile.
- Per-partition drift matters; vendor lag can keep a driver bug alive even when framework patch level looks newer.
- `userdebug`, `eng`, or `ro.debuggable=1` changes the entire starting position and must be elevated near the top of the report.
- Treat `system`, `vendor`, `boot`, and similar partition versions as separate evidence, not one blended "patch level."

### Permission and service output

- `SecurityException`, Samsung `-1300`, or "not authorized" often mean **reachable but blocked**, not irrelevant.
- A service returning structured errors is often more interesting than one that silently ignores the call, because it proves the transaction path exists.
- Exported-but-failing providers and services often reveal exactly which capability boundary you need to cross.

### SELinux output

- `avc: denied` means the surface is reachable enough for the kernel to evaluate policy.
- permissive domains are force multipliers, because "logged but allowed" collapses whole classes of barriers.
- no transition path from `shell` or `untrusted_app` should kill fantasies about easy domain hopping.

### Log and crash output

- copied diagnostics are not harmless duplicates; they can be weaker-protected exploit enablers
- bugreports and OEM logs can leak addresses, feature flags, credential material, or privileged workflow details
- ANRs and tombstones often reveal the privileged intermediary in a chain even when they do not reveal the exploit itself
- do not stop at the leaked content; identify the collector, copier, or re-exporter that stages the artifact
- on Samsung-style corpora, look for named collectors such as SysDump, SilentLog, SecurityLogAgent, DropBox fanout, or recovery-copy hooks before concluding the logs are "just there"

### Boot and integrity output

- locked bootloader + proprietary platform key + Verified Boot usually kills image-flash fantasies
- unlocked or warning-state devices move persistence paths up the ranking
- rollback or partition version drift changes whether downgrade logic deserves attention

## Weakness-signal checklist

If you are unsure where to focus first, scan for these signals in this order:

1. permissive or oddly broad SELinux policy behavior
2. privileged-app footprint plus allowlisted dangerous permissions
3. OEM providers or Binder services in `system_server`
4. logs, dumps, or copied diagnostics leaking addresses, secrets, or privileged workflow details
5. debug surfaces and build-type pivots
6. patch-gap evidence in reachable drivers

This ordering mirrors the report's core point: many successful chains begin with weak management, OEM, policy, or logging posture before they ever need a kernel primitive.

## Four chain families to consider every time

### 1. Management-plane abuse

Ask:

- Can a Device Owner or DPC be added, replaced, or abused?
- Are there equivalent OEM management planes?
- Can bugreport, certificate, logging, or package controls be hijacked?

High-value clues:

- Device Owner set after provisioning
- enterprise certificate delegation
- remote bugreport or security logging activity
- policy changes inconsistent with the expected DPC package

### 2. Privileged-app or OEM service abuse

Ask:

- Which privileged apps or services are attacker-reachable?
- Which ones hold signature or privileged permissions worth stealing?
- Are there weird entrypoints: deep links, BROWSABLE activities, WebView bridges, parsers, intents, providers?

High-value clues:

- exported privileged component
- suspicious parser or bridge class
- provider or Binder transaction in `system_server`
- app running with unusually broad allowlisted privileged permissions

Provider-specific discipline:

- If the prompt includes provider lists or `all_providers.txt`-style inventories, **do not assume the most interesting-looking authority is reachable**. Live-probe with `content query` or check `dumpsys activity providers` for exported state.
- When all provider candidates are gated, say so explicitly and pivot to Binder service or kernel paths. The worst failure mode is listing provider possibilities without closing them.
- Compare providers against Binder services on the same device: a Binder service returning structured permission errors is often a more productive lead than a gated provider, because Binder services may have per-transaction granularity where individual calls differ in their gate.

### 3. Policy or logging force-multipliers

Ask:

- Does SELinux materially weaken containment?
- Do logs or dump paths leak addresses or secrets?
- Is there a copied diagnostic path with weaker permissions than the source?

High-value clues:

- permissive domains
- bad file labels or world-readable crash artifacts
- OEM logging pipelines with kernel backtrace or sensitive system output
- named system-UID collectors that read protected sources and zip, copy, or rebroadcast them
- explicit audit or denial-log flows such as `DENIAL_NOTIFICATION` -> log collector -> `audit.old` / zip output

### 4. Kernel or driver EoP

Ask:

- Which drivers are actually reachable?
- Which ones match this kernel lineage and patch context?
- Is there an info leak that would make a real exploit cheaper?

High-value clues:

- world-RW device nodes
- unusual ioctls or vendor extensions
- patch-gap evidence
- mitigation posture that makes corruption more exploitable

## Source priority order

When you need outside grounding or cross-checks, prefer:

1. AOSP security and architecture documentation
2. Android Security Bulletins
3. primary incident or Project Zero-style root-cause analyses
4. NVD for naming and normalization
5. secondary vendor research only after validation

That order keeps the skill anchored in durable platform truth before ecosystem commentary.

## "What kills the theory?" checklist

Before recommending a path, try to falsify it:

- Does userspace handle the protocol before the kernel ever sees it?
- Does platform signing or carrier lock kill the boot or app-install path?
- Does SELinux block the required primitive from every reachable domain?
- Are the provider candidates actually exported? If `content query` returns `not exported` or `requires <custom.permission>`, the provider path is dead from this foothold — close it and compare against Binder services.
- Does the log prove the scary-looking behavior is only an observer-side symptom?
- Does the build lack the feature entirely?

If yes, close the path explicitly and say why.
