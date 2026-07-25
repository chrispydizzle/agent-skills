// BurpLicenseObserverAgent.template.java
//
// Distilled ByteBuddy premain javaagent skeleton for tracing an obfuscated JVM
// app's license validation, with optional synthetic-license injection.
//
// Authorised, educational, defensive reverse-engineering only.
//
// HOW TO USE
//  1. Replace every <PLACEHOLDER> using your Phase-1 role->name table
//     (see references/name-rederivation.md).
//  2. Add one .type(named("...")).transform(...) per re-derived class.
//  3. Pin each method with named(...).and(takesArguments(n)).and(takesArgument(i,T)).
//  4. Build with assets/build-agent.ps1.
//
// The full reference implementation (Burp 46522) is the worked example; this
// template keeps only the reusable scaffolding.

import static net.bytebuddy.matcher.ElementMatchers.*;

import java.lang.instrument.Instrumentation;
import java.lang.reflect.Constructor;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.nio.file.StandardOpenOption;
import java.time.Instant;
import net.bytebuddy.agent.builder.AgentBuilder;
import net.bytebuddy.asm.Advice;
import net.bytebuddy.description.type.TypeDescription;
import net.bytebuddy.dynamic.DynamicType;
import net.bytebuddy.implementation.bytecode.assign.Assigner;
import net.bytebuddy.utility.JavaModule;
import java.security.ProtectionDomain;

public final class BurpLicenseObserverAgent {
    private BurpLicenseObserverAgent() {}

    // ---- placeholders (fill from role->name table) ----
    private static final String STATE_ENUM_FQN   = "net.portswigger.Ztb";   // stable-ish
    private static final String STATE_ACTIVATED  = "LICENSE_ACTIVATED";
    private static final String LICENSE_IFACE_FQN = "burp.<LicenseIface>";
    private static final String HOLDER_LICENSE_FIELD = "<licenseField>";    // public final field
    private static final String LICENSE_TYPE_ENUM_FQN = "burp.<TypeEnum>";  // has FULL/...

    public static void premain(String agentArgs, Instrumentation inst) {
        Log.init(agentArgs);
        Log.event("agent.premain java=" + System.getProperty("java.version"));

        new AgentBuilder.Default()
            .with(AgentBuilder.RedefinitionStrategy.DISABLED)
            .with(new AgentBuilder.Listener.Adapter() {
                @Override public void onTransformation(TypeDescription t, ClassLoader cl,
                        JavaModule m, boolean loaded, DynamicType dt) {
                    Log.event("TRANSFORM " + t.getName() + " loaded=" + loaded);
                }
                @Override public void onError(String tn, ClassLoader cl, JavaModule m,
                        boolean loaded, Throwable th) {
                    Log.event("TRANSFORM_ERROR " + tn + " " + th);
                }
            })
            .ignore(nameStartsWith("net.bytebuddy.")
                .or(nameStartsWith("BurpLicenseObserverAgent")))

            // --- one entry per re-derived class ---
            .type(named("<orchestrator>")).transform(BurpLicenseObserverAgent::transformOrchestrator)
            .type(named("<stateMachine>")).transform(BurpLicenseObserverAgent::transformStateMachine)
            .type(named("<holderFactory>")).transform(BurpLicenseObserverAgent::transformHolderFactory)
            // .type(named("<providerSelect>")).transform(...)
            // .type(named("<reflectVerifier>")).transform(...)
            // ... etc ...
            .installOn(inst);
    }

    // ---- transforms (pin signatures precisely) ----

    private static DynamicType.Builder<?> transformOrchestrator(DynamicType.Builder<?> b,
            TypeDescription t, ClassLoader cl, JavaModule m, ProtectionDomain pd) {
        return b
            .visit(Advice.to(VoidAdvice.class).on(named("<start>").and(takesArguments(0))))
            .visit(Advice.to(ReturnAdvice.class).on(named("<secondaryGate>").and(takesArguments(3))));
    }

    private static DynamicType.Builder<?> transformStateMachine(DynamicType.Builder<?> b,
            TypeDescription t, ClassLoader cl, JavaModule m, ProtectionDomain pd) {
        return b
            // force the no-arg state method to ACTIVATED:
            .visit(Advice.to(ForceStateAdvice.class).on(named("<stateMethod>").and(takesArguments(0))));
    }

    private static DynamicType.Builder<?> transformHolderFactory(DynamicType.Builder<?> b,
            TypeDescription t, ClassLoader cl, JavaModule m, ProtectionDomain pd) {
        return b
            .visit(Advice.to(ReturnAdvice.class).on(named("<make>").and(isStatic()).and(takesArguments(4))))
            .visit(Advice.to(HolderInjectAdvice.class).on(named("<make>").and(isStatic()).and(takesArguments(4))));
    }

    // ---- advice classes (bodies are INLINED into app methods: pure java.* only) ----

    public static class VoidAdvice {
        @Advice.OnMethodEnter(suppress = Throwable.class)
        public static long enter(@Advice.Origin("#t.#m") String origin,
                @Advice.AllArguments(readOnly = true) Object[] args) throws Exception {
            write("ENTER " + origin + " args=" + summarize(args)); return System.nanoTime();
        }
        @Advice.OnMethodExit(onThrowable = Throwable.class, suppress = Throwable.class)
        public static void exit(@Advice.Origin("#t.#m") String origin, @Advice.Enter long t0,
                @Advice.Thrown Throwable thrown) throws Exception {
            write("EXIT  " + origin + " ms=" + ms(t0) + " return=<void> thrown=" + tn(thrown));
        }
    }

    public static class ReturnAdvice {
        @Advice.OnMethodEnter(suppress = Throwable.class)
        public static long enter(@Advice.Origin("#t.#m") String origin,
                @Advice.AllArguments(readOnly = true) Object[] args) throws Exception {
            write("ENTER " + origin + " args=" + summarize(args)); return System.nanoTime();
        }
        @Advice.OnMethodExit(onThrowable = Throwable.class, suppress = Throwable.class)
        public static void exit(@Advice.Origin("#t.#m") String origin, @Advice.Enter long t0,
                @Advice.Return(readOnly = false, typing = Assigner.Typing.DYNAMIC) Object returned,
                @Advice.Thrown Throwable thrown) throws Exception {
            write("EXIT  " + origin + " ms=" + ms(t0)
                + " return=" + (returned == null ? "null" : returned.getClass().getName())
                + " thrown=" + tn(thrown));
        }
    }

    // Force a no-arg state method to return ACTIVATED.
    public static class ForceStateAdvice {
        @Advice.OnMethodExit(suppress = Throwable.class)
        public static void exit(@Advice.AllArguments Object[] args,
                @Advice.Return(readOnly = false) net.portswigger.Ztb returned) {
            if (args.length == 0) returned = net.portswigger.Ztb.LICENSE_ACTIVATED;
        }
    }

    // Optional: inject a synthetic license into a null holder field (flag-gated).
    public static class HolderInjectAdvice {
        @Advice.OnMethodExit(onThrowable = Throwable.class, suppress = Throwable.class)
        public static void exit(
                @Advice.Return(readOnly = false, typing = Assigner.Typing.DYNAMIC) Object returned,
                @Advice.Thrown Throwable thrown) throws Exception {
            if (thrown == null
                    && Boolean.parseBoolean(System.getProperty("burp.observer.synthlicense", "false"))) {
                Object r = SyntheticLicense.wrapHolder(returned);
                if (r != returned) returned = r;
            }
        }
    }

    public static class SyntheticLicense implements java.lang.reflect.InvocationHandler {
        private final ClassLoader loader;
        SyntheticLicense(ClassLoader loader) { this.loader = loader; }

        public static Object wrapHolder(Object holder) {
            if (holder == null) return null;
            try {
                ClassLoader cl = holder.getClass().getClassLoader();
                Class<?> iface = Class.forName(LICENSE_IFACE_FQN, false, cl);
                Field f = holder.getClass().getDeclaredField(HOLDER_LICENSE_FIELD);
                f.setAccessible(true);
                if (f.get(holder) != null) return holder;
                Object proxy = Proxy.newProxyInstance(cl, new Class<?>[]{ iface }, new SyntheticLicense(cl));
                Constructor<?> c = holder.getClass().getDeclaredConstructor(iface, boolean.class);
                c.setAccessible(true);
                Object out = c.newInstance(proxy, Boolean.TRUE);
                Log.event("SYNTH installed synthetic license into holder." + HOLDER_LICENSE_FIELD);
                return out;
            } catch (Throwable t) { Log.event("SYNTH failed: " + t); return holder; }
        }

        @Override public Object invoke(Object proxy, Method method, Object[] args) {
            String n = method.getName();
            Class<?> rt = method.getReturnType();
            // NOTE: map these names to YOUR license interface's getters.
            if (rt == boolean.class) return Boolean.FALSE;            // e.g. expiry-close -> not close
            if (rt == java.util.Date.class) return new java.util.Date(farFuture());
            if (rt == long.class) return Long.valueOf(farFuture());
            if (rt == int.class) return Integer.valueOf(-1);          // capability mask: all bits
            if (rt == String.class) return "Professional";
            if (rt.isEnum()) {                                        // e.g. type enum -> FULL
                Object full = enumConstant(LICENSE_TYPE_ENUM_FQN, "FULL");
                if (full != null && rt.isInstance(full)) return full;
            }
            if ("toString".equals(n)) return "SyntheticLicense";
            if ("hashCode".equals(n)) return Integer.valueOf(System.identityHashCode(proxy));
            if ("equals".equals(n)) return Boolean.valueOf(proxy == (args != null && args.length > 0 ? args[0] : null));
            return null;
        }

        private Object enumConstant(String fqcn, String name) {
            try {
                Class<?> t = Class.forName(fqcn, false, loader);
                Object[] cs = t.getEnumConstants();
                if (cs != null) for (Object v : cs) if (((Enum<?>) v).name().equals(name)) return v;
            } catch (Throwable ignored) {}
            return null;
        }
        private static long farFuture() {
            return System.currentTimeMillis() + 100L*365L*24L*60L*60L*1000L;
        }
    }

    // ---- tiny helpers usable from inlined advice (pure java.*) ----
    static void write(String msg) throws Exception {
        Files.writeString(Paths.get(System.getProperty("burp.observer.log")),
            Instant.now() + " " + msg + System.lineSeparator(),
            StandardCharsets.UTF_8, StandardOpenOption.CREATE, StandardOpenOption.APPEND);
    }
    static long ms(long t0) { return (System.nanoTime() - t0) / 1_000_000L; }
    static String tn(Throwable t) { return t == null ? "null" : t.getClass().getName(); }
    static String summarize(Object[] a) {
        if (a == null) return "[]";
        StringBuilder b = new StringBuilder("[");
        for (int i = 0; i < a.length; i++) {
            if (i > 0) b.append(", ");
            b.append(i).append('=').append(a[i] == null ? "null" : a[i].getClass().getName());
        }
        return b.append(']').toString();
    }

    // ---- logger created in premain (not inlined) ----
    static final class Log {
        private static final Object LOCK = new Object();
        private static java.nio.file.Path path;
        static void init(String agentArgs) {
            String p = System.getProperty("burp.observer.log");
            if (p == null && agentArgs != null && agentArgs.startsWith("log=")) p = agentArgs.substring(4);
            if (p == null) p = Paths.get(System.getProperty("java.io.tmpdir"), "observer.log").toString();
            path = Paths.get(p);
        }
        static void event(String msg) {
            synchronized (LOCK) {
                try {
                    Files.writeString(path, Instant.now() + " " + msg + System.lineSeparator(),
                        StandardCharsets.UTF_8, StandardOpenOption.CREATE, StandardOpenOption.APPEND);
                } catch (Exception ignored) {}
            }
        }
    }
}
