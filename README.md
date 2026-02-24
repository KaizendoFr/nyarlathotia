# Nyia Keeper Multi-Assistant Infrastructure

Containerized environment for AI development assistants. Supporting Claude, Gemini, Codex, OpenCode, and Vibe.

## 🚀 Quick Start

```bash
# Install
curl -fsSL https://raw.githubusercontent.com/KaizendoFr/nyia-keeper/main/install.sh | bash

# Setup (choose your assistant)
nyia-claude --login

# Use in interactive mode
nyia-claude
```

**→ [Complete Quick Start Guide](QUICKSTART.md)** ← *2 minute setup*

## Prerequisites

- **Docker**: Required for running assistants in isolated containers
- **Git**: For branch and context management
- **API Key**: From your chosen AI provider (Anthropic, Google, OpenAI, etc.)

## Supported Assistants

| Assistant | Description | Command |
|-----------|-------------|---------|
| **Claude** | Anthropic's advanced reasoning & coding assistant | `nyia-claude` |
| **Gemini** | Google's multimodal AI (text, images, code) | `nyia-gemini` |
| **Codex** | OpenAI's code-focused assistant | `nyia-codex` |
| **OpenCode** | Open-source local AI assistant | `nyia-opencode` |
| **Vibe** | Lightweight AI for quick tasks | `nyia-vibe` |

## Key Features

- **Docker Isolation**: Each assistant runs in its own secure container
- **Exclusion Lists**: Control which files/directories AI can access
- **Git Awareness**: Automatic branch and context management
- **Multi-Project**: Work across different codebases seamlessly
- **Flavors**: Pre-configured environments (Python, Node, PHP, React, etc.)

## Get Help

```bash
nyia list                    # List available assistants
nyia-claude --help           # Detailed usage
nyia-claude --status         # Check configuration
```

## Links

- **[Quick Start Guide](QUICKSTART.md)** - Get running in 2 minutes
- **[GitHub Issues](https://github.com/KaizendoFr/nyia-keeper/issues)** - Bug reports & feature requests
- **[GitHub Discussions](https://github.com/KaizendoFr/nyia-keeper/discussions)** - Community help

---

Licensed under AGPL-3.0. See [LICENSE](LICENSE) for details.
