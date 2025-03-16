#!/bin/bash
# PHPSwitch Core Functions
# Contains essential variables and core functionality

# Set debug mode (false by default)
DEBUG_MODE=false

# Get Homebrew prefix
HOMEBREW_PREFIX=$(brew --prefix)

# Function to log debug messages
function core_debug_log {
    if [ "$DEBUG_MODE" = "true" ]; then
        echo "[DEBUG] $1" >&2
    fi
}

# Load configuration
function core_load_config {
    CONFIG_FILE="$HOME/.phpswitch.conf"
    
    # Default settings
    AUTO_RESTART_PHP_FPM=true
    BACKUP_CONFIG_FILES=true
    DEFAULT_PHP_VERSION=""
    MAX_BACKUPS=5
    
    # Load settings if config exists
    if [ -f "$CONFIG_FILE" ]; then
        core_debug_log "Loading configuration from $CONFIG_FILE"
        source "$CONFIG_FILE"
    else
        core_debug_log "No configuration file found at $CONFIG_FILE"
    fi
}

# Create default configuration
function core_create_default_config {
    # Implementation to be added
    echo "Function not yet implemented"
}

# Functions to get PHP versions
function core_get_installed_php_versions {
    # Implementation to be added
    echo "Function not yet implemented"
}

function core_get_available_php_versions {
    # Implementation to be added
    echo "Function not yet implemented"
}

function core_get_current_php_version {
    # Implementation to be added
    echo "Function not yet implemented"
}

function core_get_active_php_version {
    # Implementation to be added
    echo "Function not yet implemented"
}

# Function to check if PHP version is actually installed
function core_check_php_installed {
    # Implementation to be added
    echo "Function not yet implemented"
}
