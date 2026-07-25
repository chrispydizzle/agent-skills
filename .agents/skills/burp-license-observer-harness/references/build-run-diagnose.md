# Build / Run / Diagnose Loop

Fast iteration: edit agent → build → run → read log → adjust. Each cycle is
seconds, so prefer many small cycles over guessing.

## The loop

```
1. edit BurpLicenseObserverAgent.java   (add/adjust one hook)
2. .\build-agent.ps1 -NoSmokeTest        (compile + package)
3. .\boot-licensed.ps1 -Observe -Tail    (run; injection OFF for baseline)
4. read files\<observer>.log             (ENTER/EXIT/TRANSFORM/thrown)
5. repeat
```

Archive a known-good and known-bad log for before/after diffing
(e.g. `baseline-<date>.log` vs `success-<date>.log`).

## Reading the log

- `TRANSFORM <class> loaded=false` — hook attached. **Missing line = matcher
  missed** (wrong name/arity/static-ness). Fix the signature first.
- `ENTER <class>.<m> args=[...]` / `EXIT <class>.<m> ... return=... thrown=...`.
- Follow a `thrown=<HardStopException>` **up** the EXIT chain to the deepest
  method that first shows it — that is the origin gate.

## Diagnosing the classic null-license hard stop

Symptom: forced-activation works, but startup still aborts:
```
ENTER <stateMachine>.<stateMethod> → "returning activated"
EXIT  <holderFactory>.<make> return=<holderStruct> thrown=null
EXIT  <providerSelect>.<r>   thrown=<HardStop>          ← origin
EXIT  <orchestrator>.<gate>  return=false thrown=<HardStop>
EXIT  <orchestrator>.<start> thrown=<HardStop>          ← boot aborts
```

Add a **read-only diagnostic** advice on the holder-factory exit that reflects
the holder's license field:
```java
Field f = returned.getClass().getDeclaredField("<licenseField>");
f.setAccessible(true);
Object lic = f.get(returned);
log("DIAG " + origin + " <field>=" + (lic == null ? "null" : lic.getClass().getName()));
```
`<field>=null` confirms: the hard stop is a NPE on the license object, not a
signature/crypto failure. Proceed to synthetic injection
(`references/synthetic-license-injection.md`).

## Other diagnosis recipes

| Observation | Likely meaning | Next step |
|---|---|---|
| No `TRANSFORM` for a class | matcher missed / class never loaded | check name+signature; class may be downstream of an earlier abort |
| `thrown` at the verifier (`<reflectVerifier>.<m>`) | decode/signature failure | inspect inputs (hashed) — may need a real blob |
| Hard stop with non-null license field | a different gate (revocation/expiry/second gate) | hook that gate; inspect its boolean result |
| Hooks for revocation/expiry never fire | they sit downstream of the boot abort | clear the abort first (Phase 5), then they light up |

## Run flags (JVM)

Match the app's launcher. Typical set:
```
-Xmx2g
-Dnet.bytebuddy.experimental=true
-Dburp.observer.log=<...>\files\<observer>.log
-Dburp.observer.synthlicense=true|false
--enable-native-access=ALL-UNNAMED
--add-opens=java.base/java.lang=ALL-UNNAMED
--add-opens=java.desktop/javax.swing=ALL-UNNAMED
--add-opens=java.desktop/java.awt=ALL-UNNAMED
--add-opens=java.base/javax.crypto=ALL-UNNAMED
--add-opens=jdk.crypto.cryptoki/sun.security.pkcs11=ALL-UNNAMED
-javaagent:<...>\agent\dist\<agent>.jar
-jar <app>.jar
```

## Tips

- Use the app's **own** bundled JRE for runtime; a modern JDK for `javac`.
- `sun.misc.Unsafe` warnings from ByteBuddy are benign.
- The license holder factory runs **once per boot**; the synthetic proxy then
  persists for the process as the active license.
- Keep `files/src` (decompiled) read-only — it is evidence, not build input.
