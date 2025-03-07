#!/bin/bash

# Version: 1.2.0
# PHPSwitch - PHP Version Manager for macOS
# This script helps switch between different PHP versions installed via Homebrew
# and updates shell configuration files (.zshrc, .bashrc, etc.) accordingly

# Set debug mode (false by default)
DEBUG_MODE=false

# Parse command line arguments for debug mode
if [ "$1" = "--debug" ]; then
    DEBUG_MODE=true
    shift
fi

# Get Homebrew prefix
HOMEBREW_PREFIX=$(brew --prefix)

# Function to display a spinning animation for long-running processes
function show_spinner {
    local message="$1"
    local pid=$!
    local spin='-\|/'
    local i=0
    
    echo -n "$message "
    
    while kill -0 $pid 2>/dev/null; do
        i=$(( (i+1) % 4 ))
        printf "\r$message ${spin:$i:1}"
        sleep 0.1
    done
    
    printf "\r$message Done!   \n"
}

# Alternative function with dots animation for progress indication
function show_progress {
    local message="$1"
    local pid=$!
    local dots=""
    
    echo -n "$message"
    
    while kill -0 $pid 2>/dev/null; do
        dots="${dots}."
        if [ ${#dots} -gt 5 ]; then
            dots="."
        fi
        printf "\r$message%-6s" "$dots"
        sleep 0.3
    done
    
    printf "\r$message Done!      \n"
}

# Function to log debug messages
function debug_log {
    if [ "$DEBUG_MODE" = "true" ]; then
        echo "[DEBUG] $1" >&2
    fi
}

# Load configuration
function load_config {
    CONFIG_FILE="$HOME/.phpswitch.conf"
    
    # Default settings
    AUTO_RESTART_PHP_FPM=true
    BACKUP_CONFIG_FILES=true
    DEFAULT_PHP_VERSION=""
    
    # Load settings if config exists
    if [ -f "$CONFIG_FILE" ]; then
        debug_log "Loading configuration from $CONFIG_FILE"
        source "$CONFIG_FILE"
    else
        debug_log "No configuration file found at $CONFIG_FILE"
    fi
}

# Create default configuration
function create_default_config {
    if [ ! -f "$HOME/.phpswitch.conf" ]; then
        cat > "$HOME/.phpswitch.conf" <<EOL
# PHPSwitch Configuration
AUTO_RESTART_PHP_FPM=true
BACKUP_CONFIG_FILES=true
DEFAULT_PHP_VERSION=""
EOL
        show_status "success" "Created default configuration at ~/.phpswitch.conf"
    fi
}

# Function to detect shell type
function detect_shell {
    if [ -n "$ZSH_VERSION" ]; then
        echo "zsh"
    elif [ -n "$BASH_VERSION" ]; then
        echo "bash"
    else
        echo "unknown"
    fi
}

# Determine terminal color support
USE_COLORS=true
if [ -t 1 ]; then
    if ! tput colors &>/dev/null || [ "$(tput colors)" -lt 8 ]; then
        USE_COLORS=false
    fi
fi

# Function to display success or error message with colors
function show_status {
    local status="$1"
    local message="$2"
    
    if [ "$USE_COLORS" = "true" ]; then
        if [ "$status" = "success" ]; then
            echo -e "\033[32m✅ SUCCESS: $message\033[0m"
        elif [ "$status" = "warning" ]; then
            echo -e "\033[33m⚠️  WARNING: $message\033[0m"
        elif [ "$status" = "error" ]; then
            echo -e "\033[31m❌ ERROR: $message\033[0m"
        elif [ "$status" = "info" ]; then
            echo -e "\033[36mℹ️  INFO: $message\033[0m"
        fi
    else
        if [ "$status" = "success" ]; then
            echo "SUCCESS: $message"
        elif [ "$status" = "warning" ]; then
            echo "WARNING: $message"
        elif [ "$status" = "error" ]; then
            echo "ERROR: $message"
        elif [ "$status" = "info" ]; then
            echo "INFO: $message"
        fi
    fi
}

# Function to validate yes/no response, with default value
function validate_yes_no {
    local prompt="$1"
    local default="$2"
    
    while true; do
        read -r response
        
        # If empty and default provided, use default
        if [ -z "$response" ] && [ -n "$default" ]; then
            echo "$default"
            return 0
        fi
        
        # Check for valid responses
        if [[ "$response" =~ ^[Yy](es)?$ ]]; then
            echo "y"
            return 0
        elif [[ "$response" =~ ^[Nn]o?$ ]]; then
            echo "n"
            return 0
        else
            echo -n "Please enter 'y' or 'n': "
        fi
    done
}

# Function to get all installed PHP versions
function get_installed_php_versions {
    # Get both php@X.Y versions and the default php (which could be the latest version)
    { brew list | grep "^php@" || true; brew list | grep "^php$" | sed 's/php/php@default/g' || true; } | sort
}

# Function to get all available PHP versions from Homebrew with caching and timeout handling
function get_available_php_versions {
    local cache_file="/tmp/phpswitch_available_versions.cache"
    local cache_timeout=3600  # Cache expires after 1 hour (in seconds)
    local cmd_timeout=15      # Timeout for brew commands in seconds
    
    # Check if cache exists and is recent
    if [ -f "$cache_file" ] && [ $(($(date +%s) - $(stat -f %m "$cache_file"))) -lt "$cache_timeout" ]; then
        debug_log "Using cached available PHP versions"
        cat "$cache_file"
        return
    fi
    
    # Create a temporary file for results
    local temp_file=$(mktemp)
    
    # Function to run a command with timeout
    run_with_timeout() {
        local cmd="$1"
        local timeout="$2"
        local result_file="$3"
        
        # Run the command with timeout
        (
            eval "$cmd" > "$result_file" 2>/dev/null &
            cmd_pid=$!
            
            # Wait for the specified timeout
            sleep "$timeout" &
            sleep_pid=$!
            
            # Wait for either process to finish
            wait -n "$cmd_pid" "$sleep_pid"
            
            # Kill the other process
            kill "$cmd_pid" 2>/dev/null
            kill "$sleep_pid" 2>/dev/null
        )
    }
    
    # Run the search commands with timeout
    run_with_timeout "brew search /php@[0-9]/ | grep '^php@' || true" "$cmd_timeout" "${temp_file}.1"
    run_with_timeout "brew search /^php$/ | grep '^php$' | sed 's/php/php@default/g' || true" "$cmd_timeout" "${temp_file}.2"
    
    # Combine results and sort
    if [ -s "${temp_file}.1" ] || [ -s "${temp_file}.2" ]; then
        cat "${temp_file}.1" "${temp_file}.2" | sort > "$cache_file"
    else
        # If both commands timeout or return empty, use cached file if it exists or create a minimal result
        if [ -f "$cache_file" ]; then
            debug_log "Brew search timed out, using existing cache"
        else
            debug_log "Brew search timed out, creating minimal result set"
            echo "php@7.4" > "$cache_file"
            echo "php@8.0" >> "$cache_file"
            echo "php@8.1" >> "$cache_file"
            echo "php@8.2" >> "$cache_file"
            echo "php@8.3" >> "$cache_file"
        fi
    fi
    
    # Clean up temp files
    rm -f "${temp_file}" "${temp_file}.1" "${temp_file}.2"
    
    # Output the results
    cat "$cache_file"
}

# Function to get current linked PHP version from Homebrew
function get_current_php_version {
    current_php_path=$(readlink "$HOMEBREW_PREFIX/bin/php" 2>/dev/null)
    if [ -n "$current_php_path" ]; then
        # Check if it's a versioned PHP or the default one
        if echo "$current_php_path" | grep -q "php@[0-9]\.[0-9]"; then
            echo "$current_php_path" | grep -o "php@[0-9]\.[0-9]"
        elif echo "$current_php_path" | grep -q "/php/"; then
            # It's the default PHP installation
            echo "php@default"
        else
            echo "none"
        fi
    else
        # Try to detect from the PHP binary if the symlink doesn't exist
        php_version=$(php -v 2>/dev/null | head -n 1 | cut -d " " -f 2 | cut -d "." -f 1,2)
        if [ -n "$php_version" ]; then
            # Check if this is from a versioned PHP or the default one
            if [ -d "$HOMEBREW_PREFIX/opt/php@$php_version" ]; then
                echo "php@$php_version"
            elif [ -d "$HOMEBREW_PREFIX/opt/php" ]; then
                echo "php@default"
            else
                echo "php@$php_version" # Best guess
            fi
        else
            echo "none"
        fi
    fi
}

# Function to compare PHP versions
function compare_php_versions {
    local version1=$(echo "$1" | grep -o "[0-9]\.[0-9]")
    local version2=$(echo "$2" | grep -o "[0-9]\.[0-9]")
    
    local v1_major=${version1%%.*}
    local v1_minor=${version1##*.}
    local v2_major=${version2%%.*}
    local v2_minor=${version2##*.}
    
    if [ "$v1_major" -gt "$v2_major" ]; then
        echo "greater"
    elif [ "$v1_major" -lt "$v2_major" ]; then
        echo "less"
    elif [ "$v1_minor" -gt "$v2_minor" ]; then
        echo "greater"
    elif [ "$v1_minor" -lt "$v2_minor" ]; then
        echo "less"
    else
        echo "equal"
    fi
}

# Function to check if PHP version is actually installed
function check_php_installed {
    local version="$1"
    
    # Handle the default php installation
    if [ "$version" = "php@default" ]; then
        if [ -f "$HOMEBREW_PREFIX/opt/php/bin/php" ]; then
            return 0
        else
            return 1
        fi
    fi
    
    # Check if the PHP binary for this version exists
    if [ -f "$HOMEBREW_PREFIX/opt/$version/bin/php" ]; then
        return 0
    else
        return 1
    fi
}

# Function to install PHP version
function install_php {
    local version="$1"
    local install_version="$version"
    
    # Handle default PHP installation
    if [ "$version" = "php@default" ]; then
        install_version="php"
    fi
    
    show_status "info" "Installing $install_version... This may take a while..."
    
    # Try the installation
    if brew install "$install_version"; then
        show_status "success" "$version installed successfully"
        return 0
    else
        show_status "error" "Failed to install $version"
        echo ""
        echo "Possible solutions:"
        echo "1. Try running 'brew doctor' to check for any issues with your Homebrew installation"
        echo "2. Run 'brew update' and try again"
        echo "3. Check for any conflicting dependencies with 'brew deps --tree $version'"
        echo "4. You might need to uninstall conflicting packages first"
        echo "5. Try installing with verbose output: 'brew install -v $version'"
        echo ""
        echo -n "Would you like to try a different approach? (y/n): "
        
        if [ "$(validate_yes_no "Would you like to try a different approach?" "n")" = "y" ]; then
            echo "Choose an option:"
            echo "1) Run 'brew doctor' first then retry"
            echo "2) Run 'brew update' first then retry"
            echo "3) Try installing with verbose output"
            echo "4) Exit and let me handle it manually"
            
            local valid_choice=false
            local fix_option
            
            while [ "$valid_choice" = "false" ]; do
                read -r fix_option
                
                if [[ "$fix_option" =~ ^[1-4]$ ]]; then
                    valid_choice=true
                else
                    echo -n "Please enter a number between 1 and 4: "
                fi
            done
            
            case $fix_option in
                1)
                    show_status "info" "Running 'brew doctor'..."
                    brew doctor
                    show_status "info" "Retrying installation..."
                    brew install "$version"
                    ;;
                2)
                    show_status "info" "Running 'brew update'..."
                    brew update
                    show_status "info" "Retrying installation..."
                    brew install "$version"
                    ;;
                3)
                    show_status "info" "Installing with verbose output..."
                    brew install -v "$version"
                    ;;
                4)
                    show_status "info" "Exiting. You can try to install manually with:"
                    echo "brew install $version"
                    return 1
                    ;;
            esac
            
            # Check if the retry was successful
            if brew list | grep -q "^$version$"; then
                show_status "success" "$version installed successfully on retry"
                return 0
            else
                show_status "error" "Installation still failed. Please try to install manually:"
                echo "brew install $version"
                return 1
            fi
        else
            return 1
        fi
    fi
}

# Function to uninstall PHP version
function uninstall_php {
    local version="$1"
    local service_name=$(get_service_name "$version")
    
    if ! check_php_installed "$version"; then
        show_status "error" "$version is not installed"
        return 1
    fi
    
    # Check if it's the current active version
    local current_version=$(get_current_php_version)
    if [ "$current_version" = "$version" ]; then
        show_status "warning" "You are attempting to uninstall the currently active PHP version"
        echo -n "Would you like to continue? This may break your PHP environment. (y/n): "
        
        if [ "$(validate_yes_no "Continue?" "n")" = "n" ]; then
            show_status "info" "Uninstallation cancelled"
            return 1
        fi
    fi
    
    # Stop PHP-FPM service if running
    if brew services list | grep -q "$service_name"; then
        show_status "info" "Stopping PHP-FPM service for $version..."
        brew services stop "$service_name"
    fi
    
    # Unlink the PHP version if it's linked
    if [ "$current_version" = "$version" ]; then
        show_status "info" "Unlinking $version..."
        brew unlink "$version" 2>/dev/null
    fi
    
    # Uninstall the PHP version
    show_status "info" "Uninstalling $version... This may take a while"
    local uninstall_cmd="$version"
    
    if [ "$version" = "php@default" ]; then
        uninstall_cmd="php"
    fi
    
    if brew uninstall "$uninstall_cmd"; then
        show_status "success" "$version has been uninstalled"
        
        # Ask about config files
        echo -n "Would you like to remove configuration files as well? (y/n): "
        
        if [ "$(validate_yes_no "Remove config files?" "n")" = "y" ]; then
            # Extract version number (e.g., 8.2 from php@8.2)
            local php_version="${version#php@}"
            if [ -d "$HOMEBREW_PREFIX/etc/php/$php_version" ]; then
                show_status "info" "Removing configuration files..."
                sudo rm -rf "$HOMEBREW_PREFIX/etc/php/$php_version"
                show_status "success" "Configuration files removed"
            else
                show_status "warning" "Configuration directory not found at $HOMEBREW_PREFIX/etc/php/$php_version"
            fi
        fi
        
        # If this was the active version, suggest switching to another version
        if [ "$current_version" = "$version" ]; then
            show_status "warning" "You have uninstalled the active PHP version"
            echo -n "Would you like to switch to another installed PHP version? (y/n): "
            
            if [ "$(validate_yes_no "Switch to another version?" "y")" = "y" ]; then
                # Show menu with remaining PHP versions
                return 2
            else
                show_status "info" "Please manually switch to another PHP version if needed"
            fi
        fi
        
        return 0
    else
        show_status "error" "Failed to uninstall $version"
        echo "You may want to try:"
        echo "  brew uninstall --force $version"
        return 1
    fi
}

# Function to handle PHP version for commands (handles default php)
function get_service_name {
    local version="$1"
    
    if [ "$version" = "php@default" ]; then
        echo "php"
    else
        echo "$version"
    fi
}

# Function to restart PHP-FPM service
function restart_php_fpm {
    local version="$1"
    local service_name=$(get_service_name "$version")
    
    if [ "$AUTO_RESTART_PHP_FPM" != "true" ]; then
        debug_log "Auto restart PHP-FPM is disabled in config"
        return 0
    fi
    
    # Check if PHP-FPM service is running
    if brew services list | grep -q "$service_name"; then
        show_status "info" "Restarting PHP-FPM service for $service_name..."
        if ! brew services restart "$service_name"; then
            show_status "warning" "Failed to restart service. This could be due to permissions."
            echo -n "Would you like to try with sudo? (y/n): "
            
            if [ "$(validate_yes_no "Try with sudo?" "y")" = "y" ]; then
                show_status "info" "Trying with sudo..."
                sudo brew services restart "$service_name"
                return $?
            fi
        fi
    else
        show_status "info" "PHP-FPM service not active for $service_name"
        echo -n "Would you like to start it? (y/n): "
        
        if [ "$(validate_yes_no "Start service?" "n")" = "y" ]; then
            show_status "info" "Starting PHP-FPM service for $service_name..."
            if ! brew services start "$service_name"; then
                show_status "warning" "Failed to start service. This could be due to permissions."
                echo -n "Would you like to try with sudo? (y/n): "
                
                if [ "$(validate_yes_no "Try with sudo?" "y")" = "y" ]; then
                    show_status "info" "Trying with sudo..."
                    sudo brew services start "$service_name"
                    return $?
                fi
            fi
        fi
    fi
    
    return 0
}

# Function to update shell RC file
function update_shell_rc {
    local new_version="$1"
    local shell_type=$(detect_shell)
    local rc_file=""
    
    case "$shell_type" in
        "zsh")
            rc_file="$HOME/.zshrc"
            ;;
        "bash")
            rc_file="$HOME/.bashrc"
            ;;
        *)
            rc_file="$HOME/.profile"
            ;;
    esac
    
    local php_bin_path=""
    local php_sbin_path=""
    
    # Determine the correct paths based on version
    if [ "$new_version" = "php@default" ]; then
        php_bin_path="$HOMEBREW_PREFIX/opt/php/bin"
        php_sbin_path="$HOMEBREW_PREFIX/opt/php/sbin"
    else
        php_bin_path="$HOMEBREW_PREFIX/opt/$new_version/bin"
        php_sbin_path="$HOMEBREW_PREFIX/opt/$new_version/sbin"
    fi
    
    # Check if RC file exists
    if [ ! -f "$rc_file" ]; then
        show_status "info" "$rc_file does not exist. Creating it..."
        touch "$rc_file"
    fi
    
    # Check if we have write permissions
    if [ ! -w "$rc_file" ]; then
        show_status "error" "No write permission for $rc_file"
        exit 1
    fi
    
    # Create backup
    if [ "$BACKUP_CONFIG_FILES" = "true" ]; then
        cp "$rc_file" "${rc_file}.bak.$(date +%Y%m%d%H%M%S)"
        show_status "info" "Created backup at ${rc_file}.bak.*"
    fi
    
    show_status "info" "Updating PATH in $rc_file..."
    
    # Comment out all PHP PATH entries
    sed -i '' 's/^export PATH=".*\/opt\/homebrew\/opt\/php@[0-9]\.[0-9]\/bin:\$PATH"/#&/' "$rc_file"
    sed -i '' 's/^export PATH=".*\/opt\/homebrew\/opt\/php@[0-9]\.[0-9]\/sbin:\$PATH"/#&/' "$rc_file"
    sed -i '' 's/^export PATH=".*\/opt\/homebrew\/opt\/php\/bin:\$PATH"/#&/' "$rc_file"
    sed -i '' 's/^export PATH=".*\/opt\/homebrew\/opt\/php\/sbin:\$PATH"/#&/' "$rc_file"
    sed -i '' 's/^export PATH=".*\/usr\/local\/opt\/php@[0-9]\.[0-9]\/bin:\$PATH"/#&/' "$rc_file"
    sed -i '' 's/^export PATH=".*\/usr\/local\/opt\/php@[0-9]\.[0-9]\/sbin:\$PATH"/#&/' "$rc_file"
    sed -i '' 's/^export PATH=".*\/usr\/local\/opt\/php\/bin:\$PATH"/#&/' "$rc_file"
    sed -i '' 's/^export PATH=".*\/usr\/local\/opt\/php\/sbin:\$PATH"/#&/' "$rc_file"
    
    # Uncomment or add the new PHP PATH entries
    if [ "$new_version" = "php@default" ]; then
        # For default PHP installation
        if grep -q "#export PATH=\"$HOMEBREW_PREFIX/opt/php/bin:\$PATH\"" "$rc_file"; then
            # Uncomment existing entries
            sed -i '' "s/^#export PATH=\"$HOMEBREW_PREFIX\/opt\/php\/bin:\$PATH\"/export PATH=\"$HOMEBREW_PREFIX\/opt\/php\/bin:\$PATH\"/" "$rc_file"
            sed -i '' "s/^#export PATH=\"$HOMEBREW_PREFIX\/opt\/php\/sbin:\$PATH\"/export PATH=\"$HOMEBREW_PREFIX\/opt\/php\/sbin:\$PATH\"/" "$rc_file"
        else
            # Add new entries if they don't exist
            echo "" >> "$rc_file"
            echo "# PHP version paths" >> "$rc_file"
            echo "export PATH=\"$HOMEBREW_PREFIX/opt/php/bin:\$PATH\"" >> "$rc_file"
            echo "export PATH=\"$HOMEBREW_PREFIX/opt/php/sbin:\$PATH\"" >> "$rc_file"
        fi
    else
        # For versioned PHP installations
        if grep -q "#export PATH=\"$HOMEBREW_PREFIX/opt/${new_version}/bin:\$PATH\"" "$rc_file"; then
            # Uncomment existing entries
            sed -i '' "s/^#export PATH=\"$HOMEBREW_PREFIX\/opt\/${new_version}\/bin:\$PATH\"/export PATH=\"$HOMEBREW_PREFIX\/opt\/${new_version}\/bin:\$PATH\"/" "$rc_file"
            sed -i '' "s/^#export PATH=\"$HOMEBREW_PREFIX\/opt\/${new_version}\/sbin:\$PATH\"/export PATH=\"$HOMEBREW_PREFIX\/opt\/${new_version}\/sbin:\$PATH\"/" "$rc_file"
        else
            # Add new entries if they don't exist
            echo "" >> "$rc_file"
            echo "# PHP version paths" >> "$rc_file"
            echo "export PATH=\"$HOMEBREW_PREFIX/opt/${new_version}/bin:\$PATH\"" >> "$rc_file"
            echo "export PATH=\"$HOMEBREW_PREFIX/opt/${new_version}/sbin:\$PATH\"" >> "$rc_file"
        fi
    fi
    
    show_status "success" "Updated PATH in $rc_file for $new_version"
    
    # Add a final step to ensure immediate effect in current shell and future shells
    echo "# Added by phpswitch script - force path reload" >> "$rc_file"
    echo "if [ -d \"$php_bin_path\" ]; then" >> "$rc_file"
    echo "  export PATH=\"$php_bin_path:\$PATH\"" >> "$rc_file"
    echo "fi" >> "$rc_file"
    echo "if [ -d \"$php_sbin_path\" ]; then" >> "$rc_file"
    echo "  export PATH=\"$php_sbin_path:\$PATH\"" >> "$rc_file"
    echo "fi" >> "$rc_file"
}

# Function to switch PHP version
function switch_php {
    local new_version="$1"
    local is_installed="$2"
    local current_version=$(get_current_php_version)
    local brew_version="$new_version"
    
    # Handle default PHP
    if [ "$new_version" = "php@default" ]; then
        brew_version="php"
    fi
    
    # Install the version if not installed
    if [ "$is_installed" = "false" ]; then
        show_status "info" "$new_version is not installed"
        echo -n "Would you like to install it? (y/n): "
        
        if [ "$(validate_yes_no "Install?" "n")" = "y" ]; then
            if ! install_php "$new_version"; then
                show_status "error" "Installation failed"
                exit 1
            fi
            
            # Double check that it's actually installed now
            if ! check_php_installed "$new_version"; then
                show_status "error" "$new_version was not properly installed despite Homebrew reporting success"
                echo "Please try to install it manually with: brew install $new_version"
                exit 1
            fi
        else
            show_status "info" "Installation cancelled"
            exit 0
        fi
    else
        # Verify that the installed version is actually available
        if ! check_php_installed "$new_version"; then
            show_status "warning" "$new_version seems to be installed according to Homebrew,"
            echo "but the PHP binary couldn't be found at expected location."
            echo -n "Would you like to attempt to reinstall it? (y/n): "
            
            if [ "$(validate_yes_no "Reinstall?" "n")" = "y" ]; then
                if ! install_php "$new_version"; then
                    show_status "error" "Reinstallation failed"
                    exit 1
                fi
            else
                show_status "info" "Skipping reinstallation. Proceeding with version switch..."
            fi
        fi
    fi
    
    if [ "$current_version" = "$new_version" ]; then
        show_status "info" "$new_version is already active in Homebrew"
    else
        show_status "info" "Switching from $current_version to $new_version..."
        
        # Unlink current PHP (if any)
        if [ "$current_version" != "none" ]; then
            show_status "info" "Unlinking $current_version..."
            brew unlink "$current_version" 2>/dev/null
        fi
        
        # Link new PHP with progressive fallback strategies
        show_status "info" "Linking $new_version..."
        
        # Strategy 1: Normal linking
        if brew link "$brew_version" --force 2>/dev/null; then
            show_status "success" "Linked $new_version successfully"
        # Strategy 2: Overwrite linking
        elif brew link --overwrite "$brew_version" 2>/dev/null; then
            show_status "success" "Linked $new_version with overwrite option"
        # Strategy 3: Manual symlinking
        else
            show_status "warning" "Standard linking methods failed, trying manual symlinking..."
            
            # Try to directly create symlinks
            local php_bin_path="$HOMEBREW_PREFIX/opt/$brew_version/bin"
            
            if [ ! -d "$php_bin_path" ] && [ "$new_version" = "php@default" ]; then
                php_bin_path="$HOMEBREW_PREFIX/opt/php/bin"
            fi
            
            if [ -d "$php_bin_path" ]; then
                for file in "$php_bin_path"/*; do
                    if [ -f "$file" ]; then
                        filename=$(basename "$file")
                        ln -sf "$file" "$HOMEBREW_PREFIX/bin/$filename" 2>/dev/null
                    fi
                done
                show_status "success" "Manual linking completed"
            else
                show_status "error" "Could not find PHP installation directory"
                exit 1
            fi
        fi
    fi
    
    # Update shell RC file
    update_shell_rc "$new_version"
    
    # Restart PHP-FPM if it's being used
    restart_php_fpm "$new_version"
    
    show_status "success" "PHP version switched to $new_version"
    
    # Try to source the RC file
    if [ -z "$SOURCED" ]; then
        export SOURCED=true
        show_status "info" "Applying changes to current shell..."
        
        # Source the appropriate RC file based on shell
        local shell_type=$(detect_shell)
        case "$shell_type" in
            "zsh")
                source "$HOME/.zshrc" > /dev/null 2>&1
                ;;
            "bash")
                source "$HOME/.bashrc" > /dev/null 2>&1
                ;;
            *)
                source "$HOME/.profile" > /dev/null 2>&1
                ;;
        esac
        
        # Export the PATH directly as well to ensure it takes effect in current shell
        if [ "$new_version" = "php@default" ]; then
            export PATH="$HOMEBREW_PREFIX/opt/php/bin:$PATH"
            export PATH="$HOMEBREW_PREFIX/opt/php/sbin:$PATH"
        else
            export PATH="$HOMEBREW_PREFIX/opt/$new_version/bin:$PATH"
            export PATH="$HOMEBREW_PREFIX/opt/$new_version/sbin:$PATH"
        fi
        
        if [ $? -ne 0 ]; then
            show_status "warning" "Could not automatically apply changes to current shell"
            echo "Please run 'source ~/.zshrc' (or appropriate RC file) to apply the changes to your current terminal"
        else
            # Force the reload of PHP binary
            force_reload_php "$new_version"
            
            # Verify the active PHP version
            CURRENT_PHP_VERSION=$(php -v 2>/dev/null | head -n 1 | cut -d " " -f 2 | cut -d "." -f 1,2)
            
            if [ "$new_version" = "php@default" ]; then
                # For default PHP, we need to get the expected version from the actual binary
                DEFAULT_PHP_PATH="$HOMEBREW_PREFIX/opt/php/bin/php"
                if [ -f "$DEFAULT_PHP_PATH" ]; then
                    EXPECTED_VERSION=$($DEFAULT_PHP_PATH -v 2>/dev/null | head -n 1 | cut -d " " -f 2 | cut -d "." -f 1,2)
                else
                    EXPECTED_VERSION="unknown"
                fi
            else
                EXPECTED_VERSION=$(echo "$new_version" | grep -o "[0-9]\.[0-9]")
            fi
            
            if [ "$CURRENT_PHP_VERSION" = "$EXPECTED_VERSION" ]; then
                show_status "success" "Active PHP version is now: $CURRENT_PHP_VERSION"
                php -v | head -n 1
            else
                show_status "warning" "PHP version switch might not have been fully applied"
                echo "Current PHP version is: $(php -v | head -n 1)"
                echo "Try opening a new terminal or manually running: source ~/.zshrc (or appropriate RC file)"
            fi
        fi
    else
        show_status "info" "Please run 'source ~/.zshrc' (or appropriate RC file) to apply the changes to your current terminal"
        echo "Then verify with: php -v"
    fi
}

# Function to validate numeric input within a range
function validate_numeric_input {
    local input="$1"
    local min="$2"
    local max="$3"
    
    if [[ "$input" =~ ^[0-9]+$ ]] && [ "$input" -ge "$min" ] && [ "$input" -le "$max" ]; then
        return 0
    else
        return 1
    fi
}

# Function to force-reload the PHP binary in the current session
function force_reload_php {
    local version="$1"
    local php_bin_path=""
    
    if [ "$version" = "php@default" ]; then
        php_bin_path="$HOMEBREW_PREFIX/opt/php/bin"
    else
        php_bin_path="$HOMEBREW_PREFIX/opt/$version/bin"
    fi
    
    # Add the PHP bin directory to the start of the PATH
    if [ -d "$php_bin_path" ]; then
        export PATH="$php_bin_path:$PATH"
        
        # Force the shell to forget previous command locations
        hash -r 2>/dev/null || rehash 2>/dev/null || true
        
        return 0
    else
        return 1
    fi
}

# Function to manage PHP extensions
function manage_extensions {
    local php_version="$1"
    local service_name=$(get_service_name "$php_version")
    
    # Extract the numeric version from php@X.Y
    local numeric_version
    if [ "$php_version" = "php@default" ]; then
        numeric_version=$(php -v | head -n 1 | cut -d " " -f 2 | cut -d "." -f 1,2)
    else
        numeric_version=$(echo "$php_version" | grep -o "[0-9]\.[0-9]")
    fi
    
    # Determine the PHP ini directory
    local ini_dir
    if [ "$php_version" = "php@default" ]; then
        ini_dir="$HOMEBREW_PREFIX/etc/php"
    else
        ini_dir="$HOMEBREW_PREFIX/etc/php/$numeric_version"
    fi
    
    show_status "info" "PHP Extensions for $php_version (version $numeric_version):"
    echo ""
    
    # List installed extensions
    echo "Currently loaded extensions:"
    php -m | sort | grep -v "\[" | sed 's/^/- /'
    
    echo ""
    echo "Extension configuration files:"
    
    if [ -d "$ini_dir" ]; then
        if [ -d "$ini_dir/conf.d" ]; then
            ls -1 "$ini_dir/conf.d" | grep -i "\.ini$" | sed 's/^/- /'
        else
            echo "No conf.d directory found at $ini_dir/conf.d"
        fi
    else
        echo "No configuration directory found at $ini_dir"
    fi
    
    echo ""
    echo "Options:"
    echo "1) Enable/disable an extension"
    echo "2) Edit php.ini"
    echo "3) Show detailed extension information"
    echo "0) Back to main menu"
    echo ""
    echo -n "Please select an option (0-3): "
    
    local option
    read -r option
    
    case $option in
        1)
            echo -n "Enter extension name: "
            read -r ext_name
            if [ -n "$ext_name" ]; then
                echo "Select action for $ext_name:"
                echo "1) Enable extension"
                echo "2) Disable extension"
                echo -n "Select (1-2): "
                
                local ext_action
                read -r ext_action
                
                if [ "$ext_action" = "1" ]; then
                    show_status "info" "Enabling $ext_name..."
                    # Check if extension exists
                    if php -m | grep -q -i "^$ext_name$"; then
                        show_status "info" "Extension $ext_name is already enabled"
                    else
                        # Try to enable via Homebrew
                        if brew install "$php_version-$ext_name" 2>/dev/null; then
                            show_status "success" "Extension $ext_name installed via Homebrew"
                            restart_php_fpm "$php_version"
                        else
                            show_status "warning" "Could not install via Homebrew, trying PECL..."
                            if pecl install "$ext_name"; then
                                show_status "success" "Extension $ext_name installed via PECL"
                                restart_php_fpm "$php_version"
                            else
                                show_status "error" "Failed to enable $ext_name"
                            fi
                        fi
                    fi
                elif [ "$ext_action" = "2" ]; then
                    show_status "info" "Disabling $ext_name..."
                    if [ -f "$ini_dir/conf.d/ext-$ext_name.ini" ]; then
                        sudo mv "$ini_dir/conf.d/ext-$ext_name.ini" "$ini_dir/conf.d/ext-$ext_name.ini.disabled"
                        show_status "success" "Extension $ext_name disabled"
                        restart_php_fpm "$php_version"
                    elif [ -f "$ini_dir/conf.d/$ext_name.ini" ]; then
                        sudo mv "$ini_dir/conf.d/$ext_name.ini" "$ini_dir/conf.d/$ext_name.ini.disabled"
                        show_status "success" "Extension $ext_name disabled"
                        restart_php_fpm "$php_version"
                    else
                        show_status "error" "Could not find configuration file for $ext_name"
                    fi
                fi
            fi
            ;;
        2)
            # Find and edit php.ini
            local php_ini="$ini_dir/php.ini"
            if [ -f "$php_ini" ]; then
                show_status "info" "Opening php.ini for $php_version..."
                if [ -n "$EDITOR" ]; then
                    $EDITOR "$php_ini"
                else
                    nano "$php_ini"
                fi
                
                show_status "info" "php.ini edited. Restart PHP-FPM to apply changes"
                echo -n "Would you like to restart PHP-FPM now? (y/n): "
                if [ "$(validate_yes_no "Restart PHP-FPM?" "y")" = "y" ]; then
                    restart_php_fpm "$php_version"
                fi
            else
                show_status "error" "php.ini not found at $php_ini"
            fi
            ;;
        3)
            echo -n "Enter extension name (or leave blank for all): "
            read -r ext_detail
            if [ -n "$ext_detail" ]; then
                php -i | grep -i "$ext_detail" | less
            else
                php -i | less
            fi
            ;;
        0)
            return 0
            ;;
        *)
            show_status "error" "Invalid option"
            ;;
    esac
    
    # Allow user to perform another extension management action
    echo ""
    echo -n "Would you like to perform another extension management action? (y/n): "
    if [ "$(validate_yes_no "Another action?" "y")" = "y" ]; then
        manage_extensions "$php_version"
    fi
}

# Function to check for updates from GitHub
function check_for_updates {
    show_status "info" "Checking for updates..."
    
    # Get the current version timestamp from the script
    CURRENT_VERSION=$(grep -o "# Version: [0-9.]\+" "$0" | head -n 1 | cut -d' ' -f3)
    
    # If no version found, add it to the script
    if [ -z "$CURRENT_VERSION" ]; then
        CURRENT_VERSION="1.0.0"
        sed -i '' "1s/^/# Version: $CURRENT_VERSION\n/" "$0"
    fi
    
    # Download the latest version from GitHub
    TEMP_FILE=$(mktemp)
    if curl -s "https://raw.githubusercontent.com/NavanithanS/phpswitch/main/php-switcher.sh" -o "$TEMP_FILE"; then
        REMOTE_VERSION=$(grep -o "# Version: [0-9.]\+" "$TEMP_FILE" | head -n 1 | cut -d' ' -f3)
        
        if [ -n "$REMOTE_VERSION" ] && [ "$REMOTE_VERSION" != "$CURRENT_VERSION" ]; then
            show_status "info" "New version available: $REMOTE_VERSION (current: $CURRENT_VERSION)"
            echo -n "Would you like to update? (y/n): "
            
            if [ "$(validate_yes_no "Update?" "y")" = "y" ]; then
                show_status "info" "Updating phpswitch..."
                if [ -w "$0" ]; then
                    cp "$TEMP_FILE" "$0"
                    chmod +x "$0"
                    show_status "success" "Updated to version $REMOTE_VERSION"
                    echo "Please run phpswitch again to use the new version"
                    exit 0
                else
                    show_status "error" "Cannot update - no write permission to $0"
                    echo "Try running with sudo: sudo phpswitch --update"
                fi
            fi
        else
            show_status "success" "You are using the latest version ($CURRENT_VERSION)"
        fi
    else
        show_status "error" "Failed to check for updates"
    fi
    
    rm -f "$TEMP_FILE"
}

# Optimized show_menu function with concurrent operations
function show_menu {
    echo "PHPSwitch - PHP Version Manager for macOS"
    echo "========================================"
    
    # Start fetching available PHP versions in the background immediately
    # This helps overlap I/O operations and improve perceived performance
    available_versions_file=$(mktemp)
    get_available_php_versions > "$available_versions_file" &
    fetch_pid=$!
    
    # Get current PHP version
    current_version=$(get_current_php_version)
    show_status "info" "Current PHP version: $current_version"
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
    done < <(get_installed_php_versions)
    
    if [ ${#versions[@]} -eq 0 ]; then
        show_status "warning" "No PHP versions found installed via Homebrew"
        echo "Let's check available PHP versions to install..."
    fi
    
    # By this time, our background fetch might already be done or close to done
    echo ""
    
    # Check if the background fetch is still running
    if kill -0 $fetch_pid 2>/dev/null; then
        show_status "info" "Checking for available PHP versions to install..."
        
        # Show progress while waiting for the fetch to complete
        show_progress "Searching for available PHP versions" &
        progress_pid=$!
        
        # Associate progress display with the fetch process
        disown $progress_pid
        
        # Wait for the fetch to complete
        wait $fetch_pid
        
        # Stop the progress display
        kill $progress_pid 2>/dev/null
        wait $progress_pid 2>/dev/null
        
        # Clear the line
        printf "\r%-50s\r" " "
    fi
    
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
        show_status "error" "No PHP versions found available via Homebrew"
        exit 1
    fi
    
    local max_option=$((i-1))
    
    echo ""
    echo "u) Uninstall a PHP version"
    echo "e) Manage PHP extensions"
    echo "c) Configure PHPSwitch"
    echo "0) Exit without changes"
    echo ""
    echo -n "Please select PHP version to use (0-$max_option, u, e, c): "
    
    local selection
    local valid_selection=false
    
    while [ "$valid_selection" = "false" ]; do
        read -r selection
        
        if [ "$selection" = "0" ]; then
            show_status "info" "Exiting without changes"
            exit 0
        elif [ "$selection" = "u" ]; then
            valid_selection=true
            show_uninstall_menu
            return $?
        elif [ "$selection" = "e" ]; then
            valid_selection=true
            if [ "$current_version" = "none" ]; then
                show_status "error" "No active PHP version detected"
                return 1
            else
                manage_extensions "$current_version"
                # Return to main menu after extension management
                show_menu
                return $?
            fi
        elif [ "$selection" = "c" ]; then
            valid_selection=true
            configure_phpswitch
            # Return to main menu after configuration
            show_menu
            return $?
        elif validate_numeric_input "$selection" 1 $max_option; then
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
            show_status "info" "You selected: $selected_version"
            switch_php "$selected_version" "$selected_is_installed"
            return $?
        else
            echo -n "Invalid selection. Please enter a number between 0 and $max_option, or 'u', 'e', 'c': "
        fi
    done
}

# Function to configure PHPSwitch
function configure_phpswitch {
    echo "PHPSwitch Configuration"
    echo "======================="
    
    # Create config file if it doesn't exist
    if [ ! -f "$HOME/.phpswitch.conf" ]; then
        create_default_config
    fi
    
    # Load current config
    load_config
    
    echo "Current Configuration:"
    echo "1) Auto restart PHP-FPM: $AUTO_RESTART_PHP_FPM"
    echo "2) Backup config files: $BACKUP_CONFIG_FILES"
    echo "3) Default PHP version: ${DEFAULT_PHP_VERSION:-None}"
    echo "0) Return to main menu"
    echo ""
    echo -n "Select setting to change (0-3): "
    
    local option
    read -r option
    
    case $option in
        1)
            echo -n "Auto restart PHP-FPM when switching versions? (y/n): "
            if [ "$(validate_yes_no "Auto restart?" "$AUTO_RESTART_PHP_FPM")" = "y" ]; then
                AUTO_RESTART_PHP_FPM=true
            else
                AUTO_RESTART_PHP_FPM=false
            fi
            ;;
        2)
            echo -n "Create backups of configuration files before modifying? (y/n): "
            if [ "$(validate_yes_no "Backup files?" "$BACKUP_CONFIG_FILES")" = "y" ]; then
                BACKUP_CONFIG_FILES=true
            else
                BACKUP_CONFIG_FILES=false
            fi
            ;;
        3)
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
            done < <(get_installed_php_versions)
            
            echo -n "Select default PHP version (1-$i): "
            local ver_selection
            read -r ver_selection
            
            if validate_numeric_input "$ver_selection" 1 $i; then
                if [ "$ver_selection" = "1" ]; then
                    DEFAULT_PHP_VERSION=""
                else
                    DEFAULT_PHP_VERSION="${versions[$((ver_selection-2))]}"
                fi
            else
                show_status "error" "Invalid selection"
            fi
            ;;
        0)
            return 0
            ;;
        *)
            show_status "error" "Invalid option"
            ;;
    esac
    
    # Save the configuration
    cat > "$HOME/.phpswitch.conf" <<EOL
# PHPSwitch Configuration
AUTO_RESTART_PHP_FPM=$AUTO_RESTART_PHP_FPM
BACKUP_CONFIG_FILES=$BACKUP_CONFIG_FILES
DEFAULT_PHP_VERSION="$DEFAULT_PHP_VERSION"
EOL
    
    show_status "success" "Configuration updated"
    
    # Offer to return to configuration menu
    echo -n "Would you like to make additional configuration changes? (y/n): "
    if [ "$(validate_yes_no "More changes?" "y")" = "y" ]; then
        configure_phpswitch
    fi
}

# Function to show uninstall menu
function show_uninstall_menu {
    echo "PHP Version Uninstaller"
    echo "======================="
    
    # Get current PHP version
    current_version=$(get_current_php_version)
    show_status "info" "Current PHP version: $current_version"
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
    done < <(get_installed_php_versions)
    
    if [ ${#versions[@]} -eq 0 ]; then
        show_status "error" "No PHP versions found installed via Homebrew"
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
        elif validate_numeric_input "$selection" 1 $max_option; then
            valid_selection=true
            selected_version="${versions[$((selection-1))]}"
            show_status "info" "You selected to uninstall: $selected_version"
            
            # Uninstall the selected PHP version
            uninstall_php "$selected_version"
            uninstall_status=$?
            
            if [ $uninstall_status -eq 2 ]; then
                # User chose to switch to another version after uninstall
                show_menu
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

# Function to install as a system command
function install_as_command {
    local destination="/usr/local/bin/phpswitch"
    local alt_destination="$HOMEBREW_PREFIX/bin/phpswitch"
    
    # Check if /usr/local/bin exists, if not try Homebrew bin
    if [ ! -d "/usr/local/bin" ]; then
        if [ -d "$HOMEBREW_PREFIX/bin" ]; then
            show_status "info" "Using $HOMEBREW_PREFIX/bin directory..."
            destination=$alt_destination
        else
            show_status "info" "Creating /usr/local/bin directory..."
            sudo mkdir -p "/usr/local/bin"
        fi
    fi
    
    show_status "info" "Installing phpswitch command to $destination..."
    
    # Copy this script to the destination
    if sudo cp "$0" "$destination"; then
        sudo chmod +x "$destination"
        show_status "success" "Installation successful! You can now run 'phpswitch' from anywhere"
    else
        show_status "error" "Failed to install. Try running with sudo"
        return 1
    fi
}

# Function to uninstall the system command
function uninstall_command {
    local installed_locations=()
    
    # Check common installation locations
    if [ -f "/usr/local/bin/phpswitch" ]; then
        installed_locations+=("/usr/local/bin/phpswitch")
    fi
    
    if [ -f "$HOMEBREW_PREFIX/bin/phpswitch" ]; then
        installed_locations+=("$HOMEBREW_PREFIX/bin/phpswitch")
    fi
    
    if [ ${#installed_locations[@]} -eq 0 ]; then
        show_status "error" "phpswitch is not installed as a system command"
        return 1
    fi
    
    show_status "info" "Found phpswitch installed at:"
    for location in "${installed_locations[@]}"; do
        echo "  - $location"
    done
    
    echo -n "Are you sure you want to uninstall phpswitch? (y/n): "
    
    if [ "$(validate_yes_no "Uninstall phpswitch?" "n")" = "y" ]; then
        for location in "${installed_locations[@]}"; do
            show_status "info" "Removing $location..."
            sudo rm "$location"
        done
        
        # Ask about config file
        if [ -f "$HOME/.phpswitch.conf" ]; then
            echo -n "Would you like to remove the configuration file ~/.phpswitch.conf as well? (y/n): "
            if [ "$(validate_yes_no "Remove config?" "n")" = "y" ]; then
                rm "$HOME/.phpswitch.conf"
                show_status "success" "Configuration file removed"
            fi
        fi
        
        show_status "success" "phpswitch has been uninstalled successfully"
    else
        show_status "info" "Uninstallation cancelled"
    fi
}

# Main script logic
# Load configuration
load_config

# Parse command-line arguments
if [ "$1" = "--install" ]; then
    install_as_command
    exit 0
elif [ "$1" = "--uninstall" ]; then
    uninstall_command
    exit 0
elif [ "$1" = "--update" ]; then
    check_for_updates
    exit 0
elif [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "PHPSwitch - PHP Version Manager for macOS"
    echo "========================================"
    echo "Usage:"
    echo "  phpswitch                   - Run the interactive menu to switch PHP versions"
    echo "  phpswitch --install         - Install phpswitch as a system command"
    echo "  phpswitch --uninstall       - Remove phpswitch from your system"
    echo "  phpswitch --update          - Check for and install updates"
    echo "  phpswitch --debug           - Run with debug logging enabled"
    echo "  phpswitch --help, -h        - Display this help message"
    exit 0
else
    # No arguments or debug mode only - show the interactive menu
    
    # If default version is set and current version is different, offer to switch
    if [ -n "$DEFAULT_PHP_VERSION" ] && [ "$current_version" != "$DEFAULT_PHP_VERSION" ] && [ "$(get_current_php_version)" != "$DEFAULT_PHP_VERSION" ]; then
        echo "Default PHP version ($DEFAULT_PHP_VERSION) is different from current version ($(get_current_php_version))"
        echo -n "Would you like to switch to the default version? (y/n): "
        if [ "$(validate_yes_no "Switch to default?" "y")" = "y" ]; then
            if check_php_installed "$DEFAULT_PHP_VERSION"; then
                switch_php "$DEFAULT_PHP_VERSION" "true"
                exit 0
            else
                show_status "error" "Default PHP version ($DEFAULT_PHP_VERSION) is not installed"
            fi
        fi
    fi
    
    show_menu
    
    # Print current PHP version at the end to confirm
    echo ""
    show_status "info" "Current PHP configuration:"
    echo ""
    php -v
fi

exit 0
