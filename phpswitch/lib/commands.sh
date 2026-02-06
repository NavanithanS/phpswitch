#!/bin/bash
# PHPSwitch Command Line Parsing
# Handles command line arguments and menu display

# Main command line argument parser
function cmd_parse_arguments {
    # Debug mode detection
    if [ "$1" = "--debug" ]; then
        DEBUG_MODE=true
        shift
    fi
    
    # Skip dependency check for basic commands
    if [ "$1" != "--version" ] && [ "$1" != "-v" ] && 
       [ "$1" != "--help" ] && [ "$1" != "-h" ] && 
       [ "$1" != "--check-dependencies" ] && [ "$1" != "--fix-permissions" ]; then
        # Check dependencies
        utils_check_dependencies || {
            utils_show_status "error" "Dependency check failed. Please resolve issues before proceeding."
            exit 1
        }
    fi
    
    # Parse command-line arguments for non-interactive mode
    if [[ "$1" == --switch=* ]]; then
        version="${1#*=}"
        if ! utils_validate_version "$version"; then
            utils_show_status "error" "Invalid version format: $version"
            exit 1
        fi
        cmd_non_interactive_switch "$version" "false"
        exit $?
    elif [[ "$1" == --switch-force=* ]]; then
        version="${1#*=}"
        if ! utils_validate_version "$version"; then
            utils_show_status "error" "Invalid version format: $version"
            exit 1
        fi
        cmd_non_interactive_switch "$version" "true"
        exit $?
    elif [[ "$1" == --install=* ]]; then
        version="${1#*=}"
        if ! utils_validate_version "$version"; then
            utils_show_status "error" "Invalid version format: $version"
            exit 1
        fi
        cmd_non_interactive_install "$version"
        exit $?
    elif [[ "$1" == --uninstall=* ]]; then
        version="${1#*=}"
        if ! utils_validate_version "$version"; then
            utils_show_status "error" "Invalid version format: $version"
            exit 1
        fi
        cmd_non_interactive_uninstall "$version" "false"
        exit $?
    elif [[ "$1" == --uninstall-force=* ]]; then
        version="${1#*=}"
        if ! utils_validate_version "$version"; then
            utils_show_status "error" "Invalid version format: $version"
            exit 1
        fi
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
    elif [ "$1" = "--fix-permissions" ]; then
        cmd_fix_permissions
        exit $?
    elif [ "$1" = "--check-dependencies" ]; then
        utils_check_dependencies
        exit $?
    elif [ "$1" = "--refresh-cache" ]; then
        utils_show_status "info" "Refreshing PHP versions cache..."
        local cache_dir="$HOME/.cache/phpswitch"
        # Validate cache directory path
        if ! utils_validate_path "$cache_dir"; then
            utils_show_status "error" "Invalid cache directory path"
            exit 1
        fi
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
    elif [ "$1" = "--get-project-version" ]; then
        # Just resolve the project version and print it (used by auto-switch hooks)
        if version_check_project > /dev/null; then
            version_check_project
            exit 0
        else
            exit 1
        fi
    elif [ "$1" = "--auto-mode" ]; then
        # Special quiet mode for auto-switching - used by shell hooks
        if version_check_project > /dev/null; then
            project_php_version=$(version_check_project)
            current_version=$(core_get_current_php_version)
            
            # Only switch if the version is different
            if [ "$current_version" != "$project_php_version" ]; then
                if core_check_php_installed "$project_php_version"; then
                    # Use the simplified auto-switching function
                    auto_switch_php "$project_php_version"
                    exit $?
                else
                    # Don't attempt to install in auto-mode
                    exit 1
                fi
            else
                # Already on the correct version
                exit 0
            fi
        else
            # No project PHP version found
            exit 0
        fi
    elif [ "$1" = "--install-auto-switch" ]; then
        auto_install
        exit $?
    elif [ "$1" = "--clear-directory-cache" ]; then
        auto_clear_directory_cache
        exit 0
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
        echo "  phpswitch                      - Run the interactive menu to switch PHP versions"
        echo "  phpswitch --switch=VERSION     - Switch to specified PHP version"
        echo "  phpswitch --switch-force=VERSION - Switch to PHP version, installing if needed"
        echo "  phpswitch --install=VERSION    - Install specified PHP version"
        echo "  phpswitch --uninstall=VERSION  - Uninstall specified PHP version"
        echo "  phpswitch --uninstall-force=VERSION - Force uninstall specified PHP version"
        echo "  phpswitch --list               - List installed and available PHP versions"
        echo "  phpswitch --json               - List PHP versions in JSON format"
        echo "  phpswitch --current            - Show current PHP version"
        echo "  phpswitch --project, -p        - Switch to the PHP version specified in project file"
        echo "  phpswitch --clear-cache        - Clear cached data"
        echo "  phpswitch --refresh-cache      - Refresh cache of available PHP versions"
        echo "  phpswitch --fix-permissions    - Fix cache directory permission issues"
        echo "  phpswitch --install-auto-switch - Enable automatic PHP switching based on directory"
        echo "  phpswitch --clear-directory-cache - Clear auto-switching directory cache"
        echo "  phpswitch --check-dependencies - Check system for required dependencies"
        echo "  phpswitch --install            - Install phpswitch as a system command"
        echo "  phpswitch --uninstall          - Remove phpswitch from your system"
        echo "  phpswitch --update             - Check for and install the latest version"
        echo "  phpswitch --version, -v        - Show phpswitch version"
        echo "  phpswitch --debug              - Run with debug logging enabled"
        echo "  phpswitch --help, -h           - Display this help message"
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

# Function to handle non-interactive switching
function cmd_non_interactive_switch {
    local version="$1"
    local force="$2"
    
    utils_show_status "info" "Non-interactive mode: Switching to PHP version $version"
    
    # Validate the PHP version format
    if [[ "$version" != php@* ]] && [ "$version" != "default" ]; then
        # Try to convert to php@X.Y format
        if [[ "$version" =~ ^[0-9]+\.[0-9]+$ ]]; then
            version="php@$version"
        elif [ "$version" = "default" ]; then
            version="php@default"
        else
            utils_show_status "error" "Invalid PHP version format: $version"
            echo "Use either 'X.Y' format (e.g., 8.1) or 'php@X.Y' format (e.g., php@8.1)"
            return 1
        fi
    elif [ "$version" = "default" ]; then
        version="php@default"
    fi
    
    # Check if the requested version is installed
    if core_check_php_installed "$version"; then
        is_installed=true
    else
        is_installed=false
        if [ "$force" != "true" ]; then
            utils_show_status "error" "PHP version $version is not installed"
            echo "Use --force to install it automatically, or install it first with:"
            echo "phpswitch --install=$version"
            return 1
        fi
    fi
    
    # Switch to the specified version
    version_switch_php "$version" "$is_installed"
    return $?
}

# Function to handle non-interactive installation
function cmd_non_interactive_install {
    local version="$1"
    
    utils_show_status "info" "Non-interactive mode: Installing PHP version $version"
    
    # Validate the PHP version format
    if [[ "$version" != php@* ]] && [ "$version" != "default" ]; then
        # Try to convert to php@X.Y format
        if [[ "$version" =~ ^[0-9]+\.[0-9]+$ ]]; then
            version="php@$version"
        elif [ "$version" = "default" ]; then
            version="php@default"
        else
            utils_show_status "error" "Invalid PHP version format: $version"
            echo "Use either 'X.Y' format (e.g., 8.1) or 'php@X.Y' format (e.g., php@8.1)"
            return 1
        fi
    elif [ "$version" = "default" ]; then
        version="php@default"
    fi
    
    # Check if already installed
    if core_check_php_installed "$version"; then
        utils_show_status "info" "PHP version $version is already installed"
        return 0
    fi
    
    # Install the version
    version_install_php "$version"
    return $?
}

# Function to handle non-interactive uninstallation
function cmd_non_interactive_uninstall {
    local version="$1"
    local force="$2"
    
    utils_show_status "info" "Non-interactive mode: Uninstalling PHP version $version"
    
    # Validate the PHP version format
    if [[ "$version" != php@* ]] && [ "$version" != "default" ]; then
        # Try to convert to php@X.Y format
        if [[ "$version" =~ ^[0-9]+\.[0-9]+$ ]]; then
            version="php@$version"
        elif [ "$version" = "default" ]; then
            version="php@default"
        else
            utils_show_status "error" "Invalid PHP version format: $version"
            echo "Use either 'X.Y' format (e.g., 8.1) or 'php@X.Y' format (e.g., php@8.1)"
            return 1
        fi
    elif [ "$version" = "default" ]; then
        version="php@default"
    fi
    
    # Check if the version is installed
    if ! core_check_php_installed "$version"; then
        utils_show_status "error" "PHP version $version is not installed"
        return 1
    fi
    
    # Check if it's the current active version
    local current_version=$(core_get_current_php_version)
    if [ "$current_version" = "$version" ] && [ "$force" != "true" ]; then
        utils_show_status "error" "Cannot uninstall the currently active PHP version without --force"
        return 1
    fi
    
    # Uninstall the version
    version_uninstall_php "$version"
    return $?
}

# Function to list installed and available PHP versions
function cmd_list_php_versions {
    local format="$1"
    
    echo "Installed PHP versions:"
    echo "======================"
    while read -r version; do
        if [ "$version" = "$(core_get_current_php_version)" ]; then
            echo "$version (current)"
        else
            echo "$version"
        fi
    done < <(core_get_installed_php_versions)
    
    echo ""
    echo "Available PHP versions:"
    echo "======================"
    
    # Get installed versions as an array for comparison
    local installed_versions=()
    while read -r version; do
        installed_versions+=("$version")
    done < <(core_get_installed_php_versions)
    
    # Show available versions not yet installed
    while read -r version; do
        # Check if this version is already installed
        local is_installed=false
        for installed in "${installed_versions[@]}"; do
            if [ "$installed" = "$version" ]; then
                is_installed=true
                break
            fi
        done
        
        if [ "$is_installed" = "false" ]; then
            echo "$version (not installed)"
        fi
    done < <(core_get_available_php_versions)
    
    if [ "$format" = "json" ]; then
        # Provide JSON format for scripting
        echo ""
        echo "JSON format:"
        echo "============"
        
        echo "{"
        echo "  \"current\": \"$(core_get_current_php_version)\","
        echo "  \"installed\": ["
        local first=true
        while read -r version; do
            if [ "$first" = "true" ]; then
                echo "    \"$version\""
                first=false
            else
                echo "    ,\"$version\""
            fi
        done < <(core_get_installed_php_versions)
        echo "  ],"
        echo "  \"available\": ["
        
        # Show available versions not yet installed
        first=true
        while read -r version; do
            # Check if this version is already installed
            local is_installed=false
            for installed in "${installed_versions[@]}"; do
                if [ "$installed" = "$version" ]; then
                    is_installed=true
                    break
                fi
            done
            
            if [ "$is_installed" = "false" ]; then
                if [ "$first" = "true" ]; then
                    echo "    \"$version\""
                    first=false
                else
                    echo "    ,\"$version\""
                fi
            fi
        done < <(core_get_available_php_versions)
        echo "  ]"
        echo "}"
    fi
}

# Function to execute the fix-permissions script
function cmd_fix_permissions {
    utils_show_status "info" "Running permission fix tool..."
    
    # Determine script directory location
    local script_dir="$(dirname "$(realpath "$0" 2>/dev/null || echo "$0")")"
    local fix_script="$script_dir/tools/fix-permissions.sh"
    
    if [ -f "$fix_script" ]; then
        # Execute the fix-permissions script
        bash "$fix_script"
        return $?
    else
        # If script not found in the expected location, try to create a temporary one
        utils_show_status "warning" "Fix permissions script not found at $fix_script"
        echo "Creating a temporary permissions fix script..."
        
        local temp_script=$(mktemp)
        cat > "$temp_script" << 'EOL'
#!/bin/bash
# Temporary fix permissions script for PHPSwitch cache directory

CACHE_DIR="$HOME/.cache/phpswitch"
ALT_CACHE_DIR="$HOME/.phpswitch_cache"
CONFIG_FILE="$HOME/.phpswitch.conf"
# Get secure username with validation
USERNAME=$(id -un)
# Validate username to prevent command injection
if [[ ! "$USERNAME" =~ ^[a-zA-Z0-9._-]+$ ]]; then
    echo "Error: Invalid username detected. Exiting for security."
    return 1
fi

echo "PHPSwitch Permission Fix Tool"
echo "============================"
echo ""

# Try to fix permissions on standard cache directory
if [ -d "$CACHE_DIR" ]; then
    echo "Fixing permissions for: $CACHE_DIR"
    
    # Method 1: Standard chmod
    chmod -v u+w "$CACHE_DIR" 2>/dev/null
    
    if [ -w "$CACHE_DIR" ]; then
        echo "✅ Permissions fixed successfully!"
        exit 0
    fi
    
    # Method 2: Sudo chmod
    echo "Trying with sudo..."
    sudo chmod -v u+w "$CACHE_DIR" 2>/dev/null
    
    if [ -w "$CACHE_DIR" ]; then
        echo "✅ Permissions fixed successfully with sudo!"
        exit 0
    fi
    
    # Method 3: Change ownership
    echo "Trying to change ownership..."
    sudo chown -v "$USERNAME" "$CACHE_DIR" 2>/dev/null
    
    if [ -w "$CACHE_DIR" ]; then
        echo "✅ Ownership changed, directory is now writable!"
        exit 0
    fi
    
    # Method 4: Recreate directory
    echo "Recreating directory..."
    sudo rm -rf "$CACHE_DIR" 2>/dev/null
    mkdir -p "$CACHE_DIR" 2>/dev/null
    
    if [ -d "$CACHE_DIR" ] && [ -w "$CACHE_DIR" ]; then
        echo "✅ Directory successfully recreated!"
        exit 0
    fi
fi

# Use alternative directory in home folder
echo "Creating alternative cache directory: $ALT_CACHE_DIR"
mkdir -p "$ALT_CACHE_DIR" 2>/dev/null

if [ -d "$ALT_CACHE_DIR" ] && [ -w "$ALT_CACHE_DIR" ]; then
    echo "✅ Alternative directory created successfully!"
    
    # Update configuration
    if [ -f "$CONFIG_FILE" ]; then
        if grep -q "CACHE_DIRECTORY=" "$CONFIG_FILE"; then
            sed -i.bak "s|CACHE_DIRECTORY=.*|CACHE_DIRECTORY=\"$ALT_CACHE_DIR\"|g" "$CONFIG_FILE"
            rm -f "$CONFIG_FILE.bak" 2>/dev/null
        else
            echo "CACHE_DIRECTORY=\"$ALT_CACHE_DIR\"" >> "$CONFIG_FILE"
        fi
    else
        cat > "$CONFIG_FILE" << CONF
# PHPSwitch Configuration
AUTO_RESTART_PHP_FPM=true
BACKUP_CONFIG_FILES=true
DEFAULT_PHP_VERSION=""
MAX_BACKUPS=5
AUTO_SWITCH_PHP_VERSION=false
CACHE_DIRECTORY="$ALT_CACHE_DIR"
CONF
    fi
    echo "✅ Configuration updated to use alternative cache directory!"
    exit 0
else
    echo "❌ Failed to create alternative directory!"
    
    # Last resort: use temporary directory
    # Create secure temporary directory name
    local secure_username
    secure_username="$(id -un)"
    if [[ "$secure_username" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        TMP_DIR="/tmp/phpswitch_cache_$secure_username"
    else
        echo "Error: Invalid username for temporary directory"
        exit 1
    fi
    echo "Using temporary directory as last resort: $TMP_DIR"
    mkdir -p "$TMP_DIR" 2>/dev/null
    
    if [ -d "$TMP_DIR" ] && [ -w "$TMP_DIR" ]; then
        if [ -f "$CONFIG_FILE" ]; then
            if grep -q "CACHE_DIRECTORY=" "$CONFIG_FILE"; then
                sed -i.bak "s|CACHE_DIRECTORY=.*|CACHE_DIRECTORY=\"$TMP_DIR\"|g" "$CONFIG_FILE"
                rm -f "$CONFIG_FILE.bak" 2>/dev/null
            else
                echo "CACHE_DIRECTORY=\"$TMP_DIR\"" >> "$CONFIG_FILE"
            fi
        else
            cat > "$CONFIG_FILE" << CONF
# PHPSwitch Configuration
AUTO_RESTART_PHP_FPM=true
BACKUP_CONFIG_FILES=true
DEFAULT_PHP_VERSION=""
MAX_BACKUPS=5
AUTO_SWITCH_PHP_VERSION=false
CACHE_DIRECTORY="$TMP_DIR"
CONF
        fi
        echo "✅ Configuration updated to use temporary directory!"
        echo "⚠️  Note: Cache will be cleared on system reboot"
        exit 0
    fi
    
    echo "❌ All attempts to fix permissions failed!"
    echo "Please manually create a config file at $CONFIG_FILE and set CACHE_DIRECTORY to a writable location."
    exit 1
fi
EOL
        
        chmod +x "$temp_script"
        bash "$temp_script"
        local result=$?
        rm -f "$temp_script"
        return $result
    fi
}

# Add cache management functions
function cmd_clear_phpswitch_cache {
    local cache_dir=$(core_get_cache_dir)
    
    if [ -d "$cache_dir" ]; then
        echo -n "Are you sure you want to clear phpswitch cache? (y/n): "
        if [ "$(utils_validate_yes_no "Clear cache?" "y")" = "y" ]; then
            core_clear_cache
            utils_show_status "success" "Cleared phpswitch cache from $cache_dir"
        else
            utils_show_status "info" "Cache clearing cancelled"
        fi
    else
        utils_show_status "info" "No cache directory found at $cache_dir"
    fi
}

# Function to install as a system command
function cmd_install_as_command {
    local destination="/usr/local/bin/phpswitch"
    local alt_destination="$HOMEBREW_PREFIX/bin/phpswitch"
    
    # Check if /usr/local/bin exists, if not try Homebrew bin
    if [ ! -d "/usr/local/bin" ]; then
        if [ -d "$HOMEBREW_PREFIX/bin" ]; then
            utils_show_status "info" "Using $HOMEBREW_PREFIX/bin directory..."
            destination=$alt_destination
        else
            utils_show_status "info" "Creating /usr/local/bin directory..."
            sudo mkdir -p "/usr/local/bin"
        fi
    fi
    
    utils_show_status "info" "Installing phpswitch command to $destination..."
    
    # Copy this script to the destination
    if sudo cp "$0" "$destination"; then
        sudo chmod +x "$destination"
        utils_show_status "success" "Installation successful! You can now run 'phpswitch' from anywhere"
    else
        utils_show_status "error" "Failed to install. Try running with sudo"
        return 1
    fi
}

# Function to uninstall the system command
function cmd_uninstall_command {
    local installed_locations=()
    
    # Check common installation locations
    if [ -f "/usr/local/bin/phpswitch" ]; then
        installed_locations+=("/usr/local/bin/phpswitch")
    fi
    
    if [ -f "$HOMEBREW_PREFIX/bin/phpswitch" ]; then
        installed_locations+=("$HOMEBREW_PREFIX/bin/phpswitch")
    fi
    
    if [ ${#installed_locations[@]} -eq 0 ]; then
        utils_show_status "error" "phpswitch is not installed as a system command"
        return 1
    fi
    
    utils_show_status "info" "Found phpswitch installed at:"
    for location in "${installed_locations[@]}"; do
        echo "  - $location"
    done
    
    echo -n "Are you sure you want to uninstall phpswitch? (y/n): "
    
    if [ "$(utils_validate_yes_no "Uninstall phpswitch?" "n")" = "y" ]; then
        for location in "${installed_locations[@]}"; do
            utils_show_status "info" "Removing $location..."
            sudo rm "$location"
        done
        
        # Ask about config file
        if [ -f "$HOME/.phpswitch.conf" ]; then
            echo -n "Would you like to remove the configuration file ~/.phpswitch.conf as well? (y/n): "
            if [ "$(utils_validate_yes_no "Remove config?" "n")" = "y" ]; then
                rm "$HOME/.phpswitch.conf"
                utils_show_status "success" "Configuration file removed"
            fi
        fi
        
        # Ask about cache directory
        local cache_dir="$HOME/.cache/phpswitch"
        if [ -d "$cache_dir" ]; then
            echo -n "Would you like to remove the cache directory as well? (y/n): "
            if [ "$(utils_validate_yes_no "Remove cache?" "n")" = "y" ]; then
                rm -rf "$cache_dir"
                utils_show_status "success" "Cache directory removed"
            fi
        fi
        
        utils_show_status "success" "phpswitch has been uninstalled successfully"
    else
        utils_show_status "info" "Uninstallation cancelled"
    fi
}

# Function to update self from GitHub
function cmd_update_self {
    utils_show_status "info" "Checking for updates..."
    
    # Create a temporary directory
    local tmp_dir=$(mktemp -d)
    
    # Try to download the latest version from GitHub
    if curl -s -L "https://raw.githubusercontent.com/NavanithanS/phpswitch/master/php-switcher.sh" -o "$tmp_dir/php-switcher.sh"; then
        # Check if the download was successful
        if [ -s "$tmp_dir/php-switcher.sh" ]; then
            # Get the current version
            local current_version=$(grep "^# Version:" "$0" | cut -d":" -f2 | tr -d " ")
            
            # Get the downloaded version
            local new_version=$(grep "^# Version:" "$tmp_dir/php-switcher.sh" | cut -d":" -f2 | tr -d " ")
            
            if [ -n "$new_version" ] && [ -n "$current_version" ] && [ "$new_version" != "$current_version" ]; then
                utils_show_status "info" "New version available: $new_version (current: $current_version)"
                echo -n "Would you like to update? (y/n): "
                
                if [ "$(utils_validate_yes_no "Update?" "y")" = "y" ]; then
                    # Find the current script's location
                    local script_path=$(which phpswitch 2>/dev/null || echo "$0")
                    
                    # Backup the current script
                    local backup_path="${script_path}.bak.$(date +%Y%m%d%H%M%S)"
                    utils_show_status "info" "Creating backup at $backup_path..."
                    cp "$script_path" "$backup_path" || { utils_show_status "error" "Failed to create backup"; rm -rf "$tmp_dir"; return 1; }
                    
                    # Install the new version
                    if [ -f "/usr/local/bin/phpswitch" ] || [ -f "$HOMEBREW_PREFIX/bin/phpswitch" ]; then
                        # Update the system command
                        utils_show_status "info" "Updating system command..."
                        chmod +x "$tmp_dir/php-switcher.sh"
                        
                        # Copy to all known installation locations
                        if [ -f "/usr/local/bin/phpswitch" ]; then
                            sudo cp "$tmp_dir/php-switcher.sh" "/usr/local/bin/phpswitch" || { utils_show_status "error" "Failed to update. Try with sudo"; rm -rf "$tmp_dir"; return 1; }
                        fi
                        
                        if [ -f "$HOMEBREW_PREFIX/bin/phpswitch" ]; then
                            sudo cp "$tmp_dir/php-switcher.sh" "$HOMEBREW_PREFIX/bin/phpswitch" || { utils_show_status "error" "Failed to update. Try with sudo"; rm -rf "$tmp_dir"; return 1; }
                        fi
                    else
                        # Just update the current script
                        chmod +x "$tmp_dir/php-switcher.sh"
                        sudo cp "$tmp_dir/php-switcher.sh" "$script_path" || { utils_show_status "error" "Failed to update. Try with sudo"; rm -rf "$tmp_dir"; return 1; }
                    fi
                    
                    utils_show_status "success" "Updated to version $new_version"
                    echo "Please restart phpswitch to use the new version."
                    
                    # Clean up
                    rm -rf "$tmp_dir"
                    exit 0
                else
                    utils_show_status "info" "Update cancelled"
                fi
            else
                utils_show_status "success" "You are already using the latest version: $current_version"
            fi
        else
            utils_show_status "error" "Failed to download the latest version"
        fi
    else
        utils_show_status "error" "Failed to connect to GitHub. Check your internet connection."
    fi
    
    # Clean up
    rm -rf "$tmp_dir"
}

# Function to show the main menu
function cmd_show_menu {
    echo "PHPSwitch - PHP Version Manager for macOS"
    echo "========================================"
    
    # Check for project-specific PHP version
    local project_php_version=""
    if version_check_project > /dev/null; then
        project_php_version=$(version_check_project)
        utils_show_status "info" "Project PHP version detected: $project_php_version"
        
        # Offer to switch to project PHP version
        if [ "$(core_get_current_php_version)" != "$project_php_version" ]; then
            echo -n "Switch to project-specific PHP version? (y/n): "
            if [ "$(utils_validate_yes_no "Switch to project version?" "y")" = "y" ]; then
                if core_check_php_installed "$project_php_version"; then
                    version_switch_php "$project_php_version" "true"
                    return $?
                else
                    utils_show_status "warning" "Project PHP version ($project_php_version) is not installed"
                    echo -n "Would you like to install it? (y/n): "
                    if [ "$(utils_validate_yes_no "Install project PHP version?" "y")" = "y" ]; then
                        version_switch_php "$project_php_version" "false"
                        return $?
                    fi
                fi
            fi
        fi
    fi
    
    # Start fetching available PHP versions in the background immediately
    available_versions_file=$(mktemp)
    core_get_available_php_versions > "$available_versions_file" &
    
    # Get current PHP version
    current_version=$(core_get_current_php_version)
    utils_show_status "info" "Current PHP version: $current_version"
    
    # Show actual PHP version being used currently (may differ from Homebrew's linked version)
    active_version=$(core_get_active_php_version)
    if [ "$active_version" != "none" ]; then
        php_path=$(which php)
        if [ -L "$php_path" ]; then
            # If it's a symlink, show what it points to
            real_path=$(readlink "$php_path")
            utils_show_status "info" "Active PHP is: $active_version (symlinked from $real_path)"
        else
            utils_show_status "info" "Active PHP is: $active_version (from $php_path)"
        fi
        
        # Alert if there's a mismatch
        if [[ $current_version == php@* ]] && [[ $active_version != *$(echo "$current_version" | grep -o "[0-9]\.[0-9]")* ]]; then
            utils_show_status "warning" "Version mismatch: Active PHP ($active_version) does not match Homebrew-linked version"
        fi
    fi
    
    echo ""
    echo "Installed PHP versions:"
    
    local i=1
    local versions=()
    
    # Get all installed PHP versions from Homebrew
    while read -r version; do
        versions+=("$version")
        if [ "$version" = "$current_version" ]; then
            echo "$i) $version (current)"
        else
            echo "$i) $version"
        fi
        ((i++))
    done < <(core_get_installed_php_versions)
    
    if [ ${#versions[@]} -eq 0 ]; then
        utils_show_status "warning" "No PHP versions found installed via Homebrew"
        echo "Let's check available PHP versions to install..."
    fi
    
    echo ""
    utils_show_status "info" "Checking for available PHP versions to install..."
    
    # Wait for background fetch to complete 
    wait
    
    echo "Available PHP versions to install:"
    
    local available_versions=()
    
    while read -r version; do
        # Check if this version is already installed
        if ! echo "${versions[@]}" | grep -q "$version"; then
            available_versions+=("$version")
            echo "$i) $version (not installed)"
            ((i++))
        fi
    done < "$available_versions_file"
    
    rm -f "$available_versions_file"
    
    if [ ${#versions[@]} -eq 0 ] && [ ${#available_versions[@]} -eq 0 ]; then
        utils_show_status "error" "No PHP versions found available via Homebrew"
        exit 1
    fi
    
    local max_option=$((i-1))
    
    echo ""
    echo "u) Uninstall a PHP version"
    echo "e) Manage PHP extensions"
    echo "c) Configure PHPSwitch"
    echo "d) Diagnose PHP environment"
    echo "p) Set current PHP version as project default"
    echo "a) Configure auto-switching for PHP versions"
    echo "0) Exit without changes"
    echo ""
    echo -n "Please select PHP version to use (0-$max_option, u, e, c, d, p, a): "
    
    local selection
    local valid_selection=false
    
    while [ "$valid_selection" = "false" ]; do
        read -r selection
        
        if [ "$selection" = "0" ]; then
            utils_show_status "info" "Exiting without changes"
            exit 0
        elif [ "$selection" = "u" ]; then
            valid_selection=true
            cmd_show_uninstall_menu
            return $?
        elif [ "$selection" = "e" ]; then
            valid_selection=true
            if [ "$current_version" = "none" ]; then
                utils_show_status "error" "No active PHP version detected"
                return 1
            else
                ext_manage_extensions "$current_version"
                # Return to main menu after extension management
                cmd_show_menu
                return $?
            fi
        elif [ "$selection" = "c" ]; then
            valid_selection=true
            cmd_configure_phpswitch
            # Return to main menu after configuration
            cmd_show_menu
            return $?
        elif [ "$selection" = "d" ]; then
            valid_selection=true
            utils_diagnose_path_issues
            # Return to main menu after diagnostics
            echo ""
            echo -n "Press Enter to continue..."
            read -r
            cmd_show_menu
            return $?
        elif [ "$selection" = "p" ]; then
            valid_selection=true
            if [ "$current_version" = "none" ]; then
                utils_show_status "error" "No active PHP version detected"
            else
                version_set_project "$current_version"
            fi
            # Return to main menu after setting project version
            cmd_show_menu
            return $?
        elif [ "$selection" = "a" ]; then
            valid_selection=true
            cmd_configure_auto_switch
            # Return to main menu after setting up auto-switching
            cmd_show_menu
            return $?
        elif utils_validate_numeric_input "$selection" 1 $max_option; then
            valid_selection=true
            # Check if selection is in installed versions
            if [ "$selection" -le ${#versions[@]} ]; then
                selected_version="${versions[$((selection-1))]}"
                selected_is_installed=true
            else
                # Calculate index for available versions array
                local available_index=$((selection - 1 - ${#versions[@]}))
                selected_version="${available_versions[$available_index]}"
                selected_is_installed=false
            fi
            utils_show_status "info" "You selected: $selected_version"
            version_switch_php "$selected_version" "$selected_is_installed"
            return $?
        else
            echo -n "Invalid selection. Please enter a number between 0 and $max_option, or 'u', 'e', 'c', 'd', 'p', 'a': "
        fi
    done
}

# Function to configure auto-switching
function cmd_configure_auto_switch {
    echo "Auto-switching Configuration"
    echo "============================"
    echo ""
    echo "Auto-switching allows PHPSwitch to automatically change PHP versions when"
    echo "you enter a directory containing a .php-version file."
    echo ""
    
    # Check if auto-switching is enabled
    if [ "$AUTO_SWITCH_PHP_VERSION" = "true" ]; then
        utils_show_status "info" "Auto-switching is currently ENABLED"
        
        echo -n "Would you like to disable auto-switching? (y/n): "
        if [ "$(utils_validate_yes_no "Disable auto-switching?" "n")" = "y" ]; then
            # Update config file
            sed -i.bak "s/AUTO_SWITCH_PHP_VERSION=.*/AUTO_SWITCH_PHP_VERSION=false/" "$HOME/.phpswitch.conf"
            rm -f "$HOME/.phpswitch.conf.bak"
            
            utils_show_status "success" "Auto-switching has been disabled"
            echo "This change will take effect the next time you open a new terminal window."
        else
            # Offer to clear directory cache
            echo -n "Would you like to clear the directory cache? (y/n): "
            if [ "$(utils_validate_yes_no "Clear directory cache?" "n")" = "y" ]; then
                auto_clear_directory_cache
            fi
        fi
    else
        utils_show_status "info" "Auto-switching is currently DISABLED"
        
        echo -n "Would you like to enable auto-switching? (y/n): "
        if [ "$(utils_validate_yes_no "Enable auto-switching?" "y")" = "y" ]; then
            auto_install
        fi
    fi
}

# Function to show uninstall menu
function cmd_show_uninstall_menu {
    echo "PHP Version Uninstaller"
    echo "======================="
    
    # Get current PHP version
    current_version=$(core_get_current_php_version)
    utils_show_status "info" "Current PHP version: $current_version"
    echo ""
    
    echo "Installed PHP versions:"
    
    local i=1
    local versions=()
    
    # Get all installed PHP versions from Homebrew
    while read -r version; do
        versions+=("$version")
        if [ "$version" = "$current_version" ]; then
            echo "$i) $version (current)"
        else
            echo "$i) $version"
        fi
        ((i++))
    done < <(core_get_installed_php_versions)
    
    if [ ${#versions[@]} -eq 0 ]; then
        utils_show_status "error" "No PHP versions found installed via Homebrew"
        return 1
    fi
    
    local max_option=$((i-1))
    
    echo ""
    echo "0) Return to main menu"
    echo ""
    echo -n "Please select PHP version to uninstall (0-$max_option): "
    
    local selection
    local valid_selection=false
    
    while [ "$valid_selection" = "false" ]; do
        read -r selection
        
        if [ "$selection" = "0" ]; then
            return 1
        elif utils_validate_numeric_input "$selection" 1 $max_option; then
            valid_selection=true
            selected_version="${versions[$((selection-1))]}"
            utils_show_status "info" "You selected to uninstall: $selected_version"
            
            # Uninstall the selected PHP version
            uninstall_status=$(version_uninstall_php "$selected_version")
            uninstall_status=$?
            
            if [ $uninstall_status -eq 2 ]; then
                # User chose to switch to another version after uninstall
                cmd_show_menu
                return $?
            elif [ $uninstall_status -eq 0 ]; then
                # Successful uninstall
                return 0
            else
                # Failed uninstall
                return 1
            fi
        else
            echo -n "Invalid selection. Please enter a number between 0 and $max_option: "
        fi
    done
}

# Function to configure PHPSwitch
function cmd_configure_phpswitch {
    echo "PHPSwitch Configuration"
    echo "======================="
    
    # Create config file if it doesn't exist
    if [ ! -f "$HOME/.phpswitch.conf" ]; then
        core_create_default_config
    fi
    
    # Load current config
    core_load_config
    
    echo "Current Configuration:"
    echo "1) Auto restart PHP-FPM: $AUTO_RESTART_PHP_FPM"
    echo "2) Backup config files: $BACKUP_CONFIG_FILES"
    echo "3) Maximum backups to keep: ${MAX_BACKUPS:-5}"
    echo "4) Default PHP version: ${DEFAULT_PHP_VERSION:-None}"
    echo "5) Auto-switching PHP versions: $AUTO_SWITCH_PHP_VERSION"
    echo "0) Return to main menu"
    echo ""
    echo -n "Select setting to change (0-5): "
    
    local option
    read -r option
    
    case $option in
        1)
            echo -n "Auto restart PHP-FPM when switching versions? (y/n): "
            if [ "$(utils_validate_yes_no "Auto restart?" "$AUTO_RESTART_PHP_FPM")" = "y" ]; then
                AUTO_RESTART_PHP_FPM=true
            else
                AUTO_RESTART_PHP_FPM=false
            fi
            ;;
        2)
            echo -n "Create backups of configuration files before modifying? (y/n): "
            if [ "$(utils_validate_yes_no "Backup files?" "$BACKUP_CONFIG_FILES")" = "y" ]; then
                BACKUP_CONFIG_FILES=true
            else
                BACKUP_CONFIG_FILES=false
            fi
            ;;
        3)
            echo -n "Enter maximum number of backups to keep (1-20): "
            read -r max_backups
            if [[ "$max_backups" =~ ^[0-9]+$ ]] && [ "$max_backups" -ge 1 ] && [ "$max_backups" -le 20 ]; then
                MAX_BACKUPS="$max_backups"
            else
                utils_show_status "error" "Invalid value. Using default (5)"
                MAX_BACKUPS=5
            fi
            ;;
        4)
            echo "Available PHP versions:"
            local i=1
            local versions=()
            
            # Add "None" option
            echo "$i) None"
            ((i++))
            
            # Get all installed PHP versions
            while read -r version; do
                versions+=("$version")
                echo "$i) $version"
                ((i++))
            done < <(core_get_installed_php_versions)
            
            echo -n "Select default PHP version (1-$i): "
            local ver_selection
            read -r ver_selection
            
            if utils_validate_numeric_input "$ver_selection" 1 $i; then
                if [ "$ver_selection" = "1" ]; then
                    DEFAULT_PHP_VERSION=""
                else
                    DEFAULT_PHP_VERSION="${versions[$((ver_selection-2))]}"
                fi
            else
                utils_show_status "error" "Invalid selection"
            fi
            ;;
        5)
            echo -n "Enable automatic PHP version switching based on directory? (y/n): "
            if [ "$(utils_validate_yes_no "Enable auto-switching?" "$AUTO_SWITCH_PHP_VERSION")" = "y" ]; then
                AUTO_SWITCH_PHP_VERSION=true
                
                # Ask to set up hooks if not already done
                local shell_type=$(shell_detect_shell)
                local hook_file
                local hook_exists=false
                
                case "$shell_type" in
                    "bash")
                        hook_file="$HOME/.bashrc"
                        if [ -f "$hook_file" ] && grep -q "phpswitch_auto_detect_project" "$hook_file"; then
                            hook_exists=true
                        fi
                        ;;
                    "zsh")
                        hook_file="$HOME/.zshrc"
                        if [ -f "$hook_file" ] && grep -q "phpswitch_auto_detect_project" "$hook_file"; then
                            hook_exists=true
                        fi
                        ;;
                    "fish")
                        hook_file="$HOME/.config/fish/config.fish"
                        if [ -f "$hook_file" ] && grep -q "phpswitch_auto_detect_project" "$hook_file"; then
                            hook_exists=true
                        fi
                        ;;
                esac
                
                if [ "$hook_exists" = "false" ]; then
                    echo -n "Would you like to install the shell hooks for auto-switching? (y/n): "
                    if [ "$(utils_validate_yes_no "Install shell hooks?" "y")" = "y" ]; then
                        cmd_configure_auto_switch
                    else
                        utils_show_status "warning" "Auto-switching is enabled but shell hooks are not installed"
                        echo "Run 'phpswitch --install-auto-switch' to install the hooks later."
                    fi
                fi
            else
                AUTO_SWITCH_PHP_VERSION=false
            fi
            ;;
        0)
            return 0
            ;;
        *)
            utils_show_status "error" "Invalid option"
            ;;
    esac
    
    # Save the configuration
    cat > "$HOME/.phpswitch.conf" <<EOL
# PHPSwitch Configuration
AUTO_RESTART_PHP_FPM=$AUTO_RESTART_PHP_FPM
BACKUP_CONFIG_FILES=$BACKUP_CONFIG_FILES
DEFAULT_PHP_VERSION="$DEFAULT_PHP_VERSION"
MAX_BACKUPS=$MAX_BACKUPS
AUTO_SWITCH_PHP_VERSION=$AUTO_SWITCH_PHP_VERSION
EOL
    
    utils_show_status "success" "Configuration updated"
    
    # Offer to return to configuration menu
    echo -n "Would you like to make additional configuration changes? (y/n): "
    if [ "$(utils_validate_yes_no "More changes?" "y")" = "y" ]; then
        cmd_configure_phpswitch
    fi
}