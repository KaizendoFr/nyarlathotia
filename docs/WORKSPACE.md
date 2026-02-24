# Workspace Mode - Multi-Repository Support

Workspace mode allows a single Nyia Keeper session to work across multiple related repositories simultaneously.

## Quick Start

1. Create a workspace configuration file:
```bash
mkdir -p .nyiakeeper
cat > .nyiakeeper/workspace.conf << 'EOF'
# Paths to additional repositories (one per line)
~/projects/shared-library
~/projects/api-client
/absolute/path/to/another-repo
EOF
```

2. Run any assistant - workspace mode is auto-detected:
```bash
nyia-claude -p "Help me integrate the shared-library into this project"
```

## Configuration File Format

The `.nyiakeeper/workspace.conf` file uses a simple line-based format:

```
# Comments start with #
~/projects/repo1          # Tilde expansion supported
/absolute/path/to/repo2   # Absolute paths work
../relative/repo3         # Relative paths work (resolved from workspace root)

# Empty lines are ignored
```

### Requirements for Listed Repositories
- Each path must be a valid directory
- Each directory must be a git repository (contains `.git/`)
- The workspace cannot list itself (self-reference check)
- Symlinks are automatically resolved to canonical paths

## How It Works

### Container Mount Structure

When workspace mode is active:
```
/project/{workspace-hash}/           # Main workspace (your current directory)
/project/{workspace-hash}/repos/     # Additional repositories
    ├── shared-library-a1b2c3d4/     # Repo 1 (with hash suffix)
    ├── api-client-e5f6g7h8/         # Repo 2 (with hash suffix)
    └── another-repo-i9j0k1l2/       # Repo 3 (with hash suffix)
```

The hash suffix prevents collisions when multiple repos have the same basename.

### Branch Naming

Branch names follow the standard format: `{assistant}-{timestamp}`
- Example: `claude-2025-01-15-143025`

The same branch name is used across all repositories in the workspace, making it easy to identify related work.

### Exclusions

Each repository can have its own exclusions:
```
repo1/.nyiakeeper/exclusions.conf   # Applied to repo1 mount
repo2/.nyiakeeper/exclusions.conf   # Applied to repo2 mount
workspace/.nyiakeeper/exclusions.conf  # Applied to main workspace
```

Built-in security exclusions (`.env`, `.key`, `.pem`, etc.) are applied to all mounts.

## Limitations

### RAG (Codebase Search)
RAG is automatically disabled in workspace mode. Multi-repository indexing is not yet supported. You'll see a warning:
```
Warning: RAG disabled in workspace mode (multi-repo indexing not yet supported)
         Workspace contains 3 additional repositories
```

### Git Operations
- Git operations in the container target the main workspace only
- Each additional repo maintains its own git state
- Commits made by the assistant go to the workspace repo

### Branch Synchronization
When you start a workspace session, Nyia Keeper:
1. Captures the current branch of all repositories (main + workspace repos)
2. Creates the work branch on the main project (e.g., `claude-2025-01-15-143025`)
3. **Automatically creates the same branch on ALL workspace repositories**

This ensures all repos in your workspace are on the same branch, making coordinated work easier.

#### Atomic Rollback
If branch creation fails on any repository:
- All repositories are rolled back to their original branches
- The work branch is deleted from any repos where it was created
- You'll see an error message indicating which repo failed and why

Common failure reasons:
- Uncommitted changes in a workspace repo (commit or stash first)
- Inaccessible repository path
- Branch already exists with conflicts

#### Explicit Branch Names
Use `--work-branch` to specify the branch name:
```bash
nyia-claude --work-branch feature/my-feature
```
This branch will be created on ALL repos in the workspace.

## Status Display

When workspace mode is active, the status display shows:
```
Git Status
  Branch: claude-2025-01-15-143025
  Commits: 42
  Changes: Clean working directory
  Mode: Workspace (3 additional repos - all synced to same branch)
```

The "all synced to same branch" indicator confirms that branch synchronization completed successfully for all workspace repositories.

## Use Cases

### Monorepo Alternative
Work on related packages without a monorepo structure:
```
# workspace.conf
~/packages/ui-components
~/packages/api-client
~/packages/shared-types
```

### Cross-Project Refactoring
Make coordinated changes across multiple projects:
```
# workspace.conf
~/services/auth-service
~/services/user-service
~/libs/common-utils
```

### Documentation with Code
Keep docs and code together:
```
# workspace.conf
~/company-wiki
~/api-documentation
```

## Troubleshooting

### "Workspace repo not found"
The specified path doesn't exist. Check the path in `workspace.conf`.

### "Workspace repo is not a git repository"
The directory exists but isn't a git repo. Run `git init` in that directory.

### "Workspace cannot include itself"
Remove the current directory from `workspace.conf` - it's already the main workspace.

### Repos with Same Name
If you have multiple repos named `app/`:
```
~/project-a/app    →  /project/.../repos/app-a1b2c3d4/
~/project-b/app    →  /project/.../repos/app-e5f6g7h8/
```
The hash suffix ensures unique container paths.

### "Failed to sync branches across workspace repositories"
Branch synchronization failed. Common causes:
- **Uncommitted changes**: Commit or stash changes in the failing repo
- **Inaccessible repo**: Check the path exists and is readable
- **Permission issues**: Ensure you have write access to create branches

All repos will be rolled back to their original branches when this happens.

## Best Practices

1. **Keep workspace.conf in version control** - Share the workspace setup with your team
2. **Use absolute or home-relative paths** - More reliable than relative paths
3. **Group related repos only** - Don't include unrelated projects
4. **Consider security** - Excluded files in one repo don't affect another
5. **Document the workspace** - Add comments explaining why each repo is included
