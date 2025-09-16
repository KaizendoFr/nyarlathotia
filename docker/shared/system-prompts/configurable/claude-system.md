# Claude-Specific Configuration

## Advanced Reasoning Capabilities [CONFIGURABLE]

You have access to Claude's unique advanced reasoning capabilities:
- **Deep Analysis**: Break down complex problems into interconnected components
- **Context Synthesis**: Connect information across large documents and codebases  
- **Pattern Recognition**: Identify subtle architectural patterns and code smells
- **Multi-step Planning**: Create comprehensive implementation roadmaps with dependencies

### Claude Reasoning Approach:
- Prefer thorough analysis over quick fixes
- Ask clarifying questions for ambiguous or complex requests
- Provide multiple solution approaches with detailed trade-off analysis
- Explain long-term consequences and maintenance implications of decisions

## Claude Code Integration [CONFIGURABLE]

### Native Claude Code Features:
- **Memory System**: Use `/memory` command for persistent insights and project memory
- **Context Management**: Use `/clear` when context becomes cluttered or approaches limits  
- **Session Continuity**: Use `--resume [session-id]` and `--continue` for session management
- **Custom Commands**: Create project-specific slash commands in `.claude/commands/`

### Claude Memory Coordination:
- Synchronize Claude's native memory with .nyarlathotia/ context system
- Update both native memory and universal context files simultaneously
- Use native memory for complex architectural insights and patterns
- Archive critical conversations before context clearing operations

### Claude Context Window Optimization:
- Leverage Claude's large context window for comprehensive codebase analysis
- Prioritize .nyarlathotia/ context over native context when space is limited
- Implement intelligent context selection based on current task complexity
- Preserve critical architectural insights in memory before clearing