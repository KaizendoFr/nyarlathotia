#!/bin/bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR Proprietary
# Copyright (c) 2024 NyarlathotIA Contributors

# NyarlathotIA Centralized CLI Parser
# Single source of truth for all CLI argument parsing and help system

set -e

# Standard bash 4.0+ features used throughout

# Load input validation functions for security
cli_parser_dir="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
if [[ -f "$cli_parser_dir/input-validation.sh" ]]; then
    source "$cli_parser_dir/input-validation.sh"
fi

# === GLOBAL VARIABLES ===
# These are set by parse_args() and used by calling scripts

# Mode flags
export SHOW_HELP="false"
export SHOW_STATUS="false"
export VERBOSE="false"
export LOGIN_ONLY="false"
export CHECK_REQUIREMENTS="false"  # Moved outside DEV_BUILD - needed in runtime
export SKIP_CHECKS="false"
export SHELL_MODE="false"
export SET_API_KEY="false"
export SETUP_MODE="false"
export LIST_IMAGES="false"
export DOCKER_IMAGE=""
export FLAVOR=""
export LIST_FLAVORS="false"

# Mount exclusions flags (simplified)
export DISABLE_EXCLUSIONS="false"

# Configuration
export PROJECT_PATH=""
export BASE_BRANCH=""
export WORK_BRANCH=""
export BUILD_CUSTOM_IMAGE=""

# Command and arguments
export COMMAND=""
export ASSISTANT_NAME=""
export USER_PROMPT=""
export REMAINING_ARGS=()

# Context
export SCRIPT_TYPE=""  # "dispatcher" or "assistant"

# === ARGUMENT DEFINITIONS ===
# Using functions for bash 3.2 compatibility (instead of associative arrays)

# Get description for global arguments
get_global_arg_desc() {
    case "$1" in
        "--help,-h") echo "Show help information" ;;
        "--verbose,-v") echo "Enable verbose output" ;;
        "--path") echo "Work on different project directory" ;;
        *) echo "" ;;
    esac
}

# Get all global arguments
get_global_args() {
    echo "--help,-h --verbose,-v --path"
}

# Get description for assistant arguments
get_assistant_arg_desc() {
    case "$1" in
        "--image") echo "Select specific Docker image (tag or repo:tag)" ;;
        "--flavor") echo "Select assistant flavor/variant (e.g., node, python, rust)" ;;
        "--flavors-list") echo "List available flavors for this assistant" ;;
        "--status") echo "Show assistant status, configs, and available overlays" ;;
        "--list-images") echo "List all available Docker images for this assistant" ;;
        "--base-branch") echo "Specify Git base branch to work from" ;;
        "--work-branch") echo "Reuse existing work branch for your work" ;;
        "--build-custom-image") echo "Build custom Docker image with your overlays (power users)" ;;
        "--setup") echo "Interactive model/provider setup (OpenCode)" ;;
        "--login") echo "Authenticate using the assistant container" ;;
        "--check-requirements") echo "Check system requirements (Git, Docker, permissions)" ;;
        "--skip-checks") echo "Skip automatic requirements checking" ;;
        "--shell") echo "Start interactive bash shell in container" ;;
        "--set-api-key") echo "Helper to set OpenAI API key for team plan users" ;;
        "--disable-exclusions") echo "Disable mount exclusions for this session" ;;
        "--prompt,-p") echo "Explicit user prompt (required for non-interactive mode)" ;;
        *) echo "" ;;
    esac
}

# Get all assistant arguments (for iteration)
get_assistant_args() {
    echo "--image --flavor --flavors-list --status --list-images --base-branch --work-branch --build-custom-image --setup --login --check-requirements --skip-checks --shell --set-api-key --disable-exclusions --prompt,-p"
}

# Get description for dispatcher arguments
get_dispatcher_arg_desc() {
    case "$1" in
        "config") echo "Configuration management (list, dump, view, get)" ;;
        "list") echo "List all available assistants" ;;
        "status") echo "Show global NyarlathotIA status" ;;
        "exclusions") echo "Manage mount exclusions for security" ;;
        *) echo "" ;;
    esac
}

# Get all dispatcher arguments (for iteration)
get_dispatcher_args() {
    echo "config list status exclusions"
}

# === HELP SYSTEM ===
show_dispatcher_help() {
    local script_name="$1"
    
    cat << EOF
NyarlathotIA Multi-Assistant Infrastructure - "I whisper in code. You commit in fear."

Usage:
  $script_name <command>                    # System management commands

System Commands:
EOF
    
    for arg in $(get_dispatcher_args); do
        desc=$(get_dispatcher_arg_desc "$arg")
        printf "  %-20s # %s\n" "$arg" "$desc"
    done
    
    cat << EOF

Assistant Access (use direct commands):
  nyia-claude -p "Review this code"           # Direct Claude access
  nyia-gemini -p "Explain algorithm"          # Direct Gemini access  
  nyia-opencode -p "Analyze code"             # Direct OpenCode access

Global Options:
EOF
    
    for arg in $(get_global_args); do
        desc=$(get_global_arg_desc "$arg")
        printf "  %-20s # %s\n" "$arg" "$desc"
    done
    
    cat << EOF

Examples:
  $script_name list                             # List available assistants
  $script_name status                           # Show system status
  $script_name clean                            # Clean old images
  
  nyia-claude -p "Analyze this function"       # Use Claude assistant
  nyia-gemini --build --dev                    # Build Gemini dev image

For assistant-specific help: nyia-<assistant> --help
EOF
}

show_assistant_help() {
    local assistant_name="$1"
    local thematic_alias="${2:-assistant}"
    
    # Source shared functions for development mode detection
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -f "$script_dir/../bin/common/shared.sh" ]]; then
        source "$script_dir/../bin/common/shared.sh"
    fi
    
    # Get available overlay examples
    local overlay_examples=""
    if [[ -d "docker/overlay-examples" ]]; then
        overlay_examples=$(ls -1 docker/overlay-examples/ 2>/dev/null | grep -v "README.md" | head -6)
    fi
    
    cat << EOF
NyarlathotIA ${assistant_name} Assistant - "I whisper in code. You commit in fear."

Usage:
  nyia-${assistant_name}                      # Interactive session
  nyia-${assistant_name} -p "prompt text"     # Direct prompt
  nyia-${assistant_name} [options]            # Various operations

Quick Start:
  nyia-${assistant_name} --status             # Show configuration & overlays
  nyia-${assistant_name} -p "your prompt"     # Use assistant
  nyia-${assistant_name} --build-custom-image  # Build with your overlays

Power User Overlays:
  Create overlay at: ~/.config/nyarlathotia/${assistant_name}/overlay/Dockerfile
  Then run: nyia-${assistant_name} --build-custom-image
  
  Example overlay content:
EOF
    
    # Show available overlay examples with descriptions
    if [[ -n "$overlay_examples" ]]; then
        echo "$overlay_examples" | while read -r example; do
            case "$example" in
                "python-latest") echo "    python-latest/    # Python with pytest, black, ruff, mypy" ;;
                "php-82") echo "    php-82/          # PHP 8.2 with PHPUnit, PHPStan" ;;
                "php-81") echo "    php-81/          # PHP 8.1 environment" ;;
                "php-74") echo "    php-74/          # PHP 7.4 for legacy projects" ;;
                "php-73") echo "    php-73/          # PHP 7.3 for legacy projects" ;;
                "data-science") echo "    data-science/    # Jupyter, pandas, sklearn" ;;
                "web-dev") echo "    web-dev/         # FastAPI, Django, Flask" ;;
                *) echo "    $example/" ;;
            esac
        done
    else
        echo "    (No examples found in docker/overlay-examples/)"
    fi
    
    cat << EOF
  
  Setup overlay:
    cp docker/overlay-examples/python-latest/Dockerfile ~/.config/nyarlathotia/${assistant_name}/overlay/
    nyia-${assistant_name} --build
  
  Overlay locations (applied in order):
    1. User config: ~/.config/nyarlathotia/${assistant_name}/overlay/Dockerfile
    2. Project: ./.nyarlathotia/${assistant_name}/overlay/Dockerfile

Operations:
  -p, --prompt "text"      # Send prompt to assistant
  --shell                  # Interactive bash in container
  --login                  # Authenticate assistant
  --status                 # Show current config & overlays
  --work-branch <name>     # Reuse existing work branch
  --base-branch <name>     # Specify Git base branch

Power User:
  --build-custom-image     # Build custom image with overlays

Configuration:
  --disable-exclusions     # Disable mount exclusions
  --image <tag>           # Use specific image
  --check-requirements    # Check system requirements
  --setup                 # Interactive setup (OpenCode)
  --set-api-key           # Helper to set API key
EOF


    cat << EOF

Global Options:
  --help, -h              # Show this help
  --verbose, -v           # Verbose output
  --path <dir>           # Work on different project

Examples:
  # Basic usage:
  nyia-${assistant_name} -p "Create a Python script with tests"
  nyia-${assistant_name} --status              # Check configuration
EOF

    echo ""
    echo "  # End-user examples:"
    local registry=$(get_docker_registry)
    cat << EOF
  cat > ~/.config/nyarlathotia/${assistant_name}/overlay/Dockerfile << 'OVERLAY'
FROM ${registry}/nyarlathotia-${assistant_name}:latest
RUN apt-get update && apt-get install -y your-tools
OVERLAY
  nyia-${assistant_name} --build-custom-image  # Build custom image
EOF

    cat << EOF

Environment:
  Project directory mounted to /workspace in container
  Authentication and settings saved globally
  Git integration automatic in write mode
  Overlay system provides runtime customization
EOF
}

# === ARGUMENT PARSING ===
parse_dispatcher_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                SHOW_HELP="true"
                shift
                ;;
            --verbose|-v)
                export VERBOSE="true"
                shift
                ;;
            --path)
                if [[ -n "$2" ]] && validate_file_path "$2"; then
                    PROJECT_PATH="$2"
                    shift 2
                else
                    print_error "Invalid or unsafe path: $2"
                    exit 1
                fi
                ;;
            config|list|status|clean|exclusions|help)
                COMMAND="$1"
                shift
                REMAINING_ARGS=("$@")
                return 0
                ;;
            *)
                # First non-option argument should be the assistant name.
                if [[ -z "$ASSISTANT_NAME" ]]; then
                    if [[ "$1" == -* ]]; then
                        echo "Error: Option '$1' provided before assistant name" >&2
                        echo "Usage: $0 <assistant> [options]" >&2
                        exit 1
                    fi
                    ASSISTANT_NAME="$1"
                    shift
                    REMAINING_ARGS=("$@")
                    return 0
                else
                    echo "Error: Unknown dispatcher command: $1" >&2
                    exit 1
                fi
                ;;
        esac
    done
}

parse_assistant_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                SHOW_HELP="true"
                return 0
                ;;
            --verbose|-v)
                export VERBOSE="true"
                shift
                ;;
            --path)
                if [[ -n "$2" ]] && validate_file_path "$2"; then
                    PROJECT_PATH="$2"
                    shift 2
                else
                    print_error "Invalid or unsafe path: $2"
                    exit 1
                fi
                ;;
            --image)
                if [[ -n "$2" ]]; then
                    export DOCKER_IMAGE="$2"
                    shift 2
                else
                    echo "Error: --image requires an argument" >&2
                    echo "Usage: --image <tag|repo:tag>" >&2
                    exit 1
                fi
                ;;
            --flavor)
                if [[ -n "$2" ]]; then
                    export FLAVOR="$2"
                    shift 2
                else
                    echo "Error: --flavor requires an argument" >&2
                    echo "Usage: --flavor <flavor-name>" >&2
                    echo "Example: --flavor node18" >&2
                    exit 1
                fi
                ;;
            --flavors-list)
                export LIST_FLAVORS="true"
                shift
                ;;
            --status)
                SHOW_STATUS="true"
                shift
                ;;
            --list-images)
                LIST_IMAGES="true"
                shift
                ;;
            --login)
                LOGIN_ONLY="true"
                shift
                ;;
            --check-requirements)
                CHECK_REQUIREMENTS="true"
                shift
                ;;
            --skip-checks)
                SKIP_CHECKS="true"
                shift
                ;;
            --shell)
                SHELL_MODE="true"
                shift
                ;;
            --set-api-key)
                SET_API_KEY="true"
                shift
                ;;
            --setup)
                SETUP_MODE="true"
                shift
                ;;
            --disable-exclusions)
                export DISABLE_EXCLUSIONS="true"
                export ENABLE_MOUNT_EXCLUSIONS="false"
                shift
                ;;
            --base-branch)
                if [[ -n "$2" ]]; then
                    BASE_BRANCH="$2"
                    shift 2
                else
                    echo "Error: --base-branch requires an argument" >&2
                    echo "Usage: --base-branch <branch-name>" >&2
                    exit 1
                fi
                ;;
            --work-branch)
                if [[ -n "$2" ]]; then
                    WORK_BRANCH="$2"
                    shift 2
                else
                    echo "Error: --work-branch requires an argument" >&2
                    echo "Usage: --work-branch <branch-name>" >&2
                    exit 1
                fi
                ;;
            --build-custom-image)
                BUILD_CUSTOM_IMAGE="true"
                shift
                ;;
            --prompt|-p)
                if [[ -n "$2" ]]; then
                    USER_PROMPT="$2"
                    shift 2
                else
                    echo "Error: --prompt requires an argument" >&2
                    echo "Usage: --prompt \"Your prompt text\"" >&2
                    echo "   or: -p \"Your prompt text\"" >&2
                    exit 1
                fi
                ;;
            *)
                # Strict validation: reject unknown options
                if [[ "$1" == -* ]]; then
                    # Source shared functions for development mode detection
                    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
                    if [[ -f "$script_dir/../bin/common/shared.sh" ]]; then
                        source "$script_dir/../bin/common/shared.sh"
                    fi
                    
                    echo "Error: Unknown option: $1" >&2
                    echo "" >&2
                    echo "Valid options:" >&2
                    echo "  --status             Show assistant status and available images" >&2
                    echo "  --login              Authenticate using the assistant container" >&2
                    echo "  --shell              Interactive shell in container" >&2
                    echo "  --check-requirements Check system requirements" >&2
                    echo "  --path <dir>         Work on different project directory" >&2
                    echo "  --prompt, -p <text>  Explicit user prompt" >&2
                    echo "  --verbose, -v        Enable verbose output" >&2
                    echo "  --help, -h           Show help" >&2
                    
                    echo "" >&2
                    echo "Additional options:" >&2
                    echo "  --build-custom-image Build custom image with overlays" >&2
                    echo "  --base-branch <name> Specify Git base branch" >&2
                    echo "  --work-branch <name> Reuse work branch" >&2
                    echo "" >&2
                    echo "Example: nyia-claude -p 'Help me with my code'" >&2
                    
                    exit 1
                fi
                
                # Check if --help is in the remaining arguments
                local check_arg
                for check_arg in "$@"; do
                    if [[ "$check_arg" == "--help" || "$check_arg" == "-h" ]]; then
                        SHOW_HELP="true"
                        return
                    fi
                done
                
                # Check for common dispatcher commands used incorrectly
                if [[ "$1" == "exclusions" || "$1" == "config" || "$1" == "list" || "$1" == "status" || "$1" == "clean" ]]; then
                    echo "Error: '$1' is a system command, not an assistant command" >&2
                    echo "" >&2
                    echo "For system commands, use the dispatcher:" >&2
                    echo "  nyia $1                    # Basic usage" >&2
                    echo "  nyia --path /path $1       # With custom path" >&2
                    echo "" >&2
                    echo "For assistant usage:" >&2
                    echo "  nyia-claude -p 'your prompt'     # Example with prompt" >&2
                    echo "  nyia-gemini                       # Interactive mode" >&2
                    echo "  nyia-opencode --help              # Show assistant help" >&2
                    exit 1
                fi
                
                # Reject direct text arguments - require -p/--prompt flag
                echo "Error: Direct text prompts not supported. Use --prompt or -p flag" >&2
                echo "" >&2
                echo "Bad:  nyia-claude 'help me'" >&2
                echo "Good: nyia-claude -p 'help me'" >&2
                echo "      nyia-claude --prompt 'help me'" >&2
                echo "      nyia-claude              # Interactive mode" >&2
                echo "" >&2
                exit 1
                ;;
        esac
    done
}

# === MAIN PARSING FUNCTION ===
parse_args() {
    local script_type="$1"
    shift
    
    SCRIPT_TYPE="$script_type"
    
    # Reset all variables to defaults
    export SHOW_HELP="false"
    export SHOW_STATUS="false"
    export VERBOSE="false"
    export LOGIN_ONLY="false"
    export SKIP_CHECKS="false"
    export SHELL_MODE="false"
    export SET_API_KEY="false"
    export SETUP_MODE="false"
    export LIST_FLAVORS="false"
    export DISABLE_EXCLUSIONS="false"
    export PROJECT_PATH=""
    export FLAVOR=""
    export BASE_BRANCH=""
        export COMMAND=""
    export ASSISTANT_NAME=""
    export USER_PROMPT=""
    REMAINING_ARGS=()
    
    case "$script_type" in
        "dispatcher")
            parse_dispatcher_args "$@"
            ;;
        "assistant")
            parse_assistant_args "$@"
            ;;
        *)
            echo "Error: Invalid script type: $script_type" >&2
            exit 1
            ;;
    esac
}

# === VALIDATION ===
validate_args() {
    # Validate and normalize paths if provided
    if [[ -n "$PROJECT_PATH" ]]; then
        # Check if path exists first (before normalization)
        if [[ ! -d "$PROJECT_PATH" ]]; then
            echo "Error: Project path does not exist: $PROJECT_PATH" >&2
            exit 1
        fi
        
        # Convert to absolute path (Docker requirement) - transparent for users
        local original_path="$PROJECT_PATH"
        PROJECT_PATH=$(realpath "$PROJECT_PATH" 2>/dev/null)
        
        if [[ -z "$PROJECT_PATH" ]]; then
            echo "Error: Failed to resolve absolute path for: $original_path" >&2
            exit 1
        fi
        
        # Show conversion for transparency (only if verbose)
        if [[ "$VERBOSE" == "true" && "$original_path" != "$PROJECT_PATH" ]]; then
            echo "🔧 Normalized path: $original_path → $PROJECT_PATH" >&2
        fi
        
        # Export the normalized path
        export PROJECT_PATH
    fi
    
    
    
    # Validate build + no-cache combination
    if [[ "$NO_CACHE" == "true" && "$BUILD_IMAGE" != "true" ]]; then
        echo "Error: --no-cache can only be used with --build" >&2
        exit 1
    fi
    
    # Validate dev mode (only with build)
    if [[ "$DEV_MODE" == "true" && "$BUILD_IMAGE" != "true" ]]; then
        echo "Error: --dev can only be used with --build" >&2
        exit 1
    fi
    
    # Validate image parameter
    if [[ -n "$DOCKER_IMAGE" && "$BUILD_IMAGE" == "true" ]]; then
        echo "Error: --image cannot be used with --build (build creates specific images)" >&2
        exit 1
    fi
    
    # New validation: For assistant mode, require explicit -p flag for prompts
    # No validation needed for dispatcher mode (it handles subcommands)
    if [[ "$SCRIPT_TYPE" == "assistant" && ${#REMAINING_ARGS[@]} -gt 0 && -z "$USER_PROMPT" ]]; then
        # Check if there are any remaining args that look like prompts
        local has_non_option_args=false
        for arg in "${REMAINING_ARGS[@]}"; do
            if [[ "$arg" != --* ]]; then
                has_non_option_args=true
                break
            fi
        done
        
        if [[ "$has_non_option_args" == "true" ]]; then
            echo "Error: Direct text prompts not supported. Use --prompt or -p flag" >&2
            echo "" >&2
            echo "Bad:  nyia-claude 'help me'" >&2
            echo "Good: nyia-claude -p 'help me'" >&2
            echo "      nyia-claude --prompt 'help me'" >&2
            echo "      nyia-claude              # Interactive mode" >&2
            echo "" >&2
            exit 1
        fi
    fi
    
    # Validate flavor parameter
    if [[ -n "$FLAVOR" ]]; then
        # Source the validation function if not already available
        local script_dir="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
        if [[ -f "$script_dir/../bin/common/shared.sh" ]] && ! declare -f validate_flavor_name >/dev/null; then
            source "$script_dir/../bin/common/shared.sh"
        fi
        
        # Validate flavor name format
        if declare -f validate_flavor_name >/dev/null && ! validate_flavor_name "$FLAVOR"; then
            echo "Error: Invalid flavor name '$FLAVOR'" >&2
            echo "" >&2
            echo "Flavor names must:" >&2
            echo "  - Start and end with alphanumeric characters" >&2
            echo "  - Contain only lowercase letters, numbers, and hyphens" >&2
            echo "  - Not have consecutive hyphens" >&2
            echo "" >&2
            echo "Valid examples: node, python, node18, php81, nextjs" >&2
            echo "Invalid examples: Node, python_3, -node, php-, node--js" >&2
            exit 1
        fi
    fi
    
    # Validate conflicting image selection flags
    if [[ -n "$FLAVOR" && -n "$DOCKER_IMAGE" ]]; then
        echo "Error: Cannot use both --flavor and --image flags together" >&2
        echo "" >&2
        echo "Choose one approach:" >&2
        echo "  --flavor=node           # Use flavor system" >&2
        echo "  --image=custom:tag      # Use specific image" >&2
        exit 1
    fi
}

# === UTILITY FUNCTIONS ===
show_help() {
    local script_name="$1"
    local assistant_name="$2"
    local thematic_alias="$3"
    
    case "$SCRIPT_TYPE" in
        "dispatcher")
            show_dispatcher_help "$script_name"
            ;;
        "assistant")
            show_assistant_help "$assistant_name" "$thematic_alias"
            ;;
        *)
            echo "Error: Cannot show help for unknown script type: $SCRIPT_TYPE" >&2
            exit 1
            ;;
    esac
}

print_verbose() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo "🔧 $*" >&2
    fi
}

# === DEBUGGING ===
debug_args() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo "=== CLI Parser Debug ===" >&2
        echo "SCRIPT_TYPE: $SCRIPT_TYPE" >&2
        echo "SHOW_HELP: $SHOW_HELP" >&2
        echo "SHOW_STATUS: $SHOW_STATUS" >&2
        echo "BUILD_IMAGE: $BUILD_IMAGE" >&2
        echo "DEV_MODE: $DEV_MODE" >&2
        echo "NO_CACHE: $NO_CACHE" >&2
        echo "LOGIN_ONLY: $LOGIN_ONLY" >&2
        echo "DOCKER_IMAGE: $DOCKER_IMAGE" >&2
        echo "LIST_IMAGES: $LIST_IMAGES" >&2
        echo "PROJECT_PATH: $PROJECT_PATH" >&2
        echo "COMMAND: $COMMAND" >&2
        echo "ASSISTANT_NAME: $ASSISTANT_NAME" >&2
        echo "USER_PROMPT: $USER_PROMPT" >&2
        echo "REMAINING_ARGS: ${REMAINING_ARGS[*]}" >&2
        echo "======================" >&2
    fi
}

# === MAIN ENTRY POINT ===
# Usage: source lib/cli-parser.sh && parse_args "dispatcher|assistant" "$@"
# This file is meant to be sourced, not executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Error: cli-parser.sh should be sourced, not executed directly" >&2
    echo "Usage: source lib/cli-parser.sh && parse_args 'dispatcher' \"\$@\"" >&2
    exit 1
fi
