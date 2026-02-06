#!/bin/bash
# Script to set up the directory structure for PHPSwitch modularization

# Define the base directory
BASE_DIR="phpswitch"

# Create the main directory structure
echo "Creating directory structure..."
mkdir -p "$BASE_DIR/lib" "$BASE_DIR/config"

# Current version from existing script
if [ -f "php-switcher.sh" ]; then
    VERSION=$(grep "^# Version:" php-switcher.sh | cut -d":" -f2 | tr -d " ")
else
    VERSION="1.4.3" # Default version if script not found
fi

echo "Using version: $VERSION"

# Create the main script
cat > "$BASE_DIR/phpswitch.sh" << 'EOL'
#!/bin/bash

# Version: VERSION_PLACEHOLDER
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
EOL

# Replace the version placeholder
sed -i.bak "s/VERSION_PLACEHOLDER/$VERSION/g" "$BASE_DIR/phpswitch.sh"
rm "$BASE_DIR/phpswitch.sh.bak"

# Create the build script
cat > "$BASE_DIR/build.sh" << 'EOL'
#!/bin/bash
# Script to combine all modules into a single file for distribution

OUTPUT_FILE="phpswitch-combined.sh"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
VERSION=$(grep "^# Version:" "$SCRIPT_DIR/phpswitch.sh" | cut -d":" -f2 | tr -d " ")

echo "Building PHPSwitch version $VERSION..."

# Start with the shebang and version info
cat > "$OUTPUT_FILE" << INNEREOF
#!/bin/bash

# Version: $VERSION
# PHPSwitch - PHP Version Manager for macOS
# This script helps switch between different PHP versions installed via Homebrew
# and updates shell configuration files (.zshrc, .bashrc, etc.) accordingly

INNEREOF

# Add content from config/defaults.sh (without shebang)
echo "# Default Configuration" >> "$OUTPUT_FILE"
tail -n +2 "$SCRIPT_DIR/config/defaults.sh" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# Add content from each lib module (without shebang)
modules=("core.sh" "utils.sh" "shell.sh" "version.sh" "fpm.sh" "extensions.sh" "commands.sh")

for module in "${modules[@]}"; do
    echo "# Module: $module" >> "$OUTPUT_FILE"
    tail -n +2 "$SCRIPT_DIR/lib/$module" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
done

# Add the main script logic
echo "# Main script logic" >> "$OUTPUT_FILE"
cat >> "$OUTPUT_FILE" << INNEREOF
# Load configuration
core_load_config

# Parse command line arguments
cmd_parse_arguments "\$@"
INNEREOF

# Make the output file executable
chmod +x "$OUTPUT_FILE"

echo "Build complete: $OUTPUT_FILE"
EOL

# Create module files
echo "Creating module files..."

# Core module
cat > "$BASE_DIR/lib/core.sh" << 'EOL'
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
EOL

# Utils module
cat > "$BASE_DIR/lib/utils.sh" << 'EOL'
#!/bin/bash
# PHPSwitch Utility Functions
# Contains display and validation utilities

# Determine terminal color support
USE_COLORS=true
if [ -t 1 ]; then
    if ! tput colors &>/dev/null || [ "$(tput colors)" -lt 8 ]; then
        USE_COLORS=false
    fi
fi

# Function to display a spinning animation for long-running processes
function utils_show_spinner {
    # Implementation to be added
    echo "Function not yet implemented"
}

# Alternative function with dots animation for progress indication
function utils_show_progress {
    # Implementation to be added
    echo "Function not yet implemented"
}

# Function to display success or error message with colors
function utils_show_status {
    # Implementation to be added
    echo "Function not yet implemented"
}

# Function to validate yes/no response, with default value
function utils_validate_yes_no {
    # Implementation to be added
    echo "Function not yet implemented"
}

# Function to validate numeric input within a range
function utils_validate_numeric_input {
    # Implementation to be added
    echo "Function not yet implemented"
}

# Function to help diagnose PATH issues
function utils_diagnose_path_issues {
    # Implementation to be added
    echo "Function not yet implemented"
}

# Function to diagnose the PHP environment
function utils_diagnose_php_environment {
    # Implementation to be added
    echo "Function not yet implemented"
}
EOL

# Shell module
cat > "$BASE_DIR/lib/shell.sh" << 'EOL'
#!/bin/bash
# PHPSwitch Shell Management
# Handles shell detection and configuration file updates

# Function to detect shell type with fish support
function shell_detect_shell {
    # Implementation to be added
    echo "Function not yet implemented"
}

# Update the shell RC file function to support fish
function shell_update_rc {
    # Implementation to be added
    echo "Function not yet implemented"
}

# Enhanced force_reload_php function with fish support
function shell_force_reload {
    # Implementation to be added
    echo "Function not yet implemented"
}

# Function to cleanup old backup files
function shell_cleanup_backups {
    # Implementation to be added
    echo "Function not yet implemented"
}
EOL

# Version module
cat > "$BASE_DIR/lib/version.sh" << 'EOL'
#!/bin/bash
# PHPSwitch Version Management
# Handles PHP version switching, installation, and uninstallation

# Function to switch PHP version
function version_switch_php {
    # Implementation to be added
    echo "Function not yet implemented"
}

# Enhanced install_php function with improved error handling
function version_install_php {
    # Implementation to be added
    echo "Function not yet implemented"
}

# Function to uninstall PHP version
function version_uninstall_php {
    # Implementation to be added
    echo "Function not yet implemented"
}

# Function to properly handle the default PHP and versioned PHP
function version_resolve_php_version {
    # Implementation to be added
    echo "Function not yet implemented"
}

# Function to check for project-specific PHP version
function version_check_project {
    # Implementation to be added
    echo "Function not yet implemented"
}

# Function to create a project PHP version file
function version_set_project {
    # Implementation to be added
    echo "Function not yet implemented"
}
EOL

# FPM module
cat > "$BASE_DIR/lib/fpm.sh" << 'EOL'
#!/bin/bash
# PHPSwitch PHP-FPM Management
# Handles PHP-FPM service operations

# Function to handle PHP version for commands (handles default php)
function fpm_get_service_name {
    # Implementation to be added
    echo "Function not yet implemented"
}

# Function to stop all other PHP-FPM services except the active one
function fpm_stop_other_services {
    # Implementation to be added
    echo "Function not yet implemented"
}

# Enhanced restart_php_fpm function with better error handling
function fpm_restart {
    # Implementation to be added
    echo "Function not yet implemented"
}
EOL

# Extensions module
cat > "$BASE_DIR/lib/extensions.sh" << 'EOL'
#!/bin/bash
# PHPSwitch Extension Management
# Handles PHP extension operations

# Function to manage PHP extensions
function ext_manage_extensions {
    # Implementation to be added
    echo "Function not yet implemented"
}
EOL

# Commands module
cat > "$BASE_DIR/lib/commands.sh" << 'EOL'
#!/bin/bash
# PHPSwitch Command Line Parsing
# Handles command line arguments and menu display

# Main command line argument parser
function cmd_parse_arguments {
    # Parse command-line arguments for non-interactive mode
    if [[ "$1" == --switch=* ]]; then
        version="${1#*=}"
        cmd_non_interactive_switch "$version" "false"
        exit $?
    elif [[ "$1" == --switch-force=* ]]; then
        version="${1#*=}"
        cmd_non_interactive_switch "$version" "true"
        exit $?
    elif [[ "$1" == --install=* ]]; then
        version="${1#*=}"
        cmd_non_interactive_install "$version"
        exit $?
    elif [[ "$1" == --uninstall=* ]]; then
        version="${1#*=}"
        cmd_non_interactive_uninstall "$version" "false"
        exit $?
    elif [[ "$1" == --uninstall-force=* ]]; then
        version="${1#*=}"
        cmd_non_interactive_uninstall "$version" "true"
        exit $?
    elif [ "$1" = "--list" ]; then
        cmd_list_php_versions "normal"
        exit 0
    elif [ "$1" = "--json" ]; then
        cmd_list_php_versions "json"
        exit 0
    elif [ "$1" = "--current" ]; then
        echo "$(core_get_current_php_version)"
        exit 0
    elif [ "$1" = "--clear-cache" ]; then
        cmd_clear_phpswitch_cache
        exit 0
    elif [ "$1" = "--refresh-cache" ]; then
        utils_show_status "info" "Refreshing PHP versions cache..."
        local cache_dir="$HOME/.cache/phpswitch"
        mkdir -p "$cache_dir"
        rm -f "$cache_dir/available_versions.cache"
        core_get_available_php_versions > /dev/null
        utils_show_status "success" "PHP versions cache refreshed"
        exit 0
    elif [ "$1" = "--project" ] || [ "$1" = "-p" ]; then
        if version_check_project > /dev/null; then
            project_php_version=$(version_check_project)
            utils_show_status "info" "Project PHP version detected: $project_php_version"
            
            if core_check_php_installed "$project_php_version"; then
                version_switch_php "$project_php_version" "true"
            else
                utils_show_status "warning" "Project PHP version ($project_php_version) is not installed"
                echo -n "Would you like to install it? (y/n): "
                if [ "$(utils_validate_yes_no "Install project PHP version?" "y")" = "y" ]; then
                    version_switch_php "$project_php_version" "false"
                fi
            fi
            exit 0
        else
            utils_show_status "warning" "No project-specific PHP version found"
            exit 1
        fi
    elif [ "$1" = "--install" ]; then
        cmd_install_as_command
        exit 0
    elif [ "$1" = "--uninstall" ]; then
        cmd_uninstall_command
        exit 0
    elif [ "$1" = "--update" ]; then
        cmd_update_self
        exit 0
    elif [ "$1" = "--version" ] || [ "$1" = "-v" ]; then
        # Get version from the script
        version=$(grep "^# Version:" "$0" | cut -d":" -f2 | tr -d " ")
        echo "PHPSwitch version $version"
        exit 0
    elif [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
        echo "PHPSwitch - PHP Version Manager for macOS"
        echo "========================================"
        echo "Usage:"
        echo "  phpswitch                   - Run the interactive menu to switch PHP versions"
        echo "  phpswitch --switch=VERSION      - Switch to specified PHP version"
        echo "  phpswitch --switch-force=VERSION - Switch to PHP version, installing if needed"
        echo "  phpswitch --install=VERSION     - Install specified PHP version"
        echo "  phpswitch --uninstall=VERSION   - Uninstall specified PHP version"
        echo "  phpswitch --uninstall-force=VERSION - Force uninstall specified PHP version"
        echo "  phpswitch --list                - List installed and available PHP versions"
        echo "  phpswitch --json                - List PHP versions in JSON format"
        echo "  phpswitch --current             - Show current PHP version"
        echo "  phpswitch --project, -p         - Switch to the PHP version specified in project file"
        echo "  phpswitch --clear-cache         - Clear cached data"
        echo "  phpswitch --refresh-cache       - Refresh cache of available PHP versions"
        echo "  phpswitch --install         - Install phpswitch as a system command"
        echo "  phpswitch --uninstall       - Remove phpswitch from your system"
        echo "  phpswitch --update          - Check for and install the latest version"
        echo "  phpswitch --version, -v     - Show phpswitch version"
        echo "  phpswitch --debug           - Run with debug logging enabled"
        echo "  phpswitch --help, -h        - Display this help message"
        exit 0
    else
        # No arguments or debug mode only - show the interactive menu
        current_version=$(core_get_current_php_version)
        
        # If default version is set and current version is different, offer to switch
        if [ -n "$DEFAULT_PHP_VERSION" ] && [ "$current_version" != "$DEFAULT_PHP_VERSION" ] && [ "$(core_get_current_php_version)" != "$DEFAULT_PHP_VERSION" ]; then
            echo "Default PHP version ($DEFAULT_PHP_VERSION) is different from current version ($(core_get_current_php_version))"
            echo -n "Would you like to switch to the default version? (y/n): "
            if [ "$(utils_validate_yes_no "Switch to default?" "y")" = "y" ]; then
                if core_check_php_installed "$DEFAULT_PHP_VERSION"; then
                    version_switch_php "$DEFAULT_PHP_VERSION" "true"
                    exit 0
                else
                    utils_show_status "error" "Default PHP version ($DEFAULT_PHP_VERSION) is not installed"
                fi
            fi
        fi
        
        cmd_show_menu
        
        # Print current PHP version at the end to confirm
        echo ""
        utils_show_status "info" "Current PHP configuration:"
        echo ""
        php -v
    fi
}

# Function to show the main menu
function cmd_show_menu {
    # Implementation to be added
    echo "Function not yet implemented"
}

# Function to show uninstall menu
function cmd_show_uninstall_menu {
    # Implementation to be added
    echo "Function not yet implemented"
}

# Function to configure PHPSwitch
function cmd_configure_phpswitch {
    # Implementation to be added
    echo "Function not yet implemented"
}

# Functions for non-interactive mode
function cmd_non_interactive_switch {
    # Implementation to be added
    echo "Function not yet implemented"
}

function cmd_non_interactive_install {
    # Implementation to be added
    echo "Function not yet implemented"
}

function cmd_non_interactive_uninstall {
    # Implementation to be added
    echo "Function not yet implemented"
}

# Function to list installed and available PHP versions
function cmd_list_php_versions {
    # Implementation to be added
    echo "Function not yet implemented"
}

# Cache management functions
function cmd_clear_phpswitch_cache {
    # Implementation to be added
    echo "Function not yet implemented"
}

# Functions for system installation
function cmd_install_as_command {
    # Implementation to be added
    echo "Function not yet implemented"
}

function cmd_uninstall_command {
    # Implementation to be added
    echo "Function not yet implemented"
}

# Function to update self from GitHub
function cmd_update_self {
    # Implementation to be added
    echo "Function not yet implemented"
}
EOL

# Defaults config
cat > "$BASE_DIR/config/defaults.sh" << 'EOL'
#!/bin/bash
# PHPSwitch Default Configuration
# Contains default values for configuration

# Default configuration values
DEFAULT_AUTO_RESTART_PHP_FPM=true
DEFAULT_BACKUP_CONFIG_FILES=true
DEFAULT_PHP_VERSION=""
DEFAULT_MAX_BACKUPS=5
EOL

# Make scripts executable
chmod +x "$BASE_DIR/phpswitch.sh" "$BASE_DIR/build.sh"

echo "Directory structure and empty module files created successfully!"
echo ""
echo "Next steps:"
echo "1. cd $BASE_DIR"
echo "2. Begin moving functions from the original script to the appropriate modules"
echo "3. Test with ./phpswitch.sh"
echo "4. Build the standalone version with ./build.sh when ready"
