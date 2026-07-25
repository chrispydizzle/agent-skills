# Agent Template: Structure, Advice, Signature Matching

A ByteBuddy `premain` javaagent that logs ENTER/EXIT (args/returns/throws) for
the licensing classes, and optionally mutates returns. Fill the placeholders
from your Phase-1 role→name table.

## premain skeleton

```java
public static void premain(String agentArgs, Instrumentation inst) {
    Log.init(agentArgs);
    new AgentBuilder.Default()
        .with(AgentBuilder.RedefinitionStrategy.DISABLED)
        .with(new AgentBuilder.Listener.Adapter() {        // log TRANSFORM / errors
            public void onTransformation(TypeDescription t, ClassLoader cl,
                    JavaModule m, boolean loaded, DynamicType dt) {
                Log.event("TRANSFORM " + t.getName() + " loaded=" + loaded);
            }
            public void onError(String tn, ClassLoader cl, JavaModule m,
                    boolean loaded, Throwable th) {
                Log.event("TRANSFORM_ERROR " + tn + " " + th);
            }
        })
        .ignore(nameStartsWith("net.bytebuddy.")
            .or(nameStartsWith("BurpLicenseObserverAgent")))
        .type(named("<orchestrator>")).transform(Agent::transformOrchestrator)
        .type(named("<stateMachine>")).transform(Agent::transformStateMachine)
        .type(named("<holderFactory>")).transform(Agent::transformHolderFactory)
        // ... one .type/.transform per re-derived class ...
        .installOn(inst);
}
```

Run with: `-Dnet.bytebuddy.experimental=true` (newer JDKs) and the app's
`--add-opens` flags. The `TRANSFORM <class>` log lines confirm a hook attached;
**absence means the matcher missed** — fix the signature.

## Signature matching (the part that breaks on update)

Obfuscated overloads differ only by arity/types. Always pin precisely:

```java
named("Zs")
    .and(isStatic())                       // if static
    .and(takesArguments(4))                // exact arity
    .and(takesArgument(0, String.class))   // disambiguate overloads
```

- Disambiguate same-name overloads (e.g. a no-arg init vs a 3-arg gate) by
  `takesArguments(n)` and `takesArgument(i, T)`.
- Primitive types use `int.class`, `boolean.class`, etc.
- App types use `named("burp.Xxx")` is for the *class* matcher; for argument
  types you can match by `String.class`, `int.class`, or skip type and rely on
  arity when the app type is itself obfuscated.

## Three reusable advice classes

All write a single log line via `java.nio.file.Files.writeString(...
System.getProperty("burp.observer.log") ...)`. Keep advice bodies **pure
java.\*** + reflection (they are inlined into app classes).

### VoidAdvice — for `void` methods
```java
public static class VoidAdvice {
    @Advice.OnMethodEnter(suppress = Throwable.class)
    public static long enter(@Advice.Origin("#t.#m") String origin,
            @Advice.AllArguments(readOnly = true) Object[] args) { /* log ENTER */ return System.nanoTime(); }
    @Advice.OnMethodExit(onThrowable = Throwable.class, suppress = Throwable.class)
    public static void exit(@Advice.Origin("#t.#m") String origin,
            @Advice.Enter long t0, @Advice.Thrown Throwable thrown) { /* log EXIT void */ }
}
```

### ReturnAdvice — for value-returning methods (logs + summarizes return)
```java
public static class ReturnAdvice {
    @Advice.OnMethodEnter(suppress = Throwable.class)
    public static long enter(@Advice.Origin("#t.#m") String origin,
            @Advice.AllArguments(readOnly = true) Object[] args) { /* log ENTER */ return System.nanoTime(); }
    @Advice.OnMethodExit(onThrowable = Throwable.class, suppress = Throwable.class)
    public static void exit(@Advice.Origin("#t.#m") String origin, @Advice.Enter long t0,
            @Advice.Return(readOnly = false, typing = Assigner.Typing.DYNAMIC) Object returned,
            @Advice.Thrown Throwable thrown) { /* log EXIT return/thrown; may mutate returned */ }
}
```

### ForceEnumAdvice — force a state-enum return (e.g. → ACTIVATED)
```java
@Advice.OnMethodExit(suppress = Throwable.class)
public static void exit(@Advice.AllArguments Object[] args,
        @Advice.Return(readOnly = false) net.portswigger.Ztb returned) {
    if (args.length == 0) returned = net.portswigger.Ztb.LICENSE_ACTIVATED;
}
```
> Referencing `net.portswigger.Ztb` from inlined advice works because it
> resolves in the app's loader. Use the app's real state-enum FQN.

## Argument/return summarization (safety + signal)

- Hash long strings (`sha256` first 6 bytes) instead of logging secrets/license
  blobs verbatim; print small safe tokens (`[A-Z0-9_./:-]{≤48}`) directly.
- Redact URLs to scheme+host+path.
- For `Object[]` that looks like decoded license fields
  (`[String,String,Long,Integer,...]`), label `licenseId/contact/expiry/
  capabilityMask/type/seats`.
- For a license-interface instance, reflectively call its getters to summarize
  `License{id,contact,expiry,type,...}`.

## Logging helper

A `Log` class with a synchronized `event(String)` appending to
`System.getProperty("burp.observer.log")`, created in `premain`. Advice bodies
write directly to the same path (they can't call agent helpers reliably when
inlined, so they inline the file write).

## Build

`assets/build-agent.ps1`: compiles the single source against
`<app>.jar` + `byte-buddy.jar`, packages with a manifest
(`Premain-Class`, `Can-Retransform-Classes: true`, `Class-Path: byte-buddy.jar`,
**no** `Boot-Class-Path`), and runs a `-version` premain smoke test.
