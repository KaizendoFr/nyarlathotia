#!/bin/bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR Proprietary
# Copyright (c) 2024 NyarlathotIA Contributors
# Exclusions subcommand implementations for nyia
# Provides commands for managing mount exclusions

# Source shared cache utilities first
if ! declare -f is_exclusions_cache_valid >/dev/null 2>&1; then
    source "$(dirname "${BASH_SOURCE[0]}")/exclusions-cache-utils.sh" 2>/dev/null || true
fi

# Ensure mount-exclusions library is loaded
if ! declare -f get_exclusion_patterns >/dev/null 2>&1; then
    source "$(dirname "${BASH_SOURCE[0]}")/mount-exclusions.sh" 2>/dev/null || {
        echo "❌ Error: Could not load mount-exclusions library" >&2
        exit 1
    }
fi

# Platform-aware case sensitivity for file matching  
get_find_case_args() {
    # On macOS with case-insensitive filesystem, use case-insensitive matching
    if [[ "$(uname -s)" == "Darwin" ]]; then
        echo "-iname"
    else
        # Linux filesystems are typically case-sensitive
        echo "-name" 
    fi
}

# Color functions if not already defined
if ! declare -f print_header >/dev/null 2>&1; then
    print_header() { echo -e "\e[1m$1\e[0m"; }
    print_success() { echo -e "\e[32m✅ $1\e[0m"; }
    print_error() { echo -e "\e[31m❌ $1\e[0m"; }
    print_info() { echo -e "\e[37m📍 $1\e[0m"; }
fi

# Get project path with validation
get_project_path() {
    local path="${1:-$(pwd)}"
    [[ -d "$path" ]] || { echo "❌ Directory not found: $path" >&2; exit 1; }
    realpath "$path"
}

# === CACHE MANAGEMENT FUNCTIONS ===


# Read cached exclusion lists
read_cached_exclusions() {
    local project_path="$1"
    local cache_file="$project_path/.nyarlathotia/.excluded-files.cache"
    
    # Initialize arrays
    CACHED_EXCLUDED_FILES=()
    CACHED_EXCLUDED_DIRS=()
    CACHED_SYSTEM_FILES=()
    CACHED_SYSTEM_DIRS=()
    
    # Read cache file
    if [[ -f "$cache_file" ]]; then
        while IFS='=' read -r key value; do
            case "$key" in
                excluded_files)
                    IFS=',' read -ra CACHED_EXCLUDED_FILES <<< "$value"
                    ;;
                excluded_dirs)
                    IFS=',' read -ra CACHED_EXCLUDED_DIRS <<< "$value"
                    ;;
                system_files)
                    IFS=',' read -ra CACHED_SYSTEM_FILES <<< "$value"
                    ;;
                system_dirs)
                    IFS=',' read -ra CACHED_SYSTEM_DIRS <<< "$value"
                    ;;
            esac
        done < "$cache_file"
        return 0
    fi
    return 1
}


# List excluded files and directories
exclusions_list() {
    local project_path
    project_path=$(get_project_path "$1")
    
    print_header "📋 Files excluded in: $project_path"
    echo "============================================="
    
    if [[ "$ENABLE_MOUNT_EXCLUSIONS" != "true" ]]; then
        print_info "Exclusions disabled - no files would be excluded"
        return 0
    fi
    
    # Use associative arrays to track unique matches
    declare -A excluded_files
    declare -A excluded_dirs
    declare -A system_files
    declare -A system_dirs
    
    # Check if cache is valid and use it
    if is_exclusions_cache_valid "$project_path"; then
        # Read from cache
        if read_cached_exclusions "$project_path"; then
            # Populate associative arrays from cache
            for file in "${CACHED_EXCLUDED_FILES[@]}"; do
                [[ -n "$file" ]] && excluded_files["$file"]=1
            done
            for dir in "${CACHED_EXCLUDED_DIRS[@]}"; do
                [[ -n "$dir" ]] && excluded_dirs["$dir"]=1
            done
            for file in "${CACHED_SYSTEM_FILES[@]}"; do
                [[ -n "$file" ]] && system_files["$file"]=1
            done
            for dir in "${CACHED_SYSTEM_DIRS[@]}"; do
                [[ -n "$dir" ]] && system_dirs["$dir"]=1
            done
        fi
    else
        # Cache invalid or doesn't exist - scan filesystem
        
        # Source mount-exclusions to get is_nyarlathotia_system_path function
        if declare -f is_nyarlathotia_system_path >/dev/null 2>&1; then
            : # Function already available
        elif [[ -f "$(dirname "${BASH_SOURCE[0]}")/mount-exclusions.sh" ]]; then
            source "$(dirname "${BASH_SOURCE[0]}")/mount-exclusions.sh"
        fi
        
        # Use find for recursive pattern matching
        local max_depth="${EXCLUSION_MAX_DEPTH:-5}"
        
        # Arrays for building cache
        SCAN_EXCLUDED_FILES=()
        SCAN_EXCLUDED_DIRS=()
        SCAN_SYSTEM_FILES=()
        SCAN_SYSTEM_DIRS=()
        
        # Process file patterns using find
        while IFS=' ' read -r pattern; do
            while IFS= read -r -d '' match; do
                local rel_path="${match#$project_path/}"
                
                # Check if this is a NyarlathotIA system file
                if declare -f is_nyarlathotia_system_path >/dev/null 2>&1 && is_nyarlathotia_system_path "$rel_path" "$project_path"; then
                    system_files["$rel_path"]=1
                    SCAN_SYSTEM_FILES+=("$rel_path")
                else
                    excluded_files["$rel_path"]=1
                    SCAN_EXCLUDED_FILES+=("$rel_path")
                fi
            done < <(find "$project_path" -maxdepth "$max_depth" -type f $(get_find_case_args) "$pattern" -print0 2>/dev/null)
        done < <(get_exclusion_patterns "$project_path" | tr ' ' '\n')
        
        # Process directory patterns using find
        while IFS=' ' read -r pattern; do
            while IFS= read -r -d '' match; do
                local rel_path="${match#$project_path/}"
                
                # Check if this is a NyarlathotIA system directory
                if declare -f is_nyarlathotia_system_path >/dev/null 2>&1 && is_nyarlathotia_system_path "$rel_path" "$project_path"; then
                    system_dirs["$rel_path"]=1
                    SCAN_SYSTEM_DIRS+=("$rel_path")
                else
                    excluded_dirs["$rel_path"]=1
                    SCAN_EXCLUDED_DIRS+=("$rel_path")
                fi
            done < <(find "$project_path" -maxdepth "$max_depth" -type d $(get_find_case_args) "$pattern" -print0 2>/dev/null)
        done < <(get_exclusion_dirs "$project_path" | tr ' ' '\n')
        
        # Write results to cache for next time
        write_exclusions_cache "$project_path"
    fi
    
    # Display results
    echo "Files that will be excluded:"
    if [[ ${#excluded_files[@]} -eq 0 ]]; then
        echo "  (none found)"
    else
        for file in "${!excluded_files[@]}"; do
            echo "  🔒 $file"
        done | sort
    fi
    
    echo ""
    echo "Directories that will be excluded:"
    if [[ ${#excluded_dirs[@]} -eq 0 ]]; then
        echo "  (none found)"
    else
        for dir in "${!excluded_dirs[@]}"; do
            echo "  📁 $dir/"
        done | sort
    fi
    
    # Show NyarlathotIA system files if any (not excluded)
    if [[ ${#system_files[@]} -gt 0 || ${#system_dirs[@]} -gt 0 ]]; then
        echo ""
        echo "NyarlathotIA system files (NOT excluded - needed for operation):"
        if [[ ${#system_files[@]} -gt 0 ]]; then
            for file in "${!system_files[@]}"; do
                echo "  ✅ $file"
            done | sort
        fi
        if [[ ${#system_dirs[@]} -gt 0 ]]; then
            for dir in "${!system_dirs[@]}"; do
                echo "  ✅ $dir/"
            done | sort
        fi
    fi
    
    # Summary
    local total_excluded=$((${#excluded_files[@]} + ${#excluded_dirs[@]}))
    local total_system=$((${#system_files[@]} + ${#system_dirs[@]}))
    echo ""
    if [[ $total_excluded -eq 0 && $total_system -eq 0 ]]; then
        print_info "No sensitive files/directories found in this project"
    else
        print_info "Excluded: ${#excluded_files[@]} files, ${#excluded_dirs[@]} directories"
        if [[ $total_system -gt 0 ]]; then
            print_info "Protected NyarlathotIA system: ${#system_files[@]} files, ${#system_dirs[@]} directories"
        fi
    fi
}

# Test exclusions and show Docker volume arguments
exclusions_test() {
    local project_path
    project_path=$(get_project_path "$1")
    
    print_header "🧪 Testing exclusions for: $project_path"
    echo "=============================================="
    
    if [[ "$ENABLE_MOUNT_EXCLUSIONS" != "true" ]]; then
        print_info "Exclusions disabled - all files would be mounted normally"
        echo ""
        echo "Would use simple mount:"
        echo "  -v $project_path:/workspace:rw"
        return 0
    fi
    
    # Show what would happen
    echo "Docker volume arguments that would be generated:"
    echo ""
    
    # Create volume args to test
    create_volume_args "$project_path" "/workspace"
    
    if [[ ${#VOLUME_ARGS[@]} -gt 0 ]]; then
        local i=0
        while [[ $i -lt ${#VOLUME_ARGS[@]} ]]; do
            if [[ "${VOLUME_ARGS[$i]}" == "-v" ]]; then
                local mount_arg="${VOLUME_ARGS[$((i+1))]}"
                if [[ "$mount_arg" == *"/tmp/nyia-excluded-"* ]]; then
                    echo "  -v $mount_arg  # 🔒 EXCLUDED"
                else
                    echo "  -v $mount_arg"
                fi
                ((i+=2))
            else
                echo "  ${VOLUME_ARGS[$i]}"
                ((i++))
            fi
        done
    else
        echo "  No volume arguments generated"
    fi
    
    echo ""
    print_success "Test complete - sensitive files would be replaced with explanations"
}

# Show exclusions status
exclusions_status() {
    local project_path
    project_path=$(get_project_path "$1")
    
    print_header "🔍 Mount Exclusions Status"
    echo "=========================="
    echo ""
    echo "Global Settings:"
    echo "  Feature enabled: ${ENABLE_MOUNT_EXCLUSIONS:-true}"
    echo "  Config file: ${NYARLATHOTIA_HOME:-~/.nyarlathotia}/config/mount-exclusions.conf"
    echo ""
    
    echo "Current Status:"
    if [[ "$ENABLE_MOUNT_EXCLUSIONS" != "true" ]]; then
        echo "  🔴 DISABLED - No files will be excluded"
    else
        echo "  🟢 ENABLED - Sensitive files will be excluded"
    fi
    echo ""
    
    echo "Project Path: $project_path"
    local project_exclusions="$project_path/.nyarlathotia/exclusions.conf"
    if [[ -f "$project_exclusions" ]]; then
        echo "  📄 Has project-specific exclusions: $project_exclusions"
    else
        echo "  📍 Using global exclusion patterns only"
    fi
    echo ""
    
    echo "To disable temporarily:"
    echo "  ENABLE_MOUNT_EXCLUSIONS=false nyia-claude \"your prompt\""
    echo "  Or use: nyia-claude --disable-exclusions \"your prompt\""
}

# Show all exclusion patterns
exclusions_patterns() {
    print_header "🔍 Hardcoded Exclusion Patterns"
    echo "==============================="
    echo ""
    echo "File patterns:"
    echo "$(get_exclusion_patterns)" | tr ' ' '\n' | sort | sed 's/^/  • /'
    echo ""
    echo "Directory patterns:"
    echo "$(get_exclusion_dirs)" | tr ' ' '\n' | sort | sed 's/^/  • /'
    echo ""
    print_info "These patterns are hardcoded for security"
    print_info "To modify: edit lib/mount-exclusions.sh functions"
    print_info "To override: use .nyarlathotia/exclusions.conf with ! prefix"
}

# Initialize project-specific exclusions config
exclusions_init() {
    local project_path=""
    local force_mode="false"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force)
                force_mode="true"
                shift
                ;;
            *)
                if [[ -z "$project_path" ]]; then
                    project_path="$1"
                fi
                shift
                ;;
        esac
    done
    
    # Get validated project path
    project_path=$(get_project_path "$project_path")
    local nyia_dir="$project_path/.nyarlathotia"
    local exclusions_file="$nyia_dir/exclusions.conf"
    
    # If file exists and not forcing, show status (Git/Terraform style)
    if [[ -f "$exclusions_file" ]] && [[ "$force_mode" != "true" ]]; then
        print_info "Exclusions already initialized"
        echo "Current config: .nyarlathotia/exclusions.conf"
        
        # Count user-defined patterns
        local user_pattern_count=$(grep -v '^#' "$exclusions_file" 2>/dev/null | grep -v '^[[:space:]]*$' | wc -l)
        echo "User-defined patterns: $user_pattern_count"
        
        # Show actual exclusion effectiveness with quick scan and change detection
        echo ""
        echo "Current exclusion status:"
        
        local excluded_files=0
        local excluded_dirs=0
        
        # Use cached results from complete scan if available (most accurate)
        local main_cache_file="$nyia_dir/.excluded-files.cache"
        if [[ -f "$main_cache_file" ]]; then
            # Read from main cache written by complete scan
            while IFS='=' read -r key value; do
                case "$key" in
                    excluded_files)
                        # Count comma-separated entries
                        if [[ -n "$value" ]]; then
                            excluded_files=$(echo "$value" | tr ',' '\n' | grep -c '^.')
                        fi
                        ;;
                    excluded_dirs)
                        # Count comma-separated entries
                        if [[ -n "$value" ]]; then
                            excluded_dirs=$(echo "$value" | tr ',' '\n' | grep -c '^.')
                        fi
                        ;;
                esac
            done < "$main_cache_file"
        else
            # Fallback: quick scan for most common patterns only (cache not available)
            local max_depth=3
            local common_patterns=(".env" "*.key" "*.pem" "credentials.*" "*.tfstate" "*.tfvars")
            for pattern in "${common_patterns[@]}"; do
                local count=$(find "$project_path" -maxdepth "$max_depth" -type f $(get_find_case_args) "$pattern" 2>/dev/null | wc -l)
                excluded_files=$((excluded_files + count))
            done
            
            local common_dirs=(".aws" ".ssh" ".terraform" "secrets")
            for pattern in "${common_dirs[@]}"; do
                local count=$(find "$project_path" -maxdepth "$max_depth" -type d $(get_find_case_args) "$pattern" 2>/dev/null | wc -l)
                excluded_dirs=$((excluded_dirs + count))
            done
        fi
        
        # Read cached counts from previous scan
        local cache_file="$nyia_dir/.exclusions-cache"
        local cached_files=0
        local cached_dirs=0
        if [[ -f "$cache_file" ]]; then
            while IFS='=' read -r key value; do
                case "$key" in
                    files) cached_files="$value" ;;
                    dirs) cached_dirs="$value" ;;
                esac
            done < "$cache_file"
        fi
        
        if [[ $excluded_files -gt 0 || $excluded_dirs -gt 0 ]]; then
            print_success "Currently protecting $excluded_files+ sensitive files, $excluded_dirs+ directories"
        else
            print_info "No common sensitive files detected - your project looks secure!"
            echo "System actively scans for 200+ sensitive file patterns"
        fi
        
        # Show changes since last scan
        local files_delta=$((excluded_files - cached_files))
        local dirs_delta=$((excluded_dirs - cached_dirs))
        
        if [[ $files_delta -gt 0 || $dirs_delta -gt 0 ]]; then
            local change_msg=""
            if [[ $files_delta -gt 0 && $dirs_delta -gt 0 ]]; then
                change_msg="Detected $files_delta new files, $dirs_delta new directories since last scan"
            elif [[ $files_delta -gt 0 ]]; then
                if [[ $files_delta -eq 1 ]]; then
                    change_msg="Detected 1 new sensitive file since last scan"
                else
                    change_msg="Detected $files_delta new sensitive files since last scan"
                fi
            elif [[ $dirs_delta -gt 0 ]]; then
                if [[ $dirs_delta -eq 1 ]]; then
                    change_msg="Detected 1 new sensitive directory since last scan"
                else
                    change_msg="Detected $dirs_delta new sensitive directories since last scan"
                fi
            fi
            echo "$change_msg"
        elif [[ $files_delta -lt 0 || $dirs_delta -lt 0 ]]; then
            local removed_files=$((cached_files - excluded_files))
            local removed_dirs=$((cached_dirs - excluded_dirs))
            if [[ $removed_files -gt 0 || $removed_dirs -gt 0 ]]; then
                local removed_msg=""
                if [[ $removed_files -gt 0 && $removed_dirs -gt 0 ]]; then
                    removed_msg="$removed_files files, $removed_dirs directories were removed since last scan"
                elif [[ $removed_files -gt 0 ]]; then
                    if [[ $removed_files -eq 1 ]]; then
                        removed_msg="1 sensitive file was removed since last scan"
                    else
                        removed_msg="$removed_files sensitive files were removed since last scan"
                    fi
                elif [[ $removed_dirs -gt 0 ]]; then
                    if [[ $removed_dirs -eq 1 ]]; then
                        removed_msg="1 sensitive directory was removed since last scan"
                    else
                        removed_msg="$removed_dirs sensitive directories were removed since last scan"
                    fi
                fi
                echo "$removed_msg"
            fi
        elif [[ $cached_files -gt 0 || $cached_dirs -gt 0 ]]; then
            echo "No changes since last scan"
        fi
        
        # Update cache with current counts
        cat > "$cache_file" << EOF
files=$excluded_files
dirs=$excluded_dirs
timestamp=$(date +%s)
EOF
        
        echo ""
        echo "Use 'nyia exclusions init --force' to recreate with fresh template"
        echo "Use 'nyia exclusions list' to see all protected files"
        return 0
    fi
    
    # If forcing and file exists, backup first and capture current state
    local old_excluded_files=0
    local old_excluded_dirs=0
    if [[ -f "$exclusions_file" ]] && [[ "$force_mode" == "true" ]]; then
        # Capture current protection state before backup
        local max_depth=3
        local common_patterns=(".env" "*.key" "*.pem" "credentials.*" "*.tfstate" "*.tfvars")
        for pattern in "${common_patterns[@]}"; do
            local count=$(find "$project_path" -maxdepth "$max_depth" -type f -name "$pattern" 2>/dev/null | wc -l)
            old_excluded_files=$((old_excluded_files + count))
        done
        
        local common_dirs=(".aws" ".ssh" ".terraform" "secrets")
        for pattern in "${common_dirs[@]}"; do
            local count=$(find "$project_path" -maxdepth "$max_depth" -type d -name "$pattern" 2>/dev/null | wc -l)
            old_excluded_dirs=$((old_excluded_dirs + count))
        done
        
        local backup_file="${exclusions_file}.backup"
        cp "$exclusions_file" "$backup_file"
        print_info "⚠️  Backing up existing config to $(basename "$backup_file")"
    fi
    
    print_header "🚀 Initializing project exclusions"
    echo "=================================="
    echo "Project: $project_path"
    echo ""
    
    # Create .nyarlathotia directory if needed
    if [[ ! -d "$nyia_dir" ]]; then
        mkdir -p "$nyia_dir"
        print_success "Created .nyarlathotia directory"
    fi
    
    # Create exclusions.conf (always if forcing or doesn't exist)
    if [[ ! -f "$exclusions_file" ]] || [[ "$force_mode" == "true" ]]; then
        cat > "$exclusions_file" << 'EOF'
# NyarlathotIA Mount Exclusions Configuration
# Project-specific patterns to exclude from Docker mounts
#
# Patterns support glob syntax: * ? []
# Paths are relative to project root
#
# Examples:
# .env.local              # Exclude specific file
# secrets/                # Exclude entire directory
# *.backup                # Exclude by extension
# internal-docs/**/*.md   # Exclude nested files
#
# Override global exclusions with ! prefix:
# !.env.example          # Force include this file
# !docs/security.md      # Force include even if docs/ excluded
#
# Note: Global security patterns are always applied first
# This file adds additional project-specific exclusions

# Your project-specific exclusions:

EOF
        if [[ "$force_mode" == "true" ]]; then
            print_success "Created fresh exclusions config: .nyarlathotia/exclusions.conf"
        else
            print_success "Created exclusions config: .nyarlathotia/exclusions.conf"
        fi
        
        # Show immediate value - use cached results from complete scan
        echo ""
        echo "Scanning project for sensitive files..."
        
        local excluded_files=0
        local excluded_dirs=0
        
        # Use cached results from the complete scan (most accurate)
        local main_cache_file="$nyia_dir/.excluded-files.cache"
        if [[ -f "$main_cache_file" ]]; then
            # Read from main cache written by complete scan
            while IFS='=' read -r key value; do
                case "$key" in
                    excluded_files)
                        # Count comma-separated entries
                        if [[ -n "$value" ]]; then
                            excluded_files=$(echo "$value" | tr ',' '\n' | grep -c '^.')
                        fi
                        ;;
                    excluded_dirs)
                        # Count comma-separated entries
                        if [[ -n "$value" ]]; then
                            excluded_dirs=$(echo "$value" | tr ',' '\n' | grep -c '^.')
                        fi
                        ;;
                esac
            done < "$main_cache_file"
        else
            # Fallback: quick scan for most common patterns only (cache not available)
            local max_depth=3
            local common_patterns=(".env" "*.key" "*.pem" "credentials.*" "*.tfstate" "*.tfvars")
            for pattern in "${common_patterns[@]}"; do
                local count=$(find "$project_path" -maxdepth "$max_depth" -type f $(get_find_case_args) "$pattern" 2>/dev/null | wc -l)
                excluded_files=$((excluded_files + count))
            done
            
            local common_dirs=(".aws" ".ssh" ".terraform" "secrets")
            for pattern in "${common_dirs[@]}"; do
                local count=$(find "$project_path" -maxdepth "$max_depth" -type d $(get_find_case_args) "$pattern" 2>/dev/null | wc -l)
                excluded_dirs=$((excluded_dirs + count))
            done
        fi
        
        # Calculate and show the delta for what was added
        local added_files=$((excluded_files - old_excluded_files))
        local added_dirs=$((excluded_dirs - old_excluded_dirs))
        
        if [[ $excluded_files -gt 0 || $excluded_dirs -gt 0 ]]; then
            print_success "🛡️  Now protecting $excluded_files+ sensitive files, $excluded_dirs+ directories"
            echo "Run 'nyia exclusions list' to see all protected files"
        else
            print_info "No common sensitive files detected - your project looks secure!"
            echo "The system protects against 200+ sensitive file patterns automatically"
        fi
        
        # Show what was added (delta) - only for first-time init, not --force
        if [[ "$force_mode" != "true" ]]; then
            if [[ $added_files -gt 0 || $added_dirs -gt 0 ]]; then
                local added_msg=""
                if [[ $added_files -gt 0 && $added_dirs -gt 0 ]]; then
                    added_msg="Added $added_files files, $added_dirs directories to protection"
                elif [[ $added_files -gt 0 ]]; then
                    if [[ $added_files -eq 1 ]]; then
                        added_msg="Added 1 file to protection"
                    else
                        added_msg="Added $added_files files to protection"
                    fi
                elif [[ $added_dirs -gt 0 ]]; then
                    if [[ $added_dirs -eq 1 ]]; then
                        added_msg="Added 1 directory to protection"
                    else
                        added_msg="Added $added_dirs directories to protection"
                    fi
                fi
                echo "$added_msg"
            fi
        fi
        
        # Update simple cache with current counts for future change detection
        local simple_cache_file="$nyia_dir/.exclusions-cache"
        cat > "$simple_cache_file" << EOF
files=$excluded_files
dirs=$excluded_dirs
timestamp=$(date +%s)
EOF
        
        echo ""
        echo "Next steps:"
        echo "  1. Run 'nyia exclusions list' to see all protected files"
        echo "  2. Edit .nyarlathotia/exclusions.conf to add project-specific patterns"
        echo "  3. Run 'nyia exclusions test' to verify exclusions work"
    fi
}

# Show help for exclusions commands
exclusions_help() {
    cat << 'EOF'
NyarlathotIA Mount Exclusions Management

Security feature that prevents sensitive files from being exposed to AI assistants
by replacing them with explanation files in Docker containers.

Usage:
  nyia exclusions <command> [path]           # Specify path as command argument
  nyia --path <path> exclusions <command>    # Specify path as global option

Commands:
  list [path]         Show files/dirs that would be excluded
  test [path]         Test exclusions and show Docker mounts
  status [path]       Show if exclusions are enabled/disabled for project
  patterns            Show all exclusion patterns (global)
  init [path] [opts]  Initialize project exclusions config
  help                Show this help message

Path Options (two ways):
  [path]              Project path as command argument (defaults to current directory)
  --path <path>       Project path as global option (works before 'exclusions')
  --force             For init: recreate config from fresh template

Examples:
  # Using current directory:
  nyia exclusions list              # List excluded files in current dir
  nyia exclusions status            # Check current project status
  
  # Method 1 - Path as argument:
  nyia exclusions test ~/project    # Test exclusions for a project
  nyia exclusions init ~/project    # Initialize specific project
  
  # Method 2 - Path as global option:
  nyia --path ~/project exclusions list      # List files in project
  nyia --path ~/project exclusions status    # Check project status
  nyia --path ~/project exclusions init      # Initialize project

Note: Exclusions are auto-initialized on first nyia run in a project

To disable exclusions temporarily:
  ENABLE_MOUNT_EXCLUSIONS=false nyia-claude "your prompt"
  Or use: nyia-claude --disable-exclusions "your prompt"

To disable globally:
  Edit ~/.nyarlathotia/config/mount-exclusions.conf
  Set: ENABLE_MOUNT_EXCLUSIONS=false

EOF
}