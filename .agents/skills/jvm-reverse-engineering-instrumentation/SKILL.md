---
name: jvm-reverse-engineering-instrumentation
description: >
  Use for authorized JVM reverse engineering, dynamic analysis, Java agents, and
  Byte Buddy/java.lang.instrument troubleshooting. Use this skill when class
  transforms are reported but advice logs do not fire, when helper classes are
  invisible to the target class loader, when debugging bootstrap/system-loader
  injection, constructor advice, retransformation, silent hook failures, or Java
  version compatibility flags.
---

# JVM Reverse-Engineering Instrumentation

**Created by Posad and GitHub Copilot.**

Reusable methodology for authorized JVM dynamic analysis and Java-agent
instrumentation, especially when Byte Buddy transforms appear to succeed but
hook bodies are silent.

**Licence:** This skill is released under the MIT License. You are free to use,
share, and adapt it with attribution and without warranty.

**Feedback & Support:** Capture methodology issues as task-observer
observations so the skill can be improved through real-world use.

## When this skill helps

- A Java agent reports matched or transformed classes, but `Advice` logging does
  not appear.
- Advice calls an agent helper or nested class and the hook becomes silent.
- The target has multiple class loaders, plugin loaders, application servers,
  shaded dependencies, or bootstrap-loaded classes.
- Byte Buddy or ASM fails on a new Java release or class-file version.
- Constructor instrumentation works differently from normal method advice.
- The task needs a repeatable dynamic-analysis checklist rather than one-off
  instrumentation guesses.

## Static decompilation before instrumentation

Before instrumenting obfuscated or control-flow-flattened bytecode, recover
readable source — but treat any single decompiler's output as provisional.
Decompilers are heuristic and disagree on obfuscated code; none is authoritative.

- Decompile each class of interest with at least two independent decompilers
  (for example CFR, Procyon, and a Fernflower successor such as Vineflower),
  then diff the outputs. The cost is one extra command; the payoff is not
  committing unstructurable output as canonical source.
- Prefer the output with zero structural-failure markers. One tool may leave
  `** GOTO` blocks, `v1`-style placeholders, or invalid Java where another
  reconstructs the real control flow cleanly.
- When scoring decompiler confidence, match BOTH failure shapes:
  - **Soft warnings** — graceful degradation (for example "Unable to fully
    structure code", "Could not load").
  - **Hard failures** — exception banners plus a raw bytecode dump (for example
    `FF:`, `VF:`, "Couldn't be decompiled", "parsing failure").
  A heuristic that models only one mode produces false confidence: a class that
  completely failed in one tool can still report a clean warning count.
- A clean summary count is necessary but not sufficient. Always eyeball the
  output files for the worst-performing tool before trusting the recovered
  source.

## Core model: two-layer validation

Treat instrumentation as two separate questions:

1. **Did transformation happen?** Prove the matcher found the class and Byte
   Buddy attempted or completed transformation.
2. **Did the hook body execute?** Prove the injected advice reached runtime and
   can perform its logging without class-loader or verifier failures.

Transformation success does not prove advice execution. A class can transform
successfully while the advice body fails because referenced helper types are not
visible to the instrumented class loader, bytecode is invalid for that join
point, or runtime compatibility flags are missing.

## First-pass observer pattern

Start with the smallest observer that can prove execution:

1. Log transform events with an `AgentBuilder.Listener` or equivalent.
2. In the first advice body, use only JDK classes that the target loader can
   resolve, such as `System.err`, `Thread.currentThread()`, strings, primitive
   values, and basic stack traces.
3. Avoid calling agent helper classes, nested classes, logging frameworks, or
   shaded dependencies from inlined advice until helper visibility is solved.
4. Record method entry before collecting arguments or return values.
5. Add richer capture one step at a time, keeping the last known-good observer
   available as a rollback point.

If the JDK-only observer fires, the transform and advice path are sound; the
next problem is helper visibility, argument handling, or side effects. If it
does not fire, focus on matchers, retransformation, module access, class loading
timing, ignored types, or verifier errors.

## Helper visibility safeguards

Byte Buddy can inline advice bytecode, but referenced types still need to be
resolvable where the instrumented class runs. Before advice calls helper code:

- Identify the target class loader: bootstrap, platform, system/application,
  plugin, webapp, child-first, or custom.
- Decide where helper classes must live: avoid helpers, inject into bootstrap,
  append to the system loader, or install into each relevant application loader.
- Keep helper APIs small and stable. Passing complex target objects into helpers
  can create linkage errors or accidental retention.
- Treat silent hooks as potential linkage or class-loader failures until a
  JDK-only observer disproves that path.
- Surface errors explicitly through transform listeners and uncaught diagnostic
  logging; do not rely on broad catches or success-shaped fallbacks.

## Constructor and lifecycle cautions

Constructor advice is not equivalent to normal method advice. If constructor
instrumentation fails:

- First prove instrumentation on a normal method of the same class.
- Avoid `onThrowable` constructor exit advice unless the Byte Buddy version and
  target bytecode support it; constructor exception paths are more constrained.
- Prefer entry logging or post-construction methods for initial reconnaissance.
- Watch for class initialization timing: logging frameworks and agent helpers may
  not be safe during early bootstrap or static initialization.

## Java version compatibility

When running on a bleeding-edge Java version:

- Prefer a Byte Buddy release that explicitly supports the target class-file
  version.
- If the release notes require it, add compatibility flags such as
  `-Dnet.bytebuddy.experimental=true` for unsupported or newly released Java
  versions.
- Capture the Java version, class-file version, Byte Buddy version, module flags,
  and agent JVM arguments in the report.
- Treat compatibility flags as diagnostics, not a substitute for upgrading the
  instrumentation library.

## Troubleshooting matrix

| Symptom | Likely cause | Next check |
| --- | --- | --- |
| Transform listener reports success, but no method logs | Advice body fails or never executes | Replace advice body with JDK-only `System.err` logging |
| JDK-only advice fires, helper-based advice is silent | Helper class not visible to target loader | Inject helper into the right loader or keep advice helper-free |
| No transform events for expected classes | Matcher, ignored types, load timing, or retransformation gap | Log discovery, loaded-type names, ignored callbacks, and retransformation support |
| Constructor advice transform errors | Constructor bytecode constraints | Test a normal method first; remove `onThrowable` constructor advice |
| Unsupported class-file version | Byte Buddy/ASM too old for Java runtime | Upgrade Byte Buddy or use documented experimental flag |
| Logs disappear during early startup | Logging dependency unavailable or class initialization side effect | Use `System.err` and delay richer logging until runtime is stable |
| Decompiled source has `** GOTO`/placeholder artifacts or won't compile | A single decompiler failed to structure obfuscated control flow | Re-decompile with 2+ independent tools and diff; adopt the zero-failure-marker output |
| Decompiler summary reports 0 warnings but the output is unusable | Quality heuristic missed hard-failure/exception banners | Match hard-failure markers (`FF:`, `VF:`, "parsing failure") and eyeball the worst tool's files |

## Report structure

For troubleshooting output, use this compact structure:

1. **Scope and authorization:** What is being analyzed and why it is authorized.
2. **Runtime facts:** Java version, Byte Buddy version, JVM flags, module flags,
   target launch mode, and class-loader notes.
3. **Transform evidence:** Matchers, listener output, transformed classes, and
   any ignored or failed types.
4. **Advice execution evidence:** Whether JDK-only advice fired, where it fired,
   and what changed when helpers were introduced.
5. **Class-loader plan:** Helper-free, bootstrap injection, system-loader append,
   or per-loader injection, with rationale.
6. **Next experiment:** One narrow change that distinguishes between remaining
   hypotheses.

## Ship gate

- [ ] Obfuscated classes were cross-decompiled with 2+ tools and the canonical
      source is the corroborated, zero-failure-marker output.
- [ ] Transform success and advice execution are validated separately.
- [ ] First-pass advice uses JDK-only logging before helper calls.
- [ ] Helper visibility strategy is explicit before helper-based advice ships.
- [ ] Constructor advice constraints are checked before using exit or throwable
      handling on constructors.
- [ ] Java and Byte Buddy compatibility facts are captured.
- [ ] The final recommendation is a narrow next experiment, not a speculative
      rewrite.
