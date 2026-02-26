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
    # Pipeline replaces __RELEASE_TAG__ with a specific tag (e.g., tags/v0.1.0-alpha.41)
    # or "latest" for non-tag builds. If unreplaced, fall through to latest resolution.
    RELEASE_TYPE="__RELEASE_TAG__"
fi

# Resolve the release tag name for download URL
echo "🔍 Finding Nyia Keeper release..."

if [[ "$RELEASE_TYPE" == "__RELEASE_TAG__" || "$RELEASE_TYPE" == "latest" ]]; then
    # Resolve latest release (handles pre-releases which /releases/latest ignores)
    echo "📦 Finding latest release..."
    RELEASE_URL="https://api.github.com/repos/$PUBLIC_REPO/releases/latest"
    if RELEASE_JSON=$(curl -fsS "$RELEASE_URL" 2>/dev/null); then
        TAG_NAME=$(echo "$RELEASE_JSON" | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/')
    else
        # /releases/latest returns 404 when all releases are pre-releases (alpha/beta)
        echo "   No stable release found, checking pre-releases..."
        RELEASES_URL="https://api.github.com/repos/$PUBLIC_REPO/releases"
        if ! RELEASE_JSON=$(curl -fsS "$RELEASES_URL"); then
            echo "❌ Failed to fetch releases from GitHub API"
            echo "   Please check if the repository exists and has releases"
            exit 1
        fi
        TAG_NAME=$(echo "$RELEASE_JSON" | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/')
        if [[ -z "$TAG_NAME" ]]; then
            echo "❌ No releases found for $PUBLIC_REPO"
            exit 1
        fi
    fi
    echo "📦 Installing version: $TAG_NAME"
else
    # Specific tag requested (via argument or env var)
    TAG_NAME="${RELEASE_TYPE#tags/}"
    RELEASE_URL="https://api.github.com/repos/$PUBLIC_REPO/releases/$RELEASE_TYPE"
    if ! RELEASE_JSON=$(curl -fsS "$RELEASE_URL"); then
        echo "❌ Release $TAG_NAME not found"
        echo "   URL: $RELEASE_URL"
        echo "   Please verify this version exists"
        exit 1
    fi
fi

TARBALL_URL="https://github.com/$PUBLIC_REPO/releases/download/$TAG_NAME/nyiakeeper-runtime.tar.gz"
echo "✅ Using release: $TAG_NAME"

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
