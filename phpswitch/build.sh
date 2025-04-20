#!/bin/bash
# Script to combine all modules into a single file for distribution

# Determine script and parent directory locations
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PARENT_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"

# Set output file paths - place them in the parent directory
COMBINED_FILE="$PARENT_DIR/phpswitch-combined.sh"
RELEASE_FILE="$PARENT_DIR/php-switcher.sh"

# Also create copies in the current directory for development reference
DEV_COMBINED_FILE="$SCRIPT_DIR/phpswitch-combined.sh"
DEV_RELEASE_FILE="$SCRIPT_DIR/php-switcher.sh"

VERSION=$(grep "^# Version:" "$SCRIPT_DIR/phpswitch.sh" | cut -d":" -f2 | tr -d " ")

echo "Building PHPSwitch version $VERSION..."

# Build header for the combined file
cat > "$COMBINED_FILE" << INNEREOF
#!/bin/bash

# Version: $VERSION
# PHPSwitch - PHP Version Manager for macOS
# This script helps switch between different PHP versions installed via Homebrew
# and updates shell configuration files (.zshrc, .bashrc, etc.) accordingly

INNEREOF

# Add content from config/defaults.sh (without shebang)
echo "# Default Configuration" >> "$COMBINED_FILE"
tail -n +2 "$SCRIPT_DIR/config/defaults.sh" >> "$COMBINED_FILE"
echo "" >> "$COMBINED_FILE"

# Add content from each lib module (without shebang)
modules=("core.sh" "utils.sh" "shell.sh" "version.sh" "fpm.sh" "extensions.sh" "auto-switch.sh" "commands.sh")

for module in "${modules[@]}"; do
    echo "# Module: $module" >> "$COMBINED_FILE"
    tail -n +2 "$SCRIPT_DIR/lib/$module" >> "$COMBINED_FILE"
    echo "" >> "$COMBINED_FILE"
done

# Add the main script logic
echo "# Main script logic" >> "$COMBINED_FILE"
cat >> "$COMBINED_FILE" << INNEREOF
# Load configuration
core_load_config

# Parse command line arguments
cmd_parse_arguments "\$@"
INNEREOF

# Make the combined file executable
chmod +x "$COMBINED_FILE"

# Create the release file (main output)
cp "$COMBINED_FILE" "$RELEASE_FILE"
chmod +x "$RELEASE_FILE"

# Create copies in the development directory for reference
cp "$COMBINED_FILE" "$DEV_COMBINED_FILE"
cp "$RELEASE_FILE" "$DEV_RELEASE_FILE"
chmod +x "$DEV_COMBINED_FILE"
chmod +x "$DEV_RELEASE_FILE"

echo "Build complete!"
echo "- Main release file created at: $RELEASE_FILE"
echo "- Combined version created at: $COMBINED_FILE"
echo "- Development copies created in: $SCRIPT_DIR"