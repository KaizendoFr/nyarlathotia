#!/bin/bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR Proprietary
# Copyright (c) 2024 NyarlathotIA Contributors

# shared.sh - Common utility functions for nyarlathotepIA multi-provider system
# Shared across all providers: claude, gemini, codestral, chatgpt

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Print functions with consistent formatting
print_status() {
    echo -e "${BLUE}🔧 $1${NC}"
}

print_info() {
    echo -e "${BLUE}📍 $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Platform detection and compatibility
get_platform() {
    case "$(uname -s)" in
        Darwin*) echo "macos" ;;
        Linux*) echo "linux" ;;
        *) echo "unknown" ;;
    esac
}

is_macos() {
    [[ "$(get_platform)" == "macos" ]]
}

is_linux() {
    [[ "$(get_platform)" == "linux" ]]
}

# Configuration
get_project_home() {
    # Get the base directory for the project
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    echo "$(cd "$script_dir/../.." && pwd)"
}

# Generate project hash for data isolation
get_project_hash() {
    local project_path="$1"
    echo "$project_path" | sha256sum | cut -d' ' -f1 | cut -c1-12
}

# Platform-aware realpath function
portable_realpath() {
    local path="$1"
    if command -v realpath >/dev/null 2>&1; then
        realpath "$path"
    elif command -v greadlink >/dev/null 2>&1; then
        # GNU coreutils via Homebrew
        greadlink -f "$path"
    elif command -v readlink >/dev/null 2>&1; then
        # BSD readlink (limited functionality)
        readlink -f "$path" 2>/dev/null || {
            # Fallback for macOS
            python3 -c "import os; print(os.path.realpath('$path'))" 2>/dev/null || \
            python -c "import os; print(os.path.realpath('$path'))" 2>/dev/null || \
            echo "$path"
        }
    else
        # Last resort - use cd
        echo "$(cd "$path" 2>/dev/null && pwd)" || echo "$path"
    fi
}

# Convert relative path to absolute path
resolve_absolute_path() {
    local path="$1"
    if [[ "$path" == /* ]]; then
        # Already absolute
        echo "$path"
    else
        # Convert relative to absolute using portable realpath
        portable_realpath "$path" || {
            print_error "Path does not exist: $path"
            exit 1
        }
    fi
}

# Initialize .nyarlathotia directory with unified context structure
init_nyarlathotia_dir() {
    local project_path="$1"
    local nyia_dir="$project_path/.nyarlathotia"
    local needs_repair=false

    # Create directory if it doesn't exist
    if [[ ! -d "$nyia_dir" ]]; then
        print_status "Initializing NyarlathotIA project context directory..."
        mkdir -p "$nyia_dir"
        needs_repair=true
    else
        # Check if essential files are missing
        if [[ ! -f "$nyia_dir/todo.md" ]] || [[ ! -d "$nyia_dir/plans" ]]; then
            print_status "Repairing incomplete NyarlathotIA structure..."
            needs_repair=true
        fi
    fi
    
    # Create or repair structure
    if [[ "$needs_repair" == "true" ]]; then
        # Create plans directory structure
        mkdir -p "$nyia_dir/plans"/{critical,core,platform,integrations}
        
        # Create kanban-style todo.md if missing
        if [[ ! -f "$nyia_dir/todo.md" ]]; then
            cat > "$nyia_dir/todo.md" << EOF
# Project Todo List

## 🔥 Doing
- [ ] Analyze project structure and architecture - Priority: High - Plan: plans/core/analysis.md

## 📋 Ready
- [ ] Review existing code for patterns and conventions - Priority: High
- [ ] Set up development workflow - Priority: Medium

## 🧊 Backlog  
- [ ] Consider additional AI integrations - Priority: Low

## ✅ Done
- [x] Initialize NyarlathotIA project structure - Completed: $(date +%Y-%m-%d)

## 🚧 Blocked
# No current blockers
EOF

            print_success "Created todo.md file"
        fi
        
        # Create plans README if missing
        if [[ ! -f "$nyia_dir/plans/README.md" ]]; then
            cat > "$nyia_dir/plans/README.md" << EOF
# Implementation Plans

## Directory Structure
- **critical/**: High-priority plans that must be completed first
- **core/**: Core functionality implementation plans
- **platform/**: Platform-specific compatibility plans  
- **integrations/**: Assistant integration and feature plans

## Plan Naming Convention
Plans should be numbered for clear sequencing: 01-task-name.md

## Plan Template
Each plan should include:
- **Context**: Why this is needed
- **Scope**: What will be implemented
- **Dependencies**: What must be completed first
- **Implementation**: Step-by-step approach
- **Testing**: How to verify completion
EOF
            print_success "Created plans/README.md file"
        fi
        
        print_success "NyarlathotIA context directory structure complete"
    fi
}

# Initialize provider-specific context directory (within .nyarlathotia/)
init_provider_context() {
    local project_path="$1"
    local provider="$2"
    local nyia_dir="$project_path/.nyarlathotia"
    local context_dir="$nyia_dir/$provider"

    # Ensure .nyarlathotia exists first
    init_nyarlathotia_dir "$project_path"

    if [[ ! -d "$context_dir" ]]; then
        print_status "Initializing $provider context within .nyarlathotia/..."
        mkdir -p "$context_dir"
        
        # Create commands directory for provider-specific commands
        mkdir -p "$context_dir/commands"

        # Create provider-specific context file (no decisions.md or todo.md)
        cat > "$context_dir/context.md" << EOF
# Project: $(basename "$project_path") - $provider Context

## Architecture Understanding
- Framework: [To be detected]
- Key patterns: [To be analyzed]
- Main technologies: [To be identified]

## Project Structure
- Key directories: [Important folders]
- Main entry points: [Important files]

## Current Session Focus
- Working on: [Current feature/task]
- Last session: New project analysis

## Code Insights
- [Key architectural insights]
- [Important implementation details]
- [Technical debt observations]

## Session Bridge
- Provider: $provider
- Initialized: $(date +%Y-%m-%d)
- [Cross-session continuity information]
EOF

        print_success "$provider context directory initialized in .nyarlathotia/"
    fi
}

# Show help for common options
show_common_help() {
    cat << 'EOF'
Common Options:
  --help|-h                       Show help
  --build                         Build Docker image
  --status                        Show current project info
  --path /other/project           Work on different project
  --write                         Write mode - can modify code
  --base-branch <branch>          Write mode with specific base branch

Git Integration:
  - Read-only mode (default): No Git operations, pure consultation
  - Write mode (--write): Creates work branch for modifications
  - Interactive session: Always creates work branch, auto-cleanup on exit
  - Exit cleanup: Empty branch deleted, changes prompt to keep or delete
  - Interactive commands: /branch, /switch, /commit, /push
  - PR creation: Must be done outside container for security (use gh pr create)

Environment:
  Current directory is mounted to /workspace in container
  Project context is automatically managed in provider-specific directory
  Authentication and theme saved globally (setup once, use everywhere)
EOF
}

# Validate project path
validate_project_path() {
    local project_path="$1"
    
    if [[ ! -d "$project_path" ]]; then
        print_error "Project path does not exist: $project_path"
        exit 1
    fi
    
    return 0
}

# Get provider-specific data directory
get_provider_data_dir() {
    local provider="$1"
    local project_path="$2"
    local project_home="$3"
    
    local project_hash=$(get_project_hash "$project_path")
    echo "$project_home/data/$provider/$project_hash"
}

# Get provider-specific global directory
get_provider_global_dir() {
    local provider="$1"
    local project_home="$2"
    
    echo "$project_home/$provider"
}

# Check if running in container
is_in_container() {
    [[ -f /.dockerenv ]]
}

# Get container name for provider
get_container_name() {
    local provider="$1"
    local project_path="$2"
    
    local project_name=$(basename "$project_path" | sed 's/[^a-zA-Z0-9._-]/-/g' | tr '[:upper:]' '[:lower:]')
    echo "nyarlathotep-$provider-$project_name-$(date +%s)"
}

# Common argument parsing helpers
parse_common_args() {
    local -n args_ref=$1
    local -n write_mode_ref=$2
    local -n base_branch_ref=$3
    local -n project_path_ref=$4
    
    while [[ ${#args_ref[@]} -gt 0 ]]; do
        case "${args_ref[0]}" in
            --write)
                write_mode_ref="true"
                args_ref=("${args_ref[@]:1}")
                ;;
            --base-branch)
                base_branch_ref="${args_ref[1]}"
                args_ref=("${args_ref[@]:2}")
                ;;
            --path)
                project_path_ref=$(resolve_absolute_path "${args_ref[1]}")
                args_ref=("${args_ref[@]:2}")
                ;;
            --help|-h)
                return 1  # Signal caller to show help
                ;;
            *)
                break
                ;;
        esac
    done
    
    return 0
}

# Environment variable helpers
check_env_var() {
    local var_name="$1"
    local var_value="${!var_name}"
    
    if [[ -z "$var_value" ]]; then
        print_warning "Environment variable $var_name is not set"
        return 1
    fi
    
    return 0
}

# File system helpers
ensure_directory() {
    local dir="$1"
    
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir" || {
            print_error "Failed to create directory: $dir"
            return 1
        }
    fi
    
    return 0
}

# Logging helpers
log_command() {
    local provider="$1"
    local command="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Log to provider-specific log file if logging is enabled
    if [[ "${NYARLATHOTEP_LOGGING:-false}" == "true" ]]; then
        local log_file="/tmp/nyarlathotep-$provider.log"
        echo "[$timestamp] $command" >> "$log_file"
    fi
}

# Configuration helpers
load_provider_config() {
    local provider="$1"
    local config_file="$2"
    
    if [[ -f "$config_file" ]]; then
        # Source the config file if it's a shell script
        if [[ "$config_file" == *.sh ]]; then
            source "$config_file"
        fi
    fi
}

# Error handling
handle_error() {
    local exit_code="$1"
    local error_message="$2"
    
    print_error "$error_message"
    exit "$exit_code"
}

# Signal handlers
setup_signal_handlers() {
    trap 'handle_interrupt' INT TERM
}

handle_interrupt() {
    print_warning "Received interrupt signal, cleaning up..."
    exit 130
}

# Version and compatibility
check_bash_version() {
    if [[ ${BASH_VERSION%%.*} -lt 4 ]]; then
        print_error "This script requires Bash 4.0 or later. Current version: $BASH_VERSION"
        exit 1
    fi
}

# Initialize shared environment
init_shared_environment() {
    # Set up signal handlers
    setup_signal_handlers
    
    # Check bash version
    check_bash_version
    
    # Set default values
    export NYARLATHOTEP_LOGGING="${NYARLATHOTEP_LOGGING:-false}"
    export NYARLATHOTEP_DEBUG="${NYARLATHOTEP_DEBUG:-false}"
}

# Package manager detection and support
detect_package_manager() {
    if is_macos; then
        if command -v brew >/dev/null 2>&1; then
            echo "homebrew"
        elif command -v port >/dev/null 2>&1; then
            echo "macports"
        else
            echo "none"
        fi
    elif is_linux; then
        if command -v apt >/dev/null 2>&1; then
            echo "apt"
        elif command -v yum >/dev/null 2>&1; then
            echo "yum"
        elif command -v dnf >/dev/null 2>&1; then
            echo "dnf"
        elif command -v pacman >/dev/null 2>&1; then
            echo "pacman"
        else
            echo "none"
        fi
    else
        echo "unknown"
    fi
}

has_homebrew() {
    is_macos && command -v brew >/dev/null 2>&1
}

get_gnu_command() {
    local cmd="$1"
    if has_homebrew; then
        case "$cmd" in
            realpath) command -v greadlink >/dev/null 2>&1 && echo "greadlink -f" || echo "readlink -f" ;;
            sed) command -v gsed >/dev/null 2>&1 && echo "gsed" || echo "sed" ;;
            awk) command -v gawk >/dev/null 2>&1 && echo "gawk" || echo "awk" ;;
            grep) command -v ggrep >/dev/null 2>&1 && echo "ggrep" || echo "grep" ;;
            *) echo "$cmd" ;;
        esac
    else
        echo "$cmd"
    fi
}

# Debug helpers
debug_log() {
    if [[ "${NYARLATHOTEP_DEBUG:-false}" == "true" ]]; then
        echo -e "${CYAN}🐛 DEBUG: $1${NC}" >&2
    fi
}

# Performance helpers
time_command() {
    local start_time=$(date +%s.%N)
    "$@"
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "N/A")
    debug_log "Command took ${duration}s: $*"
}

# === PROMPT GENERATION AND CONTEXT MANAGEMENT ===

# Create local context directory for assistant (common across all assistants)
create_local_context_dir() {
    local project_path="$1"
    local assistant_cli="$2"
    local assistant_name="$3"
    
    local nyia_dir="$project_path/.nyarlathotia"
    local context_dir="$nyia_dir/$assistant_cli"
    
    # Ensure base .nyarlathotia directory exists
    init_nyarlathotia_dir "$project_path"
    
    # Create assistant-specific context directory
    if [[ ! -d "$context_dir" ]]; then
        print_status "Creating $assistant_name local context directory..."
        mkdir -p "$context_dir"
        
        # Create commands directory for assistant-specific commands
        mkdir -p "$context_dir/commands"
        
        # Generate context.md using common template
        generate_context_template "$project_path" "$assistant_cli" "$assistant_name" > "$context_dir/context.md"
        
        print_success "$assistant_name local context initialized in .nyarlathotia/$assistant_cli/"
    fi
    
    return 0
}

# Generate standard context.md template (assistant-agnostic)
generate_context_template() {
    local project_path="$1"
    local assistant_cli="$2"
    local assistant_name="$3"
    
    local project_name=$(basename "$project_path")
    local timestamp=$(date +%Y-%m-%d)
    
    cat << EOF
# Project: $project_name - $assistant_name Context

## Architecture Understanding
- Framework: [To be detected during first analysis]
- Key patterns: [To be analyzed from codebase structure]
- Main technologies: [To be identified from dependencies]
- Build system: [To be determined from config files]

## Project Structure
- Key directories: [Important folders to be mapped]
- Main entry points: [Critical files to be identified]
- Configuration files: [Settings and config to be cataloged]
- Documentation: [README, docs/ to be reviewed]

## Current Session Focus
- Working on: [Current feature/task - update as you work]
- Priority: [High/Medium/Low - set based on ../todo.md]
- Dependencies: [Blocked by or blocking other tasks]

## Code Insights
- [Key architectural insights discovered during sessions]
- [Important implementation details and patterns]
- [Technical debt observations and recommendations]
- [Security considerations and findings]

## Development Workflow
- Testing approach: [How tests are run and organized]
- Deployment process: [How changes are deployed]
- Code review process: [How changes are reviewed]
- Branch strategy: [Git workflow and branch naming]

## Session Bridge
- Provider: $assistant_cli
- Initialized: $timestamp
- Last session: New project analysis
- Cross-session continuity: [Information for next session]
- Shared project coordination: See ../todo.md and ../plans/ for project-wide tasks

## Commands and Shortcuts
- [Custom commands specific to this assistant]
- [Frequently used operations]
- [Project-specific automation]
EOF
}

# Ensure complete assistant context (consistent for all assistants)
ensure_assistant_context() {
    local project_path="$1"
    local assistant_cli="$2"
    local assistant_name="$3"
    local prompt_content="$4"
    
    print_status "Ensuring complete $assistant_name context setup..."
    
    # Create local context directory for ALL assistants (including Codex)
    if ! create_local_context_dir "$project_path" "$assistant_cli" "$assistant_name"; then
        print_error "Failed to create local context directory for $assistant_name"
        return 1
    fi
    
    print_success "$assistant_name context setup complete"
    return 0
}

# Codex global deployment removed - now uses standard project-local approach

# Note: get_nyarlathotia_home() is defined in common-functions.sh

# === REGISTRY SUPPORT ===

# Get Docker registry for images (ghcr.io vs local)
get_docker_registry() {
    # Priority order:
    # 1. Developer testing override (force registry)
    # 2. Custom registry configuration  
    # 3. Development default (local) / Runtime default (registry)
    
    # Developer testing override - force registry instead of local
    if [[ "${NYIA_FORCE_REGISTRY:-}" == "true" ]]; then
        echo "${NYIA_REGISTRY:-ghcr.io/kaizendofr}"
        return
    fi
    
    # Backward compatibility (temporary - will be removed)
    if [[ "${NYIA_USE_GHCR:-}" == "true" ]]; then
        echo "${NYIA_REGISTRY:-ghcr.io/${NYIA_GITHUB_USER:-kaizendofr}}"
        return
    fi
    
    # Error if deprecated NYIA_USE_LOCAL is used
    if [[ "${NYIA_USE_LOCAL:-}" == "true" ]]; then
        echo "Error: NYIA_USE_LOCAL is deprecated. Use --image parameter instead." >&2
        echo "Example: nyia-claude --image my-custom:latest" >&2
        exit 1
    fi
    
    
    # Runtime default: always use registry
    echo "${NYIA_REGISTRY:-ghcr.io/kaizendofr}"
}

# Get full image name with registry prefix
get_image_name() {
    local assistant="$1"
    local registry=$(get_docker_registry)
    
    if [[ -n "$registry" ]]; then
        echo "${registry}/nyarlathotia-${assistant}:latest"
    else
        echo "nyarlathotia/${assistant}:latest"
    fi
}

# Development mode detection - only exists in development source
# Runtime distributions don't need this since features are preprocessed out


# NOTE: Runtime builds get no is_development_mode function at all

# Initialize shared environment when sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    init_shared_environment
fi
