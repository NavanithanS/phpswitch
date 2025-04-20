#!/bin/bash
# Improved script to combine all modules into a single file for distribution
# Reduces duplicate output files and adds command-line options

# Display usage information
function show_usage {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help            Show this help message and exit"
    echo "  -d, --dev-copy        Create a development copy in the current directory"
    echo "  -k, --keep-combined   Keep the intermediate combined file"
    echo "  -o, --output DIR      Specify output directory (default: parent directory)"
    echo ""
    echo "Examples:"
    echo "  $0                    Build only the main release file in parent directory"
    echo "  $0 --dev-copy         Build the main file and create a development copy"
    echo "  $0 --keep-combined    Keep the intermediate combined file"
}

# Initialize options
CREATE_DEV_COPY=false
KEEP_COMBINED=false
CUSTOM_OUTPUT_DIR=""

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_usage
            exit 0
            ;;
        -d|--dev-copy)
            CREATE_DEV_COPY=true
            shift
            ;;
        -k|--keep-combined)
            KEEP_COMBINED=true
            shift
            ;;
        -o|--output)
            CUSTOM_OUTPUT_DIR="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Determine script and parent directory locations
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Set output directory - use custom if specified, otherwise use parent
if [ -n "$CUSTOM_OUTPUT_DIR" ]; then
    if [ ! -d "$CUSTOM_OUTPUT_DIR" ]; then
        echo "Creating output directory: $CUSTOM_OUTPUT_DIR"
        mkdir -p "$CUSTOM_OUTPUT_DIR"
    fi
    OUTPUT_DIR="$CUSTOM_OUTPUT_DIR"
else
    OUTPUT_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
fi

# Set output file paths
COMBINED_FILE="$SCRIPT_DIR/.phpswitch-combined.tmp.sh"
RELEASE_FILE="$OUTPUT_DIR/php-switcher.sh"

# If development copy requested, set paths
if [ "$CREATE_DEV_COPY" = true ]; then
    DEV_RELEASE_FILE="$SCRIPT_DIR/php-switcher.sh"
fi

# Get version
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

# Create the main release file
cp "$COMBINED_FILE" "$RELEASE_FILE"
chmod +x "$RELEASE_FILE"
echo "✅ Main release file created at: $RELEASE_FILE"

# Create development copy if requested
if [ "$CREATE_DEV_COPY" = true ]; then
    cp "$COMBINED_FILE" "$DEV_RELEASE_FILE"
    chmod +x "$DEV_RELEASE_FILE"
    echo "✅ Development copy created at: $DEV_RELEASE_FILE"
fi

# Keep or remove the combined temporary file
if [ "$KEEP_COMBINED" = true ]; then
    FINAL_COMBINED_FILE="$OUTPUT_DIR/phpswitch-combined.sh"
    cp "$COMBINED_FILE" "$FINAL_COMBINED_FILE"
    chmod +x "$FINAL_COMBINED_FILE"
    echo "✅ Combined version kept at: $FINAL_COMBINED_FILE"
fi

# Always clean up the temporary file
rm -f "$COMBINED_FILE"

echo "Build complete!"