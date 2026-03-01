#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR Proprietary
# Auto-update checking and version management for Nyia Keeper runtime distribution.
# Provides startup update check (throttled), explicit update/rollback commands,
# release notes display, and tarball-based update with SHA256 verification.

# Source guard — prevent double-loading
[[ -n "${_AUTO_UPDATE_LOADED:-}" ]] && return 0
_AUTO_UPDATE_LOADED=1

# --- Constants ---

readonly UPDATE_CHECK_INTERVAL=3600  # 1 hour in seconds
readonly UPDATE_CURL_TIMEOUT=5       # seconds
readonly GITHUB_REPO="KaizendoFr/nyiakeeper"
readonly GITHUB_API="https://api.github.com/repos/${GITHUB_REPO}"
readonly GITHUB_RELEASES_URL="https://github.com/${GITHUB_REPO}/releases"
readonly MAX_RELEASE_NOTES_LINES=20
readonly LOCK_STALE_TIMEOUT=300      # 5 minutes — real updates can exceed 60s on slow connections

# --- Locking ---

acquire_update_lock() {
    # Single-owner boundary: if already held by this process, skip
    [[ "${_UPDATE_LOCK_HELD:-}" == "1" ]] && return 0

    local lock_dir="${NYIAKEEPER_HOME:?}/.update-lock"
    local pid_file="$lock_dir/pid"

    if mkdir "$lock_dir" 2>/dev/null; then
        echo $$ > "$pid_file"
        export _UPDATE_LOCK_HELD=1
        return 0
    fi

    # Lock exists — check if stale
    if [[ -f "$pid_file" ]]; then
        local lock_pid
        lock_pid=$(cat "$pid_file" 2>/dev/null) || lock_pid=""

        # Check if PID is still running
        if [[ -n "$lock_pid" ]] && ! kill -0 "$lock_pid" 2>/dev/null; then
            # Process is dead — remove stale lock
            rm -rf "$lock_dir"
            if mkdir "$lock_dir" 2>/dev/null; then
                echo $$ > "$pid_file"
                export _UPDATE_LOCK_HELD=1
                return 0
            fi
        fi

        # Check if lock is old (stale timeout)
        local lock_age
        if [[ "$(uname -s)" == "Darwin" ]]; then
            lock_age=$(( $(date +%s) - $(stat -f %m "$pid_file" 2>/dev/null || echo 0) ))
        else
            lock_age=$(( $(date +%s) - $(stat -c %Y "$pid_file" 2>/dev/null || echo 0) ))
        fi

        if [[ "$lock_age" -gt "$LOCK_STALE_TIMEOUT" ]]; then
            rm -rf "$lock_dir"
            if mkdir "$lock_dir" 2>/dev/null; then
                echo $$ > "$pid_file"
                export _UPDATE_LOCK_HELD=1
                return 0
            fi
        fi
    fi

    # Could not acquire lock
    return 1
}

release_update_lock() {
    [[ "${_UPDATE_LOCK_HELD:-}" != "1" ]] && return 0
    local lock_dir="${NYIAKEEPER_HOME:?}/.update-lock"
    rm -rf "$lock_dir"
    export _UPDATE_LOCK_HELD=0
}

# --- Cache & Throttle ---

is_update_check_due() {
    local cache_file="${NYIAKEEPER_HOME:?}/.update-cache"

    # No cache = check is due
    if [[ ! -f "$cache_file" ]]; then
        return 0
    fi

    local last_check=0
    while IFS='=' read -r key value; do
        [[ "$key" == "LAST_CHECK" ]] && last_check="$value"
    done < "$cache_file"

    local now
    now=$(date +%s)
    local elapsed=$(( now - last_check ))

    if [[ "$elapsed" -ge "$UPDATE_CHECK_INTERVAL" ]]; then
        return 0
    fi

    return 1
}

_write_update_cache() {
    local latest_tag="$1"
    local current_tag="$2"
    local cache_file="${NYIAKEEPER_HOME:?}/.update-cache"

    cat > "$cache_file" <<EOF
LAST_CHECK=$(date +%s)
LATEST_TAG=${latest_tag}
CURRENT_TAG=${current_tag}
EOF
}

# --- Version Discovery ---

fetch_latest_version() {
    local current_version="${1:-}"

    # Stage 1: try /releases/latest (works when repo has non-prerelease releases)
    local response
    response=$(curl -s --max-time "$UPDATE_CURL_TIMEOUT" \
        -H "Accept: application/vnd.github.v3+json" \
        "${GITHUB_API}/releases/latest" 2>/dev/null) || response=""

    local tag=""
    if [[ -n "$response" ]]; then
        # Extract tag_name
        tag=$(echo "$response" | grep -o '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    fi

    # Stage 2: fallback to /releases (for prerelease-only repos)
    if [[ -z "$tag" ]]; then
        response=$(curl -s --max-time "$UPDATE_CURL_TIMEOUT" \
            -H "Accept: application/vnd.github.v3+json" \
            "${GITHUB_API}/releases?per_page=10" 2>/dev/null) || response=""

        if [[ -n "$response" ]]; then
            # If current version is alpha, prefer alpha tags
            if [[ "$current_version" == *"-alpha."* ]]; then
                tag=$(echo "$response" | grep -o '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*-alpha\.[^"]*"' | head -1 | sed 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
            fi
            # If no alpha match or not alpha, take first tag
            if [[ -z "$tag" ]]; then
                tag=$(echo "$response" | grep -o '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
            fi
        fi
    fi

    if [[ -n "$tag" ]]; then
        # Update cache
        _write_update_cache "$tag" "$current_version"
        echo "$tag"
    fi
    # Empty output on failure (silent fail)
}

# --- Version Comparison ---

compare_versions() {
    local v1="$1"  # installed version
    local v2="$2"  # latest version

    # Strip leading 'v'
    v1="${v1#v}"
    v2="${v2#v}"

    # Split into base and prerelease
    local base1="${v1%%-*}"
    local base2="${v2%%-*}"
    local pre1="" pre2=""

    if [[ "$v1" == *"-"* ]]; then
        pre1="${v1#*-}"
    fi
    if [[ "$v2" == *"-"* ]]; then
        pre2="${v2#*-}"
    fi

    # Compare base version (major.minor.patch)
    local IFS='.'
    read -r maj1 min1 pat1 <<< "$base1"
    read -r maj2 min2 pat2 <<< "$base2"

    maj1=${maj1:-0}; min1=${min1:-0}; pat1=${pat1:-0}
    maj2=${maj2:-0}; min2=${min2:-0}; pat2=${pat2:-0}

    if [[ "$maj1" -lt "$maj2" ]]; then return 0; fi
    if [[ "$maj1" -gt "$maj2" ]]; then return 1; fi
    if [[ "$min1" -lt "$min2" ]]; then return 0; fi
    if [[ "$min1" -gt "$min2" ]]; then return 1; fi
    if [[ "$pat1" -lt "$pat2" ]]; then return 0; fi
    if [[ "$pat1" -gt "$pat2" ]]; then return 1; fi

    # Base versions are equal — compare prerelease
    # No prerelease > any prerelease (stable > alpha)
    if [[ -n "$pre1" && -z "$pre2" ]]; then return 0; fi  # alpha < stable
    if [[ -z "$pre1" && -n "$pre2" ]]; then return 1; fi  # stable > alpha
    if [[ -z "$pre1" && -z "$pre2" ]]; then return 1; fi  # equal

    # Both have prerelease — compare alpha.N
    local num1="${pre1##*.}"
    local num2="${pre2##*.}"

    # Handle non-numeric suffixes
    if [[ "$num1" =~ ^[0-9]+$ && "$num2" =~ ^[0-9]+$ ]]; then
        if [[ "$num1" -lt "$num2" ]]; then return 0; fi
    fi

    return 1  # equal or v1 >= v2
}

# --- Release Notes ---

fetch_release_notes() {
    local tag="$1"

    local response
    response=$(curl -s --max-time "$UPDATE_CURL_TIMEOUT" \
        -H "Accept: application/vnd.github.v3+json" \
        "${GITHUB_API}/releases/tags/${tag}" 2>/dev/null) || response=""

    if [[ -z "$response" ]]; then
        echo "See ${GITHUB_RELEASES_URL}"
        return
    fi

    local body=""

    # Strategy 1: jq (if available)
    if command -v jq &>/dev/null; then
        body=$(echo "$response" | jq -r '.body // empty' 2>/dev/null) || body=""
    fi

    # Strategy 2: sed extraction
    if [[ -z "$body" ]]; then
        body=$(echo "$response" | sed -n 's/.*"body"[[:space:]]*:[[:space:]]*"\(.*\)"/\1/p' | head -1 | sed 's/\\n/\n/g; s/\\r//g; s/\\"/"/g') || body=""
    fi

    # Strategy 3: URL-only fallback
    if [[ -z "$body" ]]; then
        echo "See ${GITHUB_RELEASES_URL}/tag/${tag}"
        return
    fi

    # Truncate if too long
    local line_count
    line_count=$(echo "$body" | wc -l)
    if [[ "$line_count" -gt "$MAX_RELEASE_NOTES_LINES" ]]; then
        echo "$body" | head -n "$MAX_RELEASE_NOTES_LINES"
        echo "[...truncated — see ${GITHUB_RELEASES_URL}/tag/${tag}]"
    else
        echo "$body"
    fi
}

# --- User Prompt ---

show_update_prompt() {
    local current_version="$1"
    local new_version="$2"

    echo ""
    echo "================================================================"
    echo "  New version available: ${current_version} -> ${new_version}"
    echo "================================================================"
    echo ""

    echo "Release notes:"
    echo "---"
    fetch_release_notes "$new_version"
    echo "---"
    echo ""
    echo "Full release: ${GITHUB_RELEASES_URL}/tag/${new_version}"
    echo ""

    # Read from /dev/tty for pipe safety
    local answer=""
    read -r -p "Update now? [y/N] " answer < /dev/tty 2>/dev/null || answer="n"

    case "$answer" in
        [yY]|[yY][eE][sS]) return 0 ;;
        *) return 1 ;;
    esac
}

# --- Backup ---

backup_current_install() {
    local bin_dir="${1:?}"
    local lib_dir="${2:?}"
    local backup_dir="${NYIAKEEPER_HOME:?}/.update-backup"

    # Remove previous backup
    rm -rf "$backup_dir"
    mkdir -p "$backup_dir/bin" "$backup_dir/lib"

    # Backup bin files
    if [[ -d "$bin_dir" ]]; then
        cp -a "$bin_dir"/nyia* "$backup_dir/bin/" 2>/dev/null || true
        [[ -f "$bin_dir/assistant-template.sh" ]] && cp -a "$bin_dir/assistant-template.sh" "$backup_dir/bin/"
        [[ -f "$bin_dir/common-functions.sh" ]] && cp -a "$bin_dir/common-functions.sh" "$backup_dir/bin/"
        [[ -d "$bin_dir/common" ]] && cp -a "$bin_dir/common" "$backup_dir/bin/"
    fi

    # Backup lib files
    if [[ -d "$lib_dir" ]]; then
        cp -a "$lib_dir"/* "$backup_dir/lib/" 2>/dev/null || true
    fi

    # Save current version
    local current_version
    current_version=$(get_installed_version 2>/dev/null) || current_version="unknown"
    echo "$current_version" > "$backup_dir/VERSION"
}

# --- Checksum Verification ---

_verify_checksum() {
    local tarball="$1"
    local checksum_file="$2"

    if [[ ! -f "$checksum_file" ]]; then
        echo "Warning: No checksum file available. Skipping verification." >&2
        return 0
    fi

    local expected_hash
    expected_hash=$(awk '{print $1}' "$checksum_file")
    local actual_hash

    if command -v sha256sum &>/dev/null; then
        actual_hash=$(sha256sum "$tarball" | awk '{print $1}')
    elif command -v shasum &>/dev/null; then
        actual_hash=$(shasum -a 256 "$tarball" | awk '{print $1}')
    else
        echo "Warning: No sha256sum or shasum available. Skipping verification." >&2
        return 0
    fi

    if [[ "$expected_hash" != "$actual_hash" ]]; then
        echo "Error: Checksum verification failed!" >&2
        echo "  Expected: $expected_hash" >&2
        echo "  Got:      $actual_hash" >&2
        return 1
    fi

    return 0
}

# --- Update ---

perform_update() {
    local target_tag="${1:-}"

    if ! acquire_update_lock; then
        echo "Another update is in progress. Please try again later." >&2
        return 1
    fi

    # Determine target version
    if [[ -z "$target_tag" ]]; then
        local current
        current=$(get_installed_version 2>/dev/null) || current=""
        target_tag=$(fetch_latest_version "$current")
        if [[ -z "$target_tag" ]]; then
            echo "Error: Could not determine latest version." >&2
            release_update_lock
            return 1
        fi
    fi

    # Determine install directories
    local bin_dir lib_dir
    bin_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../bin" 2>/dev/null && pwd)" || bin_dir="$HOME/.local/bin"
    lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib/nyiakeeper" 2>/dev/null && pwd)" || lib_dir="$HOME/.local/lib/nyiakeeper"

    # Fallback: use parent of common-functions.sh location
    if [[ ! -d "$bin_dir" ]]; then
        bin_dir="$HOME/.local/bin"
    fi
    if [[ ! -d "$lib_dir" ]]; then
        lib_dir="$HOME/.local/lib/nyiakeeper"
    fi

    local tmp_dir="${TMPDIR:-/tmp}/nyia-update-$$"
    local staging_dir="${TMPDIR:-/tmp}/nyia-staging-$$"
    local tarball_url="${GITHUB_RELEASES_URL}/download/${target_tag}/nyiakeeper-runtime.tar.gz"
    local checksum_url="${GITHUB_RELEASES_URL}/download/${target_tag}/nyiakeeper-runtime.tar.gz.sha256"

    # Cleanup function
    _update_cleanup() {
        rm -rf "$tmp_dir" "$staging_dir"
    }

    mkdir -p "$tmp_dir" "$staging_dir"

    echo "Downloading ${target_tag}..."

    # Download tarball
    if ! curl -sL --max-time 60 -o "$tmp_dir/nyiakeeper-runtime.tar.gz" "$tarball_url"; then
        echo "Error: Failed to download tarball from $tarball_url" >&2
        _update_cleanup
        release_update_lock
        return 1
    fi

    # Download checksum (best-effort — warn if unavailable)
    if ! curl -sL --max-time 10 -o "$tmp_dir/nyiakeeper-runtime.tar.gz.sha256" "$checksum_url" 2>/dev/null; then
        echo "Warning: Could not download checksum file. Skipping integrity verification." >&2
    fi

    # Verify checksum
    if ! _verify_checksum "$tmp_dir/nyiakeeper-runtime.tar.gz" "$tmp_dir/nyiakeeper-runtime.tar.gz.sha256"; then
        echo "Error: Checksum verification failed. Aborting update." >&2
        _update_cleanup
        release_update_lock
        return 1
    fi

    echo "Extracting..."

    # Extract to staging
    if ! tar -xzf "$tmp_dir/nyiakeeper-runtime.tar.gz" -C "$staging_dir"; then
        echo "Error: Failed to extract tarball." >&2
        _update_cleanup
        release_update_lock
        return 1
    fi

    # Backup current install
    echo "Backing up current installation..."
    backup_current_install "$bin_dir" "$lib_dir"

    # Staged swap with .old recovery
    echo "Installing ${target_tag}..."
    local swap_failed=false

    # Swap bin/
    if [[ -d "$staging_dir/bin" ]]; then
        if mv "$bin_dir" "${bin_dir}.old" 2>/dev/null; then
            if ! mv "$staging_dir/bin" "$bin_dir" 2>/dev/null; then
                # Restore bin
                mv "${bin_dir}.old" "$bin_dir" 2>/dev/null
                swap_failed=true
            fi
        else
            swap_failed=true
        fi
    fi

    # Swap lib/
    if [[ "$swap_failed" != "true" && -d "$staging_dir/lib" ]]; then
        if mv "$lib_dir" "${lib_dir}.old" 2>/dev/null; then
            if ! mv "$staging_dir/lib/nyiakeeper" "$lib_dir" 2>/dev/null && \
               ! mv "$staging_dir/lib" "$lib_dir" 2>/dev/null; then
                # Restore lib and bin
                mv "${lib_dir}.old" "$lib_dir" 2>/dev/null
                rm -rf "$bin_dir"
                mv "${bin_dir}.old" "$bin_dir" 2>/dev/null
                swap_failed=true
            fi
        else
            swap_failed=true
        fi
    fi

    if [[ "$swap_failed" == "true" ]]; then
        echo "Error: Failed to install new version. Restoring from backup..." >&2
        _restore_from_backup "$bin_dir" "$lib_dir"
        _update_cleanup
        release_update_lock
        return 1
    fi

    # Clean up .old dirs
    rm -rf "${bin_dir}.old" "${lib_dir}.old"

    # Run setup.sh if present in staging (handles path patching etc.)
    # Must cd into staging because setup.sh uses relative bin/ and lib/ paths
    if [[ -f "$staging_dir/setup.sh" ]]; then
        (cd "$staging_dir" && bash ./setup.sh) 2>/dev/null || true
    fi

    # Verify version
    local new_version
    new_version=$(get_installed_version 2>/dev/null) || new_version=""
    if [[ -n "$new_version" ]]; then
        echo "Successfully updated to ${new_version}"
    else
        echo "Update installed. Please restart your terminal."
    fi

    _update_cleanup
    rm -rf "${bin_dir}.old" "${lib_dir}.old"
    release_update_lock
    return 0
}

_restore_from_backup() {
    local bin_dir="$1"
    local lib_dir="$2"
    local backup_dir="${NYIAKEEPER_HOME:?}/.update-backup"
    local restore_failed=false

    if [[ ! -d "$backup_dir" ]]; then
        echo "Error: No backup found to restore from." >&2
        return 1
    fi

    # Restore bin
    if [[ -d "$backup_dir/bin" ]]; then
        rm -rf "$bin_dir"
        mkdir -p "$bin_dir"
        if ! cp -a "$backup_dir/bin"/* "$bin_dir/" 2>/dev/null; then
            echo "Error: Failed to restore bin/ from backup." >&2
            restore_failed=true
        fi
    fi

    # Restore lib
    if [[ -d "$backup_dir/lib" ]]; then
        rm -rf "$lib_dir"
        mkdir -p "$lib_dir"
        if ! cp -a "$backup_dir/lib"/* "$lib_dir/" 2>/dev/null; then
            echo "Error: Failed to restore lib/ from backup." >&2
            restore_failed=true
        fi
    fi

    # Restore version
    if [[ -f "$backup_dir/VERSION" ]]; then
        local backup_version
        backup_version=$(cat "$backup_dir/VERSION")
        set_installed_version "$backup_version" 2>/dev/null || true
    fi

    if [[ "$restore_failed" == "true" ]]; then
        return 1
    fi
}

# --- Rollback ---

perform_rollback() {
    if ! acquire_update_lock; then
        echo "Another update is in progress. Please try again later." >&2
        return 1
    fi

    local backup_dir="${NYIAKEEPER_HOME:?}/.update-backup"

    if [[ ! -d "$backup_dir" ]]; then
        echo "No backup found. Cannot rollback." >&2
        echo "Rollback is only available after a successful update." >&2
        release_update_lock
        return 1
    fi

    local backup_version="unknown"
    if [[ -f "$backup_dir/VERSION" ]]; then
        backup_version=$(cat "$backup_dir/VERSION")
    fi

    local current_version
    current_version=$(get_installed_version 2>/dev/null) || current_version="unknown"

    echo ""
    echo "Rollback: ${current_version} -> ${backup_version}"
    echo ""

    local answer=""
    read -r -p "Rollback to ${backup_version}? [y/N] " answer < /dev/tty 2>/dev/null || answer="n"

    case "$answer" in
        [yY]|[yY][eE][sS]) ;;
        *)
            echo "Rollback cancelled."
            release_update_lock
            return 0
            ;;
    esac

    local bin_dir lib_dir
    bin_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../bin" 2>/dev/null && pwd)" || bin_dir="$HOME/.local/bin"
    lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib/nyiakeeper" 2>/dev/null && pwd)" || lib_dir="$HOME/.local/lib/nyiakeeper"

    echo "Restoring ${backup_version}..."
    if _restore_from_backup "$bin_dir" "$lib_dir"; then
        echo "Successfully rolled back to ${backup_version}"
        release_update_lock
        return 0
    else
        echo "Error: Rollback encountered errors. Installation may be in an inconsistent state." >&2
        echo "Backup files are preserved at: $backup_dir" >&2
        release_update_lock
        return 1
    fi
}

# --- Main Entry Point ---

check_for_updates_if_due() {
    # Guard: VERSION file must exist
    local version_file="${NYIAKEEPER_HOME:-}/VERSION"
    if [[ -z "${NYIAKEEPER_HOME:-}" ]] || [[ ! -f "$version_file" ]]; then
        return 0
    fi

    # Guard: must be a TTY
    if [[ ! -t 0 ]] && [[ ! -t 1 ]]; then
        return 0
    fi

    # Guard: throttle
    if ! is_update_check_due; then
        return 0
    fi

    if ! acquire_update_lock; then
        return 0
    fi

    local current_version
    current_version=$(get_installed_version 2>/dev/null) || {
        release_update_lock
        return 0
    }

    echo "Checking for new version..." >&2

    local latest_version
    latest_version=$(fetch_latest_version "$current_version")

    if [[ -z "$latest_version" ]]; then
        release_update_lock
        return 0
    fi

    # Compare
    if compare_versions "$current_version" "$latest_version"; then
        if show_update_prompt "$current_version" "$latest_version"; then
            perform_update "$latest_version"
        else
            echo "Update skipped. Run 'nyia update' to update later."
        fi
    fi

    release_update_lock
    return 0
}
