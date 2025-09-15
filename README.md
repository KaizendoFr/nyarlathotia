# NyarlathotIA Multi-Assistant Infrastructure

It’s a jail for AI development tools. Supporting the CLIs of Claude, Gemini, Codex, and OpenCode assistants.

## 🚀 Quick Start

```bash
# Install
curl -fsSL https://raw.githubusercontent.com/KaizendoFr/nyarlathotia/main/install.sh | bash

# Setup
nyia-claude --login

# Use
nyia-claude -p "Create a Python script with tests"
```

**→ [Complete Quick Start Guide](QUICK-START.md)** ← *2 minute setup*

## Supported Assistants

| Assistant | Strength | Setup |
|-----------|----------|--------|
| **Claude** | Advanced reasoning & coding | `nyia-claude --login` |
| **Gemini** | Multimodal AI (text, images) | `nyia-gemini --login` |
| **Codex** | Code generation specialist | `nyia-codex --setup` |
| **OpenCode** | Self-hosted intelligence | `nyia-opencode --setup` |

## Key Features

- **Docker Integration**: Isolated environments
- **Exclusion list**: Directories and files that you don’t want to share with the AI
- **Git Awareness**: Automatic branch and context management
- **Multi-Project**: Work across different codebases seamlessly

## Get Help

```bash
nyia list                    # Available assistants
nyia-claude --help           # Detailed usage
nyia-claude --status         # Configuration check
```

## Links

- **[Quick Start Guide](QUICK-START.md)** - Get running in 2 minutes
- **[GitHub Issues](https://github.com/KaizendoFr/nyarlathotia/issues)** - Bug reports & requests
- **[GitHub Discussions](https://github.com/KaizendoFr/nyarlathotia/discussions)** - Community help

---
