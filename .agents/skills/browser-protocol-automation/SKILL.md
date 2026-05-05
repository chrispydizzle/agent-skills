---
name: browser-protocol-automation
description: >
  Choose the right automation layer for browser and web workflows. Use when the
  user mentions Playwright, browser automation, debug-attachable browsers,
  Chrome/Edge remote debugging, CDP, WebSockets, API replay, record/playback,
  smart data entry, scraping, testing web apps, or says the UI script should
  instead use the API/protocol route. This skill forces an early decision
  between visible UI control, DOM automation, CDP inspection, WebSocket/API
  replay, and hybrid approaches.
---

# Browser Protocol Automation

Use this skill to avoid blindly reaching for Playwright when a lower or higher
automation layer would be more reliable.

## Layer decision

Choose the lowest reliable layer that satisfies the task:

| Layer | Use when | Avoid when |
|---|---|---|
| Visible UI / computer use | Need human-like interaction, unknown UI, visual verification | Stable DOM/API is available |
| DOM / Playwright | Need forms, clicks, screenshots, e2e tests, reliable selectors | App state is driven by hidden protocols |
| CDP / debug browser | Need cookies, network events, console logs, performance, live session inspection | Remote debugging is unavailable |
| WebSocket/API replay | Need speed, determinism, batch operations, or UI is flaky | Protocol is stateful/unknown and not yet mapped |
| Hybrid | Need UI for auth/setup, then API/protocol for scale | One layer alone is sufficient |

Start with exploration, then migrate down-layer once the protocol is known.

## Preflight

Before automating:

1. Identify the goal: extract, test, submit, monitor, or control.
2. Identify available access: logged-in browser, CDP port, cookies, API docs,
   HAR/network logs, screenshots, or credentials.
3. Preserve session state. Do not discard a user-provided logged-in browser.
4. Decide the first layer and the pivot condition.
5. Name what evidence will prove the layer is reliable.

## Pivot rules

Pivot away from Playwright/DOM when:

- The user points to WebSocket/API traffic as the real control plane
- Selectors are unstable but network messages are stable
- The task needs high-volume replay or monitoring
- The browser script only exists to trigger a known request
- The UI is too slow, flaky, or blocked by visual state

Pivot back toward UI when:

- Authentication, MFA, or anti-automation requires the real browser
- The protocol is encrypted, signed, or not safely reproducible
- Visual correctness is the actual deliverable

## Protocol mapping workflow

When inspecting network protocols:

1. Capture a minimal action in the UI.
2. Identify request, response, timing, headers, auth, cookies, and payload.
3. Replay safely with read-only or low-impact actions first.
4. Compare replay result against UI-observed result.
5. Document state dependencies and failure cases.

Do not turn a one-off captured request into an automation harness until replay
works across at least two cases or the limits are clearly documented.

## Output format

```markdown
## Automation Plan

**Chosen layer:** UI | DOM/Playwright | CDP | WebSocket/API | Hybrid
**Why this layer:** ...
**Session/access assumptions:** ...
**Pivot condition:** ...
**Validation:** ...
**Next implementation step:** ...
```

## Anti-patterns

- Continuing with Playwright after identifying a stable API route
- Replaying state-changing requests before understanding auth and side effects
- Losing the user's logged-in browser session
- Treating screenshots as proof that protocol automation works
- Writing a large framework before validating the smallest repeatable action
