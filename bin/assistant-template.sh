#!/bin/bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR Proprietary
# Copyright (c) 2024 NyarlathotIA Contributors

# NyarlathotIA Assistant Template
# Generic wrapper for all AI assistants - source this with ASSISTANT_CONFIG set

set -e

# Source centralized CLI parser and common functions
script_dir="$(dirname "$(realpath "$0")")"
source "$script_dir/../lib/cli-parser.sh"
source "$script_dir/common-functions.sh"

# Load assistant configuration
if [[ -z "$ASSISTANT_CONFIG" ]]; then
    print_error "ASSISTANT_CONFIG not set"
    exit 1
fi

# Resolve relative paths
if [[ "$ASSISTANT_CONFIG" != /* ]]; then
    ASSISTANT_CONFIG="$script_dir/$ASSISTANT_CONFIG"
fi

if [[ ! -f "$ASSISTANT_CONFIG" ]]; then
    # Docker-style fallback: check default location if user-specified path fails
    assistant_name=$(basename "$ASSISTANT_CONFIG" .conf)
    nyia_home=$(get_nyarlathotia_home 2>/dev/null)
    default_config="$nyia_home/config/${assistant_name}.conf"
    
    if [[ -f "$default_config" ]]; then
        print_info "Configuration not found at: $ASSISTANT_CONFIG"
        print_info "Using default configuration: $default_config"
        ASSISTANT_CONFIG="$default_config"
    else
        print_error "Assistant configuration file not found: $ASSISTANT_CONFIG"
        if [[ -n "$nyia_home" && -d "$nyia_home/config" ]]; then
            print_info "Default configuration directory: $nyia_home/config"
            print_info "Available configurations:"
            if ls "$nyia_home/config"/*.conf 2>/dev/null; then
                ls "$nyia_home/config"/*.conf | sed 's/^/  /'
            else
                print_info "  No configuration files found in default location"
                print_info "  Contact your administrator to install the assistant"
            fi
        fi
        exit 1
    fi
fi

source "$ASSISTANT_CONFIG"

# Validate required configuration variables
for var in ASSISTANT_NAME ASSISTANT_CLI BASE_IMAGE_NAME DOCKERFILE_PATH CONTEXT_DIR_NAME; do
    if [[ -z "${!var}" ]]; then
        print_error "Required configuration variable not set: $var"
        exit 1
    fi
done

# Assistant-specific directories are created by get_nyarlathotia_home() -> generate_default_assistant_configs()

# === MAIN EXECUTION ===
main() {
    # Store assistant name from config BEFORE parsing (CLI parser resets variables)
    config_assistant_name="$ASSISTANT_NAME"
    config_thematic_alias="$THEMATIC_ALIAS"
    
    # Parse arguments using centralized parser
    parse_args "assistant" "$@"
    validate_args
    debug_args
    
    # Set project path if not provided
    if [[ -z "$PROJECT_PATH" ]]; then
        PROJECT_PATH=$(pwd)
    fi
    
    # Auto-initialize exclusions system on first run (Git-style behavior)
    # Only if exclusions are enabled and config doesn't exist
    if [[ "$ENABLE_MOUNT_EXCLUSIONS" == "true" ]] || [[ -z "$ENABLE_MOUNT_EXCLUSIONS" ]]; then
        if [[ ! -f "$PROJECT_PATH/.nyarlathotia/exclusions.conf" ]]; then
            # Load exclusions library to get init function
            local exclusions_lib="$script_dir/../lib/exclusions-commands.sh"
            if [[ -f "$exclusions_lib" ]]; then
                source "$exclusions_lib"
                
                # Call full exclusions initialization (silent mode)
                local old_verbose="$VERBOSE"
                export VERBOSE="false"
                exclusions_init "$PROJECT_PATH" >/dev/null 2>&1
                export VERBOSE="$old_verbose"
                
                if [[ "$VERBOSE" == "true" ]]; then
                    print_info "Auto-initialized exclusions system: .nyarlathotia/exclusions.conf"
                fi
            else
                print_error "Failed to load exclusions library: $exclusions_lib"
                exit 1
            fi
        fi
    fi
    
    # SECURITY CHECKPOINT: Verify exclusions system is loaded when enabled
    if [[ "$ENABLE_MOUNT_EXCLUSIONS" == "true" ]] || [[ -z "$ENABLE_MOUNT_EXCLUSIONS" ]]; then
        # Load mount exclusions library if not already loaded
        local mount_exclusions_lib="$script_dir/../lib/mount-exclusions.sh"
        if ! declare -f create_volume_args >/dev/null 2>&1; then
            if [[ -f "$mount_exclusions_lib" ]]; then
                source "$mount_exclusions_lib"
            fi
        fi
        
        # Final verification - exclusions must work when enabled
        if ! declare -f create_volume_args >/dev/null 2>&1; then
            print_error "SECURITY ERROR: Mount exclusions enabled but system failed to load"
            print_error "This would expose sensitive files (.env, credentials) to AI assistants"
            print_error ""
            print_error "To fix:"
            print_error "  1. Restart and try again"
            print_error "  2. Use --disable-exclusions flag (NOT RECOMMENDED for security)"
            exit 1
        fi
        print_verbose "✅ Mount exclusions verified and active"
    fi
    
    # Show warning when exclusions explicitly disabled
    if [[ "$DISABLE_EXCLUSIONS" == "true" ]]; then
        print_warning() { echo -e "\e[33m⚠️  $1\e[0m" >&2; }
        print_warning "SECURITY RISK: Mount exclusions disabled"
        print_warning "Sensitive files (.env, credentials, keys) are exposed to AI"
        print_warning "Only use this in trusted environments"
        echo ""
    fi
    
    # Use explicit prompt from -p/--prompt flag or interactive mode
    local prompt="$USER_PROMPT"
    
    # Handle help
    if [[ "$SHOW_HELP" == "true" ]]; then
        show_help "$(basename "$0")" "$config_assistant_name" ""
        exit 0
    fi
    
    # Handle requirements check
    if [[ "$CHECK_REQUIREMENTS" == "true" ]]; then
        show_requirements_check "$PROJECT_PATH"
        exit $?
    fi
    
    
    # Handle custom image build (end-user power feature)
    if [[ "$BUILD_CUSTOM_IMAGE" == "true" ]]; then
        build_custom_image "$assistant_name"
        exit $?
    fi
    
    # Handle status mode
    if [[ "$SHOW_STATUS" == "true" ]]; then
        show_assistant_status
        exit 0
    fi
    
    # Handle list images mode
    if [[ "$LIST_IMAGES" == "true" ]]; then
        list_assistant_images "$BASE_IMAGE_NAME"
        exit 0
    fi

    # Handle API key setup mode
    if [[ "$SET_API_KEY" == "true" ]]; then
        set_api_key_helper "$config_assistant_name" "$ASSISTANT_CLI"
        exit $?
    fi

    # Handle interactive setup mode (OpenCode model selection)
    if [[ "$SETUP_MODE" == "true" ]]; then
        if [[ "$ASSISTANT_CLI" == "opencode" ]]; then
            "$NYARLATHOTIA_HOME/bin/opencode-setup.sh"
            exit $?
        else
            print_error "Interactive setup is only available for OpenCode assistant"
            exit 1
        fi
    fi


    # Source credentials if available
    local creds_file="$PROJECT_PATH/.nyarlathotia/creds/env"
    if [[ -f "$creds_file" ]]; then
        source "$creds_file"
        print_verbose "Loaded credentials from $creds_file"
    else
        print_verbose "No credentials file found at $creds_file"
    fi
    
    # Source provider-specific hooks if they exist and call setup hook
    # (Must happen before login and credential checks)
    local provider_hooks_file="$DOCKERFILE_PATH/${ASSISTANT_CLI}-hooks.sh"
    if [[ -f "$provider_hooks_file" ]]; then
        source "$provider_hooks_file"
        
        # Call setup hook if it exists
        if declare -f setup_env_vars >/dev/null; then
            setup_env_vars
        fi
    fi
    
    # Handle login mode
    if [[ "$LOGIN_ONLY" == "true" ]]; then
        login_assistant "$ASSISTANT_CLI" "$BASE_IMAGE_NAME" "$DOCKERFILE_PATH" "$CONFIG_DIR_NAME" "$AUTH_METHOD" "$DEV_MODE" "$SHELL_MODE" "$DOCKER_IMAGE"
        exit $?
    fi
    
    # Run requirements check before execution (unless skipped)
    if [[ "$SKIP_CHECKS" != "true" ]]; then
        if ! check_requirements_fast "$PROJECT_PATH"; then
            print_error "Requirements check failed. Fix issues above or use --skip-checks to bypass"
            print_info "Run '$config_assistant_name --check-requirements' for detailed diagnostics"
            exit 1
        fi
    fi
    
    # Execute assistant using abstracted functions  
    run_assistant "$config_assistant_name" "$ASSISTANT_CLI" "$BASE_IMAGE_NAME" "$DOCKERFILE_PATH" "$CONTEXT_DIR_NAME" "$PROJECT_PATH" "$prompt" "$BASE_BRANCH" "$DEV_MODE" "$SHELL_MODE" "$DOCKER_IMAGE" "$WORK_BRANCH"
}

# === STATUS DISPLAY ===
show_assistant_status() {
    local nyarlathotia_home=$(get_nyarlathotia_home)
    
    echo "NyarlathotIA ${config_assistant_name} Status:"
    echo "  Project: $(basename "$PROJECT_PATH")"
    echo "  Path: $PROJECT_PATH"
    echo "  Branch: $(get_current_branch)"
    
    if [[ "$DEV_MODE" == "true" ]]; then
        echo "  Mode: Development"
        local dev_image=$(get_target_image "$BASE_IMAGE_NAME" "true" "true")
        echo "  Target image: $dev_image"
        # Try to find what would actually be used
        local selected_image=$(find_best_image "$BASE_IMAGE_NAME" "true" 2>/dev/null || echo "No suitable image found")
    else
        echo "  Mode: Production (default)"
        local prod_image=$(get_target_image "$BASE_IMAGE_NAME" "false" "true")
        echo "  Target image: $prod_image"
        # Try to find what would actually be used
        local selected_image=$(find_best_image "$BASE_IMAGE_NAME" "false" 2>/dev/null || echo "No suitable image found")
    fi
    
    echo "  Selected image: $selected_image"
    echo "  Context dir: $PROJECT_PATH/$CONTEXT_DIR_NAME"
    
    # Show available images
    echo "  Available images:"
    if command -v docker >/dev/null && docker images --filter "reference=${BASE_IMAGE_NAME}*" --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}" 2>/dev/null | tail -n +2 | grep -q . 2>/dev/null; then
        docker images --filter "reference=${BASE_IMAGE_NAME}*" --format "    {{.Repository}}:{{.Tag}} ({{.Size}}, {{.CreatedAt}})" 2>/dev/null
    else
        echo "    No images found - run nyia-${config_assistant_name} --build-custom-image to create custom overlay"
    fi
    
    # Show Docker overlays
    echo ""
    echo "=== Docker Overlays ==="
    # Extract just assistant name (remove nyarlathotia- prefix if present) 
    local assistant_name=$(basename "$BASE_IMAGE_NAME" | cut -d: -f1 | sed 's/^nyarlathotia-//')
    
    # Check user overlay
    local user_overlay="$HOME/.config/nyarlathotia/$assistant_name/overlay/Dockerfile"
    if [[ -f "$user_overlay" ]]; then
        echo "  User overlay: FOUND"
        echo "    Path: $user_overlay"
    else
        echo "  User overlay: Not configured"
        echo "    Create at: ~/.config/nyarlathotia/$assistant_name/overlay/Dockerfile"
    fi
    
    # Check project overlay
    local project_overlay="$PROJECT_PATH/.nyarlathotia/$assistant_name/overlay/Dockerfile"
    if [[ -f "$project_overlay" ]]; then
        echo "  Project overlay: FOUND"
        echo "    Path: $project_overlay"
    else
        echo "  Project overlay: Not configured"
        echo "    Create at: .nyarlathotia/$assistant_name/overlay/Dockerfile"
    fi
    
    # Show example overlays
    echo ""
    echo "=== Overlay Documentation ==="
    echo "Create custom Dockerfile at overlay location:"
    echo "  FROM ghcr.io/nyarlathotia/$assistant_name:latest"
    echo "  RUN apt-get update && apt-get install -y your-tools"
    echo ""
    echo "Then build: nyia-$assistant_name --build-custom-image"
}

main "$@"
