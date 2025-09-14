#!/bin/bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR Proprietary

# NyarlathotIA Runtime Installer
set -e

INSTALL_DIR="${HOME}/.local"
BIN_DIR="${INSTALL_DIR}/bin"
LIB_DIR="${INSTALL_DIR}/lib/nyarlathotia"
CONFIG_DIR="${HOME}/.config/nyarlathotia/config"

echo "Installing NyarlathotIA runtime distribution..."

# Create directories
mkdir -p "$BIN_DIR" "$LIB_DIR" "$CONFIG_DIR"

# Copy binaries
cp -r bin/* "$BIN_DIR/"
echo "✅ Installed commands to $BIN_DIR"

# Copy libraries
cp -r lib/* "$LIB_DIR/"
echo "✅ Installed libraries to $LIB_DIR"

# Fix paths in assistant-template.sh for installed layout
if [[ -f "$BIN_DIR/assistant-template.sh" ]]; then
    # Fix cli-parser.sh path
    sed -i 's|source "\$script_dir/\.\./lib/cli-parser\.sh"|source "\$HOME/.local/lib/nyarlathotia/cli-parser.sh"|' "$BIN_DIR/assistant-template.sh"
    # Fix exclusions-commands.sh path
    sed -i 's|local exclusions_lib="\$script_dir/\.\./lib/exclusions-commands\.sh"|local exclusions_lib="\$HOME/.local/lib/nyarlathotia/exclusions-commands.sh"|' "$BIN_DIR/assistant-template.sh"
    # Fix mount-exclusions.sh path
    sed -i 's|local mount_exclusions_lib="\$script_dir/\.\./lib/mount-exclusions\.sh"|local mount_exclusions_lib="\$HOME/.local/lib/nyarlathotia/mount-exclusions.sh"|' "$BIN_DIR/assistant-template.sh"
    echo "✅ Updated paths for installed layout"
fi

# Update PATH if needed
if ! echo "$PATH" | grep -q "$BIN_DIR"; then
    echo ""
    echo "📝 Add this to your shell profile (.bashrc, .zshrc, etc.):"
    echo "   export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

echo ""
echo "✅ Installation complete!"
echo ""
echo "Next steps:"
echo "1. Add $BIN_DIR to your PATH (see above)"
echo "2. Run: nyia list"
echo "3. Use: nyia-claude --login"
