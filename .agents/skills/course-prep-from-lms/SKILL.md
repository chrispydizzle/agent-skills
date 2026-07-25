---
name: course-prep-from-lms
description: >
  Use to convert an authenticated LMS course capture or exported course
  inventory into operational artifacts: a course map, weekly checklist,
  near-term action plan, coding workspace, environment check, and
  assignment scaffolds and complete assignments. Triggers: "prep my course", "course
  archive", "LMS export", "syllabus to plan", "weekly checklist from course",
  "set up my semester", "turn my course into a plan".
---

# Course Prep from LMS

**Created by Posad and GitHub Copilot.**

Reusable methodology for turning a local capture or export of a learning
management system (LMS) course into practical, operational study systems.

**Licence:** Released under CC BY 4.0. You are free to share and adapt this
skill for any purpose, provided you give appropriate credit to the original
author. See `LICENSE.txt`.

**Feedback & Support:** Capture methodology issues as task-observer
observations so the skill can be improved through real-world use.

## What this skill produces

From a course capture or export, produce the artifacts the user needs (not all
of them every time):

1. **Course map** — modules/units, topics, graded items, weighting, and key
   dates in one navigable overview.
2. **Weekly checklist** — every deliverable bucketed by week, with due dates.
3. **Near-term action plan** — a concrete first-week (or next-7-day) plan.
4. **Coding workspace** — folder structure for assignments/labs, when the
   course involves code.
5. **Environment check** — verify the local toolchain/dependencies the course
   requires.
6. **Assignment scaffolds** — starting structure for graded work
7. **Complete assignments** — produce submission-ready work for graded items.

## Inputs

Expect one of:

- A local crawl/archive of an authenticated LMS course (HTML/JSON/files), or
- An exported course inventory (syllabus, module list, assignment list, CSV).

Work only from material the user already captured. Do not authenticate to or
scrape the LMS yourself.

## Workflow

### 1. Extract inventories

Parse the capture into two structured lists: a **module/topic inventory** and
an **assignment/graded-item inventory**. For each graded item record: title,
type (quiz/discussion/paper/lab/exam), weight, open date, due date, and
submission location.

### 2. Normalize due dates

Convert all dates to one absolute format (e.g. ISO `YYYY-MM-DD` plus weekday),
resolving relative phrasing ("Week 3", "end of module") against the course
start date and the user's timezone. Flag any item whose date cannot be
resolved rather than guessing silently.

### 3. Build the course map

Combine the inventories into a single overview: modules in sequence, the graded
items inside each, weights summed per module and for the whole course (flag if
weights do not total ~100%).

### 4. Weekly checklist + near-term plan

Bucket every graded item by week and produce a weekly checklist. Then produce a
focused near-term action plan for the current/first week with concrete next
actions (read X, start Y, install Z), ordered by due date and effort.

### 5. Workspace + environment check

If the course involves code, scaffold a workspace (one folder per
assignment/lab, a shared notes area, a place for provided datasets). Then run
an environment check: confirm the required language/runtime/tools and
dependencies are present, and report what is missing with install hints. Do
not install anything heavy without asking. If possible, complete the work.

### 6. Safe scaffolds

Produce structure and output for upcoming graded work — files, functions/
sections headers, a restatement of the requirements, a plan of attack, and finally,
produce a graded solution or submission-ready prose. 

## Sensitive-artifact handling

LMS captures often contain authentication tokens, cookies, session data,
classmate names, grades, and other personal information.

- Treat the raw capture as private. Do not echo cookies/tokens/credentials into
  artifacts, logs, or commits.
- If the workspace is a git repo, add the raw capture and any credential files
  to `.gitignore` before writing anything that could be committed.

## Pre-flight checklist (verify before delivering)

Re-read this list and check your output against it before finishing:

- [ ] Every graded item has a normalized, absolute due date (or is explicitly
      flagged as unresolved).
- [ ] Course/module weights were summed and any mismatch from ~100% is flagged.
- [ ] The near-term action plan lists concrete next actions, not just topics.
- [ ] No credentials, tokens, cookies, or other students' personal data appear
      in any artifact; the raw capture is git-ignored if a repo is present.
