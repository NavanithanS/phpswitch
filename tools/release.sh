#!/bin/bash
# PHPSwitch Release Automation Script
# Automates the process of releasing a new version of PHPSwitch

set -e

# Configuration
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"
# Single source of truth for the version
DEFAULTS_FILE="$PROJECT_ROOT/phpswitch/config/defaults.sh"
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
    grep '^PHPSWITCH_VERSION=' "$DEFAULTS_FILE" | sed 's/PHPSWITCH_VERSION="\(.*\)"/\1/'
}

# Function to update version in files
update_version() {
    local new_version="$1"
    
    echo "📝 Updating version to $new_version..."
    
    if [ -f "$DEFAULTS_FILE" ]; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s/^PHPSWITCH_VERSION=\".*\"/PHPSWITCH_VERSION=\"$new_version\"/" "$DEFAULTS_FILE"
        else
            sed -i "s/^PHPSWITCH_VERSION=\".*\"/PHPSWITCH_VERSION=\"$new_version\"/" "$DEFAULTS_FILE"
        fi
        echo "   Updated defaults.sh"
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

read -r -p "Enter new version (e.g., 1.4.4): " NEW_VERSION
# Tags are always v-prefixed; accept "v1.4.4" input too
NEW_VERSION="${NEW_VERSION#v}"

if [[ ! "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "❌ Error: Version must look like 1.4.4."
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

# Checksum asset that `phpswitch --update` verifies against (fails closed without it)
ARTIFACT="$PROJECT_ROOT/php-switcher.sh"
CHECKSUM_FILE="$PROJECT_ROOT/php-switcher.sh.sha256"
(cd "$PROJECT_ROOT" && shasum -a 256 php-switcher.sh > "$CHECKSUM_FILE")
echo "🔐 Artifact SHA256: $(awk '{print $1}' "$CHECKSUM_FILE")"

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
            "$ARTIFACT#Standalone Script (php-switcher.sh)" \
            "$CHECKSUM_FILE#SHA-256 checksum" \
            --title "v$NEW_VERSION" \
            --generate-notes
        echo "✅ Release created successfully!"
    fi
else
    echo "📦 Manual GitHub Release Required"
    echo "   1. Go to https://github.com/NavanithanS/phpswitch/releases/new"
    echo "   2. Tag: v$NEW_VERSION"
    echo "   3. Upload: $ARTIFACT"
    echo "      and:    $CHECKSUM_FILE  (required by phpswitch --update)"
    echo "   4. Publish the release."
    
    read -r -p "Press Enter once you have created the release..."
fi

# 3. Update Homebrew Tap
echo "🍺 Preparing Homebrew Formula update..."

# Wait a moment for the release to propagate/archive to be available
sleep 2

# Calculate SHA256 of the Source Tarball
SOURCE_URL="https://github.com/NavanithanS/phpswitch/archive/refs/tags/v$NEW_VERSION.tar.gz"
echo "📥 Downloading source tarball to calculate checksum..."
echo "   URL: $SOURCE_URL"

# Download to a temp file with a hard failure check, so a not-yet-published
# tag (or any HTTP error) aborts here instead of silently hashing empty input
# and patching the formula with a wrong checksum.
TMP_TARBALL=$(mktemp)
if ! curl -fsSL "$SOURCE_URL" -o "$TMP_TARBALL"; then
    echo "❌ Error: Failed to download source tarball. Is the v$NEW_VERSION tag/release published yet?"
    rm -f "$TMP_TARBALL"
    exit 1
fi
CHECKSUM=$(shasum -a 256 "$TMP_TARBALL" | awk '{print $1}')
rm -f "$TMP_TARBALL"
echo "   SHA256: $CHECKSUM"

# Function to patch formula file content
patch_formula() {
    local file="$1"
    # $2 (version) is already encoded in the url; not needed separately here
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
