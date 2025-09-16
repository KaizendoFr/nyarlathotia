# Gemini-Specific Configuration

## Memory and Context Management [CONFIGURABLE]

### Gemini Native Memory System:
- **Context File**: GEMINI.md is automatically loaded from `/workspace/.nyarlathotia/gemini/` on startup
- **Memory Function**: Use `save_memory(fact="...")` to persist important facts across sessions
- **Session Continuity**: All saved memories will be available in subsequent CLI sessions
- **Automatic Loading**: Context is loaded via `loadMemoryFromIncludeDirectories` configuration

### Memory Usage Guidelines:
- **Save Key Insights**: Use `save_memory()` for architectural decisions, patterns, and important discoveries
- **Project Understanding**: Store project-specific knowledge like frameworks, conventions, and dependencies
- **Session Bridge**: Save current work state and next steps for seamless session resumption
- **Concise Facts**: Keep memories brief and focused - this is for important facts, not conversation history

### Example Memory Operations:
```
save_memory(fact="Project uses TypeScript with strict mode enabled")
save_memory(fact="Authentication handled via OAuth2 with JWT tokens")
save_memory(fact="Database migrations use Prisma ORM")
save_memory(fact="Current focus: Implementing user permissions system")
```

## Large-Scale Processing Capabilities [CONFIGURABLE]

### Massive Context Window Advantages:
- **1M+ Token Context**: Process entire codebases in single operations
- **Holistic Codebase Analysis**: Analyze multiple files and their interdependencies simultaneously
- **Cross-Reference Detection**: Find complex patterns and relationships across large codebases
- **System-Wide Architecture Understanding**: Maintain awareness of complete project structure

### Gemini Large-Context Approach:
- Leverage massive context window for comprehensive multi-file analysis
- Process entire repository structures in single operations
- Identify system-wide architectural patterns and dependencies
- Provide holistic insights that smaller context windows cannot achieve

## Multimodal Capabilities [CONFIGURABLE]

### Visual Processing:
- **Diagram Analysis**: Process architectural diagrams, flowcharts, and system designs
- **UI/UX Analysis**: Analyze mockups, screenshots, and visual design files
- **Technical Graphics**: Interpret charts, graphs, network diagrams, and technical drawings
- **Code Visualization**: Extract information from code screenshots and visual documentation

### Multimodal Integration Workflow:
- Request visual context when beneficial for complex architectural understanding
- Generate visual explanations for complex system relationships
- Analyze existing visual documentation alongside code
- Create multimodal explanations combining text, code, and visual elements

## Google Cloud Integration [CONFIGURABLE]

### Native Google Platform Features:
- **Vertex AI Integration**: Leverage Google's AI platform capabilities and models
- **Google Cloud Services**: Optimize for GCP services, APIs, and infrastructure patterns
- **Google Workspace Integration**: Handle enterprise Google Workspace environments
- **Regional and Enterprise Features**: Support Google Cloud regional requirements and enterprise configurations

### Google Authentication Methods:
- **OAuth Integration**: Native Google OAuth flow support
- **Service Accounts**: Google Cloud service account authentication
- **API Key Management**: Google API key handling and rotation
- **Vertex AI Authentication**: Specialized Vertex AI credential management

## Session Persistence Reminder [PROTECTED]

### IMPORTANT - Memory Usage:
At the end of each work session or after discovering important information:
1. **Save Project Insights**: Use `save_memory()` for architectural patterns, dependencies, and conventions
2. **Update Work State**: Save current focus and next steps for session continuity
3. **Document Decisions**: Record important technical decisions with rationale
4. **Track Progress**: Note completed work and remaining tasks

Remember: Your GEMINI.md file in `/workspace/.nyarlathotia/gemini/` persists across sessions. Use it!