# NyarlathotIA on macOS

Quick setup guide for Apple/macOS users.

## Quick Install (Recommended)

The macOS installer handles everything automatically - Docker detection, installation guidance, and PATH configuration:

```bash
curl -fsSL https://raw.githubusercontent.com/KaizendoFr/nyarlathotia/main/scripts/install-macos.sh | bash
```

The installer will:
1. Check your macOS version (requires 13 Ventura or newer)
2. Detect if Docker Desktop is installed and running
3. Guide you through Docker installation if needed (Homebrew or direct download)
4. Check for Bash 4+ and offer to install via Homebrew if missing
5. Download and install NyarlathotIA
6. Configure your PATH automatically (detects zsh vs bash)

### Beginner Guide

If you're new to Terminal:

1. **Open Terminal**: Press `Cmd+Space`, type "Terminal", press Enter
2. **Copy the command above** (triple-click to select the whole line)
3. **Paste in Terminal**: Press `Cmd+V`, then Enter
4. **Follow the prompts** - the installer will guide you

After installation, **close Terminal and open a new window** for the PATH changes to take effect.

---

## Alternative Installation Methods

### Option 1: Standard Installer
```bash
curl -fsSL https://raw.githubusercontent.com/KaizendoFr/nyarlathotia/main/install.sh | bash
```

**Note**: This requires Docker Desktop to already be installed and running.

### Option 2: Manual Install
```bash
# Clone the repository
git clone https://github.com/KaizendoFr/nyarlathotia.git ~/.local/lib/nyarlathotia

# Add to PATH (add to ~/.zshrc for persistence)
export PATH="$HOME/.local/lib/nyarlathotia/bin:$PATH"

# Make scripts executable
chmod +x ~/.local/lib/nyarlathotia/bin/nyia*
```

---

## Prerequisites (if not using macOS installer)

1. **Bash 4.0 or newer** (macOS ships Bash 3.2 which is too old)
   ```bash
   # Install via Homebrew
   brew install bash

   # Verify version (should show 5.x)
   /opt/homebrew/bin/bash --version
   ```
   The macOS installer handles this automatically if Homebrew is available.

2. **Docker Desktop for Mac**
   - Download from: https://docs.docker.com/desktop/mac/install/
   - Or via Homebrew: `brew install --cask docker`
   - Start Docker Desktop from Applications

3. **Verify Docker is running**
   ```bash
   docker info
   ```

> **Note**: Maintainer packaging scripts (`preprocess-runtime.sh`, `release.sh`, etc.)
> are Linux-only workflow tools and are not needed on macOS end-user systems.

## First Run

```bash
# Check installation
nyia list

# Check Claude status
nyia-claude --status

# Authenticate (one-time)
nyia-claude --login
```

## macOS-Specific Notes

### Docker Desktop Differences

NyarlathotIA automatically detects macOS and adjusts:

| Feature | Linux | macOS |
|---------|-------|-------|
| Network mode | `--network host` | Bridge (default) |
| User mapping | `--user $(id -u):$(id -g)` | Docker Desktop handles |
| Ollama access | `localhost:11434` | `host.docker.internal:11434` |

### File Permissions

Docker Desktop for Mac handles file permissions differently than Linux:
- No need for user ID mapping
- Files created in container are accessible on host
- No `sudo` required for most operations

### Ollama for RAG (Optional)

If you want codebase search (RAG):

```bash
# Install Ollama
brew install ollama

# Start Ollama service
ollama serve

# Pull embedding model
ollama pull nomic-embed-text

# Configure in assistant config
echo "NYIA_RAG_MODEL=nomic-embed-text" >> ~/.config/nyarlathotia/claude.conf

# Use RAG
nyia-claude --rag -p "Search for authentication code"
```

## Quick Test

```bash
# Navigate to any git project
cd ~/your-project

# Run Claude with a prompt
nyia-claude -p "Explain the structure of this project"

# Or start interactive shell
nyia-claude --shell
```

## Troubleshooting

### "Docker is not running"
- Open Docker Desktop from Applications
- Wait for it to fully start (whale icon in menu bar stops animating)

### "Cannot connect to Docker daemon"
```bash
# Check Docker Desktop is running
open -a Docker

# Wait a few seconds, then retry
docker info
```

### Slow First Run
- First run pulls Docker images (~1-2GB)
- Subsequent runs are fast (images cached)

### Permission Denied on Scripts
```bash
chmod +x ~/.local/lib/nyarlathotia/bin/nyia*
```

### Apple Silicon (M1/M2/M3)
- Docker Desktop supports Apple Silicon natively
- Images are multi-arch (amd64 + arm64)
- No special configuration needed

## Common Commands

```bash
# List assistants
nyia list

# Use specific assistant
nyia-claude -p "your prompt"
nyia-gemini -p "your prompt"
nyia-vibe -p "your prompt"

# Check status
nyia-claude --status

# Use language flavor
nyia-claude --flavor python -p "Write pytest tests"
nyia-claude --flavor react -p "Create a React component"

# Debug mode
nyia-claude --verbose -p "your prompt"

# Interactive shell
nyia-claude --shell
```

## Uninstall

To remove NyarlathotIA:

```bash
# Remove installed files
rm -rf ~/.local/lib/nyarlathotia
rm -f ~/.local/bin/nyia*

# Optional: Remove PATH from shell config
# Edit ~/.zshrc (or ~/.bash_profile) and remove the line:
#   export PATH="$HOME/.local/bin:$PATH"
# Only do this if you don't use ~/.local/bin for other tools

# Optional: Remove Docker Desktop
# Open Finder → Applications → Docker → Move to Trash
# Or: brew uninstall --cask docker
```

## Support

- Issues: https://github.com/KaizendoFr/nyarlathotia/issues
- Docs: https://github.com/KaizendoFr/nyarlathotia/tree/main/docs
