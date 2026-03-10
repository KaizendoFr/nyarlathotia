#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR Proprietary
# Copyright (c) 2024 Nyia Keeper Contributors

# Skill Resolution Helper (Plan 177)
# Resolves skill paths and lists available skills per assistant
# 4-scope precedence: project > shared > team > global
# Scans raw source directories (not post-propagation targets)

# Get skill source directories for an assistant
# Returns 4 paths (one per line): project, shared, team, global
# Team line is empty if team_dir is not provided
# Global is the raw source ($NYIAKEEPER_HOME/skills/), not propagation target
get_skill_dirs() {
    local assistant_cli="$1"
    local project_path="$2"
    local nyiakeeper_home="$3"
    local team_dir="${4:-}"

    local project_dir=""
    local shared_dir=""
    local team_skills_dir=""
    local global_dir=""

    case "$assistant_cli" in
        claude)
            project_dir="$project_path/.claude/skills"
            ;;
        opencode)
            project_dir="$project_path/.opencode/skills"
            ;;
        vibe)
            project_dir="$project_path/.vibe/skills"
            ;;
        codex)
            project_dir="$project_path/.codex/skills"
            ;;
        gemini)
            project_dir="$project_path/.gemini/skills"
            ;;
        *)
            project_dir=""
            ;;
    esac

    # Shared skills are assistant-agnostic
    if [[ -n "$project_dir" ]]; then
        shared_dir="$project_path/.nyiakeeper/shared/skills"
    fi

    # Team skills are assistant-agnostic
    if [[ -n "$team_dir" ]]; then
        team_skills_dir="$team_dir/skills"
    fi

    # Global is the raw source (assistant-agnostic), not propagation target
    global_dir="$nyiakeeper_home/skills"

    echo "$project_dir"
    echo "$shared_dir"
    echo "$team_skills_dir"
    echo "$global_dir"
}

# Discover valid skills in a directory
# Skills are subdirectories containing SKILL.md
# Prints skill names (directory basenames) to stdout, one per line
_discover_skills_in_dir() {
    local dir="$1"

    [[ -z "$dir" || ! -d "$dir" ]] && return 0

    for skill_dir in "$dir"/*/; do
        [[ -d "$skill_dir" ]] || continue
        [[ -f "$skill_dir/SKILL.md" ]] || continue
        basename "$skill_dir"
    done
}

# List available skills for an assistant
# Scans 4 raw source directories with dedup (project > shared > team > global)
list_skills() {
    local assistant_cli="$1"
    local project_path="$2"
    local nyiakeeper_home="$3"
    local team_dir="${4:-}"

    local dirs
    dirs=$(get_skill_dirs "$assistant_cli" "$project_path" "$nyiakeeper_home" "$team_dir")
    local project_dir
    project_dir=$(echo "$dirs" | sed -n '1p')
    local shared_dir
    shared_dir=$(echo "$dirs" | sed -n '2p')
    local team_skills_dir
    team_skills_dir=$(echo "$dirs" | sed -n '3p')
    local global_dir
    global_dir=$(echo "$dirs" | sed -n '4p')

    local found_any=false
    # Track seen skill names for dedup (higher scope wins)
    local seen_skills=""

    echo "Available skills for $assistant_cli:"
    echo ""

    # Helper: check if a skill name is already seen
    _skill_is_seen() {
        local name="$1"
        local entry
        for entry in $seen_skills; do
            [[ "$entry" == "$name" ]] && return 0
        done
        return 1
    }

    # Helper: list skills from a scope with dedup
    _list_scope() {
        local scope_label="$1"
        local scope_dir="$2"

        [[ -z "$scope_dir" || ! -d "$scope_dir" ]] && return 0

        local scope_skills=()
        while IFS= read -r skill_name; do
            [[ -z "$skill_name" ]] && continue
            # Dedup: skip if already seen in higher scope
            if _skill_is_seen "$skill_name"; then
                continue
            fi
            scope_skills+=("$skill_name")
        done < <(_discover_skills_in_dir "$scope_dir")

        if [[ ${#scope_skills[@]} -gt 0 ]]; then
            echo "  $scope_label ($scope_dir/):"
            for skill_name in "${scope_skills[@]}"; do
                printf "    %-20s %s\n" "$skill_name" "(SKILL.md)"
                seen_skills="$seen_skills $skill_name"
            done
            echo ""
            found_any=true
        fi
    }

    # Scan scopes in precedence order
    _list_scope "Project skills" "$project_dir"
    _list_scope "Shared skills" "$shared_dir"
    _list_scope "Team skills" "$team_skills_dir"
    _list_scope "Global skills" "$global_dir"

    if [[ "$found_any" == "false" ]]; then
        echo "  No skills found."
        echo ""
        echo "  To create a skill, add a SKILL.md file in a subdirectory:"
        if [[ -n "$shared_dir" ]]; then
            echo "    Shared:  $shared_dir/<skill-name>/SKILL.md"
        fi
        if [[ -n "$project_dir" ]]; then
            echo "    Project: $project_dir/<skill-name>/SKILL.md"
        fi
        echo "    Global:  $global_dir/<skill-name>/SKILL.md"
    fi

    return 0
}

# Check if a specific skill exists (any scope, precedence order)
skill_exists() {
    local assistant_cli="$1"
    local skill_name="$2"
    local project_path="$3"
    local nyiakeeper_home="$4"
    local team_dir="${5:-}"

    local dirs
    dirs=$(get_skill_dirs "$assistant_cli" "$project_path" "$nyiakeeper_home" "$team_dir")

    local dir
    while IFS= read -r dir; do
        [[ -z "$dir" ]] && continue
        if [[ -d "$dir/$skill_name" && -f "$dir/$skill_name/SKILL.md" ]]; then
            return 0
        fi
    done <<< "$dirs"

    return 1
}

# Export functions
export -f get_skill_dirs
export -f _discover_skills_in_dir
export -f list_skills
export -f skill_exists
