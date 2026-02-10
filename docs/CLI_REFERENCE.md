# NyarlathotIA CLI Reference

Complete reference for all CLI flags and their interactions.

## Quick Reference Matrix

| Flag | Category | Requires | Conflicts | Description |
|------|----------|----------|-----------|-------------|
| `--work-branch <name>` | Branch | - | - | Reuse existing work branch |
| `--create` | Branch | `--work-branch` | - | Create branch if missing |
| `--base-branch <name>` | Branch | - | - | Source branch for new branch |
| `--build` | Build | - | - | Build image from source |
| `--dev` | Build | `--build` | - | Create branch-tagged image |
| `--no-cache` | Build | `--build` | - | Force rebuild from scratch |
| `--dry-run` | Build | `--build` | - | Preview build plan |
| `--build-custom-image` | Build | - | - | Build with user overlays |
| `--flavor <name>` | Image | - | `--image`* | Use flavor image |
| `--image <tag>` | Image | - | `--flavor`* | Use specific image |
| `--list-images` | Image | - | - | List available images |
| `--flavors-list` | Image | - | - | List available flavors |
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

Control how NyarlathotIA creates and manages Git branches for your work.

| Flag | Description |
|------|-------------|
| `--work-branch <name>` | Switch to an existing branch instead of creating a timestamped one |
| `--create` | Create the work branch if it doesn't exist (requires `--work-branch`) |
| `--base-branch <name>` | Specify which branch to create new branches from |

**Default behavior**: Creates timestamped branches like `claude-2026-01-11-143052`

**See also**: [BRANCH_MANAGEMENT.md](BRANCH_MANAGEMENT.md) for detailed workflows.

### Build Operations

Build Docker images locally. These flags are only available in development mode.

| Flag | Description |
|------|-------------|
| `--build` | Build image from source |
| `--dev` | Create branch-tagged image (e.g., `:dev-feature-auth`) |
| `--no-cache` | Force complete rebuild, ignore Docker cache |
| `--dry-run` | Preview build plan without building |
| `--build-custom-image` | Build with user overlay Dockerfiles |

**See also**: [IMAGE_NAMING.md](IMAGE_NAMING.md) for image naming conventions.

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
- `node` - yarn, pnpm, typescript, biome, vitest, tsx
- `php` - PHP 8.3, Composer, PHPUnit, PHPStan
- `react` - vite, storybook, testing-library + node tools
- `cypress` - E2E testing with headless Chromium
- `expo` - React Native with Expo CLI

**See also**: [USER_GUIDE_FLAVORS_OVERLAYS.md](USER_GUIDE_FLAVORS_OVERLAYS.md) for flavor details.

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
| `--dev` | `--build` | `--dev` is a build-time tag option |
| `--no-cache` | `--build` | Cache only applies to builds |
| `--dry-run` | `--build` | Previews the build |
| `--rag-verbose` | `--rag` | Verbose mode for RAG |
| `--rag-model` | `--rag` | Model selection for RAG |
| `--force` | `--login` | Force applies to login |

### Precedence Rules

| Flags | Winner | Behavior |
|-------|--------|----------|
| `--image` + `--flavor` | `--image` | Custom image overrides flavor |
| `--work-branch` + `--base-branch` | Both apply | Creates/switches work branch from base |

### Compatible Combinations

```bash
# Build with flavor and dev tag
nyia-claude --build --dev --flavor python

# Work branch from specific base
nyia-claude --work-branch feature/x --create --base-branch develop

# Verbose build with dry-run
nyia-claude --build --dry-run --verbose

# RAG with custom model
nyia-claude --rag --rag-model nomic-embed-text --verbose
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

# Build Python flavor locally
nyia-claude --build --flavor python
```

### Building Custom Images

```bash
# Build with dev tag for current branch
nyia-claude --build --dev

# Preview build without executing
nyia-claude --build --dry-run

# Build with custom overlays
nyia-claude --build-custom-image
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

### `--create requires --work-branch`

```
Error: --create requires --work-branch

The --create flag explicitly creates a branch if it doesn't exist.
Usage: nyia-assistant --work-branch feature/my-branch --create
```

**Fix**: Add `--work-branch <name>` before `--create`.

### `--dev requires --build`

```
Error: --dev can only be used with --build
```

**Fix**: Add `--build` to create a dev-tagged image.

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
- [IMAGE_NAMING.md](IMAGE_NAMING.md) - Image naming conventions
- [USER_GUIDE_FLAVORS_OVERLAYS.md](USER_GUIDE_FLAVORS_OVERLAYS.md) - Flavors and overlays guide
