#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR Proprietary
# Copyright (c) 2024 Nyia Keeper Contributors

# Nyia Keeper Public Installer
# Downloads release tarball and runs the real installer inside it

set -euo pipefail

echo "🚀 Installing Nyia Keeper..."

# Configuration
PUBLIC_REPO="KaizendoFr/nyia-keeper"

# Allow specifying version via environment variable or argument
if [[ -n "${1:-}" ]]; then
    # If argument provided, use specific tag
    RELEASE_TYPE="tags/$1"
    echo "📦 Installing specific version: $1"
elif [[ -n "${NYIA_VERSION:-}" ]]; then
    # If environment variable set, use it
    RELEASE_TYPE="tags/$NYIA_VERSION"
    echo "📦 Installing specific version: $NYIA_VERSION"
else
    # Default to latest release (pipeline may replace with specific tag for versioned releases)
    RELEASE_TYPE="tags/v0.1.0-alpha.46"
    echo "📦 Installing version: v0.1.0-alpha.46"
fi

# Find release with debugging
echo "🔍 Finding Nyia Keeper release..."
RELEASE_URL="https://api.github.com/repos/$PUBLIC_REPO/releases/$RELEASE_TYPE"
echo "Debug: API URL: $RELEASE_URL"

# Get release info with error checking
if ! RELEASE_JSON=$(curl -fsS "$RELEASE_URL"); then
    echo "❌ Failed to fetch release information from GitHub API"
    echo "   URL: $RELEASE_URL"
    echo "   Please check if the repository exists and has releases"
    exit 1
fi

# Build direct download URL
if [[ "$RELEASE_TYPE" == "latest" ]]; then
    TARBALL_URL="https://github.com/$PUBLIC_REPO/releases/latest/download/nyiakeeper-runtime.tar.gz"
else
    # Extract tag from "tags/v1.0.0" format
    TAG_NAME="${RELEASE_TYPE#tags/}"
    TARBALL_URL="https://github.com/$PUBLIC_REPO/releases/download/$TAG_NAME/nyiakeeper-runtime.tar.gz"
fi

echo "✅ Using release tarball: $TARBALL_URL"

echo "📥 Downloading Nyia Keeper runtime..."
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

TARBALL_FILE="$TEMP_DIR/nyiakeeper-runtime.tar.gz"
if ! curl -fL --retry 3 --retry-delay 1 -o "$TARBALL_FILE" "$TARBALL_URL"; then
    echo "❌ Failed to download release tarball"
    echo "   URL: $TARBALL_URL"
    echo "   Please verify the release exists and contains nyiakeeper-runtime.tar.gz"
    exit 1
fi

tar -xzf "$TARBALL_FILE" -C "$TEMP_DIR"

echo "🔧 Running real installer..."
cd "$TEMP_DIR"

# Execute the real installer inside the package
if [[ -f setup.sh ]]; then
    bash setup.sh
else
    echo "❌ Setup script not found in package"
    exit 1
fi

echo "✅ Nyia Keeper installation complete!"
echo ""
echo "Next steps:"
echo "1. Add ~/.local/bin to your PATH if not already done"
echo "2. Run: nyia list"
echo "3. Configure an assistant: nyia-claude --login"
