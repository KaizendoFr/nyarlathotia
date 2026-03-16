# Team Sharing - Shared Resources Across Machines

Nyia Keeper supports a **team directory** for sharing skills, agents, prompts, and configuration across multiple machines or team members. The team directory is a regular folder on disk (synced via git, Dropbox, NFS, or any other mechanism you choose).

## Quick Start

1. Create a shared directory with the expected structure:

```bash
mkdir -p /path/to/team-shared/{skills,agents,prompts,config}
```

2. Configure Nyia Keeper to use it:

```bash
nyia config global team_dir=/path/to/team-shared
```

3. Verify it works:

```bash
nyia status           # Shows team directory info
nyia-claude --list-skills   # Team skills appear under "Team skills"
nyia-claude --list-agents   # Team agents appear under "Team agents"
```

## Directory Structure

The team directory follows the same layout as `.nyiakeeper/shared/`:

```
/path/to/team-shared/
├── skills/              # Shared skills (each needs SKILL.md)
│   ├── code-review/
│   │   └── SKILL.md
│   └── pair-review/
│       └── SKILL.md
├── agents/              # Shared agent personas
│   ├── reviewer.md      # Claude agent (Markdown)
│   └── architect.md
├── prompts/             # Shared prompt overlays
│   └── team-guidelines.md
└── config/              # Shared configuration
    └── team-defaults.conf
```

### Skills

Each skill is a subdirectory containing a `SKILL.md` file. Skills are automatically discovered and listed by `--list-skills`. They are propagated to each assistant's project directory at launch (no-clobber: existing project skills take precedence).

### Agents

Agent personas are assistant-specific files placed directly in the `agents/` directory. File formats vary by assistant:

| Assistant | Format | Example |
|-----------|--------|---------|
| Claude | `*.md` | `reviewer.md` |
| OpenCode | `*.md`, `*.json` | `architect.md` |
| Vibe | `*.toml` | `debugger.toml` |
| Codex | Config-based | (uses `~/.codex/config.toml` sections) |
| Gemini | Not yet supported | -- |

### Prompts

Prompt overlays placed in `prompts/` are propagated to each assistant at launch. Use these for team-wide coding guidelines, review checklists, or domain-specific instructions.

### Config

Configuration files in `config/` provide team-level defaults. These are safe-parsed (no secrets -- values are read as plain key=value pairs).

## Precedence

Resources are resolved in strict precedence order. Higher-precedence sources win:

```
1. Project-local    (.claude/skills/, .claude/agents/, etc.)
2. Project-shared   (.nyiakeeper/shared/skills/, etc.)
3. Team             (team_dir/skills/, team_dir/agents/, etc.)
4. Global user      (~/.config/nyiakeeper/skills/, etc.)
```

This means:
- A project-local skill named `code-review` shadows a team skill with the same name.
- A project-shared agent named `reviewer` shadows a team agent with the same name.
- Team resources shadow global user resources.

## Configuration

### Setting the team directory

```bash
# Set for all projects (global config)
nyia config global team_dir=/path/to/team-shared

# View current configuration
nyia config global --list
```

The key is stored as `NYIA_TEAM_DIR` in `~/.config/nyiakeeper/config/nyia.conf`.

### Checking team status

```bash
nyia status
```

This shows:
- Whether a team directory is configured
- Whether the directory exists on disk
- Which subdirectories are present (skills, agents, prompts, config)

## Security

- Team configuration is **safe-parsed**: no shell expansion, no command execution.
- The team directory is read-only from Nyia Keeper's perspective -- it never writes to it.
- No secrets or credentials should be placed in the team directory.
- Team config values go through the same sanitization as all other config sources.

## Sync Strategies

Nyia Keeper does not manage synchronization of the team directory. Common approaches:

| Strategy | Pros | Cons |
|----------|------|------|
| Git repository | Version history, PR review | Requires git workflow |
| Dropbox/Google Drive | Automatic sync, no setup | No version control |
| NFS/SMB mount | Real-time access | Requires network infrastructure |
| Symlink to monorepo subdirectory | Zero-copy, always current | Ties to monorepo |

## Troubleshooting

### "Team dir configured but does not exist"

The path in your config does not exist on disk. Check:
```bash
nyia config global --list   # Verify the path
ls -la /path/to/team-shared # Check if directory exists
```

### "Team dir configured but has no content"

The directory exists but contains none of the expected subdirectories (`skills/`, `agents/`, `prompts/`, `config/`). Create at least one:
```bash
mkdir -p /path/to/team-shared/skills
```

### Team skills/agents not appearing

1. Verify the team directory is configured: `nyia config global --list`
2. Check that skills have a `SKILL.md` file in their subdirectory
3. Check that agent files use the correct format for your assistant
4. Check precedence: a project-local resource with the same name takes priority
