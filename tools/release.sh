#!/bin/bash
# PHPSwitch Release Automation Script
# Automates the process of releasing a new version of PHPSwitch

set -e

# Configuration
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"
PHPSWITCH_SOURCE="$PROJECT_ROOT/phpswitch/phpswitch.sh"
SETUP_SCRIPT="$PROJECT_ROOT/setup-phpswitch.sh"
BUILD_SCRIPT="$PROJECT_ROOT/phpswitch/build.sh"
FORMULA_FILE="$PROJECT_ROOT/Formula/phpswitch.rb"
# Default to current directory for tap, but allow override
TAP_REPO_DIR="${TAP_REPO:-$PROJECT_ROOT/../homebrew-phpswitch}"

# check dependencies
command -v git >/dev/null 2>&1 || { echo "❌ Error: 'git' is required."; exit 1; }

# Optional dependencies
HAS_GH=false
if command -v gh >/dev/null 2>&1; then
    HAS_GH=true
else
    echo "⚠️  Warning: 'gh' CLI not found. GitHub Release creation will be skipped."
fi

# Function to get current version
get_current_version() {
    grep "^# Version:" "$PHPSWITCH_SOURCE" | cut -d":" -f2 | tr -d " "
}

# Function to update version in files
update_version() {
    local new_version="$1"
    
    echo "📝 Updating version to $new_version..."
    
    # 1. Update source
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s/^# Version: .*/# Version: $new_version/" "$PHPSWITCH_SOURCE"
        sed -i '' "s/VERSION=\".*\" # Default/VERSION=\"$new_version\" # Default/" "$SETUP_SCRIPT"
    else
        sed -i "s/^# Version: .*/# Version: $new_version/" "$PHPSWITCH_SOURCE"
        sed -i "s/VERSION=\".*\" # Default/VERSION=\"$new_version\" # Default/" "$SETUP_SCRIPT"
    fi
}

# START RELEASE PROCESS
echo "🚀 PHPSwitch Release Automation"
echo "=============================="

# 1. Check Git Status
if [[ -n $(git status -s) ]]; then
    echo "⚠️  Warning: You have uncommitted changes."
    read -p "Do you want to continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

CURRENT_VERSION=$(get_current_version)
echo "ℹ️  Current Version: $CURRENT_VERSION"

read -p "Enter new version (e.g., 1.4.4): " NEW_VERSION

if [[ -z "$NEW_VERSION" ]]; then
    echo "❌ Error: Version cannot be empty."
    exit 1
fi

if [[ "$NEW_VERSION" == "$CURRENT_VERSION" ]]; then
    echo "⚠️  Version is unchanged. Proceeding with existing version..."
else
    update_version "$NEW_VERSION"
    
    # Rebuild to update the artifact
    echo "🔨 Running build..."
    "$BUILD_SCRIPT" >/dev/null
    
    # Commit version bump
    echo "💾 Committing version bump..."
    git add .
    git commit -m "chore: release v$NEW_VERSION"
    git push origin HEAD
fi

# 2. Tag and Release on GitHub
echo "🏷️  Tagging v$NEW_VERSION..."
if git rev-parse "v$NEW_VERSION" >/dev/null 2>&1; then
    echo "⚠️  Tag v$NEW_VERSION already exists. Skipping tag creation."
else
    git tag "v$NEW_VERSION"
    git push origin "v$NEW_VERSION"
fi

if [ "$HAS_GH" = true ]; then
    echo "📦 Creating GitHub Release..."
    if gh release view "v$NEW_VERSION" >/dev/null 2>&1; then
        echo "⚠️  Release v$NEW_VERSION already exists."
    else
        # Generate notes or use custom ones
        gh release create "v$NEW_VERSION" \
            "$PROJECT_ROOT/php-switcher.sh#Standalone Script (php-switcher.sh)" \
            --title "v$NEW_VERSION" \
            --generate-notes
        echo "✅ Release created successfully!"
    fi
else
    echo "📦 Manual GitHub Release Required"
    echo "   1. Go to https://github.com/NavanithanS/phpswitch/releases/new"
    echo "   2. Tag: v$NEW_VERSION"
    echo "   3. Upload: $PROJECT_ROOT/php-switcher.sh"
    echo "   4. Publish the release."
    
    read -p "Press Enter once you have created the release..."
fi

# 3. Update Homebrew Tap
echo "🍺 Preparing Homebrew Formula update..."

# Wait a moment for the release to propagate/archive to be available
sleep 2

# Calculate SHA256 of the Source Tarball
SOURCE_URL="https://github.com/NavanithanS/phpswitch/archive/refs/tags/v$NEW_VERSION.tar.gz"
echo "📥 Downloading source tarball to calculate checksum..."
echo "   URL: $SOURCE_URL"

CHECKSUM=$(curl -sL "$SOURCE_URL" | shasum -a 256 | awk '{print $1}')
echo "   SHA256: $CHECKSUM"

# Function to patch formula file content
patch_formula() {
    local file="$1"
    local version="$2"
    local checksum="$3"
    local url="$4"
    
    # Simple regex replacement for url and sha256
    # This assumes standard Formula format
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s|url \".*\"|url \"$url\"|" "$file"
        sed -i '' "s|sha256 \".*\"|sha256 \"$checksum\"|" "$file"
    else
        sed -i "s|url \".*\"|url \"$url\"|" "$file"
        sed -i "s|sha256 \".*\"|sha256 \"$checksum\"|" "$file"
    fi
}

echo "📝 Updating local Formula/phpswitch.rb..."
patch_formula "$FORMULA_FILE" "$NEW_VERSION" "$CHECKSUM" "$SOURCE_URL"

echo "✅ Local Formula updated."

# Check for Tap Repo
if [[ -d "$TAP_REPO_DIR" ]]; then
    echo "🔄 Updating external Tap repository at $TAP_REPO_DIR..."
    mkdir -p "$TAP_REPO_DIR/Formula"
    cp "$FORMULA_FILE" "$TAP_REPO_DIR/Formula/phpswitch.rb"
    
    cd "$TAP_REPO_DIR"
    if [[ -n $(git status -s) ]]; then
        git add Formula/phpswitch.rb
        git commit -m "feat: update phpswitch to v$NEW_VERSION"
        git push origin HEAD
        echo "✅ Tap repository updated and pushed!"
    else
        echo "⚠️  No changes detected in Tap repository."
    fi
else
    echo "⚠️  Tap repository not found at $TAP_REPO_DIR"
    echo "   Please manually copy '$FORMULA_FILE' to your tap repository,"
    echo "   commit, and push."
fi

echo ""
echo "🎉 Release v$NEW_VERSION complete!"
