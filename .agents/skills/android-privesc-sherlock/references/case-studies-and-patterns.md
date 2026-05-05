# Android Privesc Sherlock — Case Studies and Patterns

Use these case studies as pattern-recognition anchors, not as a bag of CVE trivia.

For each one, ask: "Do I see the same chain shape here?"

## 1. Device Owner after provisioning

Representative case:

- CVE-2025-48633

Pattern:

- foothold starts local and low privilege
- attacker reaches provisioning or policy logic that should be closed after setup
- result is Device Owner or equivalent management-plane control

Why it matters:

- this can yield policy, logging, certificate, and persistence power without kernel compromise

What the agent should notice:

- Device Owner set after provisioning
- unexpected DPC package identity
- new policy restrictions, enterprise logging, or certificate changes

## 2. OEM confused deputy + log-based mitigation defeat

Representative cases:

- CVE-2021-25337
- CVE-2021-25369

Pattern:

- attacker reaches an OEM provider or service running in a more privileged context
- that intermediary grants file access or privileged operations
- a separate OEM log or copied diagnostic leaks addresses or other exploit-helpful state
- the chain becomes practical because OEM customization created both the deputy and the leak

Why it matters:

- this is the textbook example of why OEM customization and logs belong near the top of the ranking

What the agent should notice:

- custom provider or Binder service in `system_server`
- file-descriptor or file-operation behavior across privilege boundaries
- readable OEM logs or copied backtraces
- a chain where the log is not the bug, but the reason exploitation becomes cheaper

## 3. Binder patch-gap exploitation

Representative cases:

- CVE-2019-2215
- CVE-2023-20938

Pattern:

- Binder is reachable from an app foothold
- the device or driver lags the fix or carries an incomplete remediation
- exploitation focuses on the real device state, not just the public write-up

Why it matters:

- a bug being fixed upstream does not mean released devices are safe
- fix quality and integration quality are part of the attack surface

What the agent should notice:

- reachable Binder surface
- patch-gap evidence or incomplete-fix hints
- local architecture or allocator facts that either help or kill the chain

## 4. Privileged middleware or framework trampoline

Representative case:

- CVE-2015-6606

Pattern:

- third-party or OEM-adopted middleware lives inside a privileged service or framework
- a crafted app reaches that middleware through an intended plugin or extension mechanism
- the result is signature or system-level capability

Why it matters:

- not all privesc lives in core Android; embedded middleware can be the real boundary break

What the agent should notice:

- unusual plugin architecture
- privileged framework with extensibility
- third-party or carrier middleware embedded into the system image

## 5. Tombstone, debuggerd, or init / filesystem mistake

Representative case:

- CVE-2016-2420

Pattern:

- a bug in crash handling, tombstone setup, or init-managed filesystem state creates a privilege boundary mistake
- the bug may only matter because the directory, label, or path handling is wrong

Why it matters:

- service and filesystem mistakes can be easier to miss than memory corruption

What the agent should notice:

- privileged crash-handling components touching attacker-influenced paths
- missing or miscreated directories
- init or service definitions that quietly weaken a boundary
- cases where SELinux containment turns a major bug into a dead end

## 6. Preinstalled privileged framework exposure

Representative family:

- widely deployed preinstalled carrier or OEM frameworks with exposed components

Pattern:

- privileged app footprint is broad
- exported deep-link, BROWSABLE, or local entrypoints are reachable
- the framework becomes a reusable privilege trampoline across multiple devices

Why it matters:

- one preinstalled framework can scale a local privilege pattern across an ecosystem

What the agent should notice:

- privileged package with many exposed components
- deep-link or intent-routing surfaces
- unusual network or parser behavior inside a system app

## Practical takeaway

These case studies should change the agent's instincts:

1. check management plane before assuming kernel
2. treat OEM providers and logs as chain pieces, not side details
3. treat fix quality and patch-gap evidence as first-class
4. look for middleware and framework trampolines
5. do not ignore crash-handling, tombstone, init, or filesystem mistakes

## Pattern-to-question map

When a case starts to resemble one of these examples, ask the matching question immediately:

| Pattern resembles | Ask next |
|---|---|
| Device Owner after provisioning | "What management state changed, and should it have been possible after setup?" |
| OEM provider + log leak | "What privileged intermediary exists, and is there a copied diagnostic lowering exploit cost?" |
| Binder patch-gap | "Is this build actually lagging or incompletely fixed, or am I importing a public story blindly?" |
| Middleware trampoline | "Is there embedded privileged middleware with plugin, parser, or bridge behavior?" |
| Tombstone / init mistake | "Is the real boundary error in filesystem or crash-handling setup rather than memory corruption?" |
| Preinstalled framework exposure | "Is one privileged package serving as a reusable trampoline across the whole ecosystem?" |
