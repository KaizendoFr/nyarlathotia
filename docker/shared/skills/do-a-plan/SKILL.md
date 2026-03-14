---
name: do-a-plan
description: Turn a goal into a phased execution plan with atomic, checkable steps. Creates LLM-friendly, resumable plans in .nyiakeeper/plans/. Use when starting any non-trivial task.
---

# Do-a-Plan - Execution Plan Creator

When invoked with a goal or context, do the following:

## A) Clarify the Goal

- Restate the goal in 1 sentence
- Identify scope boundaries: what is in / out (2-5 bullets)
- If critical info is missing, ask targeted questions until 100% aligned with the user

## B) Produce an Execution Plan File

Create a plan file in `.nyiakeeper/plans/` with name format: `{number}-{slug}.md`

**Required sections (per system prompt):**

```markdown
# Plan: [Clear Task Title]

## Context
Why this task is needed and current situation

## Requirements
- Specific requirement 1
- Specific requirement 2

## Approach
High-level strategy and key decisions

## Implementation Steps
1. [ ] Step 1: Specific action with file names
2. [ ] Step 2: Specific action with expected outcome

## Testing Strategy
- Unit tests: Which functions to test
- Integration tests: Which flows to verify
- Manual testing: What to check

## Risks & Mitigations
- Risk 1: Description → Mitigation: Specific action

## Resources Modified (optional — for batch runs)
- [List of files, systems, or documents this plan changes]

## Definition of Done
- Validated with user

## Resume Point
- Next steps if we stop now
```

## C) Atomic Step Rules

- Single action per step
- Verifiable outcome (what "done" looks like)
- Minimal scope (small enough to run safely)
- No hidden sub-steps
- LLM-friendly (context-limited)
- Relative outcomes (e.g., "baseline + 6 new" not "1032 total")

## D) Test-Aware Workflow (Mandatory)

- Identify relevant existing tests near the edited area
- Run baseline tests before implementation (if tests exist)
- Run the same tests after implementation
- If tests fail: behavior changed → update tests, OR regression → fix code

## E) Update todo.md

- Add new task to 📋 Ready section referencing the plan file
- Format: `- [ ] Task description - Priority: X - Plan: plans/{plan-file}.md`

## F) Pre-flight Checklist (before finalizing)

Scan the plan for these common gaps before writing:

- [ ] **Scope complete?** What else references, depends on, or documents this?
      (Related configs, generated outputs, help text, user docs, changelogs)
- [ ] **Edge cases defined?** What happens on error, empty input, missing resource, offline?
      (Define explicit behavior — not just "handle errors")
- [ ] **Undo plan?** How to reverse if it goes wrong?
- [ ] **Verification concrete?** How do you prove each step worked?
      (Prefer relative criteria: "baseline + N", not fixed counts)
- [ ] **Sections aligned?** Do requirements, approach, steps, and done criteria tell the same story?
