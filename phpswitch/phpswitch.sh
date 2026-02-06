#!/bin/bash

# Version: 1.4.4
# PHPSwitch - PHP Version Manager for macOS
# This script helps switch between different PHP versions installed via Homebrew
# and updates shell configuration files (.zshrc, .bashrc, etc.) accordingly

# Determine script location
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Source modules directly for development
if [ -d "$SCRIPT_DIR/lib" ]; then
    # Debug mode detection
    if [ "$1" = "--debug" ]; then
        DEBUG_MODE=true
        shift
    fi
    
    # Source all required modules
    source "$SCRIPT_DIR/config/defaults.sh"
    source "$SCRIPT_DIR/lib/core.sh"
    source "$SCRIPT_DIR/lib/utils.sh"
    source "$SCRIPT_DIR/lib/shell.sh"
    source "$SCRIPT_DIR/lib/version.sh"
    source "$SCRIPT_DIR/lib/fpm.sh"
    source "$SCRIPT_DIR/lib/extensions.sh"
    source "$SCRIPT_DIR/lib/auto-switch.sh"
    source "$SCRIPT_DIR/lib/commands.sh"
    
    # Load configuration
    core_load_config
    
    # Parse command-line arguments and handle commands
    cmd_parse_arguments "$@"
else
    # If the lib directory doesn't exist, we're running the standalone version
    # All functions are defined within this script
    # This section will be populated by the build script
    echo "Running in standalone mode. This script needs to be built first."
    echo "Please run from the development directory or use the build.sh script to create a standalone version."
    exit 1
fi

exit 0