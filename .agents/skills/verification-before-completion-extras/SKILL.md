---
name: verification-before-completion-extras
description: >
  Additional verification guidance for verification-before-completion. Use when
  build failures mention generated framework output, deleted routes or modules,
  stale validators, Next.js build artifacts, generated type files, or other
  cleanup-sensitive validation failures before declaring a task blocked.
---

# Verification Before Completion Extras

Open-source-style overlay extending `verification-before-completion` with
generated-artifact triage.

## Generated artifact triage

When a build or typecheck error points at generated framework output, stale
validators, or deleted route/module references:

1. Do not immediately change source code to satisfy generated stale files.
2. Remove the framework build directory or generated output cache appropriate to
   the project.
3. Rerun the same validation command once.
4. Classify the failure only after the clean rerun.

If the clean rerun passes, report the original failure as stale generated state.
If it still fails, continue normal debugging with the clean result.

## Anti-patterns

- Treating generated route/type files as authoritative when they reference a
  module or route that no longer exists.
- Declaring a task blocked before one clean rebuild when the error originates
  from generated output.
- Making source changes to appease stale build artifacts.
