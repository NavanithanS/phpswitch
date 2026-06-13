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

# Get version from the single source of truth (defaults.sh)
VERSION=$(grep '^PHPSWITCH_VERSION=' "$SCRIPT_DIR/config/defaults.sh" | sed 's/PHPSWITCH_VERSION="\(.*\)"/\1/')
if [ -z "$VERSION" ]; then
    echo "❌ Error: Could not determine version from config/defaults.sh"
    exit 1
fi

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
{
    echo "# Default Configuration"
    tail -n +2 "$SCRIPT_DIR/config/defaults.sh"
    echo ""
} >> "$COMBINED_FILE"

# Add content from each lib module (without shebang)
modules=("core.sh" "utils.sh" "shell.sh" "version.sh" "fpm.sh" "extensions.sh" "auto-switch.sh" "commands.sh")

# Validate all modules exist before building
for module in "${modules[@]}"; do
    if [ ! -f "$SCRIPT_DIR/lib/$module" ]; then
        echo "❌ Error: Missing module: lib/$module"
        rm -f "$COMBINED_FILE"
        exit 1
    fi
done

for module in "${modules[@]}"; do
    {
        echo "# Module: $module"
        tail -n +2 "$SCRIPT_DIR/lib/$module"
        echo ""
    } >> "$COMBINED_FILE"
done

# Add the main script logic
echo "# Main script logic" >> "$COMBINED_FILE"
cat >> "$COMBINED_FILE" << INNEREOF
# REL-04: Serialize concurrent auto-switch invocations only.
# Auto-switch hooks can fire rapidly on quick directory changes; the lock
# prevents overlapping --auto-mode switches. Interactive and read-only
# commands are intentionally NOT locked, so they never block each other.
# The trap is set before core_load_config so the temp-cleanup trap it
# installs chains this rm rather than clobbering it.
if [ "\$1" = "--auto-mode" ]; then
    LOCKFILE="/tmp/phpswitch_\$(id -u).lock"
    # Atomic create; fails if the lockfile already exists
    if ! ( set -o noclobber; echo "\$\$" > "\$LOCKFILE" ) 2>/dev/null; then
        _pid=\$(cat "\$LOCKFILE" 2>/dev/null)
        if kill -0 "\$_pid" 2>/dev/null; then
            # Another auto-switch is in progress; stay silent and yield.
            exit 0
        fi
        # Stale lock from a dead process: take it over.
        echo "\$\$" > "\$LOCKFILE"
    fi
    trap 'rm -f "\$LOCKFILE"' EXIT INT TERM
fi

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
# Calculate SHA256 checksum
if command -v shasum >/dev/null 2>&1; then
    checksum=$(shasum -a 256 "$RELEASE_FILE" | awk '{print $1}')
    echo ""
    echo "SHA256 Checksum for Homebrew Formula:"
    echo "$checksum"
elif command -v sha256sum >/dev/null 2>&1; then
    checksum=$(sha256sum "$RELEASE_FILE" | awk '{print $1}')
    echo ""
    echo "SHA256 Checksum for Homebrew Formula:"
    echo "$checksum"
fi
