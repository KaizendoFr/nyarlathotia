# User Guide: Flavors and Overlays

This guide explains how to use pre-built flavors and create custom overlays to extend NyarlathotIA assistants with additional tools and packages.

## Quick Decision: Flavor or Overlay?

| I need... | Use | Command |
|-----------|-----|---------|
| Python dev tools (pytest, black, mypy) | **Flavor** | `nyia-claude --flavor python` |
| PHP dev tools (PHPUnit, PHPStan) | **Flavor** | `nyia-claude --flavor php` |
| Node.js dev tools (typescript, biome) | **Flavor** | `nyia-claude --flavor node` |
| React dev tools (vite, storybook) | **Flavor** | `nyia-claude --flavor react` |
| Cypress E2E testing | **Flavor** | `nyia-claude --flavor cypress` |
| React Native/Expo | **Flavor** | `nyia-claude --flavor expo` |
| Something else (custom packages) | **Overlay** | Create Dockerfile, then `--build-custom-image` |

**Rule of thumb:**
- Flavor = ready to use, no build required
- Overlay = custom, requires Docker and building

---

## Part 1: Using Pre-built Flavors

Flavors are specialized images pre-built with common development tools. They're pulled automatically from the registry - no local build required.

### List Available Flavors

```bash
nyia-claude --flavors-list
```

### Current Flavors

| Flavor | Tools Included |
|--------|----------------|
| `python` | pytest, pytest-cov, black, mypy, ruff, isort, ipython |
| `php` | PHP 8.3, Composer, PHPUnit, PHPStan, PHP-CS-Fixer |
| `node` | yarn, pnpm, typescript, @biomejs/biome, vitest, tsx, nodemon |
| `react` | node tools + vite, create-vite, storybook, @testing-library/react |
| `cypress` | Cypress E2E testing with headless Chromium (for AI-assisted testing) |
| `expo` | expo-cli, eas-cli, yarn (React Native with cloud builds) |

### Using a Flavor

```bash
# Python development
nyia-claude --flavor python -p "Write pytest tests for this module"

# PHP development
nyia-claude --flavor php -p "Create PHPUnit tests for UserController"

# Interactive mode with flavor
nyia-claude --flavor python
```

The first time you use a flavor, it will be pulled from the registry automatically.

---

## Part 2: Creating Custom Overlays

If you need packages not included in any flavor, create a custom overlay.

**Requirements:** Docker must be installed.

### Step 1: Create Your Overlay Dockerfile

Choose one of these locations:

| Location | Scope |
|----------|-------|
| `~/.config/nyarlathotia/claude/overlay/Dockerfile` | All your projects |
| `.nyarlathotia/claude/overlay/Dockerfile` | This project only |

**Option A: Start from a template**

```bash
# Create directory
mkdir -p ~/.config/nyarlathotia/claude/overlay/

# Copy a template (if available)
# Templates are in docker/overlay-templates/ in the source distribution
```

**Option B: Write your own**

```bash
mkdir -p ~/.config/nyarlathotia/claude/overlay/

cat > ~/.config/nyarlathotia/claude/overlay/Dockerfile << 'EOF'
ARG BASE_IMAGE
FROM ${BASE_IMAGE}

# Install system packages (as root)
USER root
RUN apt-get update && apt-get install -y \
    your-package \
    another-package \
    && rm -rf /var/lib/apt/lists/*

# Install user packages (as node)
USER node
RUN pip install --no-cache-dir your-python-package
EOF
```

### Step 2: Build Your Custom Image

```bash
nyia-claude --build-custom-image
```

This creates an image named `nyarlathotia-claude-custom`.

### Step 3: Use Your Custom Image

```bash
nyia-claude --image nyarlathotia-claude-custom -p "your prompt"
```

**Note:** You must use `--image` to select your custom image. Without it, the default image is used.

---

## Part 3: Advanced - Overlay on Top of Flavor

If you want a flavor's tools PLUS your own customizations, you can layer an overlay on top of a flavor.

**Use case:** You want Python flavor (pytest, black, mypy) plus some additional packages.

### Step 1: Create Overlay with Flavor as Base

```bash
mkdir -p ~/.config/nyarlathotia/claude/overlay/

cat > ~/.config/nyarlathotia/claude/overlay/Dockerfile << 'EOF'
# Start from Python flavor instead of base
FROM ghcr.io/kaizendofr/nyarlathotia-claude-python:latest

# Python flavor already includes: pytest, black, mypy, ruff, isort, ipython
# Add your extra packages
USER node
RUN pip install --no-cache-dir \
    pandas \
    numpy \
    matplotlib
EOF
```

### Step 2: Build Manually

Since `--build-custom-image` uses the base image, build manually:

```bash
docker build -t nyarlathotia-claude-custom \
  -f ~/.config/nyarlathotia/claude/overlay/Dockerfile .
```

### Step 3: Use Your Custom Image

```bash
nyia-claude --image nyarlathotia-claude-custom -p "Analyze this data with pandas"
```

---

## Overlay Stacking

If you have overlays in both locations, they're applied in order:

1. Base image (from registry)
2. User overlay (`~/.config/nyarlathotia/claude/overlay/`)
3. Project overlay (`.nyarlathotia/claude/overlay/`)

This allows global preferences plus project-specific additions.

---

## Dockerfile Best Practices

### Always Switch Users Properly

```dockerfile
USER root
# Install system packages here
RUN apt-get update && apt-get install -y package

USER node
# Install user packages here
RUN pip install package
```

### Clean Up Package Caches

```dockerfile
RUN apt-get update && apt-get install -y package \
    && rm -rf /var/lib/apt/lists/*
```

### Use --no-cache-dir for pip

```dockerfile
RUN pip install --no-cache-dir package
```

### Don't Override the Entrypoint

The base image has a configured entrypoint. Don't change it unless you know what you're doing.

---

## Troubleshooting

### "Flavor not found"

```
❌ Error: Flavor 'nodejs' not found
```

**Solution:** Check available flavors with `--flavors-list`. Did you mean `node` instead of `nodejs`?

### "Cannot pull image"

```
Error response from daemon: pull access denied
```

**Solutions:**
- Check your network connection
- Try `docker login ghcr.io` if authentication is required
- Verify the image exists: `docker manifest inspect ghcr.io/kaizendofr/nyarlathotia-claude-python:latest`

### Build fails with permission error

```
Permission denied: /some/path
```

**Solution:** Make sure you switch to `USER node` before installing user packages, and `USER root` for system packages.

### Custom image not found

```
Error: No such image: nyarlathotia-claude-custom
```

**Solution:** Did you run `--build-custom-image` or `docker build`? Check with `docker images | grep custom`.

---

## Quick Reference

| Task | Command |
|------|---------|
| List flavors | `nyia-claude --flavors-list` |
| Use Python flavor | `nyia-claude --flavor python` |
| Use PHP flavor | `nyia-claude --flavor php` |
| Build custom overlay | `nyia-claude --build-custom-image` |
| Use custom image | `nyia-claude --image nyarlathotia-claude-custom` |
| Check available images | `nyia-claude --list-images` |

---

## See Also

- [Overlay Templates](../docker/overlay-templates/README.md) - Ready-to-use Dockerfile templates
- [Flavor System](flavor-system.md) - Technical details about flavor naming and validation
