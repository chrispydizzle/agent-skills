---
name: canvas-design-extras
description: >
  Additional production-package and QA rules for canvas-design. Use alongside
  canvas-design when a static design task involves social carousels, production
  asset packages, SVG/source files, manifests, hashes, captions, alt text,
  reviewer handoffs, or public-facing assets that need leakage scrubbing.
---

# Canvas Design Extras

Internal overlay skill extending `canvas-design` with production-package rules.

## Production package exception

When the user explicitly asks for a production package, preserve the design
quality guidance from `canvas-design` but allow the operational formats the
package requires:

- Source assets such as SVG.
- Manifests, ledgers, hashes, and provenance files.
- Export or verification scripts.
- README or handoff documentation.

Do not force a package into only `.png`, `.pdf`, or `.md` when source and
verification artifacts are part of the deliverable.

## Artifact classification

Before delivery, classify each artifact:

- **Public-facing:** rendered slide text, captions, alt text, post copy, public
  metadata.
- **Reviewer-facing:** README, preview notes, QA summaries.
- **Internal:** source ledger, workflow notes, hashes, scripts, provenance.

Public-facing artifacts must not contain internal workflow/status phrases,
draft labels, clearance language, placeholders, or package-gate terminology.
Reviewer-facing artifacts may describe review state but should not leak internal
notes into publishable copy.

## Production-package preflight

Before reporting completion:

1. Scrub public-facing files for placeholders and internal workflow language.
2. Regenerate rendered exports after any source text change.
3. Regenerate hashes or manifests after any artifact changes.
4. Verify captions, alt text, README, manifest, and rendered text agree.
5. Summarize which files are public-facing, reviewer-facing, and internal.

## Anti-patterns

- Treating source SVG, manifests, or hashes as invalid just because the base
  design task usually emits final renders.
- Sending assets to review while public copy still contains internal gate or
  workflow language.
- Updating source text without regenerating renders and hashes.
