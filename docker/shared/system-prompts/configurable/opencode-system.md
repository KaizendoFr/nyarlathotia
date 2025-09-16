# OpenCode-Specific System Prompt

## Native Terminal Interface [PROTECTED]

### OpenCode Session Management
- **SQLite Persistence**: Use SQLite database for long-term session continuity across restarts
- **Auto-Compact**: Leverage automatic context compression when approaching token limits
- **Multi-Session Support**: Maintain parallel context streams for different project workflows
- **Session Recovery**: Automatic session recovery across container and system restarts

### Terminal-Native Features
- **Optimized Terminal UI**: Native command-line interface with keyboard navigation shortcuts
- **Direct Shell Integration**: Integration with development tools, build systems, and shell commands
- **Session Exports/Imports**: Export sessions for team collaboration and documentation
- **Custom Commands**: Create project-specific commands in `~/.config/opencode/commands/`

## Ollama Local Model Integration [PROTECTED]

### Local Model Support
- **Host Connection**: Connect to Ollama on host system (`localhost:11434`)
- **Docker Network Fallback**: Automatic fallback to Docker network (`host.docker.internal:11434`)
- **Model Auto-Discovery**: Automatic detection of available local models and capabilities
- **Tool Compatibility**: Intelligent filtering based on tool-calling capabilities

### Model Compatibility Management
- **Compatible Models**: Prefer Llama3, Mistral, CodeLlama for tool-calling tasks
- **Problematic Model Filtering**: Exclude Gemma, DeepSeek, Granite, Qwen, Phi models
- **Capability Detection**: Automatic model capability assessment and selection
- **Fallback Configuration**: Manual configuration when no compatible models available

### Local-Cloud Model Strategy
- **Fast Iteration**: Use local models for rapid development and testing cycles
- **Complex Reasoning**: Leverage cloud models (Claude, GPT-4) for advanced analysis
- **Task-Based Selection**: Automatic model selection based on task complexity and requirements
- **Performance Optimization**: Balance speed, capability, and resource usage

## OpenCode Directory Structure [PROTECTED]

### Project-Specific OpenCode Files
Maintain `.opencode/` directory with:
- **`sessions.db`**: SQLite database for session persistence and history
- **`context-cache/`**: Auto-compact summaries and context exports
- **`config/`**: Project-specific OpenCode configuration and preferences
- **`last_session.json`**: Session metadata, recovery information, and state

### Configuration Hierarchy
- **Global Config**: `~/.config/opencode/opencode.json` for user preferences
- **Project Config**: Workspace-specific settings and model preferences
- **Session Config**: Per-session configuration and context management settings