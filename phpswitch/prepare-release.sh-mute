#!/bin/bash
# Script to prepare release branch

# Run the build script first
./build.sh

# Files to keep in release branch
KEEP_FILES=(
  "php-switcher.sh"
  "LICENSE"
  "README.md"
)

# Create a temporary directory
TEMP_DIR=$(mktemp -d)

# Copy files to keep to temp directory
for file in "${KEEP_FILES[@]}"; do
  cp "$file" "$TEMP_DIR/"
done

# Remove all files except .git
find . -mindepth 1 -not -path "./.git*" -exec rm -rf {} \;

# Copy back the files to keep
cp -r "$TEMP_DIR"/* ./

# Clean up
rm -rf "$TEMP_DIR"

echo "Release branch prepared with only necessary files"
