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
