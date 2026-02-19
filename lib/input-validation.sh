#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR Proprietary
# Copyright (c) 2024 NyarlathotIA Contributors
# Input validation functions for security
# Prevents command injection and directory traversal attacks

# Source shared functions for error reporting
if ! declare -f print_error >/dev/null 2>&1; then
    source "$(dirname "${BASH_SOURCE[0]}")/../bin/common/shared.sh" 2>/dev/null || {
        # Fallback if shared.sh not available
        print_error() { echo "ERROR: $*" >&2; }
        print_info() { echo "INFO: $*" >&2; }
    }
fi

# Validate branch names (prevent command injection)
validate_branch_name() {
    local branch="$1"
    
    # Empty branch name
    if [[ -z "$branch" ]]; then
        print_error "Branch name cannot be empty"
        return 1
    fi
    
    # Allow: letters, numbers, slash, dash, underscore, dot
    # Block: semicolons, pipes, backticks, spaces, etc.
    if [[ "$branch" =~ ^[a-zA-Z0-9._/-]+$ ]]; then
        return 0
    else
        print_error "Invalid branch name: '$branch'"
        print_info "Branch names can only contain: a-z A-Z 0-9 . / _ -"
        print_info "Blocked characters: ; | \` & $ ( ) < > space"
        return 1
    fi
}

# Validate file paths (prevent directory traversal)
validate_file_path() {
    local path="$1"
    
    # Empty path
    if [[ -z "$path" ]]; then
        print_error "File path cannot be empty"
        return 1
    fi
    
    # Block directory traversal attempts
    if [[ "$path" == *".."* ]]; then
        print_error "Path contains '..': '$path'"
        print_info "Directory traversal attempts are blocked for security"
        return 1
    fi
    
    # Block absolute paths outside workspace (unless it's a known safe location)
    if [[ "$path" == /* ]]; then
        case "$path" in
            /workspace*|/tmp/*|/home/node/*)
                return 0  # Allow these paths
                ;;
            *)
                print_error "Absolute path outside allowed directories: '$path'"
                print_info "Allowed absolute paths: /workspace /tmp /home/node"
                return 1
                ;;
        esac
    fi
    
    return 0
}

# Validate Docker image names (prevent registry attacks)
validate_image_name() {
    local image="$1"
    
    # Empty image name
    if [[ -z "$image" ]]; then
        print_error "Image name cannot be empty"
        return 1
    fi
    
    # Basic format validation: [registry/]name[:tag]
    # Allow: letters, numbers, dots, slashes, dashes, colons, underscores
    # Block: spaces, semicolons, pipes, backticks, parentheses
    if [[ "$image" =~ ^[a-zA-Z0-9._/-]+:[a-zA-Z0-9._-]+$ ]]; then
        # Has tag - check for dangerous patterns
        if [[ "$image" == *";"* || "$image" == *"|"* || "$image" == *"\`"* || "$image" == *" "* ]]; then
            print_error "Image name contains dangerous characters: '$image'"
            return 1
        fi
        return 0
    elif [[ "$image" =~ ^[a-zA-Z0-9._/-]+$ ]]; then
        # No tag specified - that's okay for local images
        if [[ "$image" == *";"* || "$image" == *"|"* || "$image" == *"\`"* || "$image" == *" "* ]]; then
            print_error "Image name contains dangerous characters: '$image'"
            return 1
        fi
        return 0
    else
        print_error "Invalid image name format: '$image'"
        print_info "Expected format: [registry/]name[:tag]"
        print_info "Example: nyarlathotia/claude:latest"
        return 1
    fi
}

# Sanitize branch name for safe usage
sanitize_branch_name() {
    local branch="$1"
    # Replace any non-safe characters with dashes
    echo "$branch" | sed 's/[^a-zA-Z0-9._/-]/-/g'
}

# Export functions so they can be used after sourcing
export -f validate_branch_name
export -f validate_file_path  
export -f validate_image_name
export -f sanitize_branch_name