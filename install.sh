#!/bin/bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR Proprietary
# Copyright (c) 2024 NyarlathotIA Contributors

# NyarlathotIA Runtime Installer
# Real installer that copies all files and bootstraps the system
# This file is included inside the runtime tarball

set -e

# Installation paths
INSTALL_DIR="${HOME}/.local"
BIN_DIR="${INSTALL_DIR}/bin"
LIB_DIR="${INSTALL_DIR}/lib/nyarlathotia"
CONFIG_DIR="${HOME}/.config/nyarlathotia/config"

echo "🔧 Installing NyarlathotIA runtime distribution..."

# Create all necessary directories
mkdir -p "$BIN_DIR" "$LIB_DIR" "$CONFIG_DIR"

# Copy binaries
if [[ -d bin ]]; then
    cp -r bin/* "$BIN_DIR/"
    echo "✅ Installed commands to $BIN_DIR"
else
    echo "❌ Error: bin directory not found"
    exit 1
fi

# Copy libraries
if [[ -d lib ]]; then
    cp -r lib/* "$LIB_DIR/"
    echo "✅ Installed libraries to $LIB_DIR"
else
    echo "❌ Error: lib directory not found"
    exit 1
fi

# Copy system prompts and docker assets (CRITICAL for runtime)
if [[ -d docker ]]; then
    cp -r docker "$INSTALL_DIR/"
    echo "✅ Installed system prompts to $INSTALL_DIR/docker"
else
    echo "⚠️  Warning: docker directory not found, system prompts may not work"
fi

# Copy and initialize configuration files
if [[ -d config ]]; then
    for conf_example in config/*.conf.example; do
        if [[ -f "$conf_example" ]]; then
            basename_conf=$(basename "$conf_example" .example)
            target_conf="$CONFIG_DIR/$basename_conf"
            
            if [[ ! -f "$target_conf" ]]; then
                cp "$conf_example" "$target_conf"
                echo "✅ Created config: $basename_conf"
            else
                echo "ℹ️  Config exists: $basename_conf (skipped)"
            fi
        fi
    done
else
    echo "⚠️  Warning: config directory not found"
fi

# Fix paths in assistant-template.sh for installed layout
if [[ -f "$BIN_DIR/assistant-template.sh" ]]; then
    # Fix cli-parser.sh path
    sed -i 's|source "\$script_dir/\.\./lib/cli-parser\.sh"|source "\$HOME/.local/lib/nyarlathotia/cli-parser.sh"|' "$BIN_DIR/assistant-template.sh"
    # Fix exclusions-commands.sh path  
    sed -i 's|local exclusions_lib="\$script_dir/\.\./lib/exclusions-commands\.sh"|local exclusions_lib="\$HOME/.local/lib/nyarlathotia/exclusions-commands.sh"|' "$BIN_DIR/assistant-template.sh"
    # Fix mount-exclusions.sh path
    sed -i 's|local mount_exclusions_lib="\$script_dir/\.\./lib/mount-exclusions\.sh"|local mount_exclusions_lib="\$HOME/.local/lib/nyarlathotia/mount-exclusions.sh"|' "$BIN_DIR/assistant-template.sh"
    
    # Also fix paths in main nyia script
    sed -i 's|local exclusions_lib="\$script_dir/\.\./lib/exclusions-commands\.sh"|local exclusions_lib="\$HOME/.local/lib/nyarlathotia/exclusions-commands.sh"|' "$BIN_DIR/nyia"
    sed -i 's|local mount_exclusions_lib="\$script_dir/\.\./lib/mount-exclusions\.sh"|local mount_exclusions_lib="\$HOME/.local/lib/nyarlathotia/mount-exclusions.sh"|' "$BIN_DIR/nyia"
    echo "✅ Updated paths for installed layout"
fi

# Check and update PATH
if ! echo "$PATH" | grep -q "$BIN_DIR"; then
    echo ""
    echo "📝 Add this to your shell profile (.bashrc, .zshrc, etc.):"
    echo "   export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

echo ""
echo "✅ Installation complete!"
echo ""
echo "Installation summary:"
echo "  Commands: $BIN_DIR"
echo "  Libraries: $LIB_DIR"  
echo "  System prompts: $INSTALL_DIR/docker"
echo "  Configuration: $CONFIG_DIR"