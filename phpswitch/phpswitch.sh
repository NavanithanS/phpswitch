#!/bin/bash

# Version: 1.4.5
# PHPSwitch - PHP Version Manager for macOS
# This script helps switch between different PHP versions installed via Homebrew
# and updates shell configuration files (.zshrc, .bashrc, etc.) accordingly

# Determine script location
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Source modules directly for development
if [ -d "$SCRIPT_DIR/lib" ]; then
    # Debug mode detection
    if [ "$1" = "--debug" ]; then
        # shellcheck disable=SC2034
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
    
    # REL-04: Serialize concurrent auto-switch invocations only.
    # Auto-switch hooks can fire rapidly on quick directory changes; the lock
    # prevents overlapping --auto-mode switches. Interactive and read-only
    # commands are intentionally NOT locked, so they never block each other.
    # The trap is set before core_load_config so the temp-cleanup trap it
    # installs chains this rm rather than clobbering it.
    if [ "$1" = "--auto-mode" ]; then
        LOCKFILE="/tmp/phpswitch_$(id -u).lock"
        # Atomic create; fails if the lockfile already exists
        if ! ( set -o noclobber; echo "$$" > "$LOCKFILE" ) 2>/dev/null; then
            _pid=$(cat "$LOCKFILE" 2>/dev/null)
            if kill -0 "$_pid" 2>/dev/null; then
                # Another auto-switch is in progress; stay silent and yield.
                exit 0
            fi
            # Stale lock from a dead process: take it over.
            echo "$$" > "$LOCKFILE"
        fi
        trap 'rm -f "$LOCKFILE"' EXIT INT TERM
    fi

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