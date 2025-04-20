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
function utils_show_progress {
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

# Function to display success or error message with colors
function utils_show_status {
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
function utils_validate_yes_no {
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

# Function to validate numeric input within a range
function utils_validate_numeric_input {
    local input="$1"
    local min="$2"
    local max="$3"
    
    if [[ "$input" =~ ^[0-9]+$ ]] && [ "$input" -ge "$min" ] && [ "$input" -le "$max" ]; then
        return 0
    else
        return 1
    fi
}

# Function to help diagnose PATH issues
function utils_diagnose_path_issues {
    echo "PATH Diagnostic"
    echo "==============="
    
    echo "Current PATH:"
    echo "$PATH" | tr ':' '\n' | nl
    
    echo ""
    echo "PHP binaries in PATH:"
    
    local count=0
    IFS=:
    for dir in $PATH; do
        if [ -x "$dir/php" ]; then
            count=$((count + 1))
            echo "$count) $dir/php"
            echo "   Version: $($dir/php -v 2>/dev/null | head -n 1)"
            echo "   Type: $(if [ -L "$dir/php" ]; then echo "Symlink → $(readlink "$dir/php")"; else echo "Direct binary"; fi)"
            echo ""
        fi
    done
    unset IFS
    
    if [ "$count" -eq 0 ]; then
        utils_show_status "warning" "No PHP binaries found in PATH"
    elif [ "$count" -gt 1 ]; then
        utils_show_status "warning" "Multiple PHP binaries found in PATH. This may cause confusion."
        echo "The first one in the PATH will be used."
    fi
    
    echo ""
    echo "Active PHP:"
    which php
    php -v | head -n 1
    
    echo ""
    echo "Expected PHP path for current version:"
    local current_version=$(core_get_current_php_version)
    if [ "$current_version" = "php@default" ]; then
        echo "$HOMEBREW_PREFIX/opt/php/bin/php"
    else
        echo "$HOMEBREW_PREFIX/opt/$current_version/bin/php"
    fi
    
    echo ""
    echo "Recommended actions:"
    echo "1. Ensure the PHP version you want is first in your PATH"
    echo "2. Check for conflicting PHP binaries in your PATH"
    echo "3. Run 'hash -r' (bash/zsh) or 'rehash' (fish) to clear command hash table"
    echo "4. Open a new terminal session to ensure PATH changes take effect"
}

# Function to diagnose the PHP environment
function utils_diagnose_php_environment {
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
    installed_versions=$(core_get_installed_php_versions)
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
    shell_type=$(shell_detect_shell)
    if [ "$shell_type" = "zsh" ]; then
        config_files=("$HOME/.zshrc" "$HOME/.zprofile")
    elif [ "$shell_type" = "bash" ]; then
        config_files=("$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile")
    elif [ "$shell_type" = "fish" ]; then
        config_files=("$HOME/.config/fish/config.fish")
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
        homebrew_linked=$(core_get_current_php_version)
        
        if [[ $homebrew_linked == php@* ]] && [[ $php_version != *$(echo "$homebrew_linked" | grep -o "[0-9]\.[0-9]")* ]]; then
            utils_show_status "warning" "Version mismatch detected"
            echo "  The PHP version in use ($php_version) does not match the Homebrew-linked version ($homebrew_linked)"
            echo ""
            echo "Possible causes:"
            echo "  1. Another PHP binary is taking precedence in your PATH"
            echo "  2. Shell configuration files need to be updated or sourced"
            echo "  3. The PHP binary might be a direct install or from another package manager"
            echo ""
            echo "Recommended actions:"
            shell_type=$(shell_detect_shell)
            if [ "$shell_type" = "zsh" ]; then
                echo "  1. Try running: source ~/.zshrc"
                echo "  2. Or open a new terminal window"
            elif [ "$shell_type" = "bash" ]; then
                echo "  1. Try running: source ~/.bashrc"
                echo "  2. Or open a new terminal window"
            elif [ "$shell_type" = "fish" ]; then
                echo "  1. Try running: source ~/.config/fish/config.fish"
                echo "  2. Or run: set -gx PATH $HOMEBREW_PREFIX/opt/$homebrew_linked/bin $HOMEBREW_PREFIX/opt/$homebrew_linked/sbin \$PATH; and rehash"
            else
                echo "  1. Try running: source ~/.profile"
                echo "  2. Or open a new terminal window"
            fi
            echo "  3. Consider removing or renaming conflicting PHP binaries"
        else
            utils_show_status "success" "PHP environment looks healthy"
            echo "  Current PHP version: $php_version"
            echo "  Homebrew-linked version: $homebrew_linked"
        fi
    else
        utils_show_status "error" "No PHP binary found in PATH"
        echo "  Check your Homebrew installation and PATH environment variable"
    fi
}

# Function to validate system dependencies
function utils_check_dependencies {
    utils_show_status "info" "Checking dependencies..."
    
    # Check for Homebrew
    if ! command -v brew >/dev/null 2>&1; then
        utils_show_status "error" "Homebrew is not installed"
        echo "PHPSwitch requires Homebrew to manage PHP versions."
        echo "Please install Homebrew first: https://brew.sh"
        return 1
    fi

    # Check Homebrew version
    local brew_version=$(brew --version | head -n 1 | grep -o "[0-9]\+\.[0-9]\+\.[0-9]\+" 2>/dev/null || echo "0.0.0")
    local min_version="3.0.0"
    
    # Basic version comparison
    if [[ "$(printf '%s\n' "$min_version" "$brew_version" | sort -V | head -n1)" != "$min_version" ]]; then
        utils_show_status "warning" "Detected Homebrew version $brew_version"
        echo "PHPSwitch works best with Homebrew 3.0.0 or newer."
        echo "Consider upgrading with: brew update"
    fi
    
    # Check for required system commands
    local required_commands=("curl" "grep" "sed" "awk" "mktemp" "perl")
    local missing_commands=()
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [ ${#missing_commands[@]} -gt 0 ]; then
        utils_show_status "error" "Missing required commands: ${missing_commands[*]}"
        echo "These commands are needed for PHPSwitch to function properly."
        return 1
    fi
    
    # Check for macOS
    if [[ "$OSTYPE" != "darwin"* ]]; then
        utils_show_status "warning" "PHPSwitch is designed for macOS"
        echo "Some features may not work correctly on $OSTYPE."
    else
        # Check for xcode command line tools on macOS
        if ! xcode-select -p >/dev/null 2>&1; then
            utils_show_status "warning" "Xcode Command Line Tools may not be installed"
            echo "Some Homebrew commands might fail. Install with:"
            echo "xcode-select --install"
        fi
    fi
    
    # Check for supported shell
    local shell_type=$(shell_detect_shell)
    if [ "$shell_type" = "unknown" ]; then
        utils_show_status "warning" "Unrecognized shell: $SHELL"
        echo "PHPSwitch works best with bash, zsh, or fish shells."
        echo "Shell configuration may not be properly updated."
    fi
    
    # Verify PHP is available through Homebrew
    if ! brew list --formula 2>/dev/null | grep -q "^php" && ! brew list --formula 2>/dev/null | grep -q "^php@"; then
        utils_show_status "warning" "No PHP versions detected from Homebrew"
        echo "PHPSwitch manages PHP versions installed via Homebrew."
        echo "You might need to install PHP first with: brew install php"
    fi
    
    # Check for write permissions in important directories
    local brew_prefix="$(brew --prefix)"
    if [ ! -w "$brew_prefix/bin" ] && [ ! -w "/usr/local/bin" ]; then
        utils_show_status "warning" "Limited write permissions detected"
        echo "You may need to use sudo for some operations."
    fi
    
    # Enhanced cache directory check - using the core_get_cache_dir function
    local cache_dir=$(core_get_cache_dir)
    
    # If the function returned a temporary directory, we've already fallen back
    if [[ "$cache_dir" == /tmp/* ]]; then
        utils_show_status "warning" "Using temporary cache directory: $cache_dir"
        echo "Cache will be lost on system reboot. To fix permanently, run:"
        echo "phpswitch --fix-permissions"
        
        # Try to create a more persistent cache directory for future use
        local alt_cache="$HOME/.phpswitch_cache"
        if [ ! -d "$alt_cache" ]; then
            mkdir -p "$alt_cache" 2>/dev/null
            if [ -d "$alt_cache" ] && [ -w "$alt_cache" ]; then
                # Update config file for future runs
                if [ -f "$HOME/.phpswitch.conf" ]; then
                    if grep -q "CACHE_DIRECTORY=" "$HOME/.phpswitch.conf"; then
                        sed -i.bak "s|CACHE_DIRECTORY=.*|CACHE_DIRECTORY=\"$alt_cache\"|g" "$HOME/.phpswitch.conf"
                        rm -f "$HOME/.phpswitch.conf.bak" 2>/dev/null
                    else
                        echo "CACHE_DIRECTORY=\"$alt_cache\"" >> "$HOME/.phpswitch.conf"
                    fi
                else
                    # Create config file if it doesn't exist
                    cat > "$HOME/.phpswitch.conf" << EOL
# PHPSwitch Configuration
AUTO_RESTART_PHP_FPM=true
BACKUP_CONFIG_FILES=true
DEFAULT_PHP_VERSION=""
MAX_BACKUPS=5
AUTO_SWITCH_PHP_VERSION=false
CACHE_DIRECTORY="$alt_cache"
EOL
                fi
            fi
        fi
    # If we're using the standard cache directory but it's not writable
    elif [ "$cache_dir" = "$HOME/.cache/phpswitch" ] && [ ! -w "$cache_dir" ]; then
        utils_show_status "warning" "Cache directory is not writable: $cache_dir"
        echo "This is a non-critical issue. PHPSwitch will use temporary directories instead."
        echo -n "Would you like to fix the permissions now? (y/n): "
        if [ "$(utils_validate_yes_no "Fix permissions?" "y")" = "y" ]; then
            # Check if we have the fix-permissions script
            local script_dir="$(dirname "$(realpath "$0" 2>/dev/null || echo "$0")")"
            local fix_script="$script_dir/tools/fix-permissions.sh"
            
            if [ -f "$fix_script" ]; then
                utils_show_status "info" "Running permission fix script..."
                bash "$fix_script"
            else
                # Try to fix permissions manually
                utils_show_status "info" "Attempting to fix permissions manually..."
                
                # Try to fix with standard chmod first
                chmod u+w "$cache_dir" 2>/dev/null
                if [ ! -w "$cache_dir" ]; then
                    # If that fails, try with sudo
                    utils_show_status "info" "Trying with sudo..."
                    sudo chmod u+w "$cache_dir" 2>/dev/null
                    
                    if [ ! -w "$cache_dir" ]; then
                        # Try ownership change
                        sudo chown "$(whoami)" "$cache_dir" 2>/dev/null
                        
                        if [ ! -w "$cache_dir" ]; then
                            utils_show_status "error" "Could not fix permissions with standard methods"
                            
                            # Try to remove and recreate directory
                            utils_show_status "info" "Trying to recreate the cache directory..."
                            sudo rm -rf "$cache_dir" 2>/dev/null
                            mkdir -p "$cache_dir" 2>/dev/null
                            
                            if [ ! -w "$cache_dir" ]; then
                                # Create alternative directory
                                local alt_cache="$HOME/.phpswitch_cache"
                                mkdir -p "$alt_cache" 2>/dev/null
                                
                                if [ -d "$alt_cache" ] && [ -w "$alt_cache" ]; then
                                    utils_show_status "success" "Created alternative cache directory: $alt_cache"
                                    
                                    # Update config file
                                    if [ -f "$HOME/.phpswitch.conf" ]; then
                                        if grep -q "CACHE_DIRECTORY=" "$HOME/.phpswitch.conf"; then
                                            sed -i.bak "s|CACHE_DIRECTORY=.*|CACHE_DIRECTORY=\"$alt_cache\"|g" "$HOME/.phpswitch.conf"
                                            rm -f "$HOME/.phpswitch.conf.bak" 2>/dev/null
                                        else
                                            echo "CACHE_DIRECTORY=\"$alt_cache\"" >> "$HOME/.phpswitch.conf"
                                        fi
                                    else
                                        # Create config file if it doesn't exist
                                        cat > "$HOME/.phpswitch.conf" << EOL
# PHPSwitch Configuration
AUTO_RESTART_PHP_FPM=true
BACKUP_CONFIG_FILES=true
DEFAULT_PHP_VERSION=""
MAX_BACKUPS=5
AUTO_SWITCH_PHP_VERSION=false
CACHE_DIRECTORY="$alt_cache"
EOL
                                    fi
                                else
                                    utils_show_status "error" "Failed to create alternative cache directory"
                                    echo "PHPSwitch will fall back to using temporary directories for this session."
                                fi
                            else
                                utils_show_status "success" "Cache directory recreated successfully"
                            fi
                        else
                            utils_show_status "success" "Permissions fixed by changing ownership"
                        fi
                    else
                        utils_show_status "success" "Permissions fixed with sudo"
                    fi
                else
                    utils_show_status "success" "Permissions fixed"
                fi
            fi
        fi
    fi
    
    utils_show_status "success" "All critical dependencies satisfied"
    return 0
}

# Function to compare semantic versions (returns true if version1 >= version2)
function utils_compare_versions {
    local version1="$1"
    local version2="$2"
    
    # Extract major, minor, patch versions
    local v1_parts=(${version1//./ })
    local v2_parts=(${version2//./ })
    
    # Compare major version
    if (( ${v1_parts[0]} > ${v2_parts[0]} )); then
        return 0
    elif (( ${v1_parts[0]} < ${v2_parts[0]} )); then
        return 1
    fi
    
    # Compare minor version
    if (( ${v1_parts[1]} > ${v2_parts[1]} )); then
        return 0
    elif (( ${v1_parts[1]} < ${v2_parts[1]} )); then
        return 1
    fi
    
    # Compare patch version
    if (( ${v1_parts[2]} >= ${v2_parts[2]} )); then
        return 0
    else
        return 1
    fi
}