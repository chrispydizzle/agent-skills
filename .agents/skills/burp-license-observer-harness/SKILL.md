---
name: burp-license-observer-harness
description: |
  Recreate a JVM license-validation observer harness (ByteBuddy javaagent) for an
  obfuscated desktop Java app — built for Burp Suite Pro but generalizable. Use when
  the obfuscated class/method names have changed across a new build and the existing
  agent no longer matches, when you need to re-derive the licensing flow from a fresh
  JAR, trace the startup validation path, build/run the observer agent, diagnose a
  hard-stop license exception, or inject a synthetic license object so the app boots
  under instrumentation. Triggers: "rebuild the burp observer", "new burp version",
  "license agent stopped matching", "re-derive obfuscated names", "trace licensing
  flow", "synthetic license proxy", "Zvoa hard stop".
metadata:
  portable: true
  authorised_use_only: true
---

# Burp / JVM License Observer Harness

## Overview

Obfuscated builds rename classes/methods every release (e.g. `Zvob`, `Zpq0`,
`Zk6d`), so a hard-coded ByteBuddy agent breaks on update. This skill is the
**repeatable methodology** to re-derive the licensing flow from a fresh JAR and
rebuild the observer harness — without depending on last version's names.

It distills a working reference implementation (Burp Suite Pro build 46522) into
version-independent **anchors → names** re-derivation, an agent template, a
build/run/diagnose loop, and an optional synthetic-license injection that lets
the app complete startup under instrumentation.

> **Authorised, educational, defensive reverse-engineering only.** Operate only
> on software you own/are licensed to analyse. The synthetic-license step is for
> understanding enforcement under observation, gated behind an explicit flag and
> off by default. Do not generate, distribute, or sell licences.

## When to use (and not)

- Use when: a Burp/JVM update broke the agent; you have a new JAR and need to
  remap names; you want to trace the validation path; or boot under the agent.
- Don't use for: producing license keys/cracks, redistribution, or any
  unauthorised target. This skill documents observation and analysis.

## The core problem: names move, structure doesn't

Obfuscation renames symbols but **cannot** rename:
- JDK/library types and the app's non-obfuscated packages (e.g. a
  `net.portswigger.*` state enum).
- String/URL/protocol constants (activation endpoints, prefs keys).
- Structural shape (a license *interface* with a `Date` getter + a boolean
  expiry-check taking a clock; a holder struct with a `public final <iface>`
  field; a single hard-stop exception that aborts `main`).

You re-derive the current obfuscated names by matching these **stable anchors**.
See `references/name-rederivation.md` for the full anchor table and the build-46522
worked example (your "Rosetta stone").

## Workflow (phases)

```
0. Inventory      → verify JAR, manifest (Main-Class, version), extract classes
1. Re-derive      → map stable anchors to current obfuscated names
2. Build agent    → fill the template's name/signature map, compile to a jar
3. Observe        → run app with -javaagent, read the ENTER/EXIT log
4. Diagnose       → locate the hard-stop exception and the gate that throws it
5. (Optional) Boot→ inject a synthetic license so startup completes
6. Document       → status map of enforcement points vs. instrumentation
```

### Phase 0 — Inventory
- Confirm the JAR path; read `META-INF/MANIFEST.MF` for `Main-Class` (the entry,
  e.g. `burp.StartBurp`), `Implementation-Version`, and any `Add-Opens` (JCE
  reflection is a licensing signal).
- Decompile target classes with **multiple** decompilers (CFR, Procyon,
  Vineflower); obfuscated bytecode often defeats any single one. Use a
  side-by-side compare script (`assets/decompile-compare.ps1` pattern).

### Phase 1 — Re-derive names
Follow `references/name-rederivation.md`. Output: a small mapping table from
**role** (e.g. "startup orchestrator", "state machine", "license interface",
"holder struct", "hard-stop exception") to the **current obfuscated name**.
This table is the only thing that changes between versions.

### Phase 2 — Build the agent
Use `references/agent-template.md` + `assets/BurpLicenseObserverAgent.template.java`.
Wire each re-derived name into a `type(named("..."))` + `transformX` with the
right `Advice` and **exact signature matchers** (`named(...).and(takesArguments(n))
.and(takesArgument(i, Type))`). Build with `assets/build-agent.ps1`.

### Phase 3 — Observe
Run with `assets/boot-licensed.ps1 -Observe` (injection off). Read the log: the
agent prints `ENTER/EXIT` with arg/return summaries and where exceptions are
thrown. Confirm hooks actually attach (look for `TRANSFORM <class>` lines — a
missing one means a matcher missed).

### Phase 4 — Diagnose the hard stop
Find the `EXIT ... thrown=<HardStopException>` chain back to its origin. The
common Burp failure: the holder struct's license field is **null** after forced
activation, so a downstream `licenseObj.someGetter()` NPEs → hard stop. Add a
read-only diagnostic advice that reflects the holder's license field. See
`references/build-run-diagnose.md`.

### Phase 5 — Optional synthetic-license boot
If the goal is full boot under instrumentation, inject a synthetic license
object (dynamic `Proxy` over the license interface) at the holder-factory exit.
Full technique, classloader reasoning, and value-mapping in
`references/synthetic-license-injection.md`. Keep it behind an explicit flag.

### Phase 6 — Document
Produce an enforcement-vs-instrumentation status map (which validation points
are hooked, which are dormant because they sit downstream of the boot path).

## Key invariants (carry across versions)

- The agent and a `-jar`-launched app share the **system classloader**, so
  inlined advice can reference both app classes and the agent's own helper
  classes (no `Boot-Class-Path` in the agent manifest).
- ByteBuddy **inlines** advice bodies into the target — referenced types must
  resolve in the *target's* loader; use the target object's own classloader for
  reflective `Class.forName`/`Proxy`.
- Mutating a method's return requires
  `@Advice.Return(readOnly = false, typing = Assigner.Typing.DYNAMIC)`.
- Always `suppress = Throwable.class` on advice so observation can't crash the host.

## Reference & asset files

| File | Contents |
|------|----------|
| `references/name-rederivation.md` | Stable anchors → obfuscated names; build-46522 Rosetta map |
| `references/agent-template.md` | ByteBuddy agent structure, advice patterns, signature matching |
| `references/synthetic-license-injection.md` | Synthetic `Proxy` license technique (deep dive) |
| `references/build-run-diagnose.md` | Build/run/read-log loop and diagnosis recipes |
| `assets/BurpLicenseObserverAgent.template.java` | Agent skeleton with placeholder name/signature map |
| `assets/build-agent.ps1` | Compile + package + premain smoke-test |
| `assets/boot-licensed.ps1` | Launch app with the agent (`-Observe` toggles injection) |
