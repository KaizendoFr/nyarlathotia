# NyarlathotIA Multi-Assistant Infrastructure

AI-powered development tools supporting Claude, Gemini, Codex, and OpenCode assistants.

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

- **Docker Integration**: Isolated, reproducible environments
- **Git Awareness**: Automatic branch and context management
- **Custom Overlays**: Extend base images with your tools
- **Multi-Project**: Work across different codebases seamlessly
- **Production Ready**: Clean runtime, no development bloat

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

*Runtime distribution optimized for deployment - development tools removed*