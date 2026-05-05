---
name: nodejs-backend-patterns-extras
description: >
  Additional Node.js and Next.js backend guidance for nodejs-backend-patterns.
  Use alongside nodejs-backend-patterns when Next app routes, route handlers,
  server modules, Prisma factories, dotenv loading, CLI scripts, workers, or
  standalone build tracing warnings are involved.
---

# Node.js Backend Patterns Extras

Open-source-style overlay extending `nodejs-backend-patterns` with Next.js
runtime-boundary guidance.

## Framework route environment boundaries

Shared server modules imported by framework routes should not statically import
local filesystem dotenv loaders. Keep local environment bootstrapping at
explicit CLI or worker entry points.

For Next.js app routes and route handlers:

- Let the framework provide runtime environment variables.
- Keep shared database/client factories free of `.env.local`, `fs`, and `path`
  bootstrapping imports used only for local scripts.
- Load local dotenv files explicitly in CLI entry points such as seeds, worker
  mains, manual import scripts, or one-off maintenance commands.
- Treat standalone-build tracing warnings as a signal that script-only
  bootstrap code may have crossed into route module imports.

## Anti-patterns

- Reusing a convenience CLI database factory in app routes when it statically
  loads local dotenv files.
- Hiding local filesystem bootstrapping inside shared modules imported by
  framework route handlers.
- Ignoring output tracing warnings caused by route import chains.
