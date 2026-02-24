#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR Proprietary
# Copyright (c) 2024 Nyia Keeper Contributors

# Agent Resolution Helper (Plan 149)
# Resolves agent persona paths and lists available agents per assistant
# Scope precedence: session (--agent) > project-local > global user > default

# Get assistant-specific agent directories (project-local and global)
# Returns two paths: project-local first, then global
get_agent_dirs() {
    local assistant_cli="$1"
    local project_path="$2"
    local nyiakeeper_home="$3"

    local project_dir=""
    local global_dir=""

    case "$assistant_cli" in
        claude)
            project_dir="$project_path/.claude/agents"
            global_dir="$nyiakeeper_home/claude/agents"
            ;;
        opencode)
            project_dir="$project_path/.opencode/agents"
            global_dir="$nyiakeeper_home/opencode/agents"
            ;;
        vibe)
            project_dir="$project_path/.vibe/agents"
            global_dir="$nyiakeeper_home/vibe/agents"
            ;;
        codex)
            # Codex uses config-based agents, not file-based
            project_dir=""
            global_dir=""
            ;;
        *)
            project_dir=""
            global_dir=""
            ;;
    esac

    echo "$project_dir"
    echo "$global_dir"
}

# Get the file extension pattern for agent definitions
get_agent_file_pattern() {
    local assistant_cli="$1"

    case "$assistant_cli" in
        claude)    echo "*.md" ;;
        opencode)  echo "*.md *.json" ;;
        vibe)      echo "*.toml" ;;
        *)         echo "" ;;
    esac
}

# List available agents for an assistant
# Scans project-local and global directories
list_agents() {
    local assistant_cli="$1"
    local project_path="$2"
    local nyiakeeper_home="$3"

    local dirs
    dirs=$(get_agent_dirs "$assistant_cli" "$project_path" "$nyiakeeper_home")
    local project_dir
    project_dir=$(echo "$dirs" | head -1)
    local global_dir
    global_dir=$(echo "$dirs" | tail -1)

    local found_any=false

    echo "Available agent personas for $assistant_cli:"
    echo ""

    # Codex special case: guidance-only
    if [[ "$assistant_cli" == "codex" ]]; then
        echo "  Codex uses config-based agents (not file-based)."
        echo ""
        echo "  To define agents, add sections to ~/.codex/config.toml:"
        echo "    [agents.my-agent]"
        echo "    agent_type = \"custom\""
        echo "    description = \"My custom agent\""
        echo ""
        echo "  To switch agents in a Codex session, use the /agent command."
        return 0
    fi

    # Gemini: not supported
    if [[ "$assistant_cli" == "gemini" ]]; then
        echo "  Agent persona selection is not yet supported for Gemini."
        return 0
    fi

    local patterns
    patterns=$(get_agent_file_pattern "$assistant_cli")

    # Disable glob expansion so patterns like *.md don't expand in for loops
    local restore_glob=false
    if [[ -o noglob ]]; then
        restore_glob=false
    else
        restore_glob=true
        set -f
    fi

    # Project-local agents
    if [[ -n "$project_dir" && -d "$project_dir" ]]; then
        local project_agents=()
        for pattern in $patterns; do
            while IFS= read -r -d '' f; do
                project_agents+=("$f")
            done < <(find "$project_dir" -maxdepth 1 -name "$pattern" -type f -print0 2>/dev/null)
        done
        if [[ ${#project_agents[@]} -gt 0 ]]; then
            echo "  Project agents ($project_dir/):"
            for agent_file in "${project_agents[@]}"; do
                local name
                name=$(basename "$agent_file" | sed 's/\.[^.]*$//')
                printf "    %-20s %s\n" "$name" "($(basename "$agent_file"))"
            done
            echo ""
            found_any=true
        fi
    fi

    # Global agents
    if [[ -n "$global_dir" && -d "$global_dir" ]]; then
        local global_agents=()
        for pattern in $patterns; do
            while IFS= read -r -d '' f; do
                global_agents+=("$f")
            done < <(find "$global_dir" -maxdepth 1 -name "$pattern" -type f -print0 2>/dev/null)
        done
        if [[ ${#global_agents[@]} -gt 0 ]]; then
            echo "  Global agents ($global_dir/):"
            for agent_file in "${global_agents[@]}"; do
                local name
                name=$(basename "$agent_file" | sed 's/\.[^.]*$//')
                printf "    %-20s %s\n" "$name" "($(basename "$agent_file"))"
            done
            echo ""
            found_any=true
        fi
    fi

    # Restore glob expansion
    if [[ "$restore_glob" == "true" ]]; then
        set +f
    fi

    if [[ "$found_any" == "false" ]]; then
        echo "  No agent personas found."
        echo ""
        echo "  To create an agent, add a definition file to:"
        if [[ -n "$project_dir" ]]; then
            echo "    Project: $project_dir/"
        fi
        if [[ -n "$global_dir" ]]; then
            echo "    Global:  $global_dir/"
        fi
    fi

    return 0
}

# Check if a specific agent exists (for validation)
agent_exists() {
    local assistant_cli="$1"
    local agent_name="$2"
    local project_path="$3"
    local nyiakeeper_home="$4"

    # Codex: always "exists" (guidance-only, no file check)
    if [[ "$assistant_cli" == "codex" ]]; then
        return 0
    fi

    local dirs
    dirs=$(get_agent_dirs "$assistant_cli" "$project_path" "$nyiakeeper_home")
    local project_dir
    project_dir=$(echo "$dirs" | head -1)
    local global_dir
    global_dir=$(echo "$dirs" | tail -1)

    local patterns
    patterns=$(get_agent_file_pattern "$assistant_cli")

    # Disable glob expansion so patterns like *.md don't expand in for loops
    local restore_glob=false
    if [[ -o noglob ]]; then
        restore_glob=false
    else
        restore_glob=true
        set -f
    fi

    # Check project-local first (higher precedence)
    for dir in "$project_dir" "$global_dir"; do
        if [[ -n "$dir" && -d "$dir" ]]; then
            for pattern in $patterns; do
                local ext="${pattern#\*}"
                if [[ -f "$dir/${agent_name}${ext}" ]]; then
                    [[ "$restore_glob" == "true" ]] && set +f
                    return 0
                fi
            done
        fi
    done

    # Restore glob expansion
    [[ "$restore_glob" == "true" ]] && set +f
    return 1
}

# Export functions
export -f get_agent_dirs
export -f get_agent_file_pattern
export -f list_agents
export -f agent_exists
