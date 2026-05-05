---
name: frontend-design-extras
description: >
  Additional verification and layout guidance for frontend-design. Use alongside
  frontend-design when UI code generates classes from enumerated states, when
  analytics views are dense, when dashboards need exploratory pages or tabs, or
  when filters for owned/excluded entities must be explicit and reviewable.
---

# Frontend Design Extras

Internal overlay skill extending `frontend-design` with state-class and dense
analytics guidance.

## Dynamic state class verification

When UI code maps enum or state values into CSS classes:

1. List every possible state value.
2. Cross-check each value against CSS selectors, visual treatments, and tests.
3. Verify missing or new states fail visibly instead of falling into an
   unstyled default.
4. Add a focused test or story for the full state matrix when practical.

## Dense analytics layouts

When a feature has multiple coordinated charts, timelines, matrices, filters,
or exploratory controls, prefer a dedicated page or workspace over a cramped
dashboard card. Use tabs or sections when they help separate tasks such as:

- Timeline exploration.
- Entity detail inspection.
- Matrix or heatmap analysis.
- Filter configuration and review.

## Hard filter contracts

When a filter represents user-owned, excluded, or safety-critical entities,
prefer a reviewable identifier list over implicit fuzzy pattern matching at
runtime. Generate candidates from discovery queries if useful, but make the
final filter explicit and consistently applied across every view.

## Anti-patterns

- Compressing exploratory analytics into a single card until labels, controls,
  or relationships become unreadable.
- Inferring ownership or exclusion solely from naming patterns when stable
  identifiers are available.
- Adding enum-driven CSS without checking every state has a visual treatment.
