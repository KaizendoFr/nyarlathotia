#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR Proprietary
# Copyright (c) 2024 NyarlathotIA Contributors

# Workspace mode functions for multi-repository support
# This module provides functions to detect, parse, and manage workspace configurations
# that allow a single NyarlathotIA session to work across multiple related repositories.

# === WORKSPACE DETECTION ===

# Returns 0 if workspace.conf exists, 1 otherwise
# Usage: is_workspace [project_path]
is_workspace() {
    local project_path="${1:-$(pwd)}"
    [[ -f "$project_path/.nyarlathotia/workspace.conf" ]]
}

# === WORKSPACE PARSING ===

# Reads workspace.conf, expands paths, returns array (one path per line)
# Usage: mapfile -t repos < <(parse_workspace_repos "$PROJECT_PATH")
parse_workspace_repos() {
    local project_path="$1"
    local conf_file="$project_path/.nyarlathotia/workspace.conf"

    [[ ! -f "$conf_file" ]] && return 0

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip empty lines
        [[ -z "$line" ]] && continue
        # Skip comment lines (# at start, with optional leading whitespace)
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        # Trim leading/trailing whitespace
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "$line" ]] && continue

        # Expand ~ to $HOME
        line="${line/#\~/$HOME}"

        # Resolve symlinks to canonical path (Issue #9)
        if [[ -d "$line" ]]; then
            line=$(realpath "$line" 2>/dev/null || echo "$line")
        fi

        echo "$line"
    done < "$conf_file"
}

# === WORKSPACE VERIFICATION ===

# Verify all repos exist and are git repos
# Usage: verify_workspace_repos "$workspace_path" "${repos[@]}"
verify_workspace_repos() {
    local workspace_path="$1"
    shift
    local -a repos=("$@")

    # Get canonical workspace path for self-reference check (Issue #8)
    local canonical_workspace
    canonical_workspace=$(realpath "$workspace_path" 2>/dev/null || echo "$workspace_path")

    for repo in "${repos[@]}"; do
        [[ -z "$repo" ]] && continue

        # Resolve to canonical path for comparison
        local canonical_repo
        canonical_repo=$(realpath "$repo" 2>/dev/null || echo "$repo")

        # Self-reference check (Issue #8)
        if [[ "$canonical_repo" == "$canonical_workspace" ]]; then
            if declare -f print_error >/dev/null 2>&1; then
                print_error "Workspace cannot include itself: $repo"
            else
                echo "ERROR: Workspace cannot include itself: $repo" >&2
            fi
            return 1
        fi

        # Check directory exists
        if [[ ! -d "$repo" ]]; then
            if declare -f print_error >/dev/null 2>&1; then
                print_error "Workspace repo not found: $repo"
            else
                echo "ERROR: Workspace repo not found: $repo" >&2
            fi
            return 1
        fi

        # Check is git repository
        if [[ ! -d "$repo/.git" ]]; then
            if declare -f print_error >/dev/null 2>&1; then
                print_error "Workspace repo is not a git repository: $repo"
            else
                echo "ERROR: Workspace repo is not a git repository: $repo" >&2
            fi
            return 1
        fi
    done

    return 0
}

# === VOLUME ARGS BUILDING ===

# Builds complete VOLUME_ARGS for workspace mode
# Calls create_volume_args for workspace, then appends repos
# Usage: build_workspace_volume_args "$workspace_path" "$container_path" "${repos[@]}"
build_workspace_volume_args() {
    local workspace_path="$1"
    local container_path="$2"
    shift 2
    local -a repos=("$@")

    # Step 1: Mount workspace with its exclusions (clears VOLUME_ARGS)
    if declare -f create_volume_args >/dev/null 2>&1; then
        create_volume_args "$workspace_path" "$container_path"
    else
        VOLUME_ARGS=("-v" "$workspace_path:$container_path:rw")
    fi

    # Step 2: Append each repo (does NOT clear VOLUME_ARGS)
    if declare -f append_repo_volume_args >/dev/null 2>&1; then
        for repo in "${repos[@]}"; do
            [[ -z "$repo" ]] && continue
            append_repo_volume_args "$repo" "$container_path/repos"
        done
    fi
}

# Shared helper called by run_docker_container() and run_debug_shell()
# Abstracts the workspace vs normal mode volume mounting decision
# Usage: get_workspace_volume_args "$project_path" "$container_path"
get_workspace_volume_args() {
    local project_path="$1"
    local container_path="$2"

    if [[ "$WORKSPACE_MODE" == "true" ]] && declare -f build_workspace_volume_args >/dev/null 2>&1; then
        build_workspace_volume_args "$project_path" "$container_path" "${WORKSPACE_REPOS[@]}"
    elif declare -f create_volume_args >/dev/null 2>&1; then
        create_volume_args "$project_path" "$container_path"
    else
        VOLUME_ARGS=("-v" "$project_path:$container_path:rw")
    fi
}
