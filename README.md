# NyarlathotIA Multi-Assistant Infrastructure

It’s a jail for AI development tools. Supporting the CLIs of Claude, Gemini, Codex, and OpenCode.

## 🚀 Quick Start

```bash
# Install
curl -fsSL https://raw.githubusercontent.com/KaizendoFr/nyarlathotia/main/install.sh | bash

# Setup
nyia-claude --login

# Use in interactive mode
nyia-claude
```

**→ [Complete Quick Start Guide](QUICK-START.md)** ← *2 minute setup*

## Supported Assistants

| Assistant | Strength | Setup |
|-----------|----------|--------|
| **Claude** | Advanced reasoning & coding | `nyia-claude` |
| **Gemini** | Multimodal AI (text, images) | `nyia-gemini` |
| **Codex** | Code generation specialist | `nyia-codex` |
| **OpenCode** | Self-hosted intelligence | `nyia-opencode` |

## Key Features

- **Docker Integration**: Isolated environments
- **Exclusion list**: Directories and files that you don’t want to share with the AI
- **Git Awareness**: Automatic branch and context management, manual control is possible
- **Multi-Project**: Work across different codebases seamlessly

## Get Help

```bash
nyia list                    # Available assistants
nyia-codex --help           # Detailed usage
nyia-codex --status         # Configuration check
```

## Links

- **[Quick Start Guide](QUICK-START.md)** - Get running in 2 minutes
- **[GitHub Issues](https://github.com/KaizendoFr/nyarlathotia/issues)** - Bug reports & requests
- **[GitHub Discussions](https://github.com/KaizendoFr/nyarlathotia/discussions)** - Community help

---
