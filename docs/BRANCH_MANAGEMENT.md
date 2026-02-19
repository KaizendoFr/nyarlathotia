# Branch Management Guide

How NyarlathotIA manages Git branches for AI-assisted development.

## Overview

NyarlathotIA automatically creates isolated Git branches for AI work. This keeps your main branch clean and lets you review AI changes before merging.

**Key principle**: AI work happens on separate branches, never directly on `main` or `master`.

---

## Branch Creation Modes

### Mode 1: Timestamped Branches (Default)

When you run an assistant without branch flags, it creates a unique timestamped branch:

```bash
nyia-claude
# Creates: claude-2026-01-11-143052
```

**Format**: `{assistant}-{YYYY}-{MM}-{DD}-{HHMMSS}`

**Use when**:
- Quick tasks or experiments
- You don't need to resume later
- You want automatic unique naming

### Mode 2: Named Work Branches

Create a named branch for ongoing work:

```bash
nyia-claude --work-branch feature/auth --create
# Creates: feature/auth
```

**Use when**:
- Multi-session feature development
- You want meaningful branch names
- You plan to resume work later

### Mode 3: Resume Existing Branch

Switch to a branch you created earlier:

```bash
nyia-claude --work-branch feature/auth
# Switches to existing feature/auth
```

**Behavior**:
- If branch exists: switches to it
- If branch missing: shows error with suggestions

### Mode 4: Current Branch (`-H`)

Work directly on whatever branch you're already on. No branch creation, no switching, no cleanup on exit.

```bash
git checkout feature/auth
nyia-claude -H
# Works on feature/auth — no new branch created
```

**Use when**:
- You already checked out the right branch
- You don't want nyia to manage branches at all
- You want the simplest, lowest-friction workflow

**Restrictions**:
- Cannot use on protected branches (main/master)
- Cannot use in workspace mode
- Cannot combine with `--work-branch` or `--create`

---

## Flags Reference

### `--current-branch` / `-H`

Work on the current branch. Skips all branch creation and cleanup.

```bash
# Simplest usage
nyia-claude -H

# Long form
nyia-claude --current-branch
```

**Protected branch guard**: If you're on `main` or `master`, this will error:
```
Cannot use protected branch as work branch: 'main'
```

### `--work-branch <name>` / `-w`

Specify a named branch instead of creating a timestamped one.

```bash
# Switch to existing branch
nyia-claude --work-branch feature/auth

# With --create: create if missing
nyia-claude --work-branch feature/auth --create
```

**Behavior without `--create`**:
- Existing branch: switches to it
- Missing branch: **error** with helpful message

**Why this design**: Prevents accidental branch creation from typos.

### `--create`

Explicitly create the work branch if it doesn't exist.

```bash
nyia-claude --work-branch feature/new-feature --create
```

**Requirements**: Must be used with `--work-branch`.

**Behavior**:
- Branch missing: creates it
- Branch exists: shows info message and switches to it

### `--base-branch <name>`

Specify which branch to create new branches from.

```bash
# Create feature/auth from develop (not current branch)
nyia-claude --work-branch feature/auth --create --base-branch develop

# Timestamped branch from develop
nyia-claude --base-branch develop
```

**Default**: Current branch (HEAD)

---

## Common Workflows

### Starting a New Feature

```bash
# Option 1: Named branch from main
nyia-claude --work-branch feature/user-auth --create --base-branch main

# Option 2: Named branch from current
nyia-claude --work-branch feature/user-auth --create

# Option 3: Timestamped (quick work)
nyia-claude
```

### Resuming Previous Work

```bash
# Switch to your existing branch
nyia-claude --work-branch feature/user-auth

# Check what branches exist
git branch -a | grep feature/
```

### Working from a Release Branch

```bash
# Create hotfix from release
nyia-claude --work-branch hotfix/security-fix --create --base-branch release/v2.0
```

### Multiple Features in Parallel

```bash
# Session 1: Auth feature
nyia-claude --work-branch feature/auth --create

# Session 2: Different terminal, API feature
nyia-claude --work-branch feature/api --create
```

---

## Protected Branches

NyarlathotIA prevents direct work on protected branches:

- `main`
- `master`

**Attempting to use protected branch**:
```bash
nyia-claude --work-branch main --create
# Error: Cannot use protected branch as work branch: 'main'
```

**Why**: Protects your main branch from accidental AI commits.

---

## Branch Naming Conventions

### Recommended Patterns

| Pattern | Example | Use For |
|---------|---------|---------|
| `feature/<name>` | `feature/user-auth` | New features |
| `bugfix/<name>` | `bugfix/login-error` | Bug fixes |
| `hotfix/<name>` | `hotfix/security-patch` | Urgent fixes |
| `refactor/<name>` | `refactor/api-cleanup` | Code refactoring |
| `experiment/<name>` | `experiment/new-approach` | Experiments |

### Invalid Names

- Spaces: `feature/my feature` (use dashes)
- Special chars: `feature/my;branch` (security risk)
- Protected names: `main`, `master`

---

## Error Messages and Solutions

### Branch Does Not Exist

```
Branch 'feature/typo' does not exist locally or on remote

Available local branches:
  feature/auth
  feature/api
  main

To CREATE this branch, use --create flag:
  nyia-claude --work-branch feature/typo --create
```

**Solutions**:
1. Fix the typo: `--work-branch feature/auth`
2. Create the branch: add `--create` flag

### Cannot Use Protected Branch

```
Cannot use protected branch as work branch: 'main'
Protected branches detected:
  - main
  - master
Use a feature branch name like: feature/main
```

**Solution**: Use a feature branch name instead.

### --create Requires --work-branch

```
Error: --create requires --work-branch

The --create flag explicitly creates a branch if it doesn't exist.
Usage: nyia-assistant --work-branch feature/my-branch --create
```

**Solution**: Add `--work-branch <name>` before `--create`.

---

## How It Works

### Branch Detection Flow

```
1. Check if --work-branch specified
   ├─ Yes: Check if branch exists
   │   ├─ Exists locally: switch to it
   │   ├─ Exists on remote: checkout and track
   │   └─ Missing:
   │       ├─ --create: create from --base-branch (or current)
   │       └─ No --create: ERROR with suggestions
   └─ No: Create timestamped branch from --base-branch (or current)
```

### What Gets Created

When creating a new branch:
1. Branch created from base (default: current branch)
2. Switched to new branch
3. AI work proceeds on this branch
4. Changes stay on this branch until you merge

---

## Best Practices

### Do

- Use meaningful branch names for ongoing work
- Use `--create` explicitly when making new branches
- Check `git branch` before resuming work
- Review AI commits before merging to main

### Don't

- Work directly on main/master
- Use spaces or special characters in branch names
- Forget which branch you were working on (use named branches)

---

## Related Documentation

- [CLI_REFERENCE.md](CLI_REFERENCE.md) - Complete flag reference
- [USER_GUIDE_FLAVORS_OVERLAYS.md](USER_GUIDE_FLAVORS_OVERLAYS.md) - Flavors and custom images
