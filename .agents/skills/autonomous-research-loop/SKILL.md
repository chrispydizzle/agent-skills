---
name: autonomous-research-loop
description: >
  Run disciplined autonomous research loops that preserve knowledge across
  iterations. Use this skill whenever the user asks the agent to "operate
  autonomously", "autopilot", "keep going", "research this", "track what you
  learned", "compare with previous findings", "maintain a knowledge base", or
  run a long-running investigation across multiple sessions. Especially use it
  for security research, technical spikes, agent/squad research tasks, literature
  review, tool evaluation, or any open-ended exploration where prior findings,
  dead ends, confidence, provenance, and handoff state matter.
---

# Autonomous Research Loop

**Created for the local Copilot skill library.** This skill captures a reusable
workflow for autonomous research sessions where the agent must make progress
without losing context, repeating dead ends, or returning a pile of unstructured
notes.

Use this skill to turn "go research this for a while" into a bounded loop:
read prior state, choose the next useful question, investigate, compare against
known findings, write durable notes, and hand off the next decision point.

## Core principle

Autonomous work is only useful if it compounds. Every loop should leave the next
loop in a better position than it started: clearer evidence, fewer unknowns,
documented dead ends, and an explicit next move.

## When to activate

Activate this skill for task-oriented research where one or more of these are
true:

- The user asks for autopilot, autonomous operation, or "keep going"
- The task will span multiple tool calls, sources, files, or sessions
- The user asks to track what was learned or compare against prior work
- The task has uncertain direction and needs iterative exploration
- The output should become a knowledge base, research log, tactics file, or handoff
- Multiple agents or future sessions may continue the work

Do not use this for quick factual lookups, single-command answers, or work where
the deliverable is already fully specified and does not require exploration.

## Safety and scope gate

Before starting, restate the authorized scope in practical terms:

- What system, repository, artifact set, or topic is in scope?
- What actions are allowed?
- What actions are out of scope or need explicit approval?
- What would count as useful progress?

For security research, keep the work aligned with authorized assessment,
defensive analysis, reproduction in controlled environments, or documentation.
If the scope is ambiguous, ask for clarification before taking risky action.

## The loop

### 1. Load prior state

Start each loop by finding the best available memory source. Prefer, in order:

1. User-provided handoff, progress log, status file, or research notes
2. Project files such as `STATUS.md`, `PROGRESS.md`, `findings\`, `docs\`,
   `research\`, `tactics.md`, or a repository-specific knowledge base
3. Session-local notes or the current conversation
4. A new knowledge base file if none exists and the user wants persistence

Extract:

- Current goal
- Known facts
- Open questions
- Tried paths and dead ends
- Promising leads
- Constraints, safety boundaries, or user preferences
- The last concrete next step, if one exists

Do not trust memory alone when a durable file exists. Read the source of truth.

### 2. Choose a loop objective

Pick one narrow objective for the next loop. Good objectives are evidence-driven
and finishable:

- "Verify whether finding X is still true against current source Y"
- "Map the remaining unknowns in component Z"
- "Compare three candidate tools and recommend one"
- "Reproduce the reported behavior in a controlled way"
- "Eliminate or confirm one suspected dead end"

Avoid objectives like "research everything" or "find a vuln". If the user asks
for broad autonomy, translate it into the next highest-value concrete question.

### 3. Plan a small batch

Before tool use, write a compact plan with:

- Objective
- Sources or files to inspect
- Commands or tools to run
- Expected evidence
- Stop condition for this loop

Parallelize independent reads and searches where possible. Do not duplicate
work already recorded in the knowledge base unless the evidence has changed.

### 4. Investigate

Gather evidence, not vibes. Record enough detail that a future session can
understand why a conclusion was reached:

- Source path, URL, command, log line, commit, or artifact name
- What was observed
- Why it matters
- Confidence level: high, medium, low
- Whether it confirms, contradicts, or updates prior knowledge

When a path fails, preserve the failure if it prevents future wasted work. A
good dead-end entry explains what was tried, what happened, and why it is not
worth repeating unless conditions change.

### 5. Compare against prior state

Before writing conclusions, compare new evidence with existing notes:

- Is this actually new?
- Does it supersede an older finding?
- Does it contradict anything?
- Did it reduce an open question or create a new one?
- Does it change priority?

If two findings conflict, do not smooth over the conflict. Mark it explicitly
and identify what evidence would resolve it.

### 6. Write durable knowledge

For persistent work, update the relevant project knowledge base. If no project
format exists, use this structure:

```markdown
# Research Knowledge Base

## Current goal
[One paragraph]

## Working conclusions
- **[Conclusion]** — confidence: high|medium|low. Evidence: [source].

## Open questions
- **[Question]** — why it matters; next evidence to collect.

## Leads
- **[Lead]** — priority: high|medium|low; suggested next action.

## Dead ends
- **[Path tried]** — what was tried; why it did not work; revisit only if [condition].

## Loop log
### [Date/session] — [loop objective]
- Actions:
- Evidence:
- Updates to prior knowledge:
- Next recommended move:
```

Use the existing project format if one exists. Do not create a new format that
fragments the knowledge base.

### 7. Handoff

End each loop with a concise handoff:

```markdown
## Autonomous Research Handoff

**Objective this loop:** ...
**What changed:** ...
**New evidence:** ...
**Updated conclusions:** ...
**Dead ends avoided or added:** ...
**Open questions:** ...
**Recommended next loop:** ...
**Files updated:** ...
```

If continuing autonomously, use the "Recommended next loop" as the next loop
objective and repeat. If the next step requires user input, stop and ask.

## Stop conditions

Autonomy does not mean running forever without judgment. Stop or surface to the
user when:

- The next action requires authorization, credentials, spending money, or
  physical-world access
- A potentially destructive or risky action would be needed
- You hit repeated tool failures and need a different resource
- Evidence conflicts and the resolution depends on user priority
- The loop objective is complete and the next best objective is ambiguous
- You have enough findings that the user should reprioritize

If the user explicitly asked for a time-box or minimum effort, respect it, but
still stop for safety, authorization, or destructive-risk boundaries.

## Quality checklist

Before ending a loop, verify:

- Prior state was read before new investigation
- The loop had one concrete objective
- New findings cite evidence or source paths
- Dead ends are documented when useful
- Conclusions include confidence
- The knowledge base or handoff was updated
- The next recommended loop is specific and actionable

## Anti-patterns

- Starting fresh when a progress log exists
- Treating repeated searches as progress
- Writing conclusions without evidence paths
- Hiding contradictions to make the report cleaner
- Letting broad prompts produce broad, unactionable notes
- Continuing risky work just because the user said "autopilot"
- Updating multiple competing knowledge-base files with overlapping state

## Example trigger phrases

- "Operate autonomously to research new tactics. Track what you've learned."
- "I'm putting you on autopilot. Keep going and compare against prior findings."
- "Research this repo and build a knowledge base as you go."
- "Pick up where we left off from the progress log."
- "Run a technical spike and leave a handoff for the next session."
