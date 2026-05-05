# Core Methodology

Use this reference when the case needs disciplined reasoning beyond straightforward error reading.

## Evidence hierarchy

Rank evidence roughly in this order:

1. Reproducible state transitions with consistent IDs
2. Primary crash artifacts and structured security events
3. Independent corroboration across multiple sources
4. Plain-text application logs
5. Human summaries, dashboards, or alerts derived from logs

Prefer direct evidence over narrated evidence.

## Confidence model

Every major claim should be labeled as one of:

- `proven`: directly supported by logs or artifacts
- `strongly supported`: multiple clues converge, but one key link is inferred
- `plausible`: fits the evidence, but rivals remain
- `speculative`: useful lead only

Do not mix these together casually.

## Sherlock questions

Ask these in hard cases:

1. What is the first event that required the later failure to become possible?
2. What should have logged if the obvious explanation were true?
3. Which subsystem had the earliest chance to know the truth?
4. Which line looks important only because it was the first one a human noticed?
5. What changed right before the wording changed?
6. Which actor is speaking here: caller, callee, wrapper, watchdog, or recovery logic?
7. Is the system describing a failure, or only describing how it noticed the failure?
8. Which clue would disappear if the attacker, bug, or operator wanted to mislead us?

## High-value clue families

### 1. Direct admissions

Examples:

- explicit permission denials
- stack traces with class and method names
- watchdog kill messages
- OOM, SIGSEGV, SIGABRT, or refcount warnings

These are useful, but they still need context. A crash can be downstream from the real cause.

### 2. Privilege oracles

Look for:

- `permission denied`
- `not authorized`
- `operation not permitted`
- `security exception`
- `avc: denied`
- `unknown transaction`

These often reveal:

- a reachable surface
- the identity of the guardrail that blocked it
- which privilege would have changed the outcome

### 3. State leakage

Look for accidental disclosure of:

- tokens or session IDs
- internal hostnames, ports, or URLs
- build IDs and feature flags
- filesystem paths
- package names and component names
- device IDs, account IDs, or network identifiers

### 4. Behavioral leakage

The system may leak more through behavior than content:

- retries reveal a stable oracle
- backoff reveals timing windows
- fallback reveals a weaker code path
- partial success followed by denial suggests work happened before the guardrail

### 5. Negative-space clues

Senior engineers often miss absence-based clues:

- missing "startup complete" after a restart line
- request accepted with no matching completion
- crash without a restart
- auth failure without a preceding auth attempt in the expected source
- version banner present everywhere except the one component now failing

Absence is only useful when you know a line should normally exist.

## Subtle patterns worth checking

### Wording drift

If the same apparent error changes wording, punctuation, logger name, or severity level, assume the code path or build changed until proven otherwise.

### Cardinality cliffs

Sharp drops or spikes in unique users, PIDs, request IDs, or error categories can indicate:

- log filtering changed
- one service died and traffic shifted
- a parser started collapsing distinct events into one template
- deliberate flooding or suppression

### Thread or process identity drift

If the same narrative moves between different PIDs, TIDs, or UIDs, ask whether you are seeing retries, worker failover, or a confused deputy path.

### Last-known-good boundaries

The line right before the first failure is often more informative than the first failure itself.

### Error-oracle shaping

Repeated malformed requests that produce slightly different errors may be probing for internal state, version, or privilege differences.

## Hypothesis testing discipline

For each major theory, fill this mental table:

| Theory | Supporting clues | Contradicting clues | Missing evidence | Confidence |
|---|---|---|---|---|

If one theory has no contradictions only because the logs are thin, say that explicitly.

## Security-specific checks

Always test for:

- secret or PII exposure
- privilege-boundary clues
- crash accelerants such as paths, versions, maps, or addresses
- evidence that attacker-controlled input is logged verbatim
- weak storage or export paths for sensitive diagnostics

## Report-writing guidance

Good output is compact but evidence-rich:

- explain why each clue matters
- separate what the logs say from what you infer
- call out dead ends clearly, not just leads
- end with the next two or three highest-value checks
