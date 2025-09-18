#!/bin/bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR Proprietary
# Copyright (c) 2024 NyarlathotIA Contributors
#
# bash32-compat.sh - Bash 3.2+ compatibility layer for macOS
# Provides compatibility functions for bash 4.0+ features
# Works on macOS default bash 3.2.57 and modern Linux bash

# === Version Detection ===

# Get bash major version
bash_version_major() {
    echo "${BASH_VERSINFO[0]}"
}

# Get bash minor version
bash_version_minor() {
    echo "${BASH_VERSINFO[1]}"
}

# Check if we need compatibility mode (bash < 4.0)
needs_compat() {
    [[ $(bash_version_major) -lt 4 ]]
}

# === Associative Array Emulation ===
# Uses name-prefixed variables to simulate associative arrays
# This provides bash 3.2 compatibility for declare -A functionality

# Initialize an associative array
# Usage: ba_init array_name
ba_init() {
    local array_name="$1"
    eval "_ba_${array_name}_keys=''"
}

# Set a key-value pair in emulated associative array
# Usage: ba_set array_name key value
ba_set() {
    local array_name="$1" key="$2" value="$3"
    # Escape the key to be shell-safe (replace non-alphanumeric with _)
    local safe_key="${key//[^a-zA-Z0-9_]/_}"
    
    # Track the key if new (check before setting)
    local keys_var="_ba_${array_name}_keys"
    local existing_keys
    eval "existing_keys=\"\${$keys_var}\""
    if [[ " $existing_keys " != *" $key "* ]]; then
        eval "$keys_var=\"\${$keys_var} \$key\""
    fi
    
    # Store the value
    eval "_ba_${array_name}_${safe_key}=\$value"
}

# Get a value by key from emulated associative array
# Usage: ba_get array_name key
ba_get() {
    local array_name="$1" key="$2"
    local safe_key="${key//[^a-zA-Z0-9_]/_}"
    local var_name="_ba_${array_name}_${safe_key}"
    eval "echo \"\${$var_name}\""
}

# Check if key exists in emulated associative array
# Usage: ba_exists array_name key
ba_exists() {
    local array_name="$1" key="$2"
    local safe_key="${key//[^a-zA-Z0-9_]/_}"
    local var_name="_ba_${array_name}_${safe_key}"
    eval "[[ -n \"\${$var_name+x}\" ]]"
}

# Get all keys from emulated associative array
# Usage: ba_keys array_name
ba_keys() {
    local array_name="$1"
    eval "echo \"\${_ba_${array_name}_keys}\""
}

# Clear an emulated associative array
# Usage: ba_clear array_name
ba_clear() {
    local array_name="$1"
    local keys_var="_ba_${array_name}_keys"
    local keys
    eval "keys=\"\${$keys_var}\""
    
    # Unset all key-value pairs
    for key in $keys; do
        local safe_key="${key//[^a-zA-Z0-9_]/_}"
        eval "unset _ba_${array_name}_${safe_key}"
    done
    
    # Clear the keys list
    eval "$keys_var=''"
}

# === String Case Conversion ===
# Portable alternatives to ${var^^} and ${var,,}

# Convert string to uppercase
# Usage: to_upper "string"
to_upper() {
    echo "$1" | tr '[:lower:]' '[:upper:]'
}

# Convert string to lowercase
# Usage: to_lower "string"
to_lower() {
    echo "$1" | tr '[:upper:]' '[:lower:]'
}

# === Safe Stream Redirection ===
# Portable alternative to &> redirection

# Redirect both stdout and stderr to /dev/null
# Usage: safe_redirect command [args...]
safe_redirect() {
    "$@" >/dev/null 2>&1
}

# === Compatibility Wrappers ===
# These provide transparent compatibility based on bash version

# Wrapper for associative array declaration
# Usage: compat_declare_assoc array_name
compat_declare_assoc() {
    local array_name="$1"
    if needs_compat; then
        ba_init "$array_name"
    else
        eval "declare -Ag $array_name"
    fi
}

# Wrapper for setting associative array value
# Usage: compat_assoc_set array_name key value
compat_assoc_set() {
    local array_name="$1" key="$2" value="$3"
    if needs_compat; then
        ba_set "$array_name" "$key" "$value"
    else
        eval "$array_name[\$key]=\$value"
    fi
}

# Wrapper for getting associative array value
# Usage: compat_assoc_get array_name key
compat_assoc_get() {
    local array_name="$1" key="$2"
    if needs_compat; then
        ba_get "$array_name" "$key"
    else
        eval "echo \"\${$array_name[\$key]}\""
    fi
}

# Wrapper for checking if key exists
# Usage: compat_assoc_exists array_name key
compat_assoc_exists() {
    local array_name="$1" key="$2"
    if needs_compat; then
        ba_exists "$array_name" "$key"
    else
        eval "[[ -n \"\${$array_name[\$key]+x}\" ]]"
    fi
}

# === Debug Functions ===
# Helper functions for debugging compatibility issues

# Print bash version info
print_bash_info() {
    echo "Bash version: ${BASH_VERSION}"
    echo "Major: $(bash_version_major), Minor: $(bash_version_minor)"
    echo "Compatibility mode: $(needs_compat && echo "YES" || echo "NO")"
}

# Test compatibility layer
test_compat_layer() {
    echo "=== Testing Bash Compatibility Layer ==="
    print_bash_info
    echo ""
    
    echo "Testing associative array emulation..."
    ba_init test_array
    ba_set test_array "key1" "value1"
    ba_set test_array "key2" "value2"
    
    local val1=$(ba_get test_array "key1")
    local val2=$(ba_get test_array "key2")
    
    if [[ "$val1" == "value1" ]] && [[ "$val2" == "value2" ]]; then
        echo "✅ Associative array emulation works"
    else
        echo "❌ Associative array emulation failed"
        return 1
    fi
    
    echo "Testing string case conversion..."
    local upper=$(to_upper "hello")
    local lower=$(to_lower "WORLD")
    
    if [[ "$upper" == "HELLO" ]] && [[ "$lower" == "world" ]]; then
        echo "✅ String case conversion works"
    else
        echo "❌ String case conversion failed"
        return 1
    fi
    
    echo ""
    echo "✅ All compatibility tests passed!"
    return 0
}

# Export functions if needed by other scripts
export -f bash_version_major bash_version_minor needs_compat
export -f ba_init ba_set ba_get ba_exists ba_keys ba_clear
export -f to_upper to_lower safe_redirect
export -f compat_declare_assoc compat_assoc_set compat_assoc_get compat_assoc_exists