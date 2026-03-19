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
    
    # Print header for all interactive/visible commands
    local _silent_flag=false
    case "$1" in
        --auto-mode|--get-project-version|--version|-v|--help|-h) _silent_flag=true ;;
    esac
    if [ "$_silent_flag" = "false" ]; then
        if [ "$USE_COLORS" = "true" ]; then
            utils_print_gradient "PHPSwitch  PHP Version Manager for macOS  v$PHPSWITCH_VERSION" \
                192 132 252 \
                103 232 249
            printf "\n\n"
        else
            printf "PHPSwitch  PHP Version Manager for macOS  v%s\n\n" "$PHPSWITCH_VERSION"
        fi
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
    local version=""
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
        core_get_current_php_version
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
        project_php_version=$(version_check_project 2>/dev/null)
        if [ -n "$project_php_version" ]; then
            utils_show_status "info" "Project PHP version detected: $project_php_version"
            
            if core_check_php_installed "$project_php_version"; then
                version_switch_php "$project_php_version" "true"
            else
                utils_show_status "warning" "Project PHP version ($project_php_version) is not installed"
                printf "  Install it? (y/n) "
                if [ "$(utils_validate_yes_no "" "y")" = "y" ]; then
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
        local _proj_ver
        _proj_ver=$(version_check_project 2>/dev/null)
        if [ -n "$_proj_ver" ]; then
            printf "%s\n" "$_proj_ver"
            exit 0
        else
            exit 1
        fi
    elif [ "$1" = "--auto-mode" ]; then
        # Special quiet mode for auto-switching - used by shell hooks
        project_php_version=$(version_check_project 2>/dev/null)
        if [ -n "$project_php_version" ]; then
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
        printf "PHPSwitch version %s\n" "$PHPSWITCH_VERSION"
        exit 0
    elif [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
        printf "\n  PHPSwitch  PHP Version Manager for macOS\n\n"
        printf "  Usage\n\n"
        printf "    phpswitch                            interactive menu\n"
        printf "    phpswitch --switch=VERSION           switch to version\n"
        printf "    phpswitch --switch-force=VERSION     switch, installing if needed\n"
        printf "    phpswitch --install=VERSION          install a version\n"
        printf "    phpswitch --uninstall=VERSION        uninstall a version\n"
        printf "    phpswitch --uninstall-force=VERSION  force uninstall a version\n"
        printf "    phpswitch --list                     list installed and available versions\n"
        printf "    phpswitch --json                     list versions in JSON format\n"
        printf "    phpswitch --current                  show current version\n"
        printf "    phpswitch --project, -p              switch to project version\n"
        printf "    phpswitch --clear-cache              clear cached data\n"
        printf "    phpswitch --refresh-cache            refresh available versions cache\n"
        printf "    phpswitch --fix-permissions          fix cache directory permissions\n"
        printf "    phpswitch --install-auto-switch      enable directory-based auto-switching\n"
        printf "    phpswitch --clear-directory-cache    clear auto-switching directory cache\n"
        printf "    phpswitch --check-dependencies       check system dependencies\n"
        printf "    phpswitch --install                  install as a system command\n"
        printf "    phpswitch --uninstall                remove from system\n"
        printf "    phpswitch --update                   update to the latest version\n"
        printf "    phpswitch --version, -v              show version\n"
        printf "    phpswitch --debug                    enable debug logging\n"
        printf "    phpswitch --help, -h                 show this help\n\n"
        exit 0
    else
        # No arguments or debug mode only - show the interactive menu
        current_version=$(core_get_current_php_version)


        # If default version is set and current version is different, offer to switch
        if [ -n "$DEFAULT_PHP_VERSION" ] && [ "$current_version" != "$DEFAULT_PHP_VERSION" ]; then
            printf "  Default version (%s) differs from current (%s)\n" "$DEFAULT_PHP_VERSION" "$current_version"
            printf "  Switch to default version? (y/n) "
            if [ "$(utils_validate_yes_no "" "y")" = "y" ]; then
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
        if [ "$USE_COLORS" = "true" ]; then
            printf "\n  "; utils_print_gradient "Active version" 148 182 251 125 207 250; printf "\n\n"
        else
            printf "\n  Active version\n\n"
        fi
        if command -v php &>/dev/null; then
            php -v | sed 's/^/    /'
        fi
        printf "\n"
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
            printf "  Use either 'X.Y' format (e.g., 8.1) or 'php@X.Y' format (e.g., php@8.1)\n"
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
            printf "  Use --force to install it automatically, or install it first with:\n"
            printf "    phpswitch --install=%s\n" "$version"
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
            printf "  Use either 'X.Y' format (e.g., 8.1) or 'php@X.Y' format (e.g., php@8.1)\n"
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
            printf "  Use either 'X.Y' format (e.g., 8.1) or 'php@X.Y' format (e.g., php@8.1)\n"
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
    local current_version
    current_version=$(core_get_current_php_version)
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
    
    printf "\n  Installed\n\n"
    while read -r version; do
        if [ "$version" = "$(core_get_current_php_version)" ]; then
            printf "    %s  (active)\n" "$version"
        else
            printf "    %s\n" "$version"
        fi
    done < <(core_get_installed_php_versions)

    printf "\n  Available to install\n\n"
    
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
            printf "    %s\n" "$version"
        fi
    done < <(core_get_available_php_versions)
    
    if [ "$format" = "json" ]; then
        # Provide JSON format for scripting
        printf "\n  JSON Format\n\n"
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
        printf "  Creating a temporary permissions fix script...\n"
        
        local temp_script
        temp_script=$(mktemp) || { utils_show_status "error" "Failed to create temporary script"; return 1; }
        TEMP_FILES_TO_CLEANUP+=("$temp_script")
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
    exit 1
fi

printf "\n  PHPSwitch Permission Fix Tool\n\n"

# Try to fix permissions on standard cache directory
if [ -d "$CACHE_DIR" ]; then
    printf "  Fixing permissions for: %s\n" "$CACHE_DIR"

    # Method 1: Standard chmod
    chmod -v u+w "$CACHE_DIR" 2>/dev/null

    if [ -w "$CACHE_DIR" ]; then
        printf "  Permissions fixed\n"
        exit 0
    fi

    # Method 2: Sudo chmod
    printf "  Trying with sudo...\n"
    sudo chmod -v u+w "$CACHE_DIR" 2>/dev/null

    if [ -w "$CACHE_DIR" ]; then
        printf "  Permissions fixed with sudo\n"
        exit 0
    fi

    # Method 3: Change ownership
    printf "  Trying to change ownership...\n"
    sudo chown -v "$USERNAME" "$CACHE_DIR" 2>/dev/null

    if [ -w "$CACHE_DIR" ]; then
        printf "  Ownership changed, directory is now writable\n"
        exit 0
    fi

    # Method 4: Recreate directory
    printf "  Recreating directory...\n"
    sudo rm -rf "$CACHE_DIR" 2>/dev/null
    mkdir -p "$CACHE_DIR" 2>/dev/null

    if [ -d "$CACHE_DIR" ] && [ -w "$CACHE_DIR" ]; then
        printf "  Directory successfully recreated\n"
        exit 0
    fi
fi

# Use alternative directory in home folder
printf "  Creating alternative cache directory: %s\n" "$ALT_CACHE_DIR"
mkdir -p "$ALT_CACHE_DIR" 2>/dev/null

if [ -d "$ALT_CACHE_DIR" ] && [ -w "$ALT_CACHE_DIR" ]; then
    printf "  Alternative directory created\n"
    
    # Update configuration
    if [ -f "$CONFIG_FILE" ]; then
        # Inline awk (utils_set_config_value unavailable in this embedded script)
        KEY=CACHE_DIRECTORY VALUE="$ALT_CACHE_DIR" awk '
            BEGIN{k=ENVIRON["KEY"];v=ENVIRON["VALUE"];found=0}
            $0 ~ ("^" k "="){print k "=\"" v "\"";found=1;next}
            {print}
            END{if(!found)print k "=\"" v "\""}
        ' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
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
    printf "  Configuration updated to use alternative cache directory\n"
    exit 0
else
    printf "  warn: Failed to create alternative directory\n"

    # Last resort: use temporary directory
    # Create secure temporary directory name
    secure_username="$(id -un)"
    if [[ "$secure_username" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        TMP_DIR="/tmp/phpswitch_cache_$secure_username"
    else
        echo "Error: Invalid username for temporary directory"
        exit 1
    fi
    echo "Using temporary directory as last resort: $TMP_DIR"
    mkdir -p "$TMP_DIR" 2>/dev/null

    if [ -d "$TMP_DIR" ] && [ -w "$TMP_DIR" ]; then
        if [ -f "$CONFIG_FILE" ]; then
            # Inline awk (utils_set_config_value unavailable in this embedded script)
            KEY=CACHE_DIRECTORY VALUE="$TMP_DIR" awk '
                BEGIN{k=ENVIRON["KEY"];v=ENVIRON["VALUE"];found=0}
                $0 ~ ("^" k "="){print k "=\"" v "\"";found=1;next}
                {print}
                END{if(!found)print k "=\"" v "\""}
            ' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
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
        printf "  Configuration updated to use temporary directory\n"
        printf "  warn: Cache will be cleared on system reboot\n"
        exit 0
    fi

    printf "  error: All attempts to fix permissions failed\n"
    printf "  Manually create a config file at %s and set CACHE_DIRECTORY to a writable location.\n" "$CONFIG_FILE"
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
        printf "  Clear phpswitch cache? (y/n) "
        if [ "$(utils_validate_yes_no "" "y")" = "y" ]; then
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
        printf "    - %s\n" "$location"
    done
    
    printf "  Uninstall phpswitch? (y/n) "

    if [ "$(utils_validate_yes_no "" "n")" = "y" ]; then
        for location in "${installed_locations[@]}"; do
            utils_show_status "info" "Removing $location..."
            sudo rm "$location"
        done
        
        # Ask about config file
        if [ -f "$HOME/.phpswitch.conf" ]; then
            printf "  Remove the configuration file ~/.phpswitch.conf? (y/n) "
            if [ "$(utils_validate_yes_no "" "n")" = "y" ]; then
                rm "$HOME/.phpswitch.conf"
                utils_show_status "success" "Configuration file removed"
            fi
        fi
        
        # Ask about cache directory
        local cache_dir="$HOME/.cache/phpswitch"
        if [ -d "$cache_dir" ]; then
            printf "  Remove the cache directory? (y/n) "
            if [ "$(utils_validate_yes_no "" "n")" = "y" ]; then
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
    local tmp_dir
    tmp_dir=$(mktemp -d 2>/dev/null) || { utils_show_status "error" "Failed to create temp directory for update"; return 1; }
    
    # Try to download the latest version from GitHub
    if curl -s -L "https://raw.githubusercontent.com/NavanithanS/phpswitch/master/php-switcher.sh" -o "$tmp_dir/php-switcher.sh"; then
        # Check if the download was successful
        if [ -s "$tmp_dir/php-switcher.sh" ]; then
            # Get the current version from the loaded variable
            local current_version="$PHPSWITCH_VERSION"

            # Get the downloaded version
            local new_version
            new_version=$(grep "^PHPSWITCH_VERSION=" "$tmp_dir/php-switcher.sh" | cut -d'"' -f2 | tr -d "'")
            
            # Validate new_version is semver (e.g. 1.4.5) before trusting it
            if ! [[ "$new_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                utils_show_status "error" "Could not determine downloaded version; update aborted"
                rm -rf "$tmp_dir"
                return 1
            fi
            if [ -n "$new_version" ] && [ -n "$current_version" ] && [ "$new_version" != "$current_version" ]; then
                utils_show_status "info" "New version available: $new_version (current: $current_version)"
                printf "  Update to %s? (y/n) " "$new_version"

                if [ "$(utils_validate_yes_no "" "y")" = "y" ]; then
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
                    printf "  Please restart phpswitch to use the new version.\n"
                    
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
    # Start fetching available PHP versions in the background immediately
    local available_versions_file
    available_versions_file=$(mktemp)
    TEMP_FILES_TO_CLEANUP+=("$available_versions_file")
    trap 'rm -f "$available_versions_file"' RETURN
    core_get_available_php_versions > "$available_versions_file" &

    # Get current and active PHP versions
    current_version=$(core_get_current_php_version)
    active_version=$(core_get_active_php_version)

    # Check for project-specific PHP version (single call)
    local project_php_version=""
    project_php_version=$(version_check_project 2>/dev/null)

    # Detect which file specified the project version
    local project_src=""
    if [ -n "$project_php_version" ]; then
        if [ -f "$(pwd)/.php-version" ]; then
            project_src=".php-version"
        elif [ -f "$(pwd)/composer.json" ]; then
            project_src="composer.json"
        elif [ -f "$(pwd)/.tool-versions" ]; then
            project_src=".tool-versions"
        fi
    fi

    printf "\n"

    # Current version line
    if [ "$USE_COLORS" = "true" ]; then
        printf "  "; utils_print_gradient "Current" 192 132 252 170 157 251; printf "  \033[36m%s\033[0m" "$current_version"
    else
        printf "  Current  %s" "$current_version"
    fi
    if [ "$active_version" != "none" ]; then
        if [ "$USE_COLORS" = "true" ]; then
            printf "  \033[2m(%s)\033[0m" "$active_version"
        else
            printf "  (%s)" "$active_version"
        fi
        local _ver_num="${current_version#php@}"
        if [[ "$current_version" == php@* ]] && [[ "$active_version" != *"$_ver_num"* ]]; then
            if [ "$USE_COLORS" = "true" ]; then
                printf "  \033[33mmismatch\033[0m"
            else
                printf "  mismatch"
            fi
        fi
    fi
    printf "\n"

    # Project version line (only when a project version is detected)
    if [ -n "$project_php_version" ]; then
        if [ "$USE_COLORS" = "true" ]; then
            printf "  "; utils_print_gradient "Project" 170 157 251 148 182 251
            printf "  \033[36m%s\033[0m" "$project_php_version"
            [ -n "$project_src" ] && printf "  \033[2m%s\033[0m" "$project_src"
            printf "\n"
        else
            printf "  Project  %s" "$project_php_version"
            [ -n "$project_src" ] && printf "  %s" "$project_src"
            printf "\n"
        fi
        # Offer to switch if project version differs from current
        if [ "$current_version" != "$project_php_version" ]; then
            printf "\n  Switch to project version? (y/n) "
            if [ "$(utils_validate_yes_no "" "y")" = "y" ]; then
                if core_check_php_installed "$project_php_version"; then
                    version_switch_php "$project_php_version" "true"
                    return $?
                else
                    utils_show_status "warning" "Project version ($project_php_version) is not installed"
                    printf "  Install it? (y/n) "
                    if [ "$(utils_validate_yes_no "" "y")" = "y" ]; then
                        version_switch_php "$project_php_version" "false"
                        return $?
                    fi
                fi
            fi
        fi
    fi
    printf "\n"

    # Installed versions section
    if [ "$USE_COLORS" = "true" ]; then
        printf "  "; utils_print_gradient "Installed" 148 182 251 125 207 250; printf "\n"
    else
        printf "  Installed\n"
    fi

    local i=1
    local versions=()

    # Get all installed PHP versions from Homebrew
    while read -r version; do
        versions+=("$version")
        if [ "$version" = "$current_version" ]; then
            if [ "$USE_COLORS" = "true" ]; then
                printf "    \033[1m%s\033[0m  %s  \033[32mactive\033[0m\n" "$i" "$version"
            else
                printf "    %s  %s  active\n" "$i" "$version"
            fi
        else
            printf "    %s  %s\n" "$i" "$version"
        fi
        ((i++))
    done < <(core_get_installed_php_versions)

    if [ ${#versions[@]} -eq 0 ]; then
        if [ "$USE_COLORS" = "true" ]; then
            printf "    \033[2mNone found via Homebrew\033[0m\n"
        else
            printf "    None found via Homebrew\n"
        fi
    fi

    printf "\n"

    # Wait for background fetch to complete
    if [ "$USE_COLORS" = "true" ]; then
        printf "  \033[2mChecking available versions...\033[0m"
    else
        printf "  Checking available versions..."
    fi
    wait
    printf "\r\033[2K"

    # Available versions section
    local available_versions=()

    while read -r version; do
        local _already_installed=false
        local _v
        for _v in "${versions[@]}"; do
            [ "$_v" = "$version" ] && { _already_installed=true; break; }
        done
        [ "$_already_installed" = "false" ] && available_versions+=("$version")
    done < "$available_versions_file"

    rm -f "$available_versions_file"

    if [ ${#available_versions[@]} -gt 0 ]; then
        if [ "$USE_COLORS" = "true" ]; then
            printf "  "; utils_print_gradient "Available to install" 125 207 250 103 232 249; printf "\n"
        else
            printf "  Available to install\n"
        fi

        for version in "${available_versions[@]}"; do
            if [ "$USE_COLORS" = "true" ]; then
                printf "    %s  %s  \033[2mnot installed\033[0m\n" "$i" "$version"
            else
                printf "    %s  %s\n" "$i" "$version"
            fi
            ((i++))
        done
        printf "\n"
    fi

    if [ ${#versions[@]} -eq 0 ] && [ ${#available_versions[@]} -eq 0 ]; then
        utils_show_status "error" "No PHP versions found via Homebrew"
        exit 1
    fi

    local max_option=$((i-1))

    # Options
    if [ "$USE_COLORS" = "true" ]; then
        printf "  "; utils_print_gradient "Options" 103 232 249 85 245 248; printf "\n"
        printf "    \033[1mu\033[0m  uninstall a version\n"
        printf "    \033[1me\033[0m  manage extensions\n"
        printf "    \033[1mc\033[0m  configure\n"
        printf "    \033[1md\033[0m  diagnose\n"
        printf "    \033[1mp\033[0m  set project default\n"
        printf "    \033[1ma\033[0m  auto-switch settings\n"
        printf "    \033[1m0\033[0m  exit\n"
    else
        printf "  Options\n"
        printf "    u  uninstall a version\n"
        printf "    e  manage extensions\n"
        printf "    c  configure\n"
        printf "    d  diagnose\n"
        printf "    p  set project default\n"
        printf "    a  auto-switch settings\n"
        printf "    0  exit\n"
    fi

    printf "\n"

    # Prompt
    if [ "$USE_COLORS" = "true" ]; then
        printf "  "; utils_print_gradient "Select (0-$max_option, u, e, c, d, p, a)" 148 182 251 125 207 250; printf " › "
    else
        printf "  Select (0-%s, u, e, c, d, p, a) " "$max_option"
    fi

    local selection
    local valid_selection=false

    while [ "$valid_selection" = "false" ]; do
        read -r selection

        if [ "$selection" = "0" ]; then
            printf "\n"
            # Remind about project version mismatch on exit
            if [ -n "$project_php_version" ] && [ "$current_version" != "$project_php_version" ]; then
                if [ "$USE_COLORS" = "true" ]; then
                    printf "  \033[33m!\033[0m  %s requires \033[36m%s\033[0m\n" "$project_src" "$project_php_version"
                else
                    printf "  ! %s requires %s\n" "$project_src" "$project_php_version"
                fi
                printf "\n"
            fi
            if [ "$USE_COLORS" = "true" ]; then
                printf "  "; utils_print_gradient "Good code. Keep shipping." 192 132 252 103 232 249; printf "\n"
            else
                printf "  Good code. Keep shipping.\n"
            fi
            printf "\n"
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
            printf "\n  Press Enter to continue..."
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
            utils_show_status "info" "Switching to $selected_version..."
            version_switch_php "$selected_version" "$selected_is_installed"
            return $?
        else
            printf "  Invalid selection. Try again "
        fi
    done
}

# Function to configure auto-switching
function cmd_configure_auto_switch {
    printf "\n  Auto-switch Configuration\n\n"
    printf "  Automatically change PHP versions when entering a directory\n"
    printf "  containing a .php-version, composer.json, or .tool-versions file.\n\n"

    # Check if auto-switching is enabled
    if [ "$AUTO_SWITCH_PHP_VERSION" = "true" ]; then
        utils_show_status "info" "Auto-switching is currently enabled"

        printf "  Disable auto-switching? (y/n) "
        if [ "$(utils_validate_yes_no "" "n")" = "y" ]; then
            # Update config file
            if [ -f "$HOME/.phpswitch.conf" ]; then
                utils_set_config_value "AUTO_SWITCH_PHP_VERSION" "false" "$HOME/.phpswitch.conf"
            fi
            
            utils_show_status "success" "Auto-switching disabled"
            printf "  This change takes effect the next time you open a new terminal.\n"
        else
            # Offer to clear directory cache
            printf "  Clear the directory cache? (y/n) "
            if [ "$(utils_validate_yes_no "" "n")" = "y" ]; then
                auto_clear_directory_cache
            fi
        fi
    else
        utils_show_status "info" "Auto-switching is currently disabled"

        printf "  Enable auto-switching? (y/n) "
        if [ "$(utils_validate_yes_no "" "y")" = "y" ]; then
            auto_install
        fi
    fi
}

# Function to show uninstall menu
function cmd_show_uninstall_menu {
    if [ "$USE_COLORS" = "true" ]; then
        printf "\n  "; utils_print_gradient "Uninstall PHP Version" 192 132 252 103 232 249; printf "\n\n"
    else
        printf "\n  Uninstall PHP Version\n\n"
    fi

    # Get current PHP version
    current_version=$(core_get_current_php_version)

    if [ "$USE_COLORS" = "true" ]; then
        printf "  "; utils_print_gradient "Installed" 148 182 251 125 207 250; printf "\n"
    else
        printf "  Installed\n"
    fi

    local i=1
    local versions=()

    # Get all installed PHP versions from Homebrew
    while read -r version; do
        versions+=("$version")
        if [ "$version" = "$current_version" ]; then
            if [ "$USE_COLORS" = "true" ]; then
                printf "    \033[1m%s\033[0m  %s  \033[32mactive\033[0m\n" "$i" "$version"
            else
                printf "    %s  %s  active\n" "$i" "$version"
            fi
        else
            printf "    %s  %s\n" "$i" "$version"
        fi
        ((i++))
    done < <(core_get_installed_php_versions)

    if [ ${#versions[@]} -eq 0 ]; then
        utils_show_status "error" "No PHP versions found installed via Homebrew"
        return 1
    fi

    local max_option=$((i-1))

    printf "\n    0  back to main menu\n\n"

    if [ "$USE_COLORS" = "true" ]; then
        printf "  "; utils_print_gradient "Select version to uninstall (0-$max_option)" 148 182 251 125 207 250; printf " › "
    else
        printf "  Select version to uninstall (0-%s) " "$max_option"
    fi

    local selection
    local valid_selection=false

    while [ "$valid_selection" = "false" ]; do
        read -r selection

        if [ "$selection" = "0" ]; then
            return 1
        elif utils_validate_numeric_input "$selection" 1 $max_option; then
            valid_selection=true
            selected_version="${versions[$((selection-1))]}"
            utils_show_status "info" "Uninstalling $selected_version..."
            
            # Uninstall the selected PHP version
            version_uninstall_php "$selected_version"
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
            printf "  Invalid selection. Try again "
        fi
    done
}

# Function to configure PHPSwitch
function cmd_configure_phpswitch {
    if [ "$USE_COLORS" = "true" ]; then
        printf "\n  "; utils_print_gradient "PHPSwitch Configuration" 192 132 252 103 232 249; printf "\n\n"
    else
        printf "\n  PHPSwitch Configuration\n\n"
    fi
    
    # Create config file if it doesn't exist
    if [ ! -f "$HOME/.phpswitch.conf" ]; then
        core_create_default_config
    fi
    
    # Load current config
    core_load_config
    
    if [ "$USE_COLORS" = "true" ]; then
        printf "  "; utils_print_gradient "Current settings" 192 132 252 170 157 251; printf "\n"
    else
        printf "  Current settings\n"
    fi
    printf "    1  auto restart PHP-FPM    %s\n" "$AUTO_RESTART_PHP_FPM"
    printf "    2  backup config files     %s\n" "$BACKUP_CONFIG_FILES"
    printf "    3  max backups             %s\n" "${MAX_BACKUPS:-5}"
    printf "    4  default PHP version     %s\n" "${DEFAULT_PHP_VERSION:-none}"
    printf "    5  auto-switching          %s\n" "$AUTO_SWITCH_PHP_VERSION"
    printf "    0  back to main menu\n\n"

    if [ "$USE_COLORS" = "true" ]; then
        printf "  "; utils_print_gradient "Select setting to change (0-5)" 148 182 251 125 207 250; printf " › "
    else
        printf "  Select setting to change (0-5) "
    fi
    
    local option
    read -r option
    
    case $option in
        1)
            printf "  Auto restart PHP-FPM when switching? (y/n) "
            if [ "$(utils_validate_yes_no "" "$AUTO_RESTART_PHP_FPM")" = "y" ]; then
                AUTO_RESTART_PHP_FPM=true
            else
                AUTO_RESTART_PHP_FPM=false
            fi
            ;;
        2)
            printf "  Create backups of config files before modifying? (y/n) "
            if [ "$(utils_validate_yes_no "" "$BACKUP_CONFIG_FILES")" = "y" ]; then
                BACKUP_CONFIG_FILES=true
            else
                BACKUP_CONFIG_FILES=false
            fi
            ;;
        3)
            printf "  Maximum number of backups to keep (1-20) "
            read -r max_backups
            if [[ "$max_backups" =~ ^[0-9]+$ ]] && [ "$max_backups" -ge 1 ] && [ "$max_backups" -le 20 ]; then
                MAX_BACKUPS="$max_backups"
            else
                utils_show_status "error" "Invalid value. Using default (5)"
                MAX_BACKUPS=5
            fi
            ;;
        4)
            printf "  Available PHP versions:\n\n"
            local i=1
            local versions=()

            # Add "None" option
            printf "    %s  none\n" "$i"
            ((i++))

            # Get all installed PHP versions
            while read -r version; do
                versions+=("$version")
                printf "    %s  %s\n" "$i" "$version"
                ((i++))
            done < <(core_get_installed_php_versions)

            printf "\n  Select default PHP version (1-%s) " "$i"
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
            printf "  Enable automatic PHP switching based on directory? (y/n) "
            if [ "$(utils_validate_yes_no "" "$AUTO_SWITCH_PHP_VERSION")" = "y" ]; then
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
                    printf "  Install shell hooks for auto-switching? (y/n) "
                    if [ "$(utils_validate_yes_no "" "y")" = "y" ]; then
                        cmd_configure_auto_switch
                    else
                        utils_show_status "warning" "Auto-switching is enabled but shell hooks are not installed"
                        printf "  Run 'phpswitch --install-auto-switch' to install the hooks later.\n"
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
    
    # Save the configuration atomically
    local _tmp_conf
    _tmp_conf=$(mktemp) || { utils_show_status "error" "Failed to create temp file for config"; return 1; }
    cat > "$_tmp_conf" <<EOL
# PHPSwitch Configuration
AUTO_RESTART_PHP_FPM=$AUTO_RESTART_PHP_FPM
BACKUP_CONFIG_FILES=$BACKUP_CONFIG_FILES
DEFAULT_PHP_VERSION="$DEFAULT_PHP_VERSION"
MAX_BACKUPS=$MAX_BACKUPS
AUTO_SWITCH_PHP_VERSION=$AUTO_SWITCH_PHP_VERSION
CACHE_DIRECTORY="$CACHE_DIRECTORY"
EOL
    if [ $? -ne 0 ] || [ ! -s "$_tmp_conf" ]; then
        rm -f "$_tmp_conf"
        utils_show_status "error" "Failed to write configuration"
        return 1
    fi
    mv "$_tmp_conf" "$HOME/.phpswitch.conf" || { rm -f "$_tmp_conf"; utils_show_status "error" "Failed to save configuration"; return 1; }

    utils_show_status "success" "Configuration updated"

    # Offer to return to configuration menu
    printf "  Make additional configuration changes? (y/n) "
    if [ "$(utils_validate_yes_no "" "y")" = "y" ]; then
        cmd_configure_phpswitch
    fi
}