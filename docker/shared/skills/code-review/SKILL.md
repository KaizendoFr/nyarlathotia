---
name: code-review
description: Post-implementation code reviewer. Reads the plan, reads the actual code, and reviews pragmatically. Focuses on working code, security, and best practices. Not perfectionist about style. Use after implementing a plan to verify quality.
---

# Code-Review - Pragmatic Post-Implementation Reviewer

Review code that was written to implement a plan. Focus on what matters: does it work, is it secure, will it break something. Skip cosmetic nitpicks.

## A) Argument Parsing

```
/code-review [plan-ref] [--files file1 file2 ...]

plan-ref:
  Number (e.g., "197")     -> find .nyiakeeper/plans/197-*.md (exclude pair-review-* files)
  File path                -> use directly
  Omitted                  -> check todo.md for in-progress task, use its plan

--files (optional):
  Specific files to review. If omitted, discover from plan + git diff.
```

## B) Load Context

1. **Find the plan**: Resolve plan-ref to plan file. Read it completely.
2. **Identify changed files**: Use the plan's "Implementation Steps" to find which files were touched. Cross-reference with `git diff --name-only` if available.
3. **Read the code**: Read each changed file (or the specific sections mentioned in the plan).
4. **Read existing tests**: Find test files related to the changed code.

## C) Review Checklist

Review the code against these criteria, in priority order:

### Priority 1: Must-Fix (blocks shipping)

**Does it work?**
- Does the code actually implement what the plan says?
- Are there logic errors, off-by-one, missing edge cases?
- Do the tests actually test the right things?

**Security**
- Input validation at boundaries (user input, external data, CLI args)
- No command injection (unquoted variables in bash, unsanitized eval)
- No path traversal (user-controlled paths used without sanitization)
- No secrets exposed (hardcoded keys, tokens in logs)
- File permissions appropriate (not world-writable, not 777)

**Will it break something?**
- Does it change existing behavior that other code depends on?
- Are function signatures backward-compatible (or are callers updated)?
- Does it handle the error path (not just happy path)?
- Race conditions in concurrent/async code?

### Priority 2: Should-Fix (quality issues)

**Robustness**
- Error messages are actionable (not just "error occurred")
- Defensive coding at function boundaries (null checks, type checks)
- Resource cleanup (temp files, open handles, locks)
- Idempotency where expected

**Testability**
- Are the right things tested? (behavior, not implementation details)
- Are edge cases covered? (empty input, boundary values, error paths)
- Can the code be tested in isolation?

### Priority 3: Consider (nice-to-have, do NOT block on these)

**Readability**
- Would a new developer understand this in 5 minutes?
- Are variable/function names self-explanatory?
- Complex logic has a comment explaining WHY (not WHAT)

**Maintainability**
- Functions under 30 lines? (guideline, not a hard rule)
- No copy-paste duplication that will drift apart
- Clear module boundaries

## D) Review Philosophy

**BE PRAGMATIC, NOT PERFECTIONIST:**
- Working code that is slightly ugly > beautiful code that is untested
- 3 similar lines > a premature abstraction
- A clear function name > a docstring on an obvious function
- "This works and is safe" is a valid review outcome
- Do NOT rewrite working code for style preferences

**FOCUS ON RISK, NOT TASTE:**
- "This could crash in production" = must-fix
- "I would have named this differently" = skip it
- "This SQL is injectable" = must-fix
- "This function is 25 lines instead of 20" = skip it

## E) Output Format

Present findings in this structure:

```markdown
## Code Review: Plan {N} - {title}

### Files Reviewed
- `path/to/file1.sh` (lines X-Y)
- `path/to/file2.sh` (lines X-Y)

### Must-Fix
- [{severity}] `file:line` - {description} -> {specific fix}

### Should-Fix
- `file:line` - {description} -> {suggestion}

### Looks Good
- {What was done well — be specific, reference code}

### Plan Compliance
- [ ] Requirement 1: {met/not met} - {evidence}
- [ ] Requirement 2: {met/not met} - {evidence}

### Test Coverage Assessment
- {Which behaviors are tested}
- {Which behaviors are NOT tested but should be}

### Verdict: {PASS | PASS WITH FIXES | NEEDS WORK}
```

## F) After Review

1. **If PASS**: Tell the user the code is ready. Update plan status if applicable.
2. **If PASS WITH FIXES**: List the specific fixes needed. Offer to implement must-fix items.
3. **If NEEDS WORK**: Explain what needs to change and why. Reference plan requirements.

## G) Key Rules

- **Read the actual code** — never review from memory or plan description alone
- **Run tests if possible** — `bats tests/bats/test_*.bats` for this project
- **Compare against plan** — the plan is the spec, review against it
- **One pass, not three** — don't re-review the same code multiple times in one session
- **No unsolicited refactoring** — review the code as written, suggest improvements only if asked
- **Respect the author** — the code was written with intent, understand it before criticizing
