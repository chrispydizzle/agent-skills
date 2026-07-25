# Name Re-derivation: Stable Anchors → Obfuscated Names

Obfuscation renames symbols but cannot rename the things below. Match these to
recover the current build's obfuscated names. Output a role→name table.

## Stable anchors (do not change across builds)

| Anchor (stable) | How to find it | Yields (role) |
|---|---|---|
| `Main-Class` in `META-INF/MANIFEST.MF` | read manifest | **entry point** (`burp.StartBurp`) |
| Non-obfuscated state enum `net.portswigger.*` with constants `UNLICENSED`, `LICENSE_ACTIVATED`, `LICENSE_REQUIRES_ACTIVATION`, `LICENSE_EXPIRED`, `LICENSE_ACTIVATION_FAILED`, `WRONG_EXECUTION_MODE` | grep decompiled tree for `LICENSE_ACTIVATED` | **state enum** (`Ztb`) |
| Channel/origin enum `REST_API`, `WIZARD`, `HEADLESS_WIZARD`, `ROLLER` | grep `HEADLESS_WIZARD` | **update channel enum** |
| Activation URL `portswigger.net/activate/Activate.ashx`, header `application/x-www-form-urlencoded`, body prefix `m=` | string-decode reflective constants / grep | **transport class** + **crypto facade** |
| `java.util.prefs.Preferences` usage | grep `Preferences` | **persistence class** |
| The single exception thrown to abort `main` and mapped to an INVALID_LICENSE exit | trace `main`'s catch | **hard-stop exception** |
| Interface with `Date <m>()`, `boolean <m>(<clock>)`, several `String` getters, a `long` expiry, an enum getter | structural grep | **license interface** (`Zkql`) |
| Class with `public final <licenseIface> <field>` + a boolean | grep `public final` holders | **holder struct** (`Zf8j`) |
| Enum with constants `FULL`, `TRIAL`, `TRAINING` and an `int expiryCloseTimeInDays` | grep `TRAINING` / `expiryCloseTimeInDays` | **license-type enum** (`Zpo1`) |

## Trace skeleton (roles, version-independent)

```
[entry].main
  └─ [orchestrator].<start>()              // builds facades, runs gates
       ├─ [stateMachine] ctor → <init>     // reads persisted license
       │     └─ reads prefs via [persistence]
       │     └─ decode/verify via [cryptoFacade] → [reflectVerifier]
       │     └─ revocation check via [revocationData]
       ├─ [orchestrator].<secondaryGate>(...)   // expiry-close + confirm
       │     └─ [holderFactory].<make>(...) → [holderStruct]
       │           └─ holder.<licenseField>.<dateGetter>()   // NPE site if null
       └─ [orchestrator].<post>() → may throw [hardStop]
```

## How to walk it

1. Start at `[entry].main`; find the orchestrator it constructs and the start
   method it calls.
2. In the orchestrator, find the method that builds the state machine and the
   **secondary gate** (the one that calls the holder factory and dereferences
   the license field).
3. In the state machine, find: the method that returns the **state enum**
   (forceable to ACTIVATED), the persisted-read method, the decode method
   delegating to the reflective verifier, and the revocation call.
4. Identify the **holder factory** (often a static method returning the holder
   struct) and the line that calls `holder.<licenseField>.<getter>()`.

## Build-46522 Rosetta map (worked example)

Use as a pattern, **not** as literal names for other builds.

| Role | 46522 name | Signature / note |
|---|---|---|
| entry point | `burp.StartBurp` | `main` |
| orchestrator | `Zvob` | `Zh()` start; `ZM(3)` secondary gate; `Zn()` post |
| state machine | `Zpq0` (impl `Zo1e`) | `ZZ()`→state; `ZO(String,..)` validate; `Zm(Exception,Zfvu,String)` map; `Zt(Zkql)`, `ZG(Zfvu)` |
| crypto facade | `Zj25` | `Zn(..)` decode, `ZS(5)` URL conn, `ZL(..)` verify |
| reflective verifier | `Zwfq` | `ZM(String,int)`, `ZW(String)`, `ZO(String)` (static) |
| transport | `Zozb` | `Zi(2)`, `Zz(6)` |
| TLS factory | `Zxfx` | `Zf(boolean)` |
| persistence | `Zf69` | `ZE/ZA/ZG/Ze/Zd` (static) |
| revocation data | `Zb1g` | `ZD(String)` static boolean |
| field→object map | `Zobs` | `ZI(String,Object[])` |
| license interface | `Zkql` | `ZB():Date`, `ZT(Zhlw):boolean`, `ZA/ZV/Zz/Zn/Zu:String`, `ZD:long`, `Zq/Zg:int`, `ZW:Zpo1`, `Ze:Zbdv` |
| license impls | `Zbqo` (full), `Zxoe` (sentinel) | implement `Zkql` |
| holder struct | `Zf8j` | `public final Zkql ZS; public final boolean Zz;` |
| holder factory | `Zk6d` | `Zs(stateMachine, gate, .., ..)` static → `Zf8j` |
| provider select | `Zxdp` | `Zr(5)` builds gate, calls `Zk6d.Zs`, derefs `zs.ZS.ZB()` (NPE site) |
| wizard gate / listener | `Zwcm` / `Zh4n` | `Zh4n.ZO(Zhhl)` sets license field on `LICENSE_ACTIVATED` |
| API gate / listener | `Zpjx` / `Zdf7` | `Zdf7.ZO(Zhhl)` |
| hard-stop exception | `Zvoa` | thrown to abort `main` |
| event object | `Zhhl` | fields: state `ZJ`, license `Zt`, channel `ZQ` |
| license-type enum | `Zpo1` | `FULL/TRIAL/TRAINING`, `int expiryCloseTimeInDays` |
| clock arg | `Zhlw` | passed to `Zkql.ZT` |

## Validation tip

Confirm a mapping by hooking it observe-only and checking the `ENTER/EXIT`
arg/return types in the log match the expected roles (e.g. the state-machine
method returns the state enum; the holder factory returns the holder struct).
