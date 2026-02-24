#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR Proprietary
# Copyright (c) 2024 Nyia Keeper Contributors
# MIGRATION-COMPAT: remove after v0.2.x
# Contains all "nyarlathotia" references for backward-compat migration.
# This file is excluded from the zero-reference verification gate.

# INTENTIONAL POLICY: Content rewrite updates all old-name references in
# migrated text files. This includes historical references (changelogs, plans).
# Acceptable because these are LLM-consumed files where the current name
# matters more than historical accuracy. Binary files are excluded via
# extension allowlist. Uses portable sed/grep (BSD + GNU compatible).
_migrate_file_contents() {
    local dir="$1"
    local count=0
    # Process substitution (not pipe) so count stays in current shell.
    # Bash + GNU/BSD compatible (not POSIX — uses process substitution + grep --include).
    # --include flags BEFORE path for portability/readability.
    # "|| true" on grep: exit code 1 on no matches is safe under pipefail.
    while IFS= read -r f; do
        # BSD+GNU portable: sed -i.bak + rm .bak
        sed -i.bak 's/NyarlathotIA/Nyia Keeper/g; s/NYARLATHOTIA/NYIAKEEPER/g; s/Nyarlathotia/Nyiakeeper/g; s/nyarlathotia/nyiakeeper/g' "$f"
        rm -f "$f.bak"
        count=$((count + 1))
    done < <(grep -rl --include='*.md' --include='*.conf' --include='*.json' \
        --include='*.yaml' --include='*.yml' --include='*.sh' --include='*.txt' \
        --exclude-dir='plans' \
        'nyarlathotia\|Nyarlathotia\|NyarlathotIA\|NYARLATHOTIA' \
        "$dir" 2>/dev/null || true)
    if [[ $count -gt 0 ]]; then
        echo "[MIGRATION] Updated content in $count file(s)" >&2
    fi
}

# Remove existing marker dir before mv, with safety guards.
# Marker is expendable — just a signal that migration happened.
_remove_marker_if_exists() {
    local marker="$1"
    # Safety: only delete if non-empty var, ends with expected suffix, and is a directory
    if [[ -n "$marker" && "$marker" == *".migrated-to-nyiakeeper" && -d "$marker" ]]; then
        rm -rf "$marker"
    fi
}

# Migrate config dir from old name to new name if needed.
# Called from get_nyiakeeper_home() in common-functions.sh.
# After migration, old dir is renamed to *.migrated-to-nyiakeeper as marker.
migrate_config_dir_if_needed() {
    local new_dir="$1"
    local old_dir="${new_dir/nyiakeeper/nyarlathotia}"
    local marker="${old_dir}.migrated-to-nyiakeeper"

    # No old dir (fresh install or already migrated) → nothing to do
    [[ -d "$old_dir" ]] || return 0

    echo "[MIGRATION] Migrating config: $old_dir -> $new_dir" >&2

    if [[ ! -d "$new_dir" ]]; then
        # New dir absent → rename old to new, then leave marker
        _remove_marker_if_exists "$marker"
        if mv "$old_dir" "$new_dir"; then
            mkdir "$marker"
            _migrate_file_contents "$new_dir"
            echo "[MIGRATION] Complete. Old config dir is now deprecated." >&2
        else
            echo "[MIGRATION] ERROR: Failed to move $old_dir -> $new_dir" >&2
        fi
    else
        # New dir exists (possibly empty skeleton) → merge old into new
        cp -a "$old_dir"/. "$new_dir"/
        _remove_marker_if_exists "$marker"
        if mv "$old_dir" "$marker"; then
            _migrate_file_contents "$new_dir"
            echo "[MIGRATION] Complete. Old config dir is now deprecated." >&2
        else
            echo "[MIGRATION] ERROR: Failed to rename $old_dir to marker" >&2
        fi
    fi
}

# Migrate project tracking dir from .nyarlathotia to .nyiakeeper if needed.
# Called from init_nyiakeeper_dir() in shared.sh.
# After migration, old dir is renamed to *.migrated-to-nyiakeeper as marker.
migrate_project_dir_if_needed() {
    local project_path="$1"
    local new_dir="$project_path/.nyiakeeper"
    local old_dir="$project_path/.nyarlathotia"
    local marker="${old_dir}.migrated-to-nyiakeeper"

    # No old dir (fresh install or already migrated) → nothing to do
    [[ -d "$old_dir" ]] || return 0

    echo "[MIGRATION] Migrating project dir: .nyarlathotia/ -> .nyiakeeper/" >&2

    if [[ ! -d "$new_dir" ]]; then
        # New dir absent → rename old to new, then leave marker
        _remove_marker_if_exists "$marker"
        if mv "$old_dir" "$new_dir"; then
            mkdir "$marker"
            _migrate_file_contents "$new_dir"
            echo "[MIGRATION] Complete. Old project dir is now deprecated." >&2
        else
            echo "[MIGRATION] ERROR: Failed to move $old_dir -> $new_dir" >&2
        fi
    else
        # New dir exists (possibly empty skeleton) → merge old into new
        cp -a "$old_dir"/. "$new_dir"/
        _remove_marker_if_exists "$marker"
        if mv "$old_dir" "$marker"; then
            _migrate_file_contents "$new_dir"
            echo "[MIGRATION] Complete. Old project dir is now deprecated." >&2
        else
            echo "[MIGRATION] ERROR: Failed to rename $old_dir to marker" >&2
        fi
    fi
}

export -f _migrate_file_contents _remove_marker_if_exists \
    migrate_config_dir_if_needed migrate_project_dir_if_needed
