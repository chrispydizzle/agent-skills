# Correlation and Deception

Use this reference when the case spans multiple log sources or when the data may be incomplete, manipulated, replayed, or misleading.

## Build a super timeline

Join sources using as many stable pivots as possible:

- trace ID or request ID
- PID, TID, UID, package name, service name
- socket tuple, peer address, port
- binder transaction code or service call outcome
- crash signature, fault address, abort message
- boot ID, build ID, restart count

Do not trust timestamps alone.

## Time-handling rules

1. Identify time zone, monotonic time, wall-clock time, and boot-relative time.
2. Mark reboot boundaries.
3. Estimate clock skew if one source consistently leads or lags another.
4. When uncertain, anchor on causal order instead of exact timestamps.

## Common correlation traps

- same request retried under a new ID
- PID reuse after fast process churn
- one subsystem logs local time while another logs UTC
- parser merges distinct errors into one template
- log rotation slices the incident in half

## Tampering and deception patterns

Watch for:

- control characters, embedded newlines, or broken schemas
- impossible state sequences
- abrupt format changes around the incident window
- duplicate narratives with slightly shifted timestamps
- sudden drops in expected log volume
- sudden floods of low-value noise around a high-value event
- request-side events with no server-side counterpart
- completion lines with no matching admission or start

These do not prove malicious tampering by themselves. They do prove the narrative is less trustworthy.

## Hidden pivot indicators

Some of the most valuable findings are not the headline errors. Look for:

- credentials and bearer tokens
- internal-only endpoints
- feature flags or experiments
- fallback to weaker storage, transport, or parsing mode
- copied crash or kernel diagnostics in weaker locations
- user-controlled strings that survive into logs without neutralization

## Logging pipeline as an attack surface

If attacker-controlled data is logged verbatim, ask whether the logging pipeline itself could be abused through:

- log forging or parser confusion
- lookup or interpolation behavior
- downstream alerting rules
- metrics pollution or anomaly masking

This matters even when the application bug itself looks minor.

## Contradiction checklist

Use this list when the story feels "almost right":

- Did the component claim success after a hard denial elsewhere?
- Did a watchdog kill a process that supposedly finished cleanly?
- Did a client log timeout while the server logged no request at all?
- Did security logs show blocking, but the artifact later appeared anyway?
- Did the failure happen before the preconditions were supposedly created?
- Did the same user or service occupy mutually exclusive states at the same time?

## Recommended output for messy cases

When deception, tampering, or inconsistency is present, add two explicit subsections to your report:

```markdown
## Narrative Reliability
- Which sources appear trustworthy
- Which sources may be incomplete or manipulated
- What that uncertainty changes

## Best Reconstruction
- The most defensible sequence despite gaps
- What would most reduce uncertainty next
```

## High-signal next checks

When you need follow-up evidence, prioritize:

1. structured security events
2. primary crash artifacts
3. source-system originals rather than forwarded copies
4. metadata about rotation, restart, or collection gaps
5. adjacent sources that should contain the missing counterpart event
