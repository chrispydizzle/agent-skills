---
name: systematic-debugging-extras
description: >
  Additional launcher and worker validation guidance for systematic-debugging.
  Use when debugging launchers, shell wrappers, child processes, background
  workers, startup scripts, dry-run checks, delayed crashes, service lifecycle
  issues, or argument forwarding across process boundaries.
---

# Systematic Debugging Extras

Open-source-style overlay extending `systematic-debugging` for launcher and
background-worker validation.

## Child-process boundary validation

Dry-run parsing proves syntax, not operation. When a bug crosses a launcher,
shell wrapper, package-manager command, or child script boundary:

1. Reproduce through the same command path the user runs.
2. Exercise at least one real child-process invocation.
3. Inspect the arguments received by the child process when forwarding is
   suspect.
4. Verify a foreground service with an actual request or health check.
5. Keep background workers alive long enough to inspect delayed startup logs.

## Completion rule

Do not claim a launcher or worker fix is complete until validation crosses the
same process and timing boundaries users will cross.

## Anti-patterns

- Treating dry-run argument parsing as proof that a real launcher works.
- Stopping validation immediately after a process starts, before delayed worker
  crashes can appear.
- Debugging only the parent script when the failure happens in the child.
