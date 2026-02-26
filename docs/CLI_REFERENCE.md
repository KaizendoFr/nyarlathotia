# Nyia Keeper CLI Reference

Complete reference for all CLI flags and their interactions.

## Quick Reference Matrix

| Flag | Category | Requires | Conflicts | Description |
|------|----------|----------|-----------|-------------|
| `-H`, `--current-branch` | Branch | - | `--work-branch`, `--create`, workspace | Work on current branch (skip branch creation) |
| `-w`, `--work-branch <name>` | Branch | - | `--current-branch` | Reuse existing work branch |
| `--create` | Branch | `--work-branch` | `--current-branch` | Create branch if missing |
| `--base-branch <name>` | Branch | - | - | Source branch for new branch |
| `--build-custom-image` | Build | - | - | Build with user overlays |
| `--base-image <image>` | Build | `--build-custom-image` | `--flavor` | Override base image for overlay build (dev only) |
| `--no-cache` | Build | `--build`* or `--build-custom-image` | - | Force rebuild without Docker cache |
| `--flavor <name>` | Image | - | `--image`* | Use flavor image |
| `--image <tag>` | Image | - | `--flavor`* | Use specific image |
| `--list-images` | Image | - | - | List available images |
| `--flavors-list` | Image | - | - | List available flavors |
| `--agent <name>` | Agent | - | - | Select agent persona for session |
| `--list-agents` | Agent | - | - | List available agent personas |
| `--rag` | RAG | Ollama | - | Enable codebase search |
| `--rag-verbose` | RAG | `--rag` | - | Debug RAG indexing |
| `--rag-model <name>` | RAG | `--rag` | - | Override embedding model |
| `--login` | Auth | - | - | Authenticate assistant |
| `--force` | Auth | `--login` | - | Bypass auth checks |
| `--set-api-key` | Auth | - | - | Set API key (OpenCode) |
| `--status` | Config | - | - | Show current configuration |
| `--setup` | Config | - | - | Interactive setup |
| `--path <dir>` | Config | - | - | Work on different project |
| `--shell` | System | - | - | Interactive bash shell |
| `--check-requirements` | System | - | - | Verify system requirements |
| `--disable-exclusions` | System | - | - | Disable mount exclusions |
| `--skip-checks` | System | - | - | Skip startup checks |
| `--verbose, -v` | Output | - | - | Verbose output |
| `--help, -h` | Output | - | - | Show help |

*`--image` takes precedence over `--flavor` when both specified.

---

## Flag Categories

### Branch Management

Control how Nyia Keeper creates and manages Git branches for your work.

| Flag | Short | Description |
|------|-------|-------------|
| `--current-branch` | `-H` | Work on current branch — no branch creation, no cleanup on exit |
| `--work-branch <name>` | `-w` | Switch to an existing branch instead of creating a timestamped one |
| `--create` | | Create the work branch if it doesn't exist (requires `--work-branch`) |
| `--base-branch <name>` | | Specify which branch to create new branches from |

**Default behavior**: Creates timestamped branches like `claude-2026-01-11-143052`

**`--current-branch` / `-H`**: Skips all branch management. Works directly on whatever branch you're on. Rejects protected branches (main/master). Not compatible with workspace mode.

**See also**: [BRANCH_MANAGEMENT.md](BRANCH_MANAGEMENT.md) for detailed workflows.

### Custom Image Building

| Flag | Description |
|------|-------------|
| `--build-custom-image` | Build with user overlay Dockerfiles |
| `--base-image <image>` | Override base image for overlay build (dev only). Mutually exclusive with `--flavor` |
| `--no-cache` | Force rebuild without Docker cache (requires `--build`* or `--build-custom-image`) |

*`--build` and `--base-image` are dev-only and not available in runtime distribution.

**`--base-image`**: Override which image the overlay builds on top of. Useful for testing overlays against locally-built flavor images:

```bash
# Build overlay on a local flavor image:
nyia-claude --build-custom-image --base-image nyiakeeper/claude-python:dev-feature
```

Overlay Dockerfiles must follow this pattern:
```dockerfile
ARG BASE_IMAGE
FROM ${BASE_IMAGE}

USER root
RUN apt-get update && apt-get install -y your-packages && rm -rf /var/lib/apt/lists/*
USER node
RUN pip install --no-cache-dir your-python-packages
```

See [DEV_GUIDE_FLAVORS_OVERLAYS.md](DEV_GUIDE_FLAVORS_OVERLAYS.md) for full overlay documentation.

### Image Selection

Choose which Docker image to run.

| Flag | Description |
|------|-------------|
| `--flavor <name>` | Use a pre-built flavor image (e.g., `python`, `node`) |
| `--image <tag>` | Use a specific image tag |
| `--list-images` | List all available local images |
| `--flavors-list` | List all available flavors |

**Precedence**: `--image` > `--flavor` > default

**Available flavors**:
- `python` - pytest, black, mypy, ruff, isort, ipython
- `php` - PHP 8.3, Composer, PHPUnit, PHPStan
- `node` - Node.js 22, yarn, pnpm, typescript, biome, vitest, vite, storybook, cypress, expo-cli, eas-cli
- `php-react` - PHP 8.2 + React fullstack
- `rust-tauri` - Rust, Cargo, Tauri v2, clippy, rustfmt, Node.js 22

**See also**: [USER_GUIDE_FLAVORS_OVERLAYS.md](USER_GUIDE_FLAVORS_OVERLAYS.md) for flavor details.

### Agent Personas

Select or list agent personas for the session. See [assistant-agents-matrix.md](assistant-agents-matrix.md) for per-assistant capabilities.

| Flag | Description |
|------|-------------|
| `--agent <name>` | Select agent persona (Claude, OpenCode, Vibe: direct mapping; Codex: guidance-only) |
| `--list-agents` | List available agent personas (host-side discovery, no container needed) |

**Scope precedence**: `--agent` (session) > project-local agents > global agents > assistant default.

**Agent name rules**: lowercase letters, numbers, and hyphens only. Max 64 characters.

```bash
# List available agents
nyia-claude --list-agents

# Use a specific agent
nyia-claude --agent reviewer
nyia-vibe --agent plan
nyia-opencode --agent my-custom-agent
```

### RAG (Codebase Search)

Semantic code search using local embeddings. Requires Ollama.

| Flag | Description |
|------|-------------|
| `--rag` | Enable RAG codebase search |
| `--rag-verbose` | Enable verbose debug logging for RAG indexing |
| `--rag-model <name>` | Override embedding model (default: `nomic-embed-text`) |

**Requirements**: Ollama must be installed and running locally.

### Authentication

Manage assistant authentication.

| Flag | Description |
|------|-------------|
| `--login` | Authenticate with the assistant's service |
| `--force` | Bypass authentication checks (use with `--login`) |
| `--set-api-key` | Set API key for team plan users (OpenCode) |

### Configuration

View and manage configuration.

| Flag | Description |
|------|-------------|
| `--status` | Show current configuration and overlay status |
| `--setup` | Run interactive setup wizard |
| `--path <dir>` | Work on a different project directory |

### System Operations

System-level operations.

| Flag | Description |
|------|-------------|
| `--shell` | Open interactive bash shell in container |
| `--check-requirements` | Verify Docker and system requirements |
| `--disable-exclusions` | Disable mount exclusions (mount everything) |
| `--skip-checks` | Skip startup requirement checks |

### Output Control

| Flag | Description |
|------|-------------|
| `--verbose, -v` | Enable verbose output |
| `--help, -h` | Show help message |

---

## Flag Interactions

### Required Combinations

| If you use... | You must also use... | Reason |
|---------------|---------------------|--------|
| `--create` | `--work-branch` | `--create` specifies what to create |
| `--no-cache` | `--build`* or `--build-custom-image` | Cache bypass applies to builds |
| `--base-image` | `--build-custom-image` | Base image override applies to custom builds |
| `--rag-verbose` | `--rag` | Verbose mode for RAG |
| `--rag-model` | `--rag` | Model selection for RAG |
| `--force` | `--login` | Force applies to login |

### Precedence Rules

| Flags | Winner | Behavior |
|-------|--------|----------|
| `--image` + `--flavor` | `--image` | Custom image overrides flavor |
| `--work-branch` + `--base-branch` | Both apply | Creates/switches work branch from base |

### Mutually Exclusive

| Flag A | Flag B | Reason |
|--------|--------|--------|
| `--current-branch` | `--work-branch` | One stays, the other switches |
| `--current-branch` | `--create` | Nothing to create in current-branch mode |
| `--current-branch` | Workspace mode | Workspace requires branch sync across repos |
| `--base-image` | `--flavor` | Base image override replaces flavor selection |

### Compatible Combinations

```bash
# Work on current branch (simplest option)
nyia-claude -H

# Work branch from specific base
nyia-claude --work-branch feature/x --create --base-branch develop

# RAG with custom model
nyia-claude --rag --rag-model nomic-embed-text --verbose

# Flavor with prompt
nyia-claude --flavor python -p "Write tests"
```

---

## Examples by Use Case

### Starting a New Feature

```bash
# Create named work branch from main
nyia-claude --work-branch feature/auth --create --base-branch main

# Or let it create a timestamped branch
nyia-claude
```

### Resuming Previous Work

```bash
# Switch to existing branch
nyia-claude --work-branch feature/auth
```

### Python Development

```bash
# Use Python flavor
nyia-claude --flavor python -p "Write pytest tests"

# Interactive mode with flavor
nyia-claude --flavor python
```

### Building Custom Images

```bash
# Build with custom overlays
nyia-claude --build-custom-image

# Force rebuild without Docker cache
nyia-claude --build-custom-image --no-cache

# Then use your custom image
nyia-claude --image nyiakeeper/claude-custom
```

### Codebase Search

```bash
# Enable RAG for semantic search
nyia-claude --rag -p "Find authentication code"

# Debug RAG indexing
nyia-claude --rag --rag-verbose
```

### Working on Different Project

```bash
# Work on project in different directory
nyia-claude --path /path/to/other/project
```

---

## Error Messages

### `--current-branch cannot be used with --work-branch`

```
Error: --current-branch cannot be used with --work-branch
--current-branch works on your current branch, --work-branch switches to a specific one
```

**Fix**: Use one or the other. `-H` to stay, `-w <name>` to switch.

### `Cannot use --current-branch on protected branch`

```
Cannot use protected branch as work branch: 'main'
```

**Fix**: Switch to a work branch first (`git checkout feature/x`), then use `-H`.

### `--create requires --work-branch`

```
Error: --create requires --work-branch

The --create flag explicitly creates a branch if it doesn't exist.
Usage: nyia-assistant --work-branch feature/my-branch --create
```

**Fix**: Add `--work-branch <name>` before `--create`.

### `Branch does not exist`

```
Branch 'feature/x' does not exist locally or on remote
```

**Fix**: Either:
- Use `--create` to create it: `--work-branch feature/x --create`
- Check spelling and use an existing branch

### `Cannot use protected branch`

```
Cannot use protected branch as work branch: 'main'
```

**Fix**: Use a feature branch name like `feature/my-work` instead.

---

## Related Documentation

- [BRANCH_MANAGEMENT.md](BRANCH_MANAGEMENT.md) - Detailed branch workflow guide
- [USER_GUIDE_FLAVORS_OVERLAYS.md](USER_GUIDE_FLAVORS_OVERLAYS.md) - Flavors and overlays guide
