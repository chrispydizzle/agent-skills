# Synthetic License Injection (Deep Dive)

Goal: let the app finish startup under instrumentation when forcing the state
enum to ACTIVATED is **not enough** because the licensing path leaves the
license *object* null and a downstream getter NPEs into the hard-stop exception.

> Authorised analysis only. Gate behind an explicit flag; off by default.

## Why state-forcing is insufficient

Forcing `[stateMachine].<stateMethod>()` → `LICENSE_ACTIVATED` sets the *state*,
but the holder struct's license field is populated elsewhere (by a gate listener
that consumes an activated event carrying a decoded license object). With no real
decode, that field stays null:

```java
// [providerSelect].<r>(...)            (the NPE site)
holder = [holderFactory].<make>(...);   // returns holderStruct with licenseField == null
holder.<licenseField>.<dateGetter>();   // NPE -> caught -> throw [hardStop]
```

```java
// [holderStruct]
public final <LicenseIface> <licenseField>;   // final → can't mutate in place
public final boolean <flag>;
<HolderStruct>(<LicenseIface> lic, boolean f) { ... }
```

## Fix: rebuild the holder with a synthetic license

Because the license field is `final`, construct a **new** holder via its
package-private constructor (reflection) whose license field is a dynamic
`Proxy` over the license interface.

### Why a Proxy (not the real impl)
The real license class needs a multi-arg package-private constructor plus valid
sub-objects (type enum, edition, crypto helper). A `java.lang.reflect.Proxy`
over the **interface** implements only the declared methods and returns plausible
values — no internal graph to fabricate.

### Classloader reasoning (critical)
- ByteBuddy **inlines** advice into the app class, so referenced types resolve in
  the *app's* loader.
- An agent JAR with **no `Boot-Class-Path`** is appended to the **system class
  path**; an app launched via `-jar` is also on the system loader → they share a
  loader. Hence inlined advice can reference the agent's own helper class.
- Always derive the loader from the holder object itself:
  `holder.getClass().getClassLoader()`, and build the `Proxy` / resolve interface
  and enums with that loader.
- Make the helper a `public static` nested class so the app package can reference
  it across packages.

## Implementation

### Hook: mutate the holder-factory return
```java
@Advice.OnMethodExit(onThrowable = Throwable.class, suppress = Throwable.class)
public static void exit(
        @Advice.Return(readOnly = false, typing = Assigner.Typing.DYNAMIC) Object returned,
        @Advice.Thrown Throwable thrown) {
    boolean fieldNull = /* reflect holder.<licenseField> == null */;
    if (fieldNull && thrown == null
            && Boolean.parseBoolean(System.getProperty("burp.observer.synthlicense", "false"))) {
        Object replacement = Agent.SyntheticLicense.wrapHolder(returned);
        if (replacement != returned) returned = replacement;   // swap return value
    }
}
```

### wrapHolder: rebuild via constructor
```java
public static Object wrapHolder(Object holder) {
    if (holder == null) return null;
    try {
        ClassLoader cl = holder.getClass().getClassLoader();
        Class<?> ifaceClass = Class.forName("<LicenseIface FQN>", false, cl);
        Field f = holder.getClass().getDeclaredField("<licenseField>");
        f.setAccessible(true);
        if (f.get(holder) != null) return holder;             // already populated
        Object proxy = Proxy.newProxyInstance(cl,
                new Class<?>[]{ ifaceClass }, new SyntheticLicense(cl));
        Constructor<?> c = holder.getClass()
                .getDeclaredConstructor(ifaceClass, boolean.class);
        c.setAccessible(true);
        return c.newInstance(proxy, Boolean.TRUE);
    } catch (Throwable t) {
        Log.event("SYNTH failed: " + t);
        return holder;                                         // fail-safe: original
    }
}
```

### InvocationHandler: typed "valid full license" answers
Map each interface method to a sensible value; fall back by return type.

| Method kind | Return |
|---|---|
| expiry-close boolean `<m>(clock)` | `false` (not close) |
| expiry `Date` getter | far-future `Date` |
| expiry `long` getter | `now + ~100y` |
| id/key/type `String` getters | fixed tokens / `"Professional"` |
| capability mask `int` | `-1` (all bits) |
| seats `int` | `1` |
| license-type enum getter | real enum constant (e.g. `FULL`) resolved reflectively |
| edition/object getter (a class) | `null` (best effort) |
| `toString/hashCode/equals` | sensible defaults |
| else by return type | `boolean→false`, `int→0`, `long→farFuture`, ref→`null` |

```java
private Object enumConstant(String fqcn, String name) {
    Class<?> t = Class.forName(fqcn, false, loader);
    for (Object v : t.getEnumConstants())
        if (((Enum<?>) v).name().equals(name)) return v;
    return null;
}
```

## Verification

Run with `-Dburp.observer.synthlicense=true`. Success markers in the log:
- `SYNTH installed synthetic ... into <holder>.<field>`
- holder-factory `EXIT ... action=synthetic-injected`
- the NPE site now `thrown=null`; the orchestrator's gate returns success;
  the start method exits `thrown=null`; the state machine later returns the
  `$ProxyNN` as the active license.

## Limitations / failure modes

- Hooks on the **real** license impl, revocation, and API-gate listener go
  **dormant** — the proxy bypasses them; they only fire with a real decode.
- Any consumer dereferencing a getter you mapped to `null` (e.g. edition) NPEs;
  extend the handler if a feature path hits it.
- Capability mask `-1` assumes "all bits enabled"; a bit-specific feature could
  misbehave.
- `wrapHolder` is fail-safe: on any error it returns the original (reproducing
  the baseline hard stop rather than crashing differently).
