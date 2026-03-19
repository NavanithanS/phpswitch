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

# Security: Path validation functions
function utils_validate_path {
    local path="$1"
    local allow_relative="${2:-false}"
    
    # Check for empty path
    if [[ -z "$path" ]]; then
        return 1
    fi
    
    # Check for path traversal attempts
    if [[ "$path" == *".."* ]]; then
        core_debug_log "Path validation failed: path traversal detected in '$path'"
        return 1
    fi
    
    # Check for null bytes using a more robust method
    # Use test with -z and command substitution to detect null bytes
    if [ -n "$(printf '%s' "$path" | tr -d '[:print:][:space:]')" ]; then
        core_debug_log "Path validation failed: non-printable characters detected in '$path'"
        return 1
    fi
    
    # If relative paths are not allowed, ensure it's absolute
    if [[ "$allow_relative" != "true" ]] && [[ "$path" != /* ]]; then
        core_debug_log "Path validation failed: relative path not allowed '$path'"
        return 1
    fi
    
    # Check path length (prevent extremely long paths)
    if [[ ${#path} -gt 4096 ]]; then
        core_debug_log "Path validation failed: path too long '$path'"
        return 1
    fi
    
    # Check for potentially dangerous characters
    if [[ "$path" =~ [[:cntrl:]] ]]; then
        core_debug_log "Path validation failed: control characters detected in '$path'"
        return 1
    fi
    
    return 0
}

# Security: Validate PHP version string
function utils_validate_version {
    local version="$1"
    
    # Check for empty version
    if [[ -z "$version" ]]; then
        return 1
    fi
    
    # Allow standard PHP version patterns: php@8.1, 8.1, php, etc.
    if [[ "$version" =~ ^(php(@[0-9]+\.[0-9]+)?|[0-9]+\.[0-9]+|default)$ ]]; then
        return 0
    fi
    
    core_debug_log "Version validation failed: invalid version format '$version'"
    return 1
}

# Security: Validate username string
function utils_validate_username {
    local username="$1"
    
    # Check for empty username
    if [[ -z "$username" ]]; then
        return 1
    fi
    
    # Allow only alphanumeric characters, underscores, and hyphens
    if [[ "$username" =~ ^[a-zA-Z0-9_-]+$ ]] && [[ ${#username} -le 32 ]]; then
        return 0
    fi
    
    core_debug_log "Username validation failed: invalid username '$username'"
    return 1
}

# Security: Array to track temporary files for cleanup
declare -a TEMP_FILES_TO_CLEANUP=()
declare -a TEMP_DIRS_TO_CLEANUP=()

# Security: Create secure temporary file with automatic cleanup
function utils_create_secure_temp_file {
    local temp_file
    temp_file=$(mktemp)
    
    if [[ -n "$temp_file" ]] && [[ -f "$temp_file" ]]; then
        # Set secure permissions (readable/writable by owner only)
        chmod 600 "$temp_file"
        
        # Track for cleanup
        TEMP_FILES_TO_CLEANUP+=("$temp_file")
        
        echo "$temp_file"
        return 0
    else
        core_debug_log "Failed to create secure temporary file"
        return 1
    fi
}

# Security: Create secure temporary directory with automatic cleanup
function utils_create_secure_temp_dir {
    local temp_dir
    temp_dir=$(mktemp -d)
    
    if [[ -n "$temp_dir" ]] && [[ -d "$temp_dir" ]]; then
        # Set secure permissions (accessible by owner only)
        chmod 700 "$temp_dir"
        
        # Track for cleanup
        TEMP_DIRS_TO_CLEANUP+=("$temp_dir")
        
        echo "$temp_dir"
        return 0
    else
        core_debug_log "Failed to create secure temporary directory"
        return 1
    fi
}

# Security: Cleanup all tracked temporary files and directories
function utils_cleanup_temp_files {
    local item
    
    # Clean up temporary files
    for item in "${TEMP_FILES_TO_CLEANUP[@]}"; do
        if [[ -f "$item" ]]; then
            rm -f "$item" 2>/dev/null
            core_debug_log "Cleaned up temporary file: $item"
        fi
    done
    
    # Clean up temporary directories
    for item in "${TEMP_DIRS_TO_CLEANUP[@]}"; do
        if [[ -d "$item" ]]; then
            rm -rf "$item" 2>/dev/null
            core_debug_log "Cleaned up temporary directory: $item"
        fi
    done
    
    # Clear the arrays
    TEMP_FILES_TO_CLEANUP=()
    TEMP_DIRS_TO_CLEANUP=()
}

# Security: Setup trap for automatic cleanup
function utils_setup_temp_cleanup_trap {
    trap 'utils_cleanup_temp_files; exit' INT TERM EXIT
}

# Function to print text with a smooth left-to-right RGB gradient
# Usage: utils_print_gradient "text" r1 g1 b1 r2 g2 b2
function utils_print_gradient {
    local text="$1"
    local r1=$2 g1=$3 b1=$4
    local r2=$5 g2=$6 b2=$7
    local len=${#text}
    if [ "$len" -le 1 ]; then
        printf "\033[38;2;%d;%d;%dm%s\033[0m" "$r1" "$g1" "$b1" "$text"
        return
    fi
    local i=0
    while [ $i -lt $len ]; do
        local char="${text:$i:1}"
        local r=$(( r1 + (r2 - r1) * i / (len - 1) ))
        local g=$(( g1 + (g2 - g1) * i / (len - 1) ))
        local b=$(( b1 + (b2 - b1) * i / (len - 1) ))
        printf "\033[38;2;%d;%d;%dm%s" "$r" "$g" "$b" "$char"
        i=$(( i + 1 ))
    done
    printf "\033[0m"
}

# Function to display success or error message with colors
function utils_show_status {
    local status="$1"
    local message="$2"

    if [ "$USE_COLORS" = "true" ]; then
        case "$status" in
            success) printf "     \xe2\x8e\xbf  %s\n" "$message" ;;
            warning) printf "     \xe2\x8e\xbf  %s\n" "$message" ;;
            error)   printf "     \xe2\x8e\xbf  %s\n" "$message" ;;
            info)    printf "\033[2m  \xe2\x8f\xba\033[0m  %s\n" "$message" ;;
        esac
    else
        case "$status" in
            success) echo "     L $message" ;;
            warning) echo "     L warn: $message" ;;
            error)   echo "     L error: $message" ;;
            info)    echo "  * $message" ;;
        esac
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
            printf "  Enter 'y' or 'n' "
        fi
    done
}

# Safely set a KEY="value" pair in a config file (injection-safe via ENVIRON)
function utils_set_config_value {
    local key="$1"
    local value="$2"
    local file="$3"
    KEY="$key" VALUE="$value" awk '
        BEGIN { k=ENVIRON["KEY"]; v=ENVIRON["VALUE"]; found=0 }
        $0 ~ ("^" k "=") { print k "=\"" v "\""; found=1; next }
        { print }
        END { if (!found) print k "=\"" v "\"" }
    ' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
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
    if [ "$USE_COLORS" = "true" ]; then
        printf "\n  "; utils_print_gradient "PATH Diagnostic" 192 132 252 103 232 249; printf "\n\n"
    else
        printf "\n  PATH Diagnostic\n\n"
    fi

    if [ "$USE_COLORS" = "true" ]; then
        printf "  "; utils_print_gradient "Current PATH:" 148 182 251 125 207 250; printf "\n"
    else
        printf "  Current PATH:\n"
    fi
    printf "%s" "$PATH" | tr ':' '\n' | nl | sed 's/^/  /'

    if [ "$USE_COLORS" = "true" ]; then
        printf "\n  "; utils_print_gradient "PHP binaries in PATH:" 148 182 251 125 207 250; printf "\n"
    else
        printf "\n  PHP binaries in PATH:\n"
    fi

    local count=0
    local old_IFS="$IFS"
    IFS=:
    for dir in $PATH; do
        if [ -x "$dir/php" ]; then
            count=$((count + 1))
            local _ver _type
            _ver=$("$dir/php" -v 2>/dev/null | head -n 1)
            if [ -L "$dir/php" ]; then
                _type="Symlink → $(readlink "$dir/php")"
            else
                _type="Direct binary"
            fi
            printf "  %d) %s/php\n" "$count" "$dir"
            printf "     Version: %s\n" "${_ver:-could not determine}"
            printf "     Type: %s\n\n" "$_type"
        fi
    done
    IFS="$old_IFS"

    if [ "$count" -eq 0 ]; then
        utils_show_status "warning" "No PHP binaries found in PATH"
    elif [ "$count" -gt 1 ]; then
        utils_show_status "warning" "Multiple PHP binaries found in PATH. This may cause confusion."
        printf "  The first one in the PATH will be used.\n"
    fi
    
    if [ "$USE_COLORS" = "true" ]; then
        printf "\n  "; utils_print_gradient "Active PHP:" 148 182 251 125 207 250; printf "\n"
    else
        printf "\n  Active PHP:\n"
    fi
    which php
    php -v | head -n 1

    if [ "$USE_COLORS" = "true" ]; then
        printf "\n  "; utils_print_gradient "Expected PHP path for current version:" 148 182 251 125 207 250; printf "\n"
    else
        printf "\n  Expected PHP path for current version:\n"
    fi
    local current_version
    current_version=$(core_get_current_php_version)
    if [ "$current_version" = "php@default" ]; then
        printf "  %s/opt/php/bin/php\n" "$HOMEBREW_PREFIX"
    else
        printf "  %s/opt/%s/bin/php\n" "$HOMEBREW_PREFIX" "$current_version"
    fi
    
    if [ "$USE_COLORS" = "true" ]; then
        printf "\n  "; utils_print_gradient "Recommended actions:" 148 182 251 125 207 250; printf "\n"
    else
        printf "\n  Recommended actions:\n"
    fi
    printf "    1  Ensure the PHP version you want is first in your PATH\n"
    printf "    2  Check for conflicting PHP binaries in your PATH\n"
    printf "    3  Run 'hash -r' (bash/zsh) or 'rehash' (fish) to clear command hash table\n"
    printf "    4  Open a new terminal session to ensure PATH changes take effect\n"
}

# Function to diagnose the PHP environment
function utils_diagnose_php_environment {
    if [ "$USE_COLORS" = "true" ]; then
        printf "\n  "; utils_print_gradient "PHP Environment Diagnostic" 192 132 252 103 232 249; printf "\n\n"
    else
        printf "\n  PHP Environment Diagnostic\n\n"
    fi

    # 1. Check all PHP binaries
    if [ "$USE_COLORS" = "true" ]; then
        printf "  "; utils_print_gradient "PHP Binaries" 148 182 251 125 207 250; printf "\n"
    else
        printf "  PHP Binaries\n"
    fi
    if command -v php &>/dev/null; then
        local php_path
        php_path=$(which php)
        printf "  Default PHP: %s\n" "$php_path"
        if [ -L "$php_path" ]; then
            local real_path
            real_path=$(readlink "$php_path")
            printf "    → Symlinked to: %s\n" "$real_path"
        fi
        printf "  Version: %s\n" "$(php -v | head -n 1)"
    else
        printf "  No PHP binary found in PATH\n"
    fi
    printf "\n"

    # 2. Check all installed PHP versions
    if [ "$USE_COLORS" = "true" ]; then
        printf "\n  "; utils_print_gradient "Installed PHP Versions" 148 182 251 125 207 250; printf "\n"
    else
        printf "\n  Installed PHP Versions\n"
    fi
    local installed_versions
    installed_versions=$(core_get_installed_php_versions)
    if [ -n "$installed_versions" ]; then
        printf "%s\n" "$installed_versions"
    else
        printf "  No PHP versions installed via Homebrew\n"
    fi
    printf "\n"

    # 3. Check Homebrew PHP links
    if [ "$USE_COLORS" = "true" ]; then
        printf "\n  "; utils_print_gradient "Homebrew PHP Links" 148 182 251 125 207 250; printf "\n"
    else
        printf "\n  Homebrew PHP Links\n"
    fi
    if [ -d "$HOMEBREW_PREFIX/opt" ]; then
        find "$HOMEBREW_PREFIX/opt" -maxdepth 1 -name '*php*' | sort | while IFS= read -r p; do
            printf "  %s\n" "$p"
        done
    else
        printf "  No Homebrew opt directory found\n"
    fi
    printf "\n"

    # 4. Check for conflicting PHP binaries
    if [ "$USE_COLORS" = "true" ]; then
        printf "\n  "; utils_print_gradient "PHP in PATH" 148 182 251 125 207 250; printf "\n"
    else
        printf "\n  PHP in PATH\n"
    fi
    local old_IFS="$IFS"
    IFS=:
    for dir in $PATH; do
        if [ -x "$dir/php" ]; then
            local _ver _type
            _ver=$("$dir/php" -v 2>/dev/null | head -n 1)
            if [ -L "$dir/php" ]; then
                _type="Symlink → $(readlink "$dir/php")"
            else
                _type="Direct binary"
            fi
            printf "  Found in: %s/php\n" "$dir"
            printf "    Version: %s\n" "${_ver:-could not determine}"
            printf "    Type: %s\n" "$_type"
        fi
    done
    IFS="$old_IFS"
    printf "\n"

    # 5. Check shell config files for PHP path entries
    if [ "$USE_COLORS" = "true" ]; then
        printf "\n  "; utils_print_gradient "Shell Configuration Files" 148 182 251 125 207 250; printf "\n"
    else
        printf "\n  Shell Configuration Files\n"
    fi
    local shell_type
    shell_type=$(shell_detect_shell)
    local -a config_files
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
            printf "  %s\n" "$file"
            grep -n "PATH.*php" "$file" | sed 's/^/    /' || printf "    No PHP PATH entries found\n"
        fi
    done
    printf "\n"
    
    # 6. Check PHP modules
    if [ "$USE_COLORS" = "true" ]; then
        printf "\n  "; utils_print_gradient "Loaded PHP Modules" 148 182 251 125 207 250; printf "\n"
    else
        printf "\n  Loaded PHP Modules\n"
    fi
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
    if [ "$USE_COLORS" = "true" ]; then
        printf "\n  "; utils_print_gradient "Running PHP-FPM Services" 148 182 251 125 207 250; printf "\n"
    else
        printf "\n  Running PHP-FPM Services\n"
    fi
    brew services list | grep -E "^php(@[0-9]\.[0-9])?" || echo "  No PHP services found"
    echo ""
    
    # 8. Summary and recommendations
    if [ "$USE_COLORS" = "true" ]; then
        printf "\n  "; utils_print_gradient "Summary" 148 182 251 125 207 250; printf "\n"
    else
        printf "\n  Summary\n"
    fi
    if command -v php &>/dev/null; then
        php_version=$(php -v | head -n 1 | cut -d " " -f 2)
        homebrew_linked=$(core_get_current_php_version)
        
        local brew_major_minor
        brew_major_minor=$(echo "$homebrew_linked" | grep -oE "[0-9]+\.[0-9]+")
        if [[ "$homebrew_linked" == php@* ]] && [[ "$php_version" != *"$brew_major_minor"* ]]; then
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
                    utils_set_config_value "CACHE_DIRECTORY" "$alt_cache" "$HOME/.phpswitch.conf"
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
        printf "  This is a non-critical issue. PHPSwitch will use temporary directories instead.\n"
        printf "  Fix the permissions now? (y/n) "
        if [ "$(utils_validate_yes_no "" "y")" = "y" ]; then
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
                        # Get secure username and validate it
                        local username
                        username="$(id -un)"
                        if utils_validate_username "$username"; then
                            sudo chown "$username" "$cache_dir" 2>/dev/null
                        else
                            utils_show_status "error" "Invalid username detected, skipping ownership change"
                        fi
                        
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
                                        utils_set_config_value "CACHE_DIRECTORY" "$alt_cache" "$HOME/.phpswitch.conf"
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

# Function to read PHP version from composer.json
# Uses grep/sed to avoid jq dependency
function utils_read_composer_version {
    local composer_file="$1"
    
    if [ ! -f "$composer_file" ]; then
        return 1
    fi
    
    # 1. Check config.platform.php (highest priority)
    # We look for "php": "X.Y" inside the file, hoping it's unique enough or we catch the right one.
    # To be safer without jq, we can try to look for the platform block
    local platform_php=$(grep -A 10 '"platform"' "$composer_file" 2>/dev/null | grep '"php"' | head -n 1)
    
    if [ -n "$platform_php" ]; then
        # Extract version: "php": "8.1.0" -> 8.1.0
        local version=$(echo "$platform_php" | sed -E 's/.*"php": *"([^"]+)".*/\1/')
        # extract major.minor
        echo "$version" | grep -oE '[0-9]+\.[0-9]+' | head -n 1
        return 0
    fi
    
    # 2. Check require.php
    local require_php=$(grep -A 20 '"require"' "$composer_file" 2>/dev/null | grep '"php"' | head -n 1)
    
    if [ -n "$require_php" ]; then
        # Extract version: "php": "^8.1" -> 8.1
        local version=$(echo "$require_php" | sed -E 's/.*"php": *"([^"]+)".*/\1/')
        # extract major.minor
        echo "$version" | grep -oE '[0-9]+\.[0-9]+' | head -n 1
        return 0
    fi
    
    return 1
}

# Function to read PHP version from .tool-versions (asdf)
function utils_read_tool_versions {
    local tool_file="$1"
    
    if [ ! -f "$tool_file" ]; then
        return 1
    fi
    
    # Look for line starting with php
    local php_line=$(grep "^php " "$tool_file" 2>/dev/null | head -n 1)
    
    if [ -n "$php_line" ]; then
        # Extract version: php 8.1.0 -> 8.1.0
        local version=$(echo "$php_line" | awk '{print $2}')
        # extract major.minor
        echo "$version" | grep -oE '[0-9]+\.[0-9]+' | head -n 1
        return 0
    fi
    
    return 1
}
