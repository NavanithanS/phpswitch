#!/bin/bash

# Version: 1.2.1
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
    MAX_BACKUPS=5
    
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
MAX_BACKUPS=5
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

# Function to cleanup old backup files
function cleanup_backups {
    local file_prefix="$1"
    local max_backups="${MAX_BACKUPS:-5}"
    
    # List backup files sorted by modification time (oldest first)
    for old_backup in $(ls -t "${file_prefix}.bak."* 2>/dev/null | tail -n +$((max_backups+1))); do
        debug_log "Removing old backup: $old_backup"
        rm -f "$old_backup"
    done
}

# Function to get all installed PHP versions
function get_installed_php_versions {
    # Get both php@X.Y versions and the default php (which could be the latest version)
    { brew list | grep "^php@" || true; brew list | grep "^php$" | sed 's/php/php@default/g' || true; } | sort
}

# Function to get all available PHP versions from Homebrew with caching
function get_available_php_versions {
    local cache_file="/tmp/phpswitch_available_versions.cache"
    local cache_timeout=3600  # Cache expires after 1 hour (in seconds)
    
    # Check if cache exists and is recent
    if [ -f "$cache_file" ] && [ $(($(date +%s) - $(stat -f %m "$cache_file"))) -lt "$cache_timeout" ]; then
        debug_log "Using cached available PHP versions"
        cat "$cache_file"
        return
    fi
    
    # Create a fallback for slow or failed brew searches
    echo "php@7.4" > "$cache_file.tmp"
    echo "php@8.0" >> "$cache_file.tmp"
    echo "php@8.1" >> "$cache_file.tmp" 
    echo "php@8.2" >> "$cache_file.tmp"
    echo "php@8.3" >> "$cache_file.tmp"
    
    # Try to get actual versions with a timeout
    (
        # Run brew search with a timeout
        (brew search /php@[0-9]/ | grep '^php@' > "$cache_file.search1"; brew search /^php$/ | grep '^php$' | sed 's/php/php@default/g' > "$cache_file.search2") & 
        brew_pid=$!
        
        # Wait for up to 10 seconds
        for i in {1..10}; do
            if ! kill -0 $brew_pid 2>/dev/null; then
                # Command completed
                break
            fi
            sleep 1
        done
        
        # Kill if still running
        if kill -0 $brew_pid 2>/dev/null; then
            kill $brew_pid 2>/dev/null
            wait $brew_pid 2>/dev/null || true
            echo "Brew search took too long, using cached values" >&2
        else
            # Command finished, combine results
            if [ -s "$cache_file.search1" ] || [ -s "$cache_file.search2" ]; then
                cat "$cache_file.search1" "$cache_file.search2" | sort > "$cache_file"
                rm -f "$cache_file.tmp"
            else
                # If results are empty, use the fallback
                mv "$cache_file.tmp" "$cache_file"
            fi
        fi
        
        # Clean up temp files
        rm -f "$cache_file.search1" "$cache_file.search2" "$cache_file.tmp"
    ) &
    
    # Wait for the background process
    wait
    
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

# Function to get the actual PHP version currently being used
function get_active_php_version {
    which_php=$(which php 2>/dev/null)
    debug_log "PHP binary: $which_php"
    
    if [ -n "$which_php" ]; then
        php_version=$($which_php -v 2>/dev/null | head -n 1 | cut -d " " -f 2)
        debug_log "PHP version: $php_version"
        echo "$php_version"
    else
        echo "none"
    fi
}

# Function to check for conflicting PHP installations
function check_php_conflicts {
    # Find all PHP binaries in the PATH
    IFS=:
    for dir in $PATH; do
        if [ -x "$dir/php" ]; then
            echo "Found PHP binary at: $dir/php"
            "$dir/php" -v | head -n 1
        fi
    done
    unset IFS
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

# Function to handle PHP version for commands (handles default php)
function get_service_name {
    local version="$1"
    
    if [ "$version" = "php@default" ]; then
        echo "php"
    else
        echo "$version"
    fi
}

# Function to stop all other PHP-FPM services except the active one
function stop_other_php_services {
    local active_version="$1"
    local active_service=$(get_service_name "$active_version")
    
    # Get all running PHP services
    local running_services=$(brew services list | grep -E "^php(@[0-9]\.[0-9])?" | awk '{print $1}')
    
    for service in $running_services; do
        if [ "$service" != "$active_service" ]; then
            show_status "info" "Stopping PHP-FPM service for $service..."
            brew services stop "$service" >/dev/null 2>&1
        fi
    done
}

# Function to restart PHP-FPM service
function restart_php_fpm {
    local version="$1"
    local service_name=$(get_service_name "$version")
    
    if [ "$AUTO_RESTART_PHP_FPM" != "true" ]; then
        debug_log "Auto restart PHP-FPM is disabled in config"
        return 0
    fi
    
    # First, stop all other PHP-FPM services
    stop_other_php_services "$version"
    
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
    
    # Determine shell config file
    case "$shell_type" in
        "zsh")
            rc_file="$HOME/.zshrc"
            ;;
        "bash")
            rc_file="$HOME/.bashrc"
            # If bashrc doesn't exist, check for bash_profile
            if [ ! -f "$rc_file" ]; then
                rc_file="$HOME/.bash_profile"
            fi
            # If neither exists, check for profile
            if [ ! -f "$rc_file" ]; then
                rc_file="$HOME/.profile"
            fi
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
    
    # Function to update a single shell config file
    function update_single_rc_file {
        local file="$1"
        
        # Check if file exists
        if [ ! -f "$file" ]; then
            show_status "info" "$file does not exist. Creating it..."
            touch "$file"
        fi
        
        # Check if we have write permissions
        if [ ! -w "$file" ]; then
            show_status "error" "No write permission for $file"
            exit 1
        fi
        
        # Create backup (only if enabled)
        if [ "$BACKUP_CONFIG_FILES" = "true" ]; then
            local backup_file="${file}.bak.$(date +%Y%m%d%H%M%S)"
            cp "$file" "$backup_file"
            show_status "info" "Created backup at ${backup_file}"
            
            # Clean up old backups
            cleanup_backups "$file"
        fi
        
        show_status "info" "Updating PATH in $file..."
        
        # Remove old PHP paths from PATH variable
        # First, comment out all PHP PATH entries
        sed -i '' 's|^export PATH=".*opt/homebrew/opt/php@[0-9]\.[0-9]/bin:\$PATH"|#&|' "$file"
        sed -i '' 's|^export PATH=".*opt/homebrew/opt/php@[0-9]\.[0-9]/sbin:\$PATH"|#&|' "$file"
        sed -i '' 's|^export PATH=".*opt/homebrew/opt/php/bin:\$PATH"|#&|' "$file"
        sed -i '' 's|^export PATH=".*opt/homebrew/opt/php/sbin:\$PATH"|#&|' "$file"
        sed -i '' 's|^export PATH=".*usr/local/opt/php@[0-9]\.[0-9]/bin:\$PATH"|#&|' "$file"
        sed -i '' 's|^export PATH=".*usr/local/opt/php@[0-9]\.[0-9]/sbin:\$PATH"|#&|' "$file"
        sed -i '' 's|^export PATH=".*usr/local/opt/php/bin:\$PATH"|#&|' "$file"
        sed -i '' 's|^export PATH=".*usr/local/opt/php/sbin:\$PATH"|#&|' "$file"
        
        # Remove our added "force path reload" section if it exists
        sed -i '' '/# Added by phpswitch script - force path reload/,+5d' "$file"
        
        # Clean up any empty lines at the end
        sed -i '' -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$file"
        
        # Add the new PHP PATH entries at the top of the file to ensure they take precedence
        # Create a temporary file
        temp_file=$(mktemp)
        
        # Write PHP paths to the temporary file
        cat > "$temp_file" << EOL
# PHP version paths - Added by phpswitch
export PATH="$php_bin_path:$php_sbin_path:\$PATH"

EOL
        
        # Concatenate the original file to the temporary file
        cat "$file" >> "$temp_file"
        
        # Move the temporary file back to the original
        mv "$temp_file" "$file"
        
        show_status "success" "Updated PATH in $file for $new_version"
    }
    
    # Update only the appropriate RC file for the current shell
    update_single_rc_file "$rc_file"
    
    # Check for any other potential conflicting PATH settings
    for file in "$HOME/.path" "$HOME/.config/fish/config.fish"; do
        if [ -f "$file" ] && [ "$file" != "$rc_file" ]; then
            if grep -q "PATH.*php" "$file"; then
                show_status "warning" "Found PHP PATH settings in $file that might conflict"
                echo -n "Would you like to update this file too? (y/n): "
                
                if [ "$(validate_yes_no "Update this file?" "y")" = "y" ]; then
                    update_single_rc_file "$file"
                else
                    show_status "warning" "Skipping $file - this might cause version conflicts"
                fi
            fi
        fi
    done
}

# Function to force-reload the PHP binary in the current session
function force_reload_php {
    local version="$1"
    local php_bin_path=""
    local php_sbin_path=""
    
    if [ "$version" = "php@default" ]; then
        php_bin_path="$HOMEBREW_PREFIX/opt/php/bin"
        php_sbin_path="$HOMEBREW_PREFIX/opt/php/sbin"
    else
        php_bin_path="$HOMEBREW_PREFIX/opt/$version/bin"
        php_sbin_path="$HOMEBREW_PREFIX/opt/$version/sbin"
    fi
    
    debug_log "Before PATH update: $PATH"
    
    # First, remove any existing PHP paths from the PATH
    # We need to use a temporary variable to avoid modifying PATH while iterating
    local new_path=""
    IFS=:
    for path_component in $PATH; do
        if ! echo "$path_component" | grep -q "php"; then
            if [ -z "$new_path" ]; then
                new_path="$path_component"
            else
                new_path="$new_path:$path_component"
            fi
        fi
    done
    unset IFS
    
    # Now add the new PHP bin and sbin directories to the start of the PATH
    if [ -d "$php_bin_path" ] && [ -d "$php_sbin_path" ]; then
        export PATH="$php_bin_path:$php_sbin_path:$new_path"
        debug_log "After PATH update: $PATH"
        
        # Force the shell to forget previous command locations
        hash -r 2>/dev/null || rehash 2>/dev/null || true
        
        # Verify the PHP binary now in use
        debug_log "PHP now resolves to: $(which php)"
        debug_log "PHP version now: $(php -v | head -n 1)"
        
        return 0
    else
        show_status "error" "PHP binary directories not found at $php_bin_path or $php_sbin_path"
        return 1
    fi
}

# Function to properly handle the default PHP and versioned PHP
function resolve_php_version {
    local version="$1"
    
    # Handle the case where php@8.4 is actually the default php
    if [ "$version" = "php@8.4" ] && [ ! -d "$HOMEBREW_PREFIX/opt/php@8.4" ] && [ -d "$HOMEBREW_PREFIX/opt/php" ]; then
        local default_version=$(php -v 2>/dev/null | head -n 1 | cut -d " " -f 2 | cut -d "." -f 1,2)
        if [ "$default_version" = "8.4" ]; then
            echo "php@default"
            return
        fi
    fi
    
    # Return the original version
    echo "$version"
}

# Function to switch PHP version
function switch_php {
    local new_version="$1"
    local is_installed="$2"
    local current_version=$(get_current_php_version)
    
    # Resolve potential version confusion (php@8.4 vs php@default)
    new_version=$(resolve_php_version "$new_version")
    
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
        
        # Check for any conflicting PHP installations
        check_php_conflicts
        
        # Unlink current PHP (if any)
        if [ "$current_version" != "none" ]; then
            show_status "info" "Unlinking $current_version..."
            brew unlink "$current_version" 2>/dev/null
        fi
        
        # Link new PHP with progressive fallback strategies
        show_status "info" "Linking $new_version..."
        
        # Strategy 1: Normal linking
        if brew link --force "$brew_version" 2>/dev/null; then
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
                        sudo ln -sf "$file" "$HOMEBREW_PREFIX/bin/$filename" 2>/dev/null
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
    
    # Try to apply changes to the current shell
    if [ -z "$SOURCED" ]; then
        export SOURCED=true
        show_status "info" "Applying changes to current shell..."
        
        # Directly modify the PATH to ensure the changes take effect immediately
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
            
            # Make sure to inform the user how to activate in new shells
            echo ""
            echo "To ensure this change persists in new shell sessions:"
            echo "1. Open a new terminal window/tab"
            echo "2. Or run: source ~/.zshrc (or your appropriate shell config file)"
            echo ""
            show_status "info" "You can verify the change with: php -v"
        else
            show_status "warning" "PHP version switch was not fully applied to the current shell"
            echo "Current PHP version is still: $(php -v | head -n 1)"
            echo ""
            shell_type=$(detect_shell)
            if [ "$shell_type" = "zsh" ]; then
                echo "To activate the new PHP version in your current shell, run:"
                echo "source ~/.zshrc"
            elif [ "$shell_type" = "bash" ]; then
                echo "To activate the new PHP version in your current shell, run:"
                echo "source ~/.bashrc"
            else
                echo "To activate the new PHP version in your current shell, run:"
                echo "export PATH=\"$php_bin_path:$php_sbin_path:\$PATH\""
            fi
            echo ""
            echo "Or start a new terminal session to use the new PHP version."
        fi
    else
        shell_type=$(detect_shell)
        if [ "$shell_type" = "zsh" ]; then
            show_status "info" "Please run 'source ~/.zshrc' to apply the changes to your current terminal"
        elif [ "$shell_type" = "bash" ]; then
            show_status "info" "Please run 'source ~/.bashrc' to apply the changes to your current terminal"
        else
            show_status "info" "Please run 'source ~/.profile' to apply the changes to your current terminal"
        fi
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

# Optimized show_menu function with concurrent operations
function show_menu {
    echo "PHPSwitch - PHP Version Manager for macOS"
    echo "========================================"
    
    # Start fetching available PHP versions in the background immediately
    available_versions_file=$(mktemp)
    get_available_php_versions > "$available_versions_file" &
    
    # Get current PHP version
    current_version=$(get_current_php_version)
    show_status "info" "Current PHP version: $current_version"
    
    # Show actual PHP version being used currently (may differ from Homebrew's linked version)
    active_version=$(get_active_php_version)
    if [ "$active_version" != "none" ]; then
        php_path=$(which php)
        if [ -L "$php_path" ]; then
            # If it's a symlink, show what it points to
            real_path=$(readlink "$php_path")
            show_status "info" "Active PHP is: $active_version (symlinked from $real_path)"
        else
            show_status "info" "Active PHP is: $active_version (from $php_path)"
        fi
        
        # Alert if there's a mismatch
        if [[ $current_version == php@* ]] && [[ $active_version != *$(echo "$current_version" | grep -o "[0-9]\.[0-9]")* ]]; then
            show_status "warning" "Version mismatch: Active PHP ($active_version) does not match Homebrew-linked version"
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
    done < <(get_installed_php_versions)
    
    if [ ${#versions[@]} -eq 0 ]; then
        show_status "warning" "No PHP versions found installed via Homebrew"
        echo "Let's check available PHP versions to install..."
    fi
    
    echo ""
    show_status "info" "Checking for available PHP versions to install..."
    
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
        show_status "error" "No PHP versions found available via Homebrew"
        exit 1
    fi
    
    local max_option=$((i-1))
    
    echo ""
    echo "u) Uninstall a PHP version"
    echo "e) Manage PHP extensions"
    echo "c) Configure PHPSwitch"
    echo "d) Diagnose PHP environment"
    echo "0) Exit without changes"
    echo ""
    echo -n "Please select PHP version to use (0-$max_option, u, e, c, d): "
    
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
        elif [ "$selection" = "d" ]; then
            valid_selection=true
            diagnose_php_environment
            # Return to main menu after diagnostics
            echo ""
            echo -n "Press Enter to continue..."
            read -r
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
            echo -n "Invalid selection. Please enter a number between 0 and $max_option, or 'u', 'e', 'c', 'd': "
        fi
    done
}

# Function to diagnose the PHP environment
function diagnose_php_environment {
    echo "PHP Environment Diagnostic"
    echo "=========================="
    
    # 1. Check all PHP binaries
    echo "PHP Binaries:"
    echo "-------------"
    if command -v php &>/dev/null; then
        php_path=$(which php)
        echo "Default PHP: $php_path"
        if [ -L "$php_path" ]; then
            real_path=$(readlink "$php_path")
            echo "  → Symlinked to: $real_path"
        fi
        echo "  Version: $(php -v | head -n 1)"
    else
        echo "No PHP binary found in PATH"
    fi
    echo ""
    
    # 2. Check all installed PHP versions
    echo "Installed PHP Versions:"
    echo "----------------------"
    installed_versions=$(get_installed_php_versions)
    if [ -n "$installed_versions" ]; then
        echo "$installed_versions"
    else
        echo "No PHP versions installed via Homebrew"
    fi
    echo ""
    
    # 3. Check Homebrew PHP links
    echo "Homebrew PHP Links:"
    echo "------------------"
    if [ -d "$HOMEBREW_PREFIX/opt" ]; then
        ls -la "$HOMEBREW_PREFIX/opt" | grep "php"
    else
        echo "No Homebrew opt directory found"
    fi
    echo ""
    
    # 4. Check for conflicting PHP binaries
    echo "PHP in PATH:"
    echo "-----------"
    IFS=:
    for dir in $PATH; do
        if [ -x "$dir/php" ]; then
            echo "Found in: $dir/php"
            echo "  Version: $($dir/php -v 2>/dev/null | head -n 1 || echo "Could not determine version")"
            echo "  Type: $(if [ -L "$dir/php" ]; then echo "Symlink → $(readlink "$dir/php")"; else echo "Direct binary"; fi)"
        fi
    done
    unset IFS
    echo ""
    
    # 5. Check shell config files for PHP path entries
    echo "Shell Configuration Files:"
    echo "-------------------------"
    shell_type=$(detect_shell)
    if [ "$shell_type" = "zsh" ]; then
        config_files=("$HOME/.zshrc" "$HOME/.zprofile")
    elif [ "$shell_type" = "bash" ]; then
        config_files=("$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile")
    else
        config_files=("$HOME/.profile")
    fi
    
    for file in "${config_files[@]}"; do
        if [ -f "$file" ]; then
            echo "Checking $file:"
            grep -n "PATH.*php" "$file" || echo "  No PHP PATH entries found"
        fi
    done
    echo ""
    
    # 6. Check PHP modules
    echo "Loaded PHP Modules:"
    echo "------------------"
    if command -v php &>/dev/null; then
        php -m | grep -v "\[" | sort | head -n 20
        module_count=$(php -m | grep -v "\[" | wc -l)
        if [ "$module_count" -gt 20 ]; then
            echo "...and $(($module_count - 20)) more modules"
        fi
    else
        echo "No PHP binary found to check modules"
    fi
    echo ""
    
    # 7. Check running PHP-FPM services
    echo "Running PHP-FPM Services:"
    echo "-------------------------"
    brew services list | grep -E "^php(@[0-9]\.[0-9])?" || echo "  No PHP services found"
    echo ""
    
    # 8. Summary and recommendations
    echo "Diagnostic Summary:"
    echo "------------------"
    if command -v php &>/dev/null; then
        php_version=$(php -v | head -n 1 | cut -d " " -f 2)
        homebrew_linked=$(get_current_php_version)
        
        if [[ $homebrew_linked == php@* ]] && [[ $php_version != *$(echo "$homebrew_linked" | grep -o "[0-9]\.[0-9]")* ]]; then
            show_status "warning" "Version mismatch detected"
            echo "  The PHP version in use ($php_version) does not match the Homebrew-linked version ($homebrew_linked)"
            echo ""
            echo "Possible causes:"
            echo "  1. Another PHP binary is taking precedence in your PATH"
            echo "  2. Shell configuration files need to be updated or sourced"
            echo "  3. The PHP binary might be a direct install or from another package manager"
            echo ""
            echo "Recommended actions:"
            shell_type=$(detect_shell)
            if [ "$shell_type" = "zsh" ]; then
                echo "  1. Try running: source ~/.zshrc"
                echo "  2. Or open a new terminal window"
            elif [ "$shell_type" = "bash" ]; then
                echo "  1. Try running: source ~/.bashrc"
                echo "  2. Or open a new terminal window"
            else
                echo "  1. Try running: source ~/.profile"
                echo "  2. Or open a new terminal window"
            fi
            echo "  3. Consider removing or renaming conflicting PHP binaries"
        else
            show_status "success" "PHP environment looks healthy"
            echo "  Current PHP version: $php_version"
            echo "  Homebrew-linked version: $homebrew_linked"
        fi
    else
        show_status "error" "No PHP binary found in PATH"
        echo "  Check your Homebrew installation and PATH environment variable"
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
    echo "3) Maximum backups to keep: ${MAX_BACKUPS:-5}"
    echo "4) Default PHP version: ${DEFAULT_PHP_VERSION:-None}"
    echo "0) Return to main menu"
    echo ""
    echo -n "Select setting to change (0-4): "
    
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
            echo -n "Enter maximum number of backups to keep (1-20): "
            read -r max_backups
            if [[ "$max_backups" =~ ^[0-9]+$ ]] && [ "$max_backups" -ge 1 ] && [ "$max_backups" -le 20 ]; then
                MAX_BACKUPS="$max_backups"
            else
                show_status "error" "Invalid value. Using default (5)"
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
MAX_BACKUPS=$MAX_BACKUPS
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

# Function to update self from GitHub
function update_self {
    show_status "info" "Checking for updates..."
    
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
                show_status "info" "New version available: $new_version (current: $current_version)"
                echo -n "Would you like to update? (y/n): "
                
                if [ "$(validate_yes_no "Update?" "y")" = "y" ]; then
                    # Find the current script's location
                    local script_path=$(which phpswitch 2>/dev/null || echo "$0")
                    
                    # Backup the current script
                    local backup_path="${script_path}.bak.$(date +%Y%m%d%H%M%S)"
                    show_status "info" "Creating backup at $backup_path..."
                    cp "$script_path" "$backup_path" || { show_status "error" "Failed to create backup"; rm -rf "$tmp_dir"; return 1; }
                    
                    # Install the new version
                    if [ -f "/usr/local/bin/phpswitch" ] || [ -f "$HOMEBREW_PREFIX/bin/phpswitch" ]; then
                        # Update the system command
                        show_status "info" "Updating system command..."
                        chmod +x "$tmp_dir/php-switcher.sh"
                        
                        # Copy to all known installation locations
                        if [ -f "/usr/local/bin/phpswitch" ]; then
                            sudo cp "$tmp_dir/php-switcher.sh" "/usr/local/bin/phpswitch" || { show_status "error" "Failed to update. Try with sudo"; rm -rf "$tmp_dir"; return 1; }
                        fi
                        
                        if [ -f "$HOMEBREW_PREFIX/bin/phpswitch" ]; then
                            sudo cp "$tmp_dir/php-switcher.sh" "$HOMEBREW_PREFIX/bin/phpswitch" || { show_status "error" "Failed to update. Try with sudo"; rm -rf "$tmp_dir"; return 1; }
                        fi
                    else
                        # Just update the current script
                        chmod +x "$tmp_dir/php-switcher.sh"
                        sudo cp "$tmp_dir/php-switcher.sh" "$script_path" || { show_status "error" "Failed to update. Try with sudo"; rm -rf "$tmp_dir"; return 1; }
                    fi
                    
                    show_status "success" "Updated to version $new_version"
                    echo "Please restart phpswitch to use the new version."
                    
                    # Clean up
                    rm -rf "$tmp_dir"
                    exit 0
                else
                    show_status "info" "Update cancelled"
                fi
            else
                show_status "success" "You are already using the latest version: $current_version"
            fi
        else
            show_status "error" "Failed to download the latest version"
        fi
    else
        show_status "error" "Failed to connect to GitHub. Check your internet connection."
    fi
    
    # Clean up
    rm -rf "$tmp_dir"
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
    update_self
    exit 0
elif [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "PHPSwitch - PHP Version Manager for macOS"
    echo "========================================"
    echo "Usage:"
    echo "  phpswitch                   - Run the interactive menu to switch PHP versions"
    echo "  phpswitch --install         - Install phpswitch as a system command"
    echo "  phpswitch --uninstall       - Remove phpswitch from your system"
    echo "  phpswitch --update          - Check for and install the latest version"
    echo "  phpswitch --debug           - Run with debug logging enabled"
    echo "  phpswitch --help, -h        - Display this help message"
    exit 0
else
    # No arguments or debug mode only - show the interactive menu
    current_version=$(get_current_php_version)
    
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