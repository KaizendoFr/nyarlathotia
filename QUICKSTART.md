# NyarlathotIA Quick Start

Get up and running with AI-powered development assistants in a leash in under 2 minutes.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/KaizendoFr/nyarlathotia/main/install.sh | bash
```

## Choose Your Assistant

```bash
nyia list                    # Show available assistants
```

Available options: `claude`, `gemini`, `codex`, `opencode`, `vibe`

## Setup Authentication

**Claude (Recommended):**
```bash
nyia-claude --login          # Follow prompts to authenticate
nyia-claude --status         # Verify setup
```

**Gemini:**
```bash
nyia-gemini --login          # OAuth setup
```

**Codex:**
```bash
nyia-codex --setup           # API key setup
```

**Vibe (Mistral AI):**
```bash
export MISTRAL_API_KEY="your-api-key"  # Get key from console.mistral.ai
nyia-vibe --status                      # Verify setup
```

## Start Coding

```bash
# Interactive session
nyia-claude

# Direct prompt
nyia-claude -p "Create a Python script with tests"

# Work in specific directory  
nyia-claude --path /your/project -p "Add error handling"
```

## Branch Management

By default, NyarlathotIA creates timestamped branches for your work:

```bash
nyia-claude                    # Creates: claude-2026-01-11-143052
```

For named branches:

```bash
# Create a named branch
nyia-claude --work-branch feature/my-feature --create

# Resume existing branch
nyia-claude --work-branch feature/my-feature
```

See [docs/BRANCH_MANAGEMENT.md](docs/BRANCH_MANAGEMENT.md) for detailed workflows.

## Power User Features

```bash
# Custom image overlays
mkdir -p ~/.config/nyarlathotia/claude/overlay
cat > ~/.config/nyarlathotia/claude/overlay/Dockerfile << 'EOF'
FROM ghcr.io/kaizendofr/nyarlathotia-claude:latest
RUN apt-get update && apt-get install -y python3-dev build-essential
EOF

nyia-claude --build-custom-image
```

## Troubleshooting

**Docker Issues:**
```bash
# Check Docker is running
docker --version
sudo systemctl start docker    # Linux
```

**Authentication Problems:**
```bash
# Reset credentials
rm -rf ~/.config/nyarlathotia/creds/
nyia-claude --login
```

**Permission Errors:**
```bash
# Fix Docker permissions (Linux)
sudo usermod -aG docker $USER
newgrp docker
```

## What's Next?

- **Full Documentation**: [GitHub Repository](https://github.com/KaizendoFr/nyarlathotia)
- **Advanced Usage**: `nyia-claude --help`
- **Custom Overlays**: Check `~/.config/nyarlathotia/claude/overlay/`

---

*Runtime distribution - optimized for production deployment*