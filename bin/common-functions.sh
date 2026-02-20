#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR Proprietary
# Copyright (c) 2024 NyarlathotIA Contributors

# NyarlathotIA - Common Functions for Multi-Assistant Infrastructure
# Shared utilities for all AI assistants in the NyarlathotIA ecosystem

set -e

# macOS ships Bash 3.2 — auto-detect and re-exec under Homebrew Bash 5.x if needed
if [ "${BASH_VERSINFO[0]}" -lt 4 ] && [ -z "${_NYIA_BASH_REEXEC:-}" ]; then
    for _brew_bash in /opt/homebrew/bin/bash /usr/local/bin/bash; do
        if [ -x "$_brew_bash" ]; then
            export _NYIA_BASH_REEXEC=1
            exec "$_brew_bash" "$0" "$@"
        fi
    done
    echo "Error: Bash 4.0+ required. Current version: ${BASH_VERSION}" >&2
    echo "Install modern Bash with: brew install bash" >&2
    exit 1
fi
unset _NYIA_BASH_REEXEC

# Standard bash 4.0+ features used throughout

# === MOUNT EXCLUSIONS INTEGRATION ===
# Load mount exclusions library if available

# Runtime configuration (always present in dist)
_exclusions_lib="$HOME/.local/lib/nyarlathotia/mount-exclusions.sh"
if [[ -f "$_exclusions_lib" ]]; then
    source "$_exclusions_lib"
fi
_workspace_lib="$HOME/.local/lib/nyarlathotia/workspace.sh"
if [[ -f "$_workspace_lib" ]]; then
    source "$_workspace_lib"
fi
# Runtime doesn't need mount-exclusions.conf - that's a dev feature

# Development override (removed in dist)

# Load shared utility functions (runtime path)
if [[ -f "$HOME/.local/bin/common/shared.sh" ]]; then
    source "$HOME/.local/bin/common/shared.sh"
fi

# Load input validation functions for security
if [[ -f "$HOME/.local/lib/nyarlathotia/input-validation.sh" ]]; then
    source "$HOME/.local/lib/nyarlathotia/input-validation.sh"
fi

# Platform-aware Docker user mapping
get_docker_user_args() {
    if is_macos; then
        # On macOS with Docker Desktop, use default user mapping
        # Docker Desktop handles file permissions differently
        echo ""
    else
        # On Linux, preserve host user mapping
        echo "--user $(id -u):$(id -g)"
    fi
}

# Platform-aware Docker network configuration
get_docker_network_args() {
    if is_macos; then
        # On macOS, --network host is not supported in Docker Desktop
        # Use default bridge network
        echo ""
    else
        # On Linux, use host networking for direct access
        echo "--network host"
    fi
}

# Docker availability and setup validation
check_docker_availability() {
    if ! command -v docker >/dev/null 2>&1; then
        print_error "Docker is not installed"
        if is_macos; then
            print_info "Install Docker Desktop for Mac from: https://docs.docker.com/desktop/mac/install/"
        elif is_linux; then
            local pkg_mgr=$(detect_package_manager)
            case "$pkg_mgr" in
                apt) print_info "Install with: sudo apt update && sudo apt install docker.io" ;;
                yum|dnf) print_info "Install with: sudo $pkg_mgr install docker" ;;
                pacman) print_info "Install with: sudo pacman -S docker" ;;
                *) print_info "Install Docker from: https://docs.docker.com/engine/install/" ;;
            esac
        fi
        return 1
    fi
    
    if ! docker info >/dev/null 2>&1; then
        print_error "Docker is not running"
        if is_macos; then
            print_info "Start Docker Desktop application"
            print_info "Or check if Docker Desktop is installed and running in Applications"
        elif is_linux; then
            print_info "Start Docker service: sudo systemctl start docker"
            print_info "Enable Docker service: sudo systemctl enable docker"
        fi
        return 1
    fi
    
    return 0
}

# === CONFIGURATION ===
ensure_directory_exists() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir" || {
            print_error "Cannot create directory: $dir"
            return 1
        }
    fi
}

# Generate commented config from example file
generate_commented_config() {
    local example_file="$1"
    local target_file="$2"
    
    if [[ ! -f "$example_file" ]]; then
        return 1
    fi
    
    # Read the example file and enhance with comments
    {
        echo "# Auto-generated config - customize as needed"
        echo "# Generated on $(date)"
        echo "# Based on: $(basename "$example_file")"
        echo ""
        
        while IFS= read -r line; do
            # Skip existing comment-only lines at the top
            if [[ "$line" =~ ^[[:space:]]*# ]] && [[ ! "$line" =~ ^#[[:space:]]*=== ]]; then
                echo "$line"
            elif [[ "$line" =~ ^[[:space:]]*$ ]]; then
                echo "$line"
            elif [[ "$line" =~ ^[[:space:]]*([A-Z_]+)= ]]; then
                # Add inline comment for config values
                local var_name=$(echo "$line" | sed 's/^[[:space:]]*\([A-Z_]*\)=.*/\1/')
                case "$var_name" in
                    ASSISTANT_NAME)
                        echo "$line  # Assistant identifier"
                        ;;
                    BASE_IMAGE_NAME)
                        echo "$line  # Docker image name"
                        ;;
                    ALLOW_DEV_IMAGES)
                        echo "$line  # Enable branch-specific development images"
                        ;;
                    AUTH_METHOD)
                        echo "$line  # Authentication method (oauth2, api_key, etc.)"
                        ;;
                    *)
                        echo "$line"
                        ;;
                esac
            else
                echo "$line"
            fi
        done < "$example_file"
        
        echo ""
        echo "# === ADVANCED OPTIONS ==="
        echo "# Uncomment and modify these for custom setups:"
        echo "# CUSTOM_ENTRYPOINT=\"/custom/entrypoint.sh\""
        echo "# ADDITIONAL_ENV_VARS=\"KEY1=value1,KEY2=value2\""
        echo "# MEMORY_LIMIT=\"2g\""
        echo "# CPU_LIMIT=\"1.0\""
        echo ""
        echo "# For more options, see: $(basename "$example_file")"
        
    } > "$target_file"
}

# Validate assistant configuration file
validate_config() {
    local config_file="$1"
    local required_fields=("ASSISTANT_NAME" "ASSISTANT_CLI" "BASE_IMAGE_NAME" "DOCKERFILE_PATH" "CONTEXT_DIR_NAME")

    # Check if file exists and is readable
    [[ -f "$config_file" && -r "$config_file" ]] || return 1

    # Check for required fields
    for field in "${required_fields[@]}"; do
        if ! grep -q "^${field}=" "$config_file" 2>/dev/null; then
            return 1  # Missing required field
        fi
    done
    return 0  # Valid config
}

# Repair broken assistant configuration by adding missing required fields
repair_config() {
    local config_file="$1"
    local example_file="$2"
    local assistant_name="$3"

    echo "Repairing configuration: $(basename "$config_file")"

    # Add missing required fields with defaults
    if ! grep -q "^ASSISTANT_NAME=" "$config_file" 2>/dev/null; then
        echo "ASSISTANT_NAME=\"$assistant_name\"" >> "$config_file"
        echo "  Added: ASSISTANT_NAME"
    fi

    if ! grep -q "^ASSISTANT_CLI=" "$config_file" 2>/dev/null; then
        echo "ASSISTANT_CLI=\"$assistant_name\"" >> "$config_file"
        echo "  Added: ASSISTANT_CLI"
    fi

    if ! grep -q "^BASE_IMAGE_NAME=" "$config_file" 2>/dev/null; then
        echo "BASE_IMAGE_NAME=\"nyarlathotia-$assistant_name\"" >> "$config_file"
        echo "  Added: BASE_IMAGE_NAME"
    fi

    # Add other required fields from example
    for field in DOCKERFILE_PATH CONTEXT_DIR_NAME; do
        if ! grep -q "^${field}=" "$config_file" 2>/dev/null; then
            local value=$(grep "^${field}=" "$example_file" 2>/dev/null | head -1)
            if [[ -n "$value" ]]; then
                echo "$value" >> "$config_file"
                echo "  Added: $field"
            fi
        fi
    done
}

# Auto-generate assistant config files from examples
generate_default_assistant_configs() {
    local user_config_dir="$1"
    local project_config_dir="$2"
    
    # Create config subdirectory
    local config_subdir="$user_config_dir/config"
    ensure_directory_exists "$config_subdir"
    
    # Create assistant-specific directories (critical for Docker mount persistence)
    for conf_file in "$project_config_dir"/*.conf.example; do
        if [[ -f "$conf_file" ]]; then
            local assistant_name=$(basename "$conf_file" .conf.example)
            local assistant_dir="$user_config_dir/$assistant_name"
            ensure_directory_exists "$assistant_dir"
        fi
    done
    
    # Copy example files to user config directory
    for example_file in "$project_config_dir"/*.conf.example; do
        if [[ -f "$example_file" ]]; then
            local example_basename=$(basename "$example_file")
            local user_example="$config_subdir/$example_basename"
            
            # Always update example files (they might have changed)
            cp "$example_file" "$user_example"
            
            # Generate or repair .conf file
            local base_name=$(basename "$example_file" .conf.example)
            local target_file="$config_subdir/${base_name}.conf"

            if [[ ! -f "$target_file" ]]; then
                # Generate new config
                generate_commented_config "$example_file" "$target_file"
                if [[ "$VERBOSE" == "true" ]]; then
                    print_info "Generated new config: ${base_name}.conf"
                fi
            elif ! validate_config "$target_file"; then
                # Repair existing broken config
                repair_config "$target_file" "$example_file" "$base_name"
            else
                # Config exists and is valid - no action needed
                if [[ "$VERBOSE" == "true" ]]; then
                    print_verbose "Config valid: ${base_name}.conf"
                fi
            fi
        fi
    done
}

# Ensure prompts directory exists with templates
ensure_prompts_directory() {
    local nyia_home="$1"
    local prompts_dir="$nyia_home/prompts"

    # Always ensure directory exists
    ensure_directory_exists "$prompts_dir"

    # Generate templates if README is missing (indicates first setup)
    if [[ ! -f "$prompts_dir/README.md" ]]; then
        generate_user_prompts_templates "$prompts_dir"
    fi
}

# Ensure project-level prompts directory exists with templates
ensure_project_prompts_directory() {
    local project_path="$1"
    local project_prompts_dir="$project_path/.nyarlathotia/prompts"

    # Always ensure directory exists
    ensure_directory_exists "$project_prompts_dir"

    # Generate project-specific templates if README is missing
    if [[ ! -f "$project_prompts_dir/README.md" ]]; then
        generate_project_prompts_templates "$project_prompts_dir"
    fi
}

# Generate user prompts directory with templates and README
generate_user_prompts_templates() {
    local prompts_dir="$1"
    
    # Create README.md if it doesn't exist
    local readme_file="$prompts_dir/README.md"
    if [[ ! -f "$readme_file" ]]; then
        cat > "$readme_file" << 'EOF'
# NyarlathotIA User Prompt Customization

This directory allows you to customize the system prompts for all NyarlathotIA assistants.

## How It Works

NyarlathotIA uses a layered prompt system. Your custom prompts are merged with the system prompts in this order:

1. **Protected System Constraints** (cannot be overridden)
2. **Universal Base Prompt** (shared by all assistants)
3. **Your Base Customizations** (`base-overrides.md`) ← YOU CUSTOMIZE HERE
4. **Assistant-Specific System Prompts** (claude, gemini, etc.)
5. **Your Assistant Customizations** (`{assistant}-overrides.md`) ← YOU CUSTOMIZE HERE
6. **Project-Specific Overrides** (in project's `.nyarlathotia/prompts/`)
7. **Protected System Enforcement** (cannot be overridden)

## Available Customization Files

### Universal Customizations
- **`base-overrides.md`** - Customize behavior for ALL assistants
  - Communication style (tone, verbosity, explanation level)
  - Code quality preferences and standards
  - Development philosophy and approaches
  - Git workflow preferences

### Assistant-Specific Customizations
- **`claude-overrides.md`** - Customize Claude's behavior
- **`gemini-overrides.md`** - Customize Gemini's behavior
- **`opencode-overrides.md`** - Customize OpenCode's behavior
- **`codex-overrides.md`** - Customize Codex's behavior

## Getting Started

1. **Copy an example file:**
   ```bash
   cp base-overrides.md.example base-overrides.md
   ```

2. **Edit the file with your preferences:**
   ```bash
   nano base-overrides.md
   ```

3. **Test your changes:**
   ```bash
   nyia-claude -p "Hello" --verbose
   ```
   Look for "User Base Customizations" in the generated prompt.

## Example Customizations

### Change Communication Style
```markdown
# base-overrides.md
## Communication Preferences
- Use casual, friendly tone instead of professional
- Be more verbose with explanations
- Always ask clarifying questions before starting work
```

### Customize Code Standards
```markdown
# base-overrides.md
## Code Quality Standards
- Always use TypeScript instead of JavaScript
- Prefer functional programming patterns
- Include comprehensive JSDoc comments
- Write tests for every function
```

### Assistant-Specific Behavior
```markdown
# claude-overrides.md
## Claude-Specific Preferences
- Always create detailed architectural diagrams
- Focus on security analysis in code reviews
- Use formal language for documentation
```

## File Locations

- **User Global**: `~/.config/nyarlathotia/prompts/` (this directory)
- **Project Specific**: `{project}/.nyarlathotia/prompts/`
- **System Prompts**: `{nyarlathotia}/docker/shared/system-prompts/`

## Troubleshooting

### My changes aren't taking effect
1. Check file name matches exactly (case sensitive)
2. Ensure file has `.md` extension
3. Run with `--verbose` to see prompt composition
4. Regenerate prompt: remove `.nyarlathotia/{assistant}/ASSISTANT.md`

### Syntax errors in generated prompts
1. Use proper Markdown syntax
2. Test your Markdown in a preview tool
3. Avoid conflicting with system constraints

### Need help?
Check the system prompt files in `docker/shared/system-prompts/configurable/` for examples of proper syntax and structure.
EOF
        if [[ "$VERBOSE" == "true" ]]; then
            print_info "Generated prompts README: prompts/README.md"
        fi
    fi
    
    # Create example files if they don't exist
    create_prompt_example_file "$prompts_dir/base-overrides.md.example" "Universal Base" "all assistants"
    create_prompt_example_file "$prompts_dir/claude-overrides.md.example" "Claude" "Claude assistant"
    create_prompt_example_file "$prompts_dir/gemini-overrides.md.example" "Gemini" "Gemini assistant"
    create_prompt_example_file "$prompts_dir/opencode-overrides.md.example" "OpenCode" "OpenCode assistant"
    create_prompt_example_file "$prompts_dir/codex-overrides.md.example" "Codex" "Codex assistant"
}

# Generate project-level prompts directory with templates and README
generate_project_prompts_templates() {
    local prompts_dir="$1"

    # Create README.md if it doesn't exist
    local readme_file="$prompts_dir/README.md"
    if [[ ! -f "$readme_file" ]]; then
        cat > "$readme_file" << 'EOF'
# Project-Level Prompt Customization

This directory allows you to customize prompts specifically for this project.

## How It Works

Project prompts override global prompts and are applied in this order:
1. Global prompts (`~/.config/nyarlathotia/prompts/`)
2. **Project prompts** (this directory) ← HIGHEST PRIORITY

## Available Files

### Project-Wide Customizations
- **`project-overrides.md`** - Custom behavior for ALL assistants in this project
  - Project-specific coding standards
  - Domain-specific terminology and approaches
  - Project workflow preferences

### Assistant-Specific Project Customizations
- **`claude-project.md`** - Claude customizations for this project
- **`gemini-project.md`** - Gemini customizations for this project
- **`opencode-project.md`** - OpenCode customizations for this project
- **`codex-project.md`** - Codex customizations for this project

## Quick Start

1. **Create project-wide overrides:**
   ```bash
   cp project-overrides.md.example project-overrides.md
   nano project-overrides.md
   ```

2. **Create assistant-specific overrides:**
   ```bash
   cp claude-project.md.example claude-project.md
   nano claude-project.md
   ```

## Examples

Common project customizations:
- Domain-specific language and terminology
- Project-specific coding standards and patterns
- Technology stack preferences (e.g., "use TypeScript", "prefer functional programming")
- Database and API conventions for this project

EOF
    fi

    # Create example files if they don't exist
    create_project_prompt_example_file "$prompts_dir/project-overrides.md.example" "Project" "all assistants in this project"
    create_project_prompt_example_file "$prompts_dir/claude-project.md.example" "Claude Project" "Claude assistant in this project"
    create_project_prompt_example_file "$prompts_dir/gemini-project.md.example" "Gemini Project" "Gemini assistant in this project"
    create_project_prompt_example_file "$prompts_dir/opencode-project.md.example" "OpenCode Project" "OpenCode assistant in this project"
    create_project_prompt_example_file "$prompts_dir/codex-project.md.example" "Codex Project" "Codex assistant in this project"
}

# Helper function to create individual project prompt example files
create_project_prompt_example_file() {
    local file_path="$1"
    local prompt_type="$2"
    local scope="$3"

    if [[ ! -f "$file_path" ]]; then
        cat > "$file_path" << EOF
# ${prompt_type} Customization

## Project-Specific Instructions for ${scope}

This file customizes prompts specifically for this project, overriding global settings.

### Project Context
- Project type: [e.g., Web application, Mobile app, Data science, etc.]
- Technology stack: [e.g., React, Python, Docker, etc.]
- Domain: [e.g., E-commerce, Healthcare, Finance, etc.]

### Code Quality Standards [CONFIGURABLE]
- Preferred patterns: [e.g., Repository pattern, MVC, Functional programming]
- Naming conventions: [e.g., camelCase, snake_case, specific prefixes]
- Documentation requirements: [e.g., JSDoc, Python docstrings, etc.]

### Project-Specific Behavior [CONFIGURABLE]
- Communication style: [e.g., Brief and direct, Detailed explanations, etc.]
- Error handling approach: [e.g., Comprehensive logging, User-friendly messages]
- Testing preferences: [e.g., Jest, pytest, specific test patterns]

### Domain Knowledge [CONFIGURABLE]
- Business terminology: [Define project-specific terms and concepts]
- API conventions: [REST patterns, GraphQL schema conventions, etc.]
- Database patterns: [ORM usage, query patterns, migration strategies]

### Example Customizations
\`\`\`markdown
- Always use TypeScript for new components
- Follow the repository pattern for data access
- Use Tailwind CSS for styling
- Prefer functional components over class components
- Include comprehensive error handling in all API calls
\`\`\`

EOF
    fi
}

# Helper function to create individual prompt example files
create_prompt_example_file() {
    local file_path="$1"
    local prompt_type="$2"
    local assistant_context="$3"
    
    if [[ ! -f "$file_path" ]]; then
        cat > "$file_path" << EOF
# ${prompt_type} Customizations

This file allows you to customize the behavior of ${assistant_context}.
To activate these customizations, copy this file and remove the \`.example\` extension.

## Example Customizations

### Communication Style
\`\`\`markdown
## My Communication Preferences
- Use casual, friendly tone
- Be more detailed in explanations
- Always confirm before making significant changes
\`\`\`

### Code Quality Standards
\`\`\`markdown
## My Code Standards
- Always use TypeScript over JavaScript
- Include comprehensive error handling
- Write unit tests for all functions
- Use meaningful variable names
\`\`\`

### Development Workflow
\`\`\`markdown
## My Workflow Preferences
- Always create feature branches
- Use conventional commit messages
- Run tests before committing
- Update documentation with code changes
\`\`\`

## Activation

1. Copy this file: \`cp $(basename "$file_path") ${file_path%.example}\`
2. Edit the new file with your preferences
3. Test with: \`nyia-${assistant_context%% *} -p "test prompt" --verbose\`

## Notes

- Use standard Markdown syntax
- Changes take effect on next assistant run
- See README.md for complete documentation
- Remove sections you don't want to customize
EOF
        if [[ "$VERBOSE" == "true" ]]; then
            print_info "Generated example: $(basename "$file_path")"
        fi
    fi
}

get_nyarlathotia_home() {
    # 1. Environment variable override (highest priority)
    if [[ -n "$NYARLATHOTIA_HOME" ]]; then
        ensure_directory_exists "$NYARLATHOTIA_HOME"
        
        # Auto-generate assistant configs for environment override too
        local project_config_dir="$script_dir/../config"
        if [[ -d "$project_config_dir" ]]; then
            generate_default_assistant_configs "$NYARLATHOTIA_HOME" "$project_config_dir"
        fi

        # Ensure prompts directory exists
        ensure_prompts_directory "$NYARLATHOTIA_HOME"

        echo "$NYARLATHOTIA_HOME"
        return 0
    fi
    
    
    # 2. Platform-specific default (auto-create)
    local config_dir
    case "$(uname -s)" in
        Linux*)
            config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/nyarlathotia"
            ;;
        Darwin*)
            config_dir="$HOME/Library/Application Support/nyarlathotia"
            ;;
        CYGWIN*|MINGW*|MSYS*)
            config_dir="${APPDATA:-$HOME/AppData/Roaming}/nyarlathotia"
            ;;
        *)
            # Unix fallback for unknown systems
            config_dir="$HOME/.config/nyarlathotia"
            ;;
    esac
    
    ensure_directory_exists "$config_dir"
    
    # Auto-generate assistant configs on first run or when examples are updated
    local project_config_dir="$script_dir/../config"
    if [[ -d "$project_config_dir" ]]; then
        generate_default_assistant_configs "$config_dir" "$project_config_dir"
    fi

    # Ensure prompts directory exists
    ensure_prompts_directory "$config_dir"

    # Ensure VERSION file exists (migration for existing installations)
    local version_file="$config_dir/VERSION"
    if [[ ! -f "$version_file" ]]; then
        echo "latest" > "$version_file" 2>/dev/null || true
        print_verbose "Created VERSION file with default: latest"
    fi

    echo "$config_dir"
    return 0
}

# === CONFIG BACKUP ===

# Backup assistant config files before container launch.
# Protects against corruption (e.g., disk full during session).
# One backup per day, keeps last 7 days, silent by default.
backup_assistant_config() {
    local config_dir="$1"
    local backup_base="$config_dir/.backups"
    local today=$(date +%Y-%m-%d)
    local today_backup="$backup_base/$today"

    # Skip if today's backup already exists
    if [[ -d "$today_backup" ]]; then
        print_verbose "Config backup already exists for today: $today_backup"
        return 0
    fi

    # Skip if no files to backup (empty config dir)
    local file_count
    file_count=$(find "$config_dir" -maxdepth 1 -type f 2>/dev/null | wc -l)
    if [[ "$file_count" -eq 0 ]]; then
        print_verbose "No config files to backup in $config_dir"
        return 0
    fi

    # Create today's backup and copy top-level files only
    mkdir -p "$today_backup"
    find "$config_dir" -maxdepth 1 -type f -exec cp {} "$today_backup/" \;
    print_verbose "Config backed up to $today_backup ($file_count files)"

    # Prune old backups: keep last 7 daily backups
    if [[ -d "$backup_base" ]]; then
        local old_backups
        old_backups=$(ls -1d "$backup_base"/????-??-?? 2>/dev/null | sort -r | tail -n +8)
        if [[ -n "$old_backups" ]]; then
            echo "$old_backups" | while read -r old_dir; do
                rm -rf "$old_dir"
                print_verbose "Pruned old config backup: $old_dir"
            done
        fi
    fi
}

# === VERSION MANAGEMENT ===

# Get installed version from VERSION file
# Returns: version string (e.g., "v0.0.5-alpha" or "latest")
# Fallback: "latest" if file missing or corrupted
get_installed_version() {
    local nyia_home=$(get_nyarlathotia_home)
    local version_file="$nyia_home/VERSION"

    # Priority 1: Environment variable override (for power users)
    if [[ -n "${NYIA_VERSION:-}" ]]; then
        print_verbose "Using version from NYIA_VERSION env: $NYIA_VERSION"
        echo "$NYIA_VERSION"
        return 0
    fi

    # Priority 2: VERSION file
    if [[ -f "$version_file" ]]; then
        local version=$(cat "$version_file" 2>/dev/null | tr -d '[:space:]' | head -1)

        # Validate version format (v*.*.* or "latest")
        if [[ -n "$version" && ( "$version" == "latest" || "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+ ) ]]; then
            print_verbose "Using installed version: $version"
            echo "$version"
            return 0
        else
            print_verbose "Invalid version in VERSION file: '$version', using latest"
        fi
    else
        print_verbose "No VERSION file found at: $version_file"
    fi

    # Priority 3: Fallback to latest
    print_verbose "Falling back to: latest"
    echo "latest"
    return 0
}

# Write version to VERSION file
# Args: $1 = version string (e.g., "v0.0.5-alpha")
set_installed_version() {
    local version="$1"
    local nyia_home=$(get_nyarlathotia_home)
    local version_file="$nyia_home/VERSION"

    if [[ -z "$version" ]]; then
        print_error "set_installed_version: version argument required"
        return 1
    fi

    # Validate version format
    if [[ "$version" != "latest" && ! "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+ ]]; then
        print_warning "Unusual version format: $version (expected v*.*.* or 'latest')"
    fi

    echo "$version" > "$version_file" || {
        print_error "Failed to write VERSION file: $version_file"
        return 1
    }

    print_verbose "Set installed version to: $version"
    return 0
}

# === BRANCH DETECTION & DEV IMAGE SUPPORT ===

# Check if repository has at least one commit
# Returns 0 if commits exist, 1 if empty repo (unborn branch)
has_commits() {
    local project_path="${1:-$(pwd)}"
    git -C "$project_path" rev-parse HEAD >/dev/null 2>&1
}

get_current_branch() {
    local project_path="${1:-$(pwd)}"
    if git -C "$project_path" rev-parse --git-dir > /dev/null 2>&1; then
        git -C "$project_path" branch --show-current 2>/dev/null || echo "HEAD"
    else
        echo "no-git"
    fi
}

is_production_branch() {
    local branch="$1"
    case "$branch" in
        main|master|stable|production|release)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

sanitize_branch_name() {
    local branch="$1"
    local max_length=60  # Leave room for prefix
    
    # Convert to lowercase
    branch=$(echo "$branch" | tr '[:upper:]' '[:lower:]')
    
    # Replace invalid characters with dashes
    branch=$(echo "$branch" | sed 's/[^a-z0-9._-]/-/g')
    
    # Remove consecutive dashes/periods
    branch=$(echo "$branch" | sed 's/[-\.]\+/-/g')
    
    # Remove leading/trailing dashes or periods
    branch=$(echo "$branch" | sed 's/^[-\.]*//;s/[-\.]*$//')
    
    # Truncate if too long
    if [[ ${#branch} -gt $max_length ]]; then
        branch="${branch:0:$max_length}"
        # Ensure we don't end with a dash after truncation
        branch=$(echo "$branch" | sed 's/-*$//')
    fi
    
    # Fallback for empty or problematic names
    if [[ -z "$branch" || "$branch" =~ ^[0-9]+$ ]]; then
        branch="dev-$(date +%Y%m%d-%H%M%S)"
    fi
    
    echo "$branch"
}

get_target_image() {
    local base_name="$1"
    local dev_mode="$2"
    local build_mode="$3"
    

    # Runtime: Use registry image with installed version
    local assistant_name=$(basename "$base_name")
    local registry=$(get_docker_registry)
    local version=$(get_installed_version)

    print_verbose "Target image: ${registry}/${assistant_name}:${version}"
    echo "${registry}/${assistant_name}:${version}"
    return
}

find_best_image() {
    local base_name="$1"
    local prefer_dev="$2"

    # Runtime: Use registry-based image selection with installed version
    local assistant_name=$(basename "$base_name")
    local registry=$(get_docker_registry)
    local version=$(get_installed_version)

    print_verbose "Best image: ${registry}/${assistant_name}:${version}"
    echo "${registry}/${assistant_name}:${version}"
    return
}

# === OUTPUT & UI ===
print_status() {
    echo -e "\033[0;34m🔧 $1\033[0m"
}

print_success() {
    echo -e "\033[0;32m✅ $1\033[0m"
}

print_error() {
    echo -e "\033[0;31m❌ $1\033[0m"
}

print_warning() {
    echo -e "\033[1;33m⚠️  $1\033[0m"
}

print_fix() {
    echo -e "\033[0;36m💡 Fix: $1\033[0m"
}

print_info() {
    echo -e "\033[0;37m📍 $1\033[0m"
}

# === PATH & PROJECT MANAGEMENT ===
resolve_absolute_path() {
    local path="$1"
    if [[ "$path" == /* ]]; then
        # Already absolute
        echo "$path"
    else
        # Convert relative to absolute
        echo "$(cd "$path" 2>/dev/null && pwd)" || {
            print_error "Path does not exist: $path"
            exit 1
        }
    fi
}

get_project_hash() {
    local project_path="$1"
    echo "$project_path" | sha256sum | cut -d' ' -f1 | cut -c1-12
}

# === REQUIREMENTS CHECKING ===

check_git_available() {
    if ! command -v git >/dev/null 2>&1; then
        print_error "Git not available"
        print_fix "Install Git:"
        print_fix "  Ubuntu/Debian: sudo apt update && sudo apt install git"
        print_fix "  RHEL/CentOS: sudo yum install git"
        print_fix "  macOS: brew install git"
        return 1
    fi
    return 0
}

check_git_repository() {
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        print_error "Not in a Git repository"
        print_warning "AI assistants can modify files - Git required for safety!"
        print_fix "Initialize Git repository:"
        print_fix "  git init"
        print_fix "  git add ."
        print_fix "  git commit -m 'Initial commit before AI assistance'"
        return 1
    fi
    return 0
}

check_docker_available() {
    if ! command -v docker >/dev/null 2>&1; then
        print_error "Docker not available"
        print_fix "Install Docker:"
        print_fix "  curl -fsSL https://get.docker.com -o get-docker.sh && sh get-docker.sh"
        print_fix "  Or visit: https://docs.docker.com/get-docker/"
        return 1
    fi
    return 0
}

check_docker_running() {
    if ! /usr/bin/docker info >/dev/null 2>&1; then
        print_error "Docker daemon not running"
        print_fix "Start Docker daemon:"
        print_fix "  sudo systemctl start docker"
        print_fix "  # Or: sudo service docker start"
        print_warning "You may need to add yourself to docker group:"
        print_fix "  sudo usermod -aG docker \$USER"
        print_fix "  # Then logout and login again"
        return 1
    fi
    return 0
}

check_directory_permissions() {
    local project_path="$1"
    
    # Check if directory is readable
    if [[ ! -r "$project_path" ]]; then
        print_error "Project directory not readable: $project_path"
        print_fix "Fix permissions: chmod 755 '$project_path'"
        return 1
    fi
    
    # Check if directory is writable
    if [[ ! -w "$project_path" ]]; then
        print_error "Project directory not writable: $project_path"
        print_fix "Fix permissions:"
        print_fix "  chmod 755 '$project_path'"
        print_fix "  # Or if owned by root: sudo chown -R \$USER:\$USER '$project_path'"
        return 1
    fi
    
    return 0
}

check_user_mapping() {
    local uid=$(id -u)
    local gid=$(id -g)
    
    if [[ "$uid" -eq 0 ]]; then
        print_warning "Running as root user"
        print_warning "Recommended: Run as regular user for better security"
        print_info "Docker user mapping: $uid:$gid (root)"
    else
        print_verbose "Docker user mapping: $uid:$gid"
    fi
    
    return 0
}

check_git_clean_state() {
    if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
        print_warning "Uncommitted changes detected"
        print_info "Recommended: Commit changes before AI assistance"
        print_fix "Commit changes:"
        print_fix "  git add ."
        print_fix "  git commit -m 'Pre-AI changes'"
        # Return 0 - this is a warning, not a blocker
    fi
    return 0
}

# Runtime-safe disk space check (available in both dev and runtime)
check_disk_space() {
    local project_path="$1"
    
    # Simple check that works in all environments
    if command -v df >/dev/null 2>&1; then
        local available_mb=$(df "$project_path" 2>/dev/null | awk 'NR==2 {print int($4/1024)}' 2>/dev/null)
        local min_required_mb=1024  # 1GB minimum
        
        if [[ -n "$available_mb" && "$available_mb" -lt "$min_required_mb" ]]; then
            print_warning "Low disk space: ${available_mb}MB available"
            print_info "Recommended: At least ${min_required_mb}MB for container operations"
            print_fix "Free up disk space or use different directory"
        fi
    fi
    
    return 0
}

# Note: check_disk_space() moved above to be runtime-safe

# Fast requirements check (< 200ms)
check_requirements_fast() {
    local project_path="${1:-$(pwd)}"
    local exit_code=0
    
    print_status "Checking system requirements..."
    
    # Critical checks that must pass
    check_git_available || exit_code=1
    check_git_repository || exit_code=1
    check_docker_available || exit_code=1
    check_directory_permissions "$project_path" || exit_code=1
    
    # Warnings (don't fail)
    check_git_clean_state
    check_user_mapping
    check_disk_space "$project_path"
    
    return $exit_code
}

# Full requirements check (includes expensive operations)
check_requirements_full() {
    local project_path="${1:-$(pwd)}"
    local exit_code=0
    
    print_status "Running comprehensive requirements check..."
    
    # Run fast checks first
    check_requirements_fast "$project_path" || exit_code=1
    
    # Additional expensive checks
    if [[ $exit_code -eq 0 ]]; then
        print_status "Checking Docker daemon..."
        check_docker_running || exit_code=1
    fi
    
    if [[ $exit_code -eq 0 ]]; then
        print_success "All requirements satisfied ✓"
    else
        print_error "Requirements check failed"
        print_info "Fix the issues above and try again"
    fi
    
    return $exit_code
}

# Show requirements check results
show_requirements_check() {
    local project_path="${1:-$(pwd)}"
    
    echo "=== NyarlathotIA Requirements Check ==="
    echo "Project: $(basename "$project_path")"
    echo "Path: $project_path"
    echo ""
    
    check_requirements_full "$project_path"
    local result=$?
    
    echo ""
    if [[ $result -eq 0 ]]; then
        echo "🎉 Ready to use AI assistants!"
    else
        echo "❌ Please fix the requirements above before proceeding"
        echo ""
        echo "💡 Quick fixes:"
        echo "   ./bin/openai-codex --check-requirements  # Run this check again"
        echo "   git init && git add . && git commit -m 'Initial'  # If no Git repo"
        echo "   sudo systemctl start docker  # If Docker not running"
    fi
    
    return $result
}

# === PROMPT COMPOSITION ===
compose_project_prompt() {
    local assistant_type="$1"
    local project_path="$2"
    local nyia_home="$(get_nyarlathotia_home)"
    
    print_verbose "Composing prompt for $assistant_type"
    
    local final_prompt=""
    local script_dir="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
    local nyia_prompts="$script_dir/../docker/shared/system-prompts"
    local user_prompts="$nyia_home/prompts"
    local project_prompts="$project_path/.nyarlathotia/prompts"
    
    # 1. Protected prefix (security constraints)
    if [[ -f "$nyia_prompts/protected/universal-prefix.md" ]]; then
        final_prompt+="$(cat "$nyia_prompts/protected/universal-prefix.md")"$'\n\n'
    else
        print_error "Critical: Missing protected prefix"
        return 1
    fi
    
    # 2. Configurable universal base
    if [[ -f "$nyia_prompts/configurable/universal-base.md" ]]; then
        final_prompt+="$(cat "$nyia_prompts/configurable/universal-base.md")"$'\n\n'
    fi
    
    # 3. User global base overrides
    if [[ -f "$user_prompts/base-overrides.md" ]]; then
        final_prompt+="# User Base Customizations"$'\n'
        final_prompt+="$(cat "$user_prompts/base-overrides.md")"$'\n\n'
    fi
    
    # 4. Assistant-specific configurable
    if [[ -f "$nyia_prompts/configurable/${assistant_type}-system.md" ]]; then
        final_prompt+="$(cat "$nyia_prompts/configurable/${assistant_type}-system.md")"$'\n\n'
    fi
    
    # 5. User global assistant overrides
    if [[ -f "$user_prompts/${assistant_type}-overrides.md" ]]; then
        final_prompt+="# User ${assistant_type} Customizations"$'\n'
        final_prompt+="$(cat "$user_prompts/${assistant_type}-overrides.md")"$'\n\n'
    fi
    
    # 6. Project global overrides
    if [[ -f "$project_prompts/project-overrides.md" ]]; then
        final_prompt+="# Project Global Overrides"$'\n'
        final_prompt+="$(cat "$project_prompts/project-overrides.md")"$'\n\n'
    fi
    
    # 7. Project assistant-specific
    if [[ -f "$project_prompts/${assistant_type}-project.md" ]]; then
        final_prompt+="# Project ${assistant_type} Specific"$'\n'
        final_prompt+="$(cat "$project_prompts/${assistant_type}-project.md")"$'\n\n'
    fi
    
    # 8. Protected suffix (enforcement)
    if [[ -f "$nyia_prompts/protected/universal-suffix.md" ]]; then
        final_prompt+="$(cat "$nyia_prompts/protected/universal-suffix.md")"$'\n\n'
    else
        print_error "Critical: Missing protected suffix"
        return 1
    fi
    
    # Add composition metadata
    final_prompt+="# Prompt Composition Info"$'\n'
    final_prompt+="- Assistant: $assistant_type"$'\n'
    final_prompt+="- Composed: $(date -Iseconds)"$'\n'
    final_prompt+="- System Prompt: $(echo "$final_prompt" | head -c 10000 | wc -c) chars"$'\n'
    final_prompt+="- User Prompt: 1 chars"$'\n'
    final_prompt+="- Total Size: $(echo "$final_prompt" | wc -c) chars"$'\n'
    
    echo "$final_prompt"
}

get_prompt_filename() {
    local assistant_cli="$1"
    case "$assistant_cli" in
        claude) echo "CLAUDE.md" ;;
        gemini) echo "GEMINI.md" ;;
        codex) echo "AGENTS.md" ;;
        opencode) echo "OPENCODE.md" ;;
        vibe) echo "VIBE.md" ;;
        *) echo "$(echo "$assistant_cli" | tr '[:lower:]' '[:upper:]').md" ;;
    esac
}

# Runtime-safe git exclusions helper (needed for end users)
check_git_exclusions() {
    local project_path="$1"
    local prompt_filename="$2"
    
    # Skip if not a git repository
    if [[ ! -d "$project_path/.git" ]]; then
        return 0
    fi
    
    local exclude_file="$project_path/.git/info/exclude"
    
    # Ensure exclude file exists
    mkdir -p "$(dirname "$exclude_file")"
    touch "$exclude_file"
    
    # Check if this specific file is already excluded
    if grep -q "^$prompt_filename$" "$exclude_file" 2>/dev/null; then
        return 0  # Already excluded
    fi
    
    # Ask user about this specific file
    echo ""
    print_info "NyarlathotIA Setup: Git Exclusions"
    echo "NyarlathotIA will create a symlink to generated prompt file:"
    echo "  $prompt_filename -> .nyarlathotia/[assistant]/$prompt_filename"
    echo ""
    echo "This symlink allows the assistant to find its prompt."
    echo "Would you like to exclude $prompt_filename from git tracking?"
    echo "(Uses .git/info/exclude - local only, never committed)"
    echo ""
    read -p "Exclude $prompt_filename from git? [Y/n]: " response
    
    # Add this file to exclusions
    if [[ ! "$response" =~ ^[Nn]$ ]]; then
        echo "$prompt_filename" >> "$exclude_file"
        print_success "Added $prompt_filename to .git/info/exclude"
    else
        print_info "Skipped git exclusion for $prompt_filename"
    fi
}


generate_assistant_prompts() {
    local assistant_name="$1"
    local assistant_cli="$2"
    local project_path="$3"
    
    print_status "Generating prompts for $assistant_name"
    
    # Get correct prompt filename for this assistant
    local prompt_filename=$(get_prompt_filename "$assistant_cli")
    
    # Generate content using the common prompt sandwich function (unchanged)
    local prompt_content
    if ! prompt_content=$(compose_project_prompt "$assistant_cli" "$project_path"); then
        print_error "Failed to generate prompt for $assistant_name"
        return 1
    fi
    
    # Use common functions to ensure complete context setup
    if ! ensure_assistant_context "$project_path" "$assistant_cli" "$assistant_name" "$prompt_content"; then
        print_error "Failed to setup complete context for $assistant_name"
        return 1
    fi
    
    # Handle project-level symlinks and files for ALL assistants (including Codex)
    local symlink_path="$project_path/$prompt_filename"
    
    # Remove existing symlink or file if it exists
    if [[ -L "$symlink_path" ]] || [[ -f "$symlink_path" ]]; then
        rm -f "$symlink_path"
    fi
    
    # Create relative symlink to the context directory
    ln -s ".nyarlathotia/$assistant_cli/$prompt_filename" "$symlink_path"
    
    # Write prompt content to the actual file location
    local prompt_file="$project_path/.nyarlathotia/$assistant_cli/$prompt_filename"
    echo "$prompt_content" > "$prompt_file"
    
    local file_size=$(wc -c < "$prompt_file")
    print_success "Generated $prompt_filename ($file_size chars)"
    
    return 0
}

# === DOCKER OPERATIONS ===


# Runtime overlay base image selection
determine_overlay_base_image() {
    local current_step="$1"
    local assistant_name="$2"
    local dev_mode="$3"
    shift 3
    local -a previous_tags=("$@")
    
    if [[ $current_step -eq 0 ]]; then
        # Runtime: Use registry image with proper namespace
        local registry=$(get_docker_registry)
        echo "${registry}/nyarlathotia-${assistant_name}:latest"
    else
        # Subsequent overlays: use previous overlay output
        echo "${previous_tags[$((current_step-1))]}"
    fi
}

# Custom image building for end-users (power user feature)
build_custom_image() {
    local assistant_name="$1"

    # Always use ghcr.io as base (end-users don't build from source)
    local registry=$(get_docker_registry)
    local base_image

    # Determine base image (priority: override > flavor > default)
    if [[ -n "${FLAVOR:-}" ]]; then
        base_image="${registry}/nyarlathotia-${assistant_name}-${FLAVOR}:latest"
        print_info "Using flavor '${FLAVOR}' as base"
    else
        base_image="${registry}/nyarlathotia-${assistant_name}:latest"
    fi
    
    # Check for Docker
    if ! command -v docker >/dev/null 2>&1; then
        print_error "Docker is required for custom image building"
        print_info "Install Docker: https://docs.docker.com/get-docker/"
        return 1
    fi
    
    # Check for overlays
    local user_overlay="$HOME/.config/nyarlathotia/${assistant_name}/overlay/Dockerfile"
    local project_overlay="$(pwd)/.nyarlathotia/${assistant_name}/overlay/Dockerfile"
    local has_overlay=false
    
    if [[ -f "$user_overlay" ]]; then
        print_info "Found user overlay: $user_overlay"
        has_overlay=true
    fi
    
    if [[ -f "$project_overlay" ]]; then
        print_info "Found project overlay: $project_overlay"
        has_overlay=true
    fi
    
    if [[ "$has_overlay" == "false" ]]; then
        print_error "No overlay Dockerfile found for custom image"
        print_info ""
        print_info "Create an overlay at one of these locations:"
        print_info "  User:    $user_overlay"
        print_info "  Project: $project_overlay"
        print_info ""
        print_info "Example overlay Dockerfile:"
        print_info "  ARG BASE_IMAGE"
        print_info "  FROM \${BASE_IMAGE}"
        print_info "  RUN apt-get update && apt-get install -y your-tools"
        print_info ""
        print_info "Build options:"
        print_info "  nyia-${assistant_name} --build-custom-image                 # Base image"
        print_info "  nyia-${assistant_name} --build-custom-image --flavor python # Python flavor as base"
        return 1
    fi
    
    # Build custom image (include flavor in name if used)
    local custom_image_name
    if [[ -n "${FLAVOR:-}" ]]; then
        custom_image_name="nyarlathotia-${assistant_name}-${FLAVOR}-custom"
    else
        custom_image_name="nyarlathotia-${assistant_name}-custom"
    fi
    local build_context="$(pwd)"
    
    print_info "Building custom image: $custom_image_name"
    print_info "Base image: $base_image"
    
    # Create temporary Dockerfile that combines overlays
    local temp_dockerfile=$(mktemp /tmp/nyia-custom-build.XXXXXX.dockerfile)
    chmod 644 "$temp_dockerfile"
    
    # Start with base image
    echo "FROM $base_image" > "$temp_dockerfile"
    echo "" >> "$temp_dockerfile"
    
    # Apply user overlay if exists
    if [[ -f "$user_overlay" ]]; then
        print_info "Applying user overlay..."
        # Strip ARG BASE_IMAGE and FROM lines, keep everything else
        sed '/^ARG BASE_IMAGE/d; /^FROM/d' "$user_overlay" >> "$temp_dockerfile"
        echo "" >> "$temp_dockerfile"
    fi
    
    # Apply project overlay if exists
    if [[ -f "$project_overlay" ]]; then
        print_info "Applying project overlay..."
        # Strip ARG BASE_IMAGE and FROM lines, keep everything else
        sed '/^ARG BASE_IMAGE/d; /^FROM/d' "$project_overlay" >> "$temp_dockerfile"
    fi
    
    # Show what will be built
    print_info "Combined Dockerfile:"
    cat "$temp_dockerfile" | sed 's/^/  /'
    
    # Build the image
    local no_cache_flag=""
    [[ "${NO_CACHE:-false}" == "true" ]] && no_cache_flag="--no-cache"
    print_info "Building image (this may take a while)..."
    if docker build $no_cache_flag -t "$custom_image_name" -f "$temp_dockerfile" "$build_context"; then
        print_success "Custom image built successfully: $custom_image_name"
        print_info ""
        print_info "To use your custom image:"
        print_info "  nyia-${assistant_name} --image $custom_image_name -p \"your prompt\""
    else
        print_error "Failed to build custom image"
        rm -f "$temp_dockerfile"
        return 1
    fi
    
    # Cleanup
    rm -f "$temp_dockerfile"
    return 0
}




check_docker_image() {
    local image_name="$1"

    if ! /usr/bin/docker image inspect "$image_name" >/dev/null 2>&1; then
        return 1
    fi
    return 0
}

# Get environment variables from .creds/env file
# Arguments:
#   $1 - Project path (optional, defaults to current directory)
# Returns docker -e arguments for all exported variables
get_creds_env_args() {
    local project_path="${1:-$(pwd)}"
    local creds_file="$project_path/.nyarlathotia/creds/env"
    local env_args=()
    
    if [[ -f "$creds_file" ]]; then
        print_verbose "Loading environment variables from $creds_file"
        
        # Parse .creds/env and pass all exported variables
        while IFS= read -r line; do
            # Skip comments and empty lines
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ -z "${line// }" ]] && continue
            
            # Extract export statements with their values
            if [[ "$line" =~ ^[[:space:]]*export[[:space:]]+([A-Z_][A-Z0-9_]*)=(.*)$ ]]; then
                local var_name="${BASH_REMATCH[1]}"
                local var_value="${BASH_REMATCH[2]}"

                # Remove surrounding quotes if present
                var_value="${var_value#\"}"
                var_value="${var_value%\"}"
                var_value="${var_value#\'}"
                var_value="${var_value%\'}"

                # Add to environment arguments
                env_args+=(-e "${var_name}=${var_value}")
                print_verbose "Adding ${var_name} to container environment"
            fi
        done < "$creds_file"
    else
        print_verbose "No credentials file found at $creds_file"
    fi
    
    printf '%s\n' "${env_args[@]}"
}

# Global array for environment arguments
declare -a DOCKER_ENV_ARGS

# Create temporary environment file for Docker container
create_docker_env_file() {
    local project_path="${1:-$(pwd)}"
    local assistant_name="${2:-}"
    
    # Create temp file with secure permissions from start
    # Use system temp dir which should have sticky bit set for security
    local env_file=$(mktemp -t nyia-env.XXXXXX)
    
    # Set secure permissions: owner read/write, group read (for Docker daemon)
    # This allows Docker to read the file while preventing world access
    chmod 640 "$env_file"
    
    # Verify we own the file before writing secrets (defense in depth)
    if [[ ! -O "$env_file" ]]; then
        print_error "Security check failed: temp file not owned by current user"
        rm -f "$env_file" 2>/dev/null || true
        return 1
    fi
    
    # Note: Cleanup handled by calling function to avoid nested trap issues
    # The calling functions (run_docker_container, run_debug_shell) set up cleanup
    
    print_verbose "Creating Docker environment file (secure): $env_file"
    
    # Add credentials from .nyarlathotia/creds/env file
    local creds_file="$project_path/.nyarlathotia/creds/env"
    if [[ -f "$creds_file" ]]; then
        print_verbose "Loading credentials from $creds_file"
        # Extract just the VAR=value part from -e VAR=value arguments
        while IFS= read -r env_arg; do
            if [[ "$env_arg" =~ ^-e[[:space:]]+(.+)$ ]]; then
                echo "${BASH_REMATCH[1]}" >> "$env_file"
                print_verbose "Added credential: ${BASH_REMATCH[1]%%=*}"
            fi
        done < <(get_creds_env_args "$project_path")
    fi
    
    # Source config file to get variables like GOOGLE_CLOUD_PROJECT
    local config_file=""
    if [[ -n "$assistant_name" ]]; then
        # Get proper config directory
        local nyia_home=$(get_nyarlathotia_home)
        # Handle openai-codex case where assistant_cli is "codex" but config file is "openai-codex.conf"
        if [[ "$assistant_name" == "codex" ]]; then
            config_file="$nyia_home/config/openai-codex.conf"
        else
            config_file="$nyia_home/config/${assistant_name}.conf"
        fi
    else
        # Fallback to basename detection (may not work in all contexts)
        local nyia_home=$(get_nyarlathotia_home)
        config_file="$nyia_home/config/$(basename "$0" .sh).conf"
    fi
    
    if [[ -f "$config_file" ]]; then
        print_verbose "Sourcing config file: $config_file"
        # Create temporary script to source config and export variables
        local temp_script=$(mktemp)
        cat > "$temp_script" << 'EOF'
source "$1"

# Debug: Show AUTH_METHOD value
if [[ -n "${VERBOSE:-}" ]] || [[ "${NYIA_DEBUG:-}" == "true" ]]; then
    echo "# DEBUG: AUTH_METHOD=$AUTH_METHOD" >&2
fi

# Export important config variables
for var_name in GOOGLE_CLOUD_PROJECT ANTHROPIC_API_KEY GEMINI_API_KEY MISTRAL_API_KEY; do
    if [[ -n "${!var_name:-}" ]]; then
        echo "${var_name}=${!var_name}"
    fi
done

# Only pass OPENAI_API_KEY if not using chatgpt_signin authentication
# AUTH_METHOD is loaded from the config file we just sourced
if [[ -n "$OPENAI_API_KEY" && "$AUTH_METHOD" != "chatgpt_signin" ]]; then
    echo "OPENAI_API_KEY=$OPENAI_API_KEY"
    if [[ -n "${VERBOSE:-}" ]] || [[ "${NYIA_DEBUG:-}" == "true" ]]; then
        echo "# DEBUG: Passing OPENAI_API_KEY because AUTH_METHOD='$AUTH_METHOD' != 'chatgpt_signin'" >&2
    fi
else
    if [[ -n "${VERBOSE:-}" ]] || [[ "${NYIA_DEBUG:-}" == "true" ]]; then
        echo "# DEBUG: NOT passing OPENAI_API_KEY (AUTH_METHOD='$AUTH_METHOD', key exists: ${OPENAI_API_KEY:+yes})" >&2
    fi
fi
EOF
        bash "$temp_script" "$config_file" >> "$env_file"
        rm -f "$temp_script"
    else
        print_verbose "Config file not found: $config_file"
    fi
    
    # Remove duplicates (keep last occurrence)
    local temp_sorted=$(mktemp)
    chmod 640 "$temp_sorted"  # Set same permissions on temp file
    tac "$env_file" | awk -F= '!seen[$1]++' | tac > "$temp_sorted"
    mv "$temp_sorted" "$env_file"
    chmod 640 "$env_file"  # Ensure permissions are preserved after move
    
    if [[ "${NYIA_DEBUG:-false}" == "true" ]]; then
        print_verbose "Environment file contents:"
        while IFS= read -r line; do
            print_verbose "  ${line%%=*}=***"
        done < "$env_file"
    fi
    
    echo "$env_file"
}

# Legacy function for backward compatibility
get_all_env_args() {
    local project_path="${1:-$(pwd)}"
    
    # Create env file and return --env-file argument
    local env_file=$(create_docker_env_file "$project_path")
    echo "--env-file"
    echo "$env_file"
}

# Check if assistant credentials are available
# Arguments:
#   $1 - CLI command name
#   $2 - Assistant config directory (e.g. ~/.nyarlathotia/assistant)
#   $3 - Directory name for credentials (e.g. .codex)
#   $4 - API key environment variable
check_credentials() {
    local cli="$1"
    local cfg_dir="$2"
    local dir_name="$3"
    local api_env="$4"

    print_verbose "== Credential check for $cli =="
    print_verbose "Looking in directory: $cfg_dir"
    print_verbose "Directory contents:"
    if [[ -d "$cfg_dir" ]]; then
        print_verbose "$(ls -la "$cfg_dir" 2>/dev/null || echo 'Directory listing failed')"
    else
        print_verbose "Directory does not exist"
    fi

    # Assistant-specific credential checking
    case "$cli" in
        claude)
            # Check for Claude credentials on the host in the NyarlathotIA config directory
            # These will be mounted into the container at ~/.claude/
            if [[ ! -f "$cfg_dir/.credentials.json" ]]; then
                print_verbose "Claude credentials not found: $cfg_dir/.credentials.json"
                return 1
            fi

            # Also check for config file (settings/preferences)
            if [[ ! -f "$cfg_dir/.claude.json" ]]; then
                print_warning "Claude configuration not found"
                print_info "Claude will create default settings on first use"
                print_verbose "Missing config file: $cfg_dir/.claude.json"
                # Don't fail, just warn
            fi

            print_verbose "Claude credentials found at $cfg_dir/.credentials.json"
            return 0
            ;;
        opencode)
            # No pre-flight credentials needed - handles auth internally
            print_verbose "No pre-flight credential check needed for $cli"
            return 0
            ;;
        gemini)
            # Method 1: OAuth file exists (most common after interactive auth)
            local oauth_file="$cfg_dir/oauth_creds.json"
            print_verbose "Checking OAuth file: $oauth_file"
            if [[ -f "$oauth_file" ]]; then
                print_verbose "OAuth file exists, size: $(stat -c%s "$oauth_file" 2>/dev/null || echo 'unknown')"
                if [[ -s "$oauth_file" ]]; then
                    print_verbose "OAuth file has content - credentials found"
                    return 0
                else
                    print_verbose "OAuth file is empty"
                fi
            else
                print_verbose "OAuth file does not exist"
            fi
            
            # Method 2: API key provided
            print_verbose "Checking GEMINI_API_KEY: ${GEMINI_API_KEY:+SET}"
            if [[ -n "${GEMINI_API_KEY}" ]]; then
                print_verbose "Found GEMINI_API_KEY"
                return 0
            fi
            
            # Method 3: Vertex AI (both required)
            print_verbose "Checking Vertex AI: GOOGLE_CLOUD_PROJECT=${GOOGLE_CLOUD_PROJECT:+SET}, GOOGLE_APPLICATION_CREDENTIALS=${GOOGLE_APPLICATION_CREDENTIALS:+SET}"
            if [[ -n "${GOOGLE_CLOUD_PROJECT}" && -n "${GOOGLE_APPLICATION_CREDENTIALS}" && -f "${GOOGLE_APPLICATION_CREDENTIALS}" ]]; then
                print_verbose "Found Vertex AI credentials"
                return 0
            fi
            
            print_verbose "No Gemini credentials found"
            return 1
            ;;
        codex)
            # Codex can work with env var OR auth.json
            if [[ -n "${OPENAI_API_KEY}" ]]; then
                print_verbose "Found OPENAI_API_KEY"
                return 0
            elif [[ -f "$cfg_dir/auth.json" && -s "$cfg_dir/auth.json" ]]; then
                print_verbose "Found auth.json"
                return 0
            else
                print_verbose "No OPENAI_API_KEY or auth.json found"
                return 1
            fi
            ;;
        vibe)
            # Vibe requires MISTRAL_API_KEY
            # Check 1: Environment variable (takes priority)
            if [[ -n "${MISTRAL_API_KEY}" ]]; then
                print_verbose "Found MISTRAL_API_KEY in environment"
                return 0
            fi

            # Check 2: Config file fallback
            local vibe_config_file
            vibe_config_file="$(dirname "$cfg_dir")/config/vibe.conf"
            if [[ -f "$vibe_config_file" ]]; then
                local key_from_config
                key_from_config=$(grep '^MISTRAL_API_KEY=' "$vibe_config_file" 2>/dev/null | head -1 | cut -d'=' -f2- | tr -d '"' | tr -d "'" | xargs)
                if [[ -n "$key_from_config" ]]; then
                    export MISTRAL_API_KEY="$key_from_config"
                    print_verbose "Found MISTRAL_API_KEY in config file"
                    return 0
                fi
            fi

            print_verbose "No MISTRAL_API_KEY found in environment or config"
            return 1
            ;;
        *)
            # Fallback: use generic logic for unknown assistants
            print_verbose "Using generic credential check for unknown assistant: $cli"
            
            # Skip credential check if no API key is expected
            if [[ -z "$api_env" ]]; then
                print_verbose "No API key required for $cli"
                return 0
            fi

            # Check environment variable
            if [[ -n "$api_env" && -n "${!api_env}" ]]; then
                print_verbose "Found credentials in ${api_env}"
                return 0
            fi

            # Check auth files
            local auth_file="$cfg_dir/auth.json"
            local cfg_file="$cfg_dir/${dir_name}.json"
            if [[ -f "$auth_file" && -s "$auth_file" ]]; then
                print_verbose "Found credentials file $auth_file"
                return 0
            fi
            if [[ -f "$cfg_file" && -s "$cfg_file" ]]; then
                print_verbose "Found credentials file $cfg_file"
                return 0
            fi
            
            print_verbose "No credentials found for $cli"
            return 1
            ;;
    esac
}

# Print appropriate message when credentials are missing
# Arguments:
#   $1 - assistant_cli (e.g., "claude", "gemini")
#   $2 - context: "login" or "run" (default: "run")
print_credential_failure_message() {
    local assistant_cli="$1"
    local context="${2:-run}"

    # Capitalize first letter for display
    local display_name="${assistant_cli^}"

    if [[ "$context" == "login" ]]; then
        # User is already in login mode - guide them through the process
        print_info ""
        print_info "Starting $display_name authentication..."
        print_info "A browser window will open for you to log in."
    else
        # User tried to run without credentials - tell them to login first
        print_error "$display_name is not authenticated"
        print_info ""
        print_info "To authenticate, run:"
        print_info "  nyia-$assistant_cli --login"
    fi
}

generate_container_name() {
    local assistant_name="$1"
    local project_path="$2"
    local project_basename=$(basename "$project_path" | sed 's/[^a-zA-Z0-9._-]/-/g' | tr '[:upper:]' '[:lower:]')
    echo "nyarlathotia-${assistant_name}-${project_basename}-$(date +%s)"
}

# Run debug shell without git-entrypoint
run_debug_shell() {
    local full_image_name="$1"
    local project_path="$2" 
    local project_data_dir="$3"
    local global_config_dir="$4"
    local container_name="$5"
    local config_dir_name="$6"
    local assistant_cli="$7"

    print_verbose "Starting debug shell container $container_name"
    print_verbose "Image: $full_image_name"
    print_verbose "Bypassing git-entrypoint for direct shell access"

    # Derive canonical container path for unique project identification (Plan 71)
    local container_path
    container_path=$(get_canonical_container_path "$project_path")
    print_verbose "Project mount: $project_path -> $container_path"

    # Prepare environment variables
    local docker_env_args=()
    docker_env_args+=(-e NYIA_CONTEXT_DIR="${config_dir_name}")
    docker_env_args+=(-e NYIA_ASSISTANT_CLI="${assistant_cli}")
    docker_env_args+=(-e NYIA_PROVIDER="${assistant_cli}")
    docker_env_args+=(-e NYIA_ENABLE_PROMPT_LAYERING="${NYIA_ENABLE_PROMPT_LAYERING:-true}")
    docker_env_args+=(-e NYIA_ENABLE_SESSION_PERSISTENCE="${NYIA_ENABLE_SESSION_PERSISTENCE:-true}")
    docker_env_args+=(-e NYIA_PROJECT_PATH="$container_path")

    # Pass workspace mode to container (for RAG disable, exclusions status)
    if [[ "$WORKSPACE_MODE" == "true" ]]; then
        docker_env_args+=(-e NYIA_WORKSPACE_MODE="true")
        docker_env_args+=(-e NYIA_WORKSPACE_REPOS="$(printf '%s\n' "${WORKSPACE_REPOS[@]}")")
    fi

    # Create environment file for Docker
    local env_file=$(create_docker_env_file "$project_path" "$assistant_cli")
    docker_env_args+=("--env-file" "$env_file")
    
    # Enhanced cleanup function for environment file (security)
    cleanup_env_file() {
        [[ -f "$env_file" ]] && { 
            rm -f "$env_file" 2>/dev/null || true
            print_verbose "Cleaned up env file: $env_file"
        }
    }
    trap cleanup_env_file EXIT INT TERM QUIT  # Handle more signals
    
    # Get volume arguments (workspace mode or standard exclusions)
    if declare -f get_workspace_volume_args >/dev/null 2>&1; then
        get_workspace_volume_args "$project_path" "$container_path"
        if [[ "$WORKSPACE_MODE" == "true" ]]; then
            print_verbose "Using workspace mode volume mounting"
        else
            print_verbose "Using mount exclusions system"
        fi
        print_verbose "VOLUME_ARGS has ${#VOLUME_ARGS[@]} elements"
        if [[ "$VERBOSE" == "true" ]]; then
            for arg in "${VOLUME_ARGS[@]}"; do
                print_verbose "  Volume arg: $arg"
            done
        fi
    elif declare -f create_volume_args >/dev/null 2>&1; then
        create_volume_args "$project_path" "$container_path"
        print_verbose "Using mount exclusions system (legacy path)"
        print_verbose "VOLUME_ARGS has ${#VOLUME_ARGS[@]} elements"
    else
        VOLUME_ARGS=("-v" "$project_path:$container_path:rw")
        print_verbose "Using direct mount (exclusions not available)"
    fi

    # Try to pull image if using registry
    if [[ "$full_image_name" == ghcr.io/* ]]; then
        print_status "Pulling image from registry: $full_image_name"
        /usr/bin/docker pull "$full_image_name" 2>/dev/null || {
            print_warning "Failed to pull $full_image_name - using local image if available"
        }
    fi

    # Build additional credential mounts for codex (OpenAI CLI compatibility)
    local credential_mounts=()
    if [[ "$assistant_cli" == "codex" ]]; then
        credential_mounts+=(-v "$global_config_dir":/home/node/.openai:rw)
        credential_mounts+=(-v "$global_config_dir":/home/node/.config/openai:rw)
        print_verbose "Added OpenAI credential mounts for codex"
    fi

    # Direct bash execution, no entrypoint
    /usr/bin/docker run -it --rm \
        $(get_docker_network_args) \
        $(get_docker_user_args) \
        --entrypoint bash \
        "${VOLUME_ARGS[@]}" \
        -v "$project_data_dir":/data:rw \
        -v "$global_config_dir":/nyia-global:rw \
        -v "$global_config_dir":/home/node/.${assistant_cli}:rw \
        -v "$global_config_dir":/home/node/.config/${assistant_cli}:rw \
        "${credential_mounts[@]}" \
        "${docker_env_args[@]}" \
        --name "$container_name" \
        "$full_image_name"
    
    # Cleanup immediately after Docker run
    cleanup_env_file
    trap - EXIT
}

get_canonical_container_path() {
    # Derives a unique, reproducible container path from host project path
    # Format: /project/{sanitized-dirname}-{5char-hash}
    # Example: /home/user/myapp → /project/myapp-a3f2d
    local project_path="$1"

    # Get absolute path (resolves symlinks, relative paths)
    local full_path
    full_path=$(realpath "$project_path" 2>/dev/null || echo "$project_path")

    # Extract last directory name
    local dir_name
    dir_name=$(basename "$full_path")

    # Sanitize: lowercase, spaces→hyphens, remove special chars, limit to 40 chars
    local sanitized
    sanitized=$(echo "$dir_name" | \
        tr '[:upper:]' '[:lower:]' | \
        tr '[:space:]_' '--' | \
        sed 's/[^a-z0-9-]//g' | \
        sed 's/-\+/-/g' | \
        sed 's/^-\|-$//g' | \
        cut -c1-40)

    # Handle edge case: empty sanitized name (all special chars)
    if [[ -z "$sanitized" ]]; then
        sanitized="project"
    fi

    # Generate 5-char hash from full absolute path (1M+ unique combinations)
    local hash
    hash=$(echo -n "$full_path" | sha256sum | cut -c1-5)

    # Return canonical path
    echo "/project/${sanitized}-${hash}"
}

run_docker_container() {
    local full_image_name="$1"
    local project_path="$2"
    local project_data_dir="$3"
    local global_config_dir="$4"
    local container_name="$5"
    local base_branch="$6"
    local config_dir_name="$7"
    local context_dir_name="$8"
    local assistant_cli="$9"
    shift 9
    local container_args=("$@")

    # Derive canonical container path for unique project identification (Plan 71)
    local container_path
    container_path=$(get_canonical_container_path "$project_path")

    print_verbose "Running Docker container $container_name"
    print_verbose "Image: $full_image_name"
    print_verbose "Mount config dir: $global_config_dir -> /home/node/${config_dir_name}"
    print_verbose "Context dir env: $context_dir_name"
    print_verbose "Project mount: $project_path -> $container_path"

    # Build container command arguments
    local final_args=()
    
    if [[ -n "$base_branch" ]]; then
        final_args+=("--base-branch" "$base_branch")
    fi
    
    # Add remaining arguments
    final_args+=("${container_args[@]}")

    # Prepare environment variables
    local docker_env_args=()
    docker_env_args+=(-e NYIA_CONTEXT_DIR="${context_dir_name}")
    docker_env_args+=(-e NYIA_ASSISTANT_CLI="${assistant_cli}")
    docker_env_args+=(-e NYIA_PROVIDER="${assistant_cli}")
    docker_env_args+=(-e NYIA_ENABLE_PROMPT_LAYERING="${NYIA_ENABLE_PROMPT_LAYERING:-true}")
    docker_env_args+=(-e NYIA_ENABLE_SESSION_PERSISTENCE="${NYIA_ENABLE_SESSION_PERSISTENCE:-true}")
    docker_env_args+=(-e NYIA_PROJECT_PATH="$container_path")
    docker_env_args+=(-e NYIA_BUILD_TIMESTAMP="$(date -Iseconds)")

    # Pass work branch to container if set (for --work-branch support)
    if [[ -n "${NYIA_WORK_BRANCH:-}" ]]; then
        docker_env_args+=(-e NYIA_WORK_BRANCH="${NYIA_WORK_BRANCH}")
    fi

    # Pass current-branch mode to container (skip cleanup trap) - Plan 134
    if [[ "${NYIA_CURRENT_BRANCH_MODE:-}" == "true" ]]; then
        docker_env_args+=(-e NYIA_CURRENT_BRANCH_MODE="true")
    fi

    # Pass RAG settings to container (Plan 66 - Opt-in RAG)
    if [[ -n "${ENABLE_RAG:-}" ]]; then
        docker_env_args+=(-e ENABLE_RAG="${ENABLE_RAG}")
    fi
    if [[ -n "${NYIA_RAG_MODEL:-}" ]]; then
        docker_env_args+=(-e NYIA_RAG_MODEL="${NYIA_RAG_MODEL}")
    fi

    # Pass workspace mode to container (for RAG disable, exclusions status)
    if [[ "$WORKSPACE_MODE" == "true" ]]; then
        docker_env_args+=(-e NYIA_WORKSPACE_MODE="true")
        docker_env_args+=(-e NYIA_WORKSPACE_REPOS="$(printf '%s\n' "${WORKSPACE_REPOS[@]}")")
    fi

    # Create environment file for Docker
    local env_file=$(create_docker_env_file "$project_path" "$assistant_cli")
    docker_env_args+=("--env-file" "$env_file")
    
    # Enhanced cleanup function for environment file (security)
    cleanup_env_file() {
        [[ -f "$env_file" ]] && { 
            rm -f "$env_file" 2>/dev/null || true
            print_verbose "Cleaned up env file: $env_file"
        }
    }
    trap cleanup_env_file EXIT INT TERM QUIT  # Handle more signals
    
    # Get volume arguments (workspace mode or standard exclusions)
    if declare -f get_workspace_volume_args >/dev/null 2>&1; then
        get_workspace_volume_args "$project_path" "$container_path"
        if [[ "$WORKSPACE_MODE" == "true" ]]; then
            print_verbose "Using workspace mode volume mounting"
        else
            print_verbose "Using mount exclusions system"
        fi
        print_verbose "VOLUME_ARGS has ${#VOLUME_ARGS[@]} elements"
        if [[ "$VERBOSE" == "true" ]]; then
            for arg in "${VOLUME_ARGS[@]}"; do
                print_verbose "  Volume arg: $arg"
            done
        fi
    elif declare -f create_volume_args >/dev/null 2>&1; then
        create_volume_args "$project_path" "$container_path"
        print_verbose "Using mount exclusions system (legacy path)"
        print_verbose "VOLUME_ARGS has ${#VOLUME_ARGS[@]} elements"
    else
        VOLUME_ARGS=("-v" "$project_path:$container_path:rw")
        print_verbose "Using direct mount (exclusions not available)"
    fi

    print_verbose "Starting Docker container"
    print_verbose "Docker env args: ${docker_env_args[@]}"
    
    # Verify mount source exists and is writable (critical for credential persistence)
    if [[ ! -d "$global_config_dir" ]]; then
        print_warning "Config directory missing, creating: $global_config_dir"
        mkdir -p "$global_config_dir"
    fi
    if [[ ! -w "$global_config_dir" ]]; then
        print_error "Config directory not writable: $global_config_dir"
        print_info "Fix with: sudo chown -R $(id -u):$(id -g) $global_config_dir"
        return 1
    fi
    print_verbose "Mount verification: $global_config_dir -> /home/node/.${assistant_cli} (OK)"

    # Try to pull image if using registry
    if [[ "$full_image_name" == ghcr.io/* ]]; then
        print_status "Pulling image from registry: $full_image_name"
        /usr/bin/docker pull "$full_image_name" 2>/dev/null || {
            print_warning "Failed to pull $full_image_name - using local image if available"
        }
    fi

    # Build additional credential mounts for codex (OpenAI CLI compatibility)
    local credential_mounts=()
    if [[ "$assistant_cli" == "codex" ]]; then
        credential_mounts+=(-v "$global_config_dir":/home/node/.openai:rw)
        credential_mounts+=(-v "$global_config_dir":/home/node/.config/openai:rw)
        print_verbose "Added OpenAI credential mounts for codex"
    fi

    /usr/bin/docker run -it --rm \
        $(get_docker_network_args) \
        $(get_docker_user_args) \
        -w "$container_path" \
        "${VOLUME_ARGS[@]}" \
        -v "$project_data_dir":/data:rw \
        -v "$global_config_dir":/nyia-global:rw \
        -v "$global_config_dir":/home/node/.${assistant_cli}:rw \
        -v "$global_config_dir":/home/node/.config/${assistant_cli}:rw \
        "${credential_mounts[@]}" \
        "${docker_env_args[@]}" \
        --name "$container_name" \
        "$full_image_name" "${final_args[@]}"
    
    # Cleanup immediately after Docker run
    cleanup_env_file
    trap - EXIT
}

# Run interactive login using the assistant container
# Arguments:
#   $1 - Assistant CLI command
#   $2 - Base image name
#   $3 - Dockerfile path
#   $4 - Config directory name for credentials
#   $5 - Authentication method (e.g. device_code, chatgpt_signin)
#   $6 - Dev mode flag (true/false)
# Helper to set up API key for team plan users
set_api_key_helper() {
    local assistant_name="$1"
    local assistant_cli="$2"
    
    echo "🔑 OpenAI API Key Setup for $assistant_name"
    echo ""
    echo "ℹ️  This helper extracts API key from your codex login for team plan users."
    echo ""
    
    # Check if already exported
    if [[ -n "$OPENAI_API_KEY" ]]; then
        print_success "OPENAI_API_KEY is already set: ${OPENAI_API_KEY:0:20}..."
        return 0
    fi
    
    # Look for auth.json from codex login
    local nyia_home=$(get_nyarlathotia_home)
    local auth_file="$nyia_home/$assistant_cli/auth.json"
    
    if [[ ! -f "$auth_file" ]]; then
        print_error "No auth.json found. Please run: $assistant_name --login first"
        return 1
    fi
    
    print_status "Found auth.json, extracting API key..."
    
    # Extract API key from auth.json
    local api_key=$(grep -o '"OPENAI_API_KEY": "[^"]*"' "$auth_file" | cut -d'"' -f4)
    
    if [[ -z "$api_key" ]]; then
        print_error "No OPENAI_API_KEY found in auth.json"
        print_info "Your account might be Plus/Pro (no API key needed)"
        print_info "Try running: $assistant_name \"test prompt\" directly"
        return 1
    fi
    
    if [[ ! "$api_key" =~ ^sk- ]]; then
        print_warning "Extracted key doesn't look like an API key: ${api_key:0:20}..."
    fi
    
    # Export the key
    export OPENAI_API_KEY="$api_key"
    
    # Suggest permanent setup
    echo ""
    print_success "✅ API key set for current session"
    echo ""
    print_info "💡 To make this permanent, add to your shell profile:"
    echo "   echo 'export OPENAI_API_KEY=\"$api_key\"' >> ~/.bashrc"
    echo "   echo 'export OPENAI_API_KEY=\"$api_key\"' >> ~/.zshrc"
    echo ""
    print_warning "⚠️  BILLING: Team plan usage will be charged at API rates"
    print_info "📊 Monitor usage: https://platform.openai.com/usage"
    echo ""
    print_info "🧪 Test with: $assistant_name \"hello world\""
    
    return 0
}

login_assistant() {
    local assistant_cli="$1"
    local base_image_name="$2"
    local dockerfile_path="$3"
    local config_dir_name="$4"
    local auth_method="$5"
    local shell_mode="${6:-false}"
    local docker_image="${7:-}"

    local nyia_home=$(get_nyarlathotia_home)
    local global_config_dir="$nyia_home/$assistant_cli"
    mkdir -p "$global_config_dir"

    # Backup config before login (protects against corruption)
    backup_assistant_config "$global_config_dir"

    # Source provider-specific hooks if they exist (ensure functions are available)
    local provider_hooks_file="$dockerfile_path/${assistant_cli}-hooks.sh"
    if [[ -f "$provider_hooks_file" ]]; then
        print_verbose "Sourcing provider hooks: $provider_hooks_file"
        source "$provider_hooks_file"
    fi

    # Check if already authenticated (unless --force used)
    if [[ "${FORCE_LOGIN:-false}" != "true" ]]; then
        if check_credentials "$assistant_cli" "$global_config_dir" "$config_dir_name" "$API_KEY_ENV"; then
            print_success "✅ $assistant_cli is already authenticated"
            print_info "📁 Config directory: $global_config_dir"

            # Show file status
            if [[ -f "$global_config_dir/.credentials.json" ]]; then
                print_info "📁 Credentials: Found"
            fi
            if [[ -f "$global_config_dir/.claude.json" ]]; then
                print_info "📁 Settings: Found"
            fi

            echo ""
            print_info "💡 No login needed. To force re-authentication:"
            print_info "   nyia-$assistant_cli --login --force"
            return 0
        fi
    else
        print_info "🔄 Force login requested - proceeding with re-authentication"
    fi

    # If credentials were missing (not force mode), show login start message
    if [[ "${FORCE_LOGIN:-false}" != "true" ]]; then
        print_credential_failure_message "$assistant_cli" "login"
    fi

    # Select Docker image to use
    local full_image_name
    if ! full_image_name=$(select_docker_image "$base_image_name" "$docker_image"); then
        print_error "Failed to select Docker image for login"
        exit 1
    fi
    
    # Check if the selected image exists
    if ! /usr/bin/docker image inspect "$full_image_name" >/dev/null 2>&1; then
        print_status "Image not found: $full_image_name"
        print_status "Pulling image from registry for login..."
        local registry=$(get_docker_registry)
        local registry_image="${registry}/nyarlathotia-${assistant_cli}:latest"
        if ! docker pull "$registry_image"; then
            print_error "Failed to pull image: $registry_image"
            exit 1
        fi
        full_image_name="$registry_image"
    fi

    # Ask provider hook for login command, fallback to modern commands
    local login_cmd
    if declare -f get_login_command > /dev/null; then
        print_verbose "Using provider-specific login command for $assistant_cli"
        read -a login_cmd <<< "$(get_login_command "$assistant_cli")"
        print_verbose "Login command: ${login_cmd[*]}"
    else
        print_verbose "No get_login_command function found, using modern fallback for $assistant_cli"
        # Modern fallback: use current command patterns
        case "$assistant_cli" in
            claude)
                login_cmd=("claude" "/quit")
                ;;
            codex)
                login_cmd=("$assistant_cli" "login")
                ;;
            *)
                # Default for other assistants
                login_cmd=("$assistant_cli" "login")
                ;;
        esac
        print_verbose "Fallback login command: ${login_cmd[*]}"
    fi
    case "$auth_method" in
        device_code)
            login_cmd+=("--device-code")
            ;;
        token_setup)
            # Claude setup-token doesn't require additional flags
            ;;
        chatgpt_signin)
            # Codex no longer requires an explicit flag for ChatGPT sign-in
            ;;

    esac

    print_status "Starting $assistant_cli authentication..."
    
    # Warning about account types and billing
    if [[ "$assistant_cli" == "codex" ]]; then
        echo ""
        print_warning "⚠️  IMPORTANT: After login, you may need to export the API key:"
        echo "   📱 Plus/Pro (individual): Login usually works directly (included in subscription)"
        echo "   🏢 Team Plan: Login works, but you need to export the API key afterward"
        echo ""
        print_info "💰 Team plan usage will consume tokens at standard API rates"
        print_info "📖 More info: https://platform.openai.com/docs/guides/rate-limits"
        echo ""
        print_info "🔧 If you get API key errors after login: nyia-codex --set-api-key"
        echo ""
    fi

    # Mount credential path for CLI to persist tokens
    mkdir -p "$global_config_dir"

    local -a docker_opts=(
        $(get_docker_user_args)
        -v "$global_config_dir":/nyia-global:rw
        -v "$global_config_dir":/home/node/.${assistant_cli}:rw
        -v "$global_config_dir":/home/node/.config/${assistant_cli}:rw
        -e NYIA_ASSISTANT_CLI="$assistant_cli"
        -e NYIA_CONTEXT_DIR="$config_dir_name"
    )

    if [[ "$auth_method" == "chatgpt_signin" ]]; then
        docker_opts+=(--network host)
    fi

    if [[ "$shell_mode" == "true" ]]; then
        # Shell mode: debug shell in login container
        print_status "🐚 Debug shell mode in login container"
        print_status "You can manually run: ${login_cmd[*]}"
        
        /usr/bin/docker run -it --rm \
            --entrypoint bash \
            "${docker_opts[@]}" \
            "$full_image_name"
    else
        # Normal login mode
        if [[ "$assistant_cli" == "claude" ]]; then
            # For Claude, run with a special script that handles config preservation
            print_verbose "Starting Claude login with config watcher"

            # Create a wrapper script that will run inside container
            local wrapper_script=$(mktemp)

            # Build the login command string
            local login_cmd_str="${login_cmd[*]}"

            cat > "$wrapper_script" << EOF
#!/usr/bin/env bash
# Start config watcher in background - continuously monitors for changes
(
    timeout=300  # 5 minutes max
    elapsed=0
    config_file="/home/node/.claude.json"
    mount_file="/home/node/.claude/.claude.json"
    last_checksum=""
    file_found=false

    echo "Config watcher: Starting continuous monitoring..."

    while [[ \$elapsed -lt \$timeout ]]; do
        if [[ -f "\$config_file" && ! -L "\$config_file" ]]; then
            # Calculate file checksum to detect changes
            current_checksum=\$(md5sum "\$config_file" 2>/dev/null | cut -d' ' -f1)

            if [[ "\$current_checksum" != "\$last_checksum" ]]; then
                # File created or changed - copy it
                cp "\$config_file" "\$mount_file"
                last_checksum="\$current_checksum"

                if [[ "\$file_found" == "false" ]]; then
                    echo "Config watcher: Initial file captured"
                    file_found=true
                else
                    echo "Config watcher: File updated, copied again"
                fi
            fi
        fi

        sleep 0.5
        elapsed=\$((elapsed + 1))
    done

    echo "Config watcher: Timeout after \${timeout}s"
) &
watcher_pid=\$!

# Run the actual login command (normal claude)
$login_cmd_str
login_exit=\$?

# Kill watcher
kill \$watcher_pid 2>/dev/null || true

# Final copy to catch all updates
if [[ \$login_exit -eq 0 && -f "/home/node/.claude.json" && ! -L "/home/node/.claude.json" ]]; then
    cp "/home/node/.claude.json" "/home/node/.claude/.claude.json"
    echo "Final config preservation complete"
fi

exit \$login_exit
EOF
            chmod +x "$wrapper_script"

            # Run with wrapper script
            /usr/bin/docker run -it --rm \
                "${docker_opts[@]}" \
                -v "$wrapper_script":/tmp/login-wrapper.sh:ro \
                --entrypoint /tmp/login-wrapper.sh \
                "$full_image_name"
            local login_exit=$?

            # Cleanup wrapper script
            rm -f "$wrapper_script"

            if [[ $login_exit -eq 0 ]]; then
                print_success "Claude login completed with config preservation"
            fi
        else
            # Normal login for other assistants
            /usr/bin/docker run -it --rm \
                "${docker_opts[@]}" \
                "$full_image_name" "${login_cmd[@]}"
        fi

        # Verify credentials persisted to host after login
        verify_credential_persistence "$assistant_cli" "$global_config_dir"
    fi
}

# Verify that credentials were persisted from container to host
verify_credential_persistence() {
    local assistant_cli="$1"
    local global_config_dir="$2"
    
    print_verbose "Verifying credential persistence for $assistant_cli"
    
    case "$assistant_cli" in
        claude)
            # Check for Claude credentials file
            if [[ -f "$global_config_dir/.credentials.json" ]]; then
                print_success "✅ Claude credentials saved to: $global_config_dir"
                print_verbose "Credentials file size: $(stat -c%s "$global_config_dir/.credentials.json" 2>/dev/null || echo 'unknown') bytes"

                # Also check for config file
                if [[ -f "$global_config_dir/.claude.json" ]]; then
                    print_success "✅ Claude configuration saved to: $global_config_dir/.claude.json"
                    print_verbose "Config file size: $(stat -c%s "$global_config_dir/.claude.json" 2>/dev/null || echo 'unknown') bytes"
                else
                    print_info "ℹ️  Claude configuration will be created on first use"
                fi

                return 0
            else
                print_warning "⚠️  Claude credentials not found on host after login"
                print_info "Expected location: $global_config_dir/.credentials.json"
                print_info "This may indicate a Docker mount issue"

                # Diagnostic information
                if [[ -d "$global_config_dir" ]]; then
                    print_verbose "Directory contents:"
                    ls -la "$global_config_dir" >&2
                else
                    print_error "Config directory doesn't exist: $global_config_dir"
                    print_info "Creating directory and retrying login may help"
                fi
                return 1
            fi
            ;;
        gemini)
            # Check for Gemini OAuth file
            if [[ -f "$global_config_dir/oauth_creds.json" ]]; then
                print_success "✅ Gemini credentials saved to: $global_config_dir"
                return 0
            else
                print_verbose "Gemini OAuth file not found (may be using API key instead)"
                return 0
            fi
            ;;
        codex|opencode)
            # These handle their own persistence
            print_verbose "Credential persistence handled internally by $assistant_cli"
            return 0
            ;;
        *)
            print_verbose "No persistence verification for $assistant_cli"
            return 0
            ;;
    esac
}

# === PROJECT CONTEXT INITIALIZATION ===
init_project_context() {
    local project_path="$1"
    local context_dir_name="$2"
    local assistant_name="$3"
    local context_dir="$project_path/$context_dir_name"

    if [[ ! -d "$context_dir" ]]; then
        print_status "Initializing ${assistant_name} context directory..."
        mkdir -p "$context_dir"

        # Create initial context file
        cat > "$context_dir/context.md" << EOF
# Project: $(basename "$project_path")

## Architecture
- Framework: [To be detected]
- Key patterns: [To be analyzed]

## Project Structure
- Main files: [To be identified]

## Current Focus
- Status: New project analysis needed

## Important Notes
- Initial setup completed
EOF

        # Note: decisions.md and todo.md are no longer created here
        # Project-wide todo.md is in .nyarlathotia/todo.md
        # Decisions are tracked in context.md as insights

        print_success "${assistant_name} context directory initialized"
    fi
}

# === STATUS DISPLAY ===
show_assistant_status() {
    local assistant_name="$1"
    local project_path="$2"
    local nyarlathotia_home="$3"
    local base_image_name="$4"
    local context_dir_name="$5"
    local force_production="${6:-false}"
    
    local project_hash=$(get_project_hash "$project_path")
    local global_config_dir="$nyarlathotia_home/$assistant_name"
    local data_dir="$nyarlathotia_home/data/$project_hash"
    local current_branch=$(get_current_branch "$project_path")
    local full_image_name=$(get_docker_image_name "$base_image_name" "$force_production")

    echo "NyarlathotIA ${assistant_name} Status:"
    echo "  Project: $(basename "$project_path")"
    echo "  Path: $project_path"
    echo "  Branch: $current_branch"
    
    # Show image information

    # Runtime: Show registry image status
    local registry=$(get_docker_registry)
    local registry_image="${registry}/nyarlathotia-${assistant_name}:latest"
    echo "  Image: $registry_image (registry)"
    if docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "$registry_image"; then
        echo "  Status: ✅ Available locally"
    else
        echo "  Status: ⏳ Will be pulled when needed"
    fi
    
    echo "  Hash: $project_hash"
    echo "  Data dir: $data_dir"
    echo "  Context dir: $project_path/$context_dir_name"
    echo "  Assistant config: $global_config_dir"

    if [[ -d "$project_path/$context_dir_name" ]]; then
        echo "  Context files:"
        ls -la "$project_path/$context_dir_name/" 2>/dev/null || echo "    None found"
    else
        echo "  Context: Not initialized"
    fi

    if [[ -d "$global_config_dir" ]]; then
        echo "  Assistant config: ✅ Ready"
        echo "    Contents:"
        ls -la "$global_config_dir/" 2>/dev/null || echo "    Empty (setup needed)"
    else
        echo "  Assistant config: ❌ Not set up"
    fi

    # Check if current Docker image exists

    # Runtime: Check registry image availability
    local registry=$(get_docker_registry)
    local registry_image="${registry}/nyarlathotia-${assistant_name}:latest"
    if docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "$registry_image"; then
        echo "  Current image: ✅ Ready"
    else
        echo "  Current image: ⏳ Available from registry"
    fi
    
    # Show all available images for this assistant
    echo "  Available images:"
    if docker images --filter "reference=${base_image_name}*" --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}" | tail -n +2 | grep -q .; then
        docker images --filter "reference=${base_image_name}*" --format "    {{.Repository}}:{{.Tag}} ({{.Size}}, {{.CreatedAt}})"
    else
        echo "    No images found"
    fi
}

# === CLI PARSING REMOVED ===
# CLI argument parsing has been moved to lib/cli-parser.sh for centralization

# === IMAGE MANAGEMENT ===
list_assistant_images() {
    local base_image_name="$1"

    # Strip nyarlathotia- prefix to match actual image names
    local clean_name="${base_image_name#nyarlathotia-}"
    local search_pattern="nyarlathotia/${clean_name}"

    print_status "Available images for ${clean_name}:"

    if command -v docker >/dev/null && docker images --filter "reference=${search_pattern}*" --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}" 2>/dev/null | tail -n +2 | grep -q . 2>/dev/null; then
        docker images --filter "reference=${search_pattern}*" --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"
    else
        print_info "No images found for ${clean_name}"
        print_info "Build images with:"
        print_info "  --build      # Production image (:latest)"
        print_info "  --build --dev # Development image (:dev)"
    fi
}

select_docker_image() {
    local base_image_name="$1"
    local docker_image="$2"

    # Use flavor-aware image resolution
    # Precedence: --image > --flavor > default
    local selected_image
    if selected_image=$(resolve_flavor_image "$base_image_name" "$FLAVOR" "$docker_image"); then
        # Check if it's a custom image (--image flag) vs flavor/default
        if [[ -n "$docker_image" ]]; then
            # Validate custom image name for security
            if ! validate_image_name "$docker_image"; then
                print_error "Invalid Docker image specification"
                return 1
            fi
            print_status "Image selection: Using specified image: $selected_image" >&2
        elif [[ -n "$FLAVOR" ]]; then
            print_status "Image selection: Using flavor '$FLAVOR': $selected_image" >&2
        else
            print_status "Image selection: Using default image: $selected_image" >&2
        fi
        echo "$selected_image"
        return 0
    else
        print_error "Failed to resolve image with flavor support"
        return 1
    fi
}

# List available flavors for an assistant
list_assistant_flavors() {
    local assistant_name="$1"
    local script_dir="$(dirname "${BASH_SOURCE[0]}")"
    local flavors_file="$script_dir/../lib/flavors.list"

    echo "NyarlathotIA ${assistant_name} - Available Flavors:"
    echo ""

    if [[ -f "$flavors_file" ]]; then
        while IFS='|' read -r name desc; do
            [[ -z "$name" ]] && continue
            printf "  %-12s - %s\n" "$name" "$desc"
        done < "$flavors_file"
    else
        # Fallback if file missing
        echo "  python, php, node, react, cypress, expo, php-react"
        echo ""
        echo "  (Run from installation directory for full descriptions)"
    fi

    echo ""
    echo "Usage:"
    echo "  nyia-${assistant_name} --flavor python -p \"Write pytest tests\""
    echo "  nyia-${assistant_name} --flavor react -p \"Create Storybook stories\""
    echo ""
    echo "Note: Flavors are pulled from registry on first use."
}

# === ASSISTANT EXECUTION ===
run_assistant() {
    local assistant_name="$1"
    local assistant_cli="$2"
    local base_image_name="$3"
    local dockerfile_path="$4"
    local context_dir_name="$5"
    local project_path="$6"
    local prompt="$7"
    local base_branch="$8"
    local shell_mode="${9:-false}"
    local docker_image="${10:-}"
    local work_branch="${11:-}"

    # Get NyarlathotIA home
    local nyarlathotia_home=$(get_nyarlathotia_home)
    
    # Validate project path
    if [[ ! -d "$project_path" ]]; then
        print_error "Project path does not exist: $project_path"
        exit 1
    fi

    # Get project hash for data persistence
    local project_hash=$(get_project_hash "$project_path")
    local project_data_dir="$nyarlathotia_home/data/$project_hash"

    # Create data directory if needed
    mkdir -p "$project_data_dir"

    # Create assistant config directory - use CLI name for consistency with login
    local global_config_dir="$nyarlathotia_home/$assistant_cli"
    mkdir -p "$global_config_dir"

    # Container path for credentials (default: uses config value or assistant CLI)
    local config_dir_name="${CONFIG_DIR_NAME:-.$assistant_cli}"

    print_verbose "Assistant config dir: $global_config_dir"
    print_verbose "Config directory name: $config_dir_name"

    # Backup config before launch (protects against corruption)
    backup_assistant_config "$global_config_dir"

    # Get prompt filename for this assistant
    local prompt_filename=$(get_prompt_filename "$assistant_cli")
    
    # Check git exclusions on first run
    check_git_exclusions "$project_path" "$prompt_filename"
    
    # Generate assistant prompts before container start
    if ! generate_assistant_prompts "$assistant_name" "$assistant_cli" "$project_path"; then
        print_error "Failed to generate prompts for $assistant_name"
        exit 1
    fi

    # Ensure credentials exist before launching container (skip for shell mode)
    if [[ "$shell_mode" != "true" ]] && ! check_credentials "$assistant_cli" "$global_config_dir" "$config_dir_name" "$API_KEY_ENV"; then
        # Vibe: offer interactive prompt to enter API key
        if [[ "$assistant_cli" == "vibe" ]]; then
            print_info "No Mistral API key found."
            print_info "Get your key at: https://console.mistral.ai/api-keys"
            echo ""
            read -r -p "Enter your Mistral API key (or press Enter to cancel): " vibe_api_key
            if [[ -n "$vibe_api_key" ]]; then
                # Save to config file
                local vibe_config_file="$global_config_dir/../config/vibe.conf"
                if [[ -f "$vibe_config_file" ]]; then
                    # Append to existing config
                    echo "" >> "$vibe_config_file"
                    echo "# Added by nyia-vibe on $(date +%Y-%m-%d)" >> "$vibe_config_file"
                    echo "MISTRAL_API_KEY=\"$vibe_api_key\"" >> "$vibe_config_file"
                else
                    # Create minimal config
                    echo "MISTRAL_API_KEY=\"$vibe_api_key\"" > "$vibe_config_file"
                fi
                export MISTRAL_API_KEY="$vibe_api_key"
                print_success "API key saved to config file"
                # Continue execution - don't return 1
            else
                print_warning "No API key provided. Cannot continue."
                return 1
            fi
        else
            # Other assistants: show error message and exit
            case "$assistant_cli" in
                gemini)
                    print_warning "Gemini authentication required. Choose one method:"
                    print_warning "1. Run 'nyia-gemini --shell' for interactive OAuth authentication"
                    print_warning "2. Set GEMINI_API_KEY environment variable"
                    print_warning "3. For Vertex AI: Set GOOGLE_CLOUD_PROJECT + GOOGLE_APPLICATION_CREDENTIALS"
                    ;;
                codex)
                    print_warning "No credentials found for $assistant_name"
                    print_warning "Set OPENAI_API_KEY or run 'nyia-$assistant_name --login' to authenticate"
                    ;;
                *)
                    # Use helper function for consistent messaging
                    print_credential_failure_message "$assistant_cli" "run"
                    ;;
            esac
            return 1
        fi
    fi
    

    # Initialize project context
    init_project_context "$project_path" "$context_dir_name" "$assistant_name"

    # Select Docker image to use
    local full_image_name
    if ! full_image_name=$(select_docker_image "$base_image_name" "$docker_image"); then
        print_error "Failed to select Docker image"
        exit 1
    fi
    
    # Check if the selected image exists
    if ! /usr/bin/docker image inspect "$full_image_name" >/dev/null 2>&1; then
        print_error "Image not found: $full_image_name"
        
        # Show available images for reference
        print_info "Available images:"
        if docker images --filter "reference=${base_image_name}*" --format "  {{.Repository}}:{{.Tag}}" 2>/dev/null | head -10 | grep -q .; then
            docker images --filter "reference=${base_image_name}*" --format "  {{.Repository}}:{{.Tag}}" 2>/dev/null | head -10
        else
            print_info "  No images found for $base_image_name"
        fi
        
        # Different behavior based on what caused the failure
        if [[ -n "$docker_image" ]]; then
            # User explicitly specified --image: fail with helpful message, no building
            echo ""
            print_error "Explicit image selection failed"
            print_info "💡 Usage examples:"
            print_info "  nyia-${assistant_cli} --image dev                 # Use dev image"
            print_info "  nyia-${assistant_cli} --image latest              # Use latest"
            print_info "  nyia-${assistant_cli} --list-images               # List available"
            print_info "  nyia-${assistant_cli}                             # Use default"
            exit 1
        elif [[ -n "$FLAVOR" ]]; then
            # User specified --flavor but image doesn't exist
            show_flavor_error "$assistant_cli" "$FLAVOR"
            exit 1
        else
            # No explicit image specified: normal user without image
            echo ""

            print_status "Pulling image from registry..."
            local registry=$(get_docker_registry)
            local registry_image="${registry}/nyarlathotia-${assistant_cli}:latest"
            if ! docker pull "$registry_image"; then
                print_error "Failed to pull image: $registry_image"
                print_info "💡 Contact administrator if registry access issues persist"
                exit 1
            fi
            full_image_name="$registry_image"
        fi
    else
        print_success "Image found: $full_image_name"
    fi

    # Generate container name
    local container_name=$(generate_container_name "$assistant_name" "$project_path")

    # Show execution context
    local current_branch=$(get_current_branch "$project_path")
    print_status "Starting $assistant_name for project: $(basename "$project_path")"
    print_status "Branch: $current_branch"
    print_status "Using image: $full_image_name"
    print_status "Project hash: $project_hash"
    print_status "Assistant config: $global_config_dir"
    print_status "Running as user: $(id -u):$(id -g) (mapped to node in container)"

    # Handle branch creation/switching before running container
    if [[ "$shell_mode" != "true" ]]; then
        # --current-branch is not compatible with workspace mode (Plan 134)
        if [[ "${CURRENT_BRANCH_MODE:-false}" == "true" && "${WORKSPACE_MODE:-false}" == "true" ]]; then
            print_error "--current-branch is not compatible with workspace mode"
            print_info "Workspace mode requires branch synchronization across repos."
            print_info "Use --work-branch <name> instead."
            exit 1
        fi

        # --current-branch mode: validate current branch, skip branch creation (Plan 134)
        if [[ "${CURRENT_BRANCH_MODE:-false}" == "true" ]]; then
            local current=$(get_current_branch "$project_path")
            # Reject detached HEAD
            if [[ -z "$current" || "$current" == "HEAD" || "$current" == "no-git" ]]; then
                print_error "Cannot use --current-branch in detached HEAD state"
                print_info "Checkout a branch first: git checkout <branch-name>"
                exit 1
            fi
            # Reuse existing branch validation (protected branch + format check)
            if ! validate_work_branch "$current" "$project_path"; then
                exit 1
            fi
            print_info "Working on current branch: $current (--current-branch mode)"
            export NYIA_WORK_BRANCH="$current"
            export NYIA_CURRENT_BRANCH_MODE="true"
        else

        # Capture original branches BEFORE any branch operations (for rollback in workspace mode)
        if [[ "$WORKSPACE_MODE" == "true" ]] && [[ ${#WORKSPACE_REPOS[@]} -gt 0 ]]; then
            capture_original_branches "$project_path"

            # Check if the target work branch exists BEFORE create_assistant_branch
            # This tells us if we're creating a new branch or switching to existing
            local target_branch="${work_branch:-}"
            if [[ -z "$target_branch" ]]; then
                # Auto-generated branch will be new
                export MAIN_BRANCH_PRE_EXISTED=false
            elif git -C "$project_path" branch --list "$target_branch" 2>/dev/null | grep -q .; then
                # Explicit branch exists - we'll switch to it
                export MAIN_BRANCH_PRE_EXISTED=true
            else
                # Explicit branch doesn't exist - we'll create it
                export MAIN_BRANCH_PRE_EXISTED=false
            fi
        fi

        # Create or switch to appropriate branch (skip for shell mode)
        # Pass CREATE_BRANCH (5th param) for --create flag support
        if ! create_assistant_branch "$assistant_name" "$project_path" "$base_branch" "$work_branch" "${CREATE_BRANCH:-false}"; then
            print_error "Failed to create or switch to branch"
            exit 1
        fi
        # Capture the current branch after branch creation/switching for container
        local current_work_branch=$(get_current_branch "$project_path")
        export NYIA_WORK_BRANCH="$current_work_branch"

        # Sync branch to workspace repos (if in workspace mode) - Plan 103
        if [[ "$WORKSPACE_MODE" == "true" ]] && [[ ${#WORKSPACE_REPOS[@]} -gt 0 ]]; then
            if ! sync_workspace_branches "$project_path" "$current_work_branch" "true"; then
                print_error "Failed to sync branches across workspace repositories"
                exit 1
            fi
        fi

        fi  # end CURRENT_BRANCH_MODE check
    fi

    if [[ "$shell_mode" == "true" ]]; then
        # Shell mode - debug bash shell (bypass git-entrypoint)
        print_status "Starting debug shell..."
        print_status "🐚 Debug shell mode - direct container access, no git workflow"
        
        # Use a different container execution that bypasses git-entrypoint
        run_debug_shell "$full_image_name" "$project_path" "$project_data_dir" "$global_config_dir" "$container_name" "$config_dir_name" "$assistant_cli"
    elif [[ -z "$prompt" ]]; then
        # Interactive mode (no prompt provided)
        print_status "Starting interactive session..."
        print_status "🎯 ${assistant_name} auth & theme saved globally (setup once, use everywhere!)"
        
        run_docker_container "$full_image_name" "$project_path" "$project_data_dir" "$global_config_dir" "$container_name" "$base_branch" "$config_dir_name" "$context_dir_name" "$assistant_cli" "bash"
    else
        # Direct prompt mode
        print_status "Running prompt: $prompt"
        
        run_docker_container "$full_image_name" "$project_path" "$project_data_dir" "$global_config_dir" "$container_name" "$base_branch" "$config_dir_name" "$context_dir_name" "$assistant_cli" "$assistant_cli" "$prompt"
    fi
}

# === INTELLIGENT BRANCH MANAGEMENT ===

# Get list of protected branches that should never be used as work branches
get_protected_branches() {
    local protected_branches=()
    
    # Always protect main and master
    protected_branches+=("main" "master")
    
    # Detect default branch from git
    local default_branch
    default_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || true)
    if [[ -n "$default_branch" ]]; then
        protected_branches+=("$default_branch")
    fi
    
    # Try to get GitHub protected branches via gh CLI (optional)
    if command -v gh >/dev/null 2>&1; then
        local github_protected
        github_protected=$(gh api repos/:owner/:repo/branches --jq '.[] | select(.protected==true) | .name' 2>/dev/null || true)
        if [[ -n "$github_protected" ]]; then
            # Add each protected branch
            while IFS= read -r branch; do
                [[ -n "$branch" ]] && protected_branches+=("$branch")
            done <<< "$github_protected"
        fi
    fi
    
    # Remove duplicates and sort
    printf '%s\n' "${protected_branches[@]}" | sort -u | grep -v '^$'
}

# Validate a work branch name for security and policy
validate_work_branch() {
    local branch_name="$1"
    local project_path="${2:-$(pwd)}"
    
    # Validate input format first
    if ! validate_branch_name "$branch_name" 2>/dev/null; then
        print_error "Invalid work branch name format: '$branch_name'"
        print_info "Work branch names can only contain: a-z A-Z 0-9 . / _ -"
        return 1
    fi

    # Get list of protected branches
    local protected_branches
    protected_branches=$(cd "$project_path" && get_protected_branches 2>/dev/null)
    
    # Check if branch is protected
    while IFS= read -r protected_branch; do
        if [[ -n "$protected_branch" && "$branch_name" == "$protected_branch" ]]; then
            print_error "Cannot use protected branch as work branch: '$branch_name'"
            print_info "Protected branches detected:"
            echo "$protected_branches" | sed 's/^/  - /'
            print_info "Use a feature branch name like: feature/$branch_name"
            return 1
        fi
    done <<< "$protected_branches"
    
    return 0
}

# Check if branch exists locally, remotely, or not at all
check_branch_existence() {
    local branch_name="$1"
    local project_path="${2:-$(pwd)}"

    cd "$project_path" || return 3

    # Check local branches FIRST (no network needed)
    if git branch | grep -q "^[* ] $branch_name$"; then
        echo "local"
        return 0
    fi

    # Only fetch from remote if not found locally
    # This avoids SSH prompts for local-only branches
    git fetch --quiet 2>/dev/null || true

    # Check remote branches - handle both "origin/branch" and "branch" formats
    local clean_branch="$branch_name"
    if [[ "$branch_name" =~ ^origin/ ]]; then
        clean_branch="${branch_name#origin/}"
    fi

    # Look for the branch on any remote
    if git branch -r | grep -qE "(^|\s+)[^/]+/$clean_branch$"; then
        echo "remote"
        return 0
    fi

    # Branch doesn't exist anywhere
    echo "none"
    return 1
}

# Removed fuzzy matching - just show available branches

# Create or switch to work branch (FIXED - no more surprise branch creation!)
# Parameter 5 (create_mode): "true" to create branch if missing, "false" for switch-only
create_or_switch_work_branch() {
    local assistant_name="$1"
    local work_branch="$2"
    local base_branch="$3"
    local project_path="${4:-$(pwd)}"
    local create_mode="${5:-false}"

    cd "$project_path" || {
        print_error "Cannot access project path: $project_path"
        return 1
    }

    # Validate work branch first
    if ! validate_work_branch "$work_branch" "$project_path"; then
        return 1
    fi

    # 🔥 NEW: Check if branch actually exists before doing anything
    local existence_status
    existence_status=$(check_branch_existence "$work_branch" "$project_path")
    local check_result=$?

    case "$existence_status" in
        "local")
            # Switch to existing local branch
            if [[ "$create_mode" == "true" ]]; then
                print_info "ℹ️  Branch '$work_branch' already exists locally, switching to it"
            else
                print_info "🔄 USING existing local branch: $work_branch"
            fi
            git checkout "$work_branch" || {
                print_error "Failed to switch to existing branch: $work_branch"
                return 1
            }
            print_success "✅ Now using work branch: $work_branch"
            ;;
        "remote")
            # Checkout remote branch as local tracking branch
            if [[ "$create_mode" == "true" ]]; then
                print_info "ℹ️  Branch '$work_branch' exists on remote, checking out locally"
            else
                print_info "🌐 CHECKING OUT remote branch as local: $work_branch"
            fi
            local clean_branch="$work_branch"
            [[ "$work_branch" =~ ^origin/ ]] && clean_branch="${work_branch#origin/}"

            # Find the actual remote reference
            local remote_ref=$(git branch -r | grep -E "(^|\s+)[^/]+/$clean_branch$" | head -1 | sed 's/^[[:space:]]*//')

            git checkout -b "$clean_branch" "$remote_ref" || {
                print_error "Failed to checkout remote branch: $remote_ref"
                return 1
            }
            print_success "✅ Created local tracking branch: $clean_branch from $remote_ref"
            ;;
        "none")
            # Branch doesn't exist - behavior depends on create_mode
            if [[ "$create_mode" == "true" ]]; then
                # Create mode: create the branch from base_branch
                print_info "🆕 Creating new branch: $work_branch from $base_branch"
                git checkout -b "$work_branch" "$base_branch" || {
                    print_error "Failed to create branch: $work_branch from $base_branch"
                    return 1
                }
                print_success "✅ Created and switched to new branch: $work_branch"
            else
                # Switch-only mode: error with helpful suggestions
                print_error "❌ Branch '$work_branch' does not exist locally or on remote"
                echo ""
                print_info "📍 Available local branches:"
                git branch | sed 's/^[* ]*/    /' | head -10
                echo ""
                print_info "🌐 Available remote branches:"
                git branch -r | sed 's/^[[:space:]]*/    /' | head -10
                echo ""
                print_info "💡 To CREATE this branch, use --create flag:"
                print_info "    nyia-$assistant_name --work-branch $work_branch --create"
                print_info "    nyia-$assistant_name --work-branch $work_branch --create --base-branch develop"
                echo ""
                print_info "💡 Or create a timestamped branch instead:"
                print_info "    nyia-$assistant_name --base-branch main     # Creates timestamped branch from main"
                print_info "    nyia-$assistant_name                        # Creates timestamped branch from current"
                echo ""
                print_error "🚫 STOPPED: Branch does not exist. Use --create or check spelling."
                return 1
            fi
            ;;
        *)
            print_error "Failed to check branch existence"
            return 1
            ;;
    esac

    return 0
}

# Enhanced branch creation that supports both timestamped and work branches
# Parameter 5 (create_mode): passed to create_or_switch_work_branch for --create flag
create_assistant_branch() {
    local assistant_name="$1"
    local project_path="$2"
    local base_branch="${3:-}"  # Optional base branch
    local work_branch="${4:-}"  # Optional work branch name
    local create_mode="${5:-false}"  # Optional create mode for --create flag

    cd "$project_path" || return 1

    # Check for empty repository (no commits yet)
    if ! has_commits "$project_path"; then
        print_error "Repository has no commits - cannot create branch"
        print_info "Please make an initial commit first: git commit --allow-empty -m 'Initial commit'"
        return 1
    fi

    # If base_branch is empty, use current branch
    if [[ -z "$base_branch" ]]; then
        base_branch=$(get_current_branch "$project_path")
        if [[ -z "$base_branch" ]] || [[ "$base_branch" == "no-git" ]]; then
            print_error "Cannot determine current branch"
            return 1
        fi
    fi

    if [[ -n "$work_branch" ]]; then
        # Use specified work branch (with validation)
        # Pass create_mode to allow branch creation with --create flag
        if ! create_or_switch_work_branch "$assistant_name" "$work_branch" "$base_branch" "$project_path" "$create_mode"; then
            # STOP EXECUTION if work branch fails
            return 1
        fi
    else
        # Default behavior - create timestamped branch
        local timestamp=$(date +%Y-%m-%d-%H%M%S)
        local timestamped_branch="${assistant_name}-${timestamp}"
        
        print_info "Creating timestamped branch: $timestamped_branch from $base_branch"
        git checkout -b "$timestamped_branch" "$base_branch" || {
            print_error "Failed to create timestamped branch"
            return 1
        }
        print_success "Created and switched to branch: $timestamped_branch"
    fi
    
    return 0
}

# === WORKSPACE BRANCH SYNCHRONIZATION (Plan 103) ===

# Captures current branch for main project and all workspace repos
# Sets global associative array: ORIGINAL_BRANCHES[repo_path]=branch_name
# Arguments:
#   $1 - main_project_path
# Globals Read:
#   WORKSPACE_REPOS - array of workspace repo paths
# Globals Set:
#   ORIGINAL_BRANCHES - associative array (repo_path → branch_name)
# Returns:
#   0 - always (capture doesn't fail)
capture_original_branches() {
    local main_project="$1"

    # Declare global associative array
    declare -gA ORIGINAL_BRANCHES
    ORIGINAL_BRANCHES=()

    # Capture main project
    ORIGINAL_BRANCHES["$main_project"]=$(get_current_branch "$main_project")
    print_verbose "Captured original branch for main: ${ORIGINAL_BRANCHES[$main_project]}"

    # Capture each workspace repo
    for repo in "${WORKSPACE_REPOS[@]}"; do
        ORIGINAL_BRANCHES["$repo"]=$(get_current_branch "$repo")
        print_verbose "Captured original branch for $repo: ${ORIGINAL_BRANCHES[$repo]}"
    done
}

# Rolls back all repos to their original branches and deletes work branch
# Arguments:
#   $1 - work_branch: the branch to delete
# Globals Read:
#   ORIGINAL_BRANCHES - associative array (repo_path → original_branch)
#   REPOS_WITH_NEW_BRANCH - array of repos where we created the branch
# Returns:
#   0 - rollback succeeded (or best effort)
#   1 - rollback had errors (but still attempted all)
rollback_all_branches() {
    local work_branch="$1"
    local rollback_errors=0
    local current_dir=$(pwd)

    print_warning "Rolling back branch '$work_branch' from all repositories..."

    # Rollback in reverse order (last created first)
    for ((i=${#REPOS_WITH_NEW_BRANCH[@]}-1; i>=0; i--)); do
        local repo="${REPOS_WITH_NEW_BRANCH[i]}"
        local original="${ORIGINAL_BRANCHES[$repo]}"

        print_verbose "Rolling back $repo to $original"

        if ! cd "$repo" 2>/dev/null; then
            print_warning "Cannot cd to $repo for rollback"
            ((rollback_errors++))
            continue
        fi

        # Switch back to original branch
        if ! git checkout "$original" 2>/dev/null; then
            print_warning "Cannot checkout $original in $repo"
            ((rollback_errors++))
        fi

        # Only delete the branch if WE created it (not if it already existed)
        if [[ "${BRANCH_WAS_CREATED[$repo]}" == "true" ]]; then
            if git branch --list "$work_branch" | grep -q .; then
                if ! git branch -D "$work_branch" 2>/dev/null; then
                    print_warning "Cannot delete branch $work_branch in $repo"
                    ((rollback_errors++))
                else
                    print_verbose "Deleted branch $work_branch from $repo"
                fi
            fi
        else
            print_verbose "Keeping existing branch $work_branch in $repo (not created by us)"
        fi
    done

    # Return to original directory
    cd "$current_dir"

    if [[ $rollback_errors -gt 0 ]]; then
        print_warning "Rollback completed with $rollback_errors errors"
        return 1
    fi

    print_verbose "Rollback completed successfully"
    return 0
}

# Synchronizes work branch across all workspace repositories
# If any repo fails, rolls back ALL repos (including main project) to original state
# Arguments:
#   $1 - main_project: path to main project
#   $2 - work_branch: the branch name to sync
#   $3 - create_mode: "true" to create if missing (default), "false" for switch-only
# Globals Read:
#   WORKSPACE_REPOS - array of workspace repo paths
# Returns:
#   0 - Success (all repos on same branch)
#   1 - Failure (all repos rolled back to original state)
sync_workspace_branches() {
    local main_project="$1"
    local work_branch="$2"
    local create_mode="${3:-true}"
    local current_dir=$(pwd)

    # Early exit if no workspace repos
    if [[ ${#WORKSPACE_REPOS[@]} -eq 0 ]]; then
        print_verbose "No workspace repos to sync"
        return 0
    fi

    print_verbose "Syncing branch '$work_branch' to ${#WORKSPACE_REPOS[@]} workspace repos"

    # ORIGINAL_BRANCHES should already be set by run_assistant() before create_assistant_branch()
    # This ensures we have the true original branches, not the work branch

    # Step 1: Track repos where we successfully create/switch branch
    declare -ga REPOS_WITH_NEW_BRANCH
    REPOS_WITH_NEW_BRANCH=()

    # Track which repos had branch CREATED vs just SWITCHED
    # Only delete branches we created, not existing ones!
    declare -gA BRANCH_WAS_CREATED
    BRANCH_WAS_CREATED=()

    # Main project already has the branch (created by create_assistant_branch)
    # Use MAIN_BRANCH_PRE_EXISTED flag set by run_assistant before create_assistant_branch
    REPOS_WITH_NEW_BRANCH+=("$main_project")
    if [[ "${MAIN_BRANCH_PRE_EXISTED:-false}" == "true" ]]; then
        BRANCH_WAS_CREATED["$main_project"]=false  # Branch existed, don't delete
        print_verbose "Main project branch existed before, won't delete on rollback"
    else
        BRANCH_WAS_CREATED["$main_project"]=true   # We created it, safe to delete
        print_verbose "Main project branch was created, will delete on rollback"
    fi

    # Step 3: Create/switch branch on each workspace repo
    for repo in "${WORKSPACE_REPOS[@]}"; do
        print_verbose "Creating branch on workspace repo: $repo"

        if ! cd "$repo" 2>/dev/null; then
            print_error "Cannot access workspace repo: $repo"
            rollback_all_branches "$work_branch"
            cd "$current_dir"
            return 1
        fi

        # Check for uncommitted changes (would prevent checkout)
        if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
            print_error "Workspace repo has uncommitted changes: $repo"
            print_error "Please commit or stash changes before running"
            rollback_all_branches "$work_branch"
            cd "$current_dir"
            return 1
        fi

        # Get base branch for this repo (its current branch)
        local repo_base_branch=$(git branch --show-current)

        # Check if branch already exists
        if git branch --list "$work_branch" | grep -q .; then
            # Branch exists - switch to it (DO NOT delete on rollback!)
            if ! git checkout "$work_branch" 2>/dev/null; then
                print_error "Cannot switch to existing branch '$work_branch' in $repo"
                rollback_all_branches "$work_branch"
                cd "$current_dir"
                return 1
            fi
            print_verbose "Switched to existing branch '$work_branch' in $repo"
            BRANCH_WAS_CREATED["$repo"]=false  # Existing branch, don't delete on rollback
        else
            # Branch doesn't exist - create it
            if [[ "$create_mode" != "true" ]]; then
                print_error "Branch '$work_branch' doesn't exist in $repo and create_mode is false"
                rollback_all_branches "$work_branch"
                cd "$current_dir"
                return 1
            fi

            if ! git checkout -b "$work_branch" 2>/dev/null; then
                print_error "Cannot create branch '$work_branch' in $repo"
                rollback_all_branches "$work_branch"
                cd "$current_dir"
                return 1
            fi
            print_verbose "Created branch '$work_branch' in $repo from $repo_base_branch"
            BRANCH_WAS_CREATED["$repo"]=true  # We created it, safe to delete on rollback
        fi

        # Track successful sync (both created and switched)
        REPOS_WITH_NEW_BRANCH+=("$repo")
    done

    # Return to original directory
    cd "$current_dir"

    print_status "Branch '$work_branch' synced to ${#WORKSPACE_REPOS[@]} workspace repos"
    return 0
}

# === HELP SYSTEM REMOVED ===
# Help system has been moved to lib/cli-parser.sh for centralization
