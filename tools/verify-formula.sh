#!/bin/bash
# Script to verify the Homebrew Formula

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"
FORMULA_PATH="$PROJECT_ROOT/Formula/phpswitch.rb"
FORMULA_NAME="phpswitch"

echo "🧪 Verifying Homebrew Formula..."

# 1. Check syntax
echo "   Checking syntax..."
ruby -c "$FORMULA_PATH"

# 2. Try to install dependencies if any (none for phpswitch usually)

# 3. Test installation
echo "   Testing installation from local formula..."
# Remove any existing installation
brew uninstall --force "$FORMULA_NAME" >/dev/null 2>&1 || true

# Setup temporary tap
TAP_NAME="phpswitch-verify-$(date +%s)"
TAP_DIR="$(brew --repo)/Library/Taps/homebrew/homebrew-$TAP_NAME"
mkdir -p "$TAP_DIR/Formula"
cp "$FORMULA_PATH" "$TAP_DIR/Formula/"

# Install from temporary tap
echo "   Installing from temporary tap homebrew/$TAP_NAME..."
if brew install --build-from-source "homebrew/$TAP_NAME/$FORMULA_NAME"; then
    echo "✅ Installation successful!"
    brew uninstall --force "$FORMULA_NAME" >/dev/null 2>&1 || true
    rm -rf "$TAP_DIR"
else
    echo "❌ Installation failed."
    rm -rf "$TAP_DIR"
    exit 1
fi

# 4. Verify functionality
echo "   Verifying installed command..."
if phpswitch --version; then
    echo "✅ phpswitch command is working!"
else
    echo "❌ phpswitch command failed."
    exit 1
fi

# 5. Run Audit (Requires Tap)
echo "   running 'brew audit'..."
# Auditing by path is deprecated, so we skip strict audit here and rely on install test
# If the user has tapped it, we can audit the tap:
if brew tap | grep -q "navanithans/phpswitch"; then
    brew audit --strict "navanithans/phpswitch/phpswitch" || echo "⚠️  Audit found issues (see above)"
else
    echo "ℹ️  Skipping strict link audit (tap not installed)"
fi

echo ""
echo "🎉 Formula Verification Complete!"
