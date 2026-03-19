#!/bin/bash

# Version: 1.4.5
# PHPSwitch - PHP Version Manager for macOS
# This script helps switch between different PHP versions installed via Homebrew
# and updates shell configuration files (.zshrc, .bashrc, etc.) accordingly

# Default Configuration
# PHPSwitch Default Configuration
# Contains default values for configuration

PHPSWITCH_VERSION="1.4.5"

# Default configuration values
DEFAULT_AUTO_RESTART_PHP_FPM=true
DEFAULT_BACKUP_CONFIG_FILES=true
DEFAULT_PHP_VERSION=""
DEFAULT_MAX_BACKUPS=5
DEFAULT_AUTO_SWITCH_PHP_VERSION=false
DEFAULT_CACHE_DIRECTORY=""  # Empty means use default location in ~/.cache/phpswitch

# Module: core.sh
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
    AUTO_SWITCH_PHP_VERSION=false
    CACHE_DIRECTORY=""  # Empty means use default location
    
    # Load settings if config exists
    if [ -f "$CONFIG_FILE" ]; then
        core_debug_log "Loading configuration from $CONFIG_FILE"
        source "$CONFIG_FILE"
    else
        core_debug_log "No configuration file found at $CONFIG_FILE"
    fi
    
    # Validate Homebrew prefix for security
    if [[ -z "$HOMEBREW_PREFIX" ]]; then
        echo "Error: Could not determine Homebrew prefix" >&2
        exit 1
    fi
    
    # Basic validation for Homebrew prefix (more permissive than utils_validate_path)
    if [[ "$HOMEBREW_PREFIX" != /* ]] || [[ "$HOMEBREW_PREFIX" == *".."* ]] || [[ ${#HOMEBREW_PREFIX} -gt 4096 ]]; then
        echo "Error: Invalid Homebrew prefix path: $HOMEBREW_PREFIX" >&2
        exit 1
    fi
    
    # Setup automatic cleanup for temporary files
    utils_setup_temp_cleanup_trap
}

# Create default configuration
function core_create_default_config {
    if [ ! -f "$HOME/.phpswitch.conf" ]; then
        cat > "$HOME/.phpswitch.conf" <<EOL
# PHPSwitch Configuration
AUTO_RESTART_PHP_FPM=true
BACKUP_CONFIG_FILES=true
DEFAULT_PHP_VERSION=""
MAX_BACKUPS=5
AUTO_SWITCH_PHP_VERSION=false
CACHE_DIRECTORY=""
EOL
        utils_show_status "success" "Created default configuration at ~/.phpswitch.conf"
    fi
}

# Function to get all installed PHP versions
function core_get_installed_php_versions {
    # Get both php@X.Y versions and the default php (which could be the latest version)
    local brew_list
    brew_list=$(brew list 2>/dev/null)
    local versions
    versions=$(echo "$brew_list" | grep "^php@" || true)

    # Check if the "php" formula is installed and get its version
    if echo "$brew_list" | grep -q "^php$"; then
        # Add php@default for internal logic
        versions="$versions"$'\n'"php@default"
        
        # Resolve the actual version of the default php formula
        # Use brew list --versions to get the version string (e.g., php 8.4.1)
        local major_minor
        major_minor=$(brew list --versions php 2>/dev/null | awk 'NR==1{split($2,a,"."); print a[1] "." a[2]}')
        if [ -n "$major_minor" ]; then
            versions="$versions"$'\n'"php@$major_minor"
        fi
    fi
    
    echo "$versions" | sort | uniq
}

# Function to get and manage the cache directory with better error handling
function core_get_cache_dir {
    # Check if custom cache directory is set in config
    if [ -n "$CACHE_DIRECTORY" ]; then
        # Use custom location from config
        local cache_dir="$CACHE_DIRECTORY"
        
        # Try to create it if it doesn't exist
        if [ ! -d "$cache_dir" ]; then
            mkdir -p "$cache_dir" 2>/dev/null
            if [ $? -ne 0 ]; then
                core_debug_log "Failed to create custom cache directory: $cache_dir"
                # Fallback to temporary directory
                cache_dir=$(mktemp -d /tmp/phpswitch.XXXXXX)
                core_debug_log "Using fallback temporary directory: $cache_dir"
            fi
        # Check if custom dir is writable
        elif [ ! -w "$cache_dir" ]; then
            core_debug_log "Custom cache directory is not writable: $cache_dir"
            # Fallback to temporary directory
            cache_dir=$(mktemp -d /tmp/phpswitch.XXXXXX)
            core_debug_log "Using fallback temporary directory: $cache_dir"
        fi
    else
        # Use default location
        local cache_dir="$HOME/.cache/phpswitch"
        
        # Try to create the cache directory
        if [ ! -d "$cache_dir" ]; then
            mkdir -p "$cache_dir" 2>/dev/null
        fi
        
        # Check if we can write to the default cache directory
        if [ ! -w "$cache_dir" ] 2>/dev/null; then
            core_debug_log "Default cache directory is not writable: $cache_dir"
            
            # Try these alternatives in order:
            
            # 1. Try ~/.phpswitch_cache in home directory 
            local alt_cache="$HOME/.phpswitch_cache"
            if [ ! -d "$alt_cache" ]; then
                mkdir -p "$alt_cache" 2>/dev/null
            fi
            
            if [ -d "$alt_cache" ] && [ -w "$alt_cache" ]; then
                cache_dir="$alt_cache"
                core_debug_log "Using alternative cache in home directory: $cache_dir"
                
                # Save this location to config for future use
                if [ -f "$HOME/.phpswitch.conf" ]; then
                    utils_set_config_value "CACHE_DIRECTORY" "$alt_cache" "$HOME/.phpswitch.conf"
                else
                    # Create config file if it doesn't exist
                    core_create_default_config
                    echo "CACHE_DIRECTORY=\"$alt_cache\"" >> "$HOME/.phpswitch.conf"
                fi
            else
                # 2. Use a temporary directory as last resort
                cache_dir=$(mktemp -d /tmp/phpswitch.XXXXXX)
                core_debug_log "Using temporary directory as fallback: $cache_dir"
            fi
        fi
    fi
    
    # Return the resolved cache directory
    echo "$cache_dir"
}

# Enhanced get_available_php_versions function with persistent caching and better error handling
function core_get_available_php_versions {
    # Get the appropriate cache directory
    local cache_dir=$(core_get_cache_dir)
    local cache_file="$cache_dir/available_versions.cache"
    local cache_timeout=3600  # Cache expires after 1 hour (in seconds)
    
    # Function to check cache freshness
    function is_cache_fresh {
        local cache_file="$1"
        local timeout="$2"
        
        if [ ! -f "$cache_file" ]; then
            return 1
        fi
        
        # Get cache file's modification time
        if [ "$(uname)" = "Darwin" ]; then
            # macOS
            local mod_time=$(stat -f %m "$cache_file" 2>/dev/null)
            if [ $? -ne 0 ]; then
                return 1
            fi
        else
            # Linux and others
            local mod_time=$(stat -c %Y "$cache_file" 2>/dev/null)
            if [ $? -ne 0 ]; then
                return 1
            fi
        fi
        
        # Get current time
        local current_time=$(date +%s)
        
        # Check if cache is fresh
        if [ $((current_time - mod_time)) -lt "$timeout" ]; then
            return 0
        else
            return 1
        fi
    }
    
    # Check if cache exists and is recent
    if is_cache_fresh "$cache_file" "$cache_timeout"; then
        core_debug_log "Using cached available PHP versions from $cache_file"
        cat "$cache_file" 2>/dev/null || core_fallback_php_versions
        return
    fi
    
    core_debug_log "Cache is stale or doesn't exist. Refreshing PHP versions..."
    
    # Create a fallback PHP versions function instead of a file
    function core_fallback_php_versions {
        echo "php@7.4"
        echo "php@8.0"
        echo "php@8.1"
        echo "php@8.2"
        echo "php@8.3"
        echo "php@8.4"
        echo "php@default"
    }
    
    # Create a temporary file for the new cache
    local temp_cache_file
    temp_cache_file=$(utils_create_secure_temp_file)
    
    # Try to get actual versions with a timeout
    (
        # Run brew search with a timeout
        core_debug_log "Searching for PHP versions with Homebrew..."
        {
            # Use temp files for output
            local search_file1 search_file2
            search_file1=$(utils_create_secure_temp_file)
            search_file2=$(utils_create_secure_temp_file)
            
            # Run searches in background, track both PIDs
            brew search /php@[0-9]/ 2>/dev/null | grep '^php@' > "$search_file1" &
            local brew_pid1=$!
            brew search /^php$/ 2>/dev/null | sed 's/^php$/php@default/' > "$search_file2" &
            local brew_pid2=$!

            # Wait for up to 10 seconds
            for i in {1..10}; do
                if ! kill -0 $brew_pid1 2>/dev/null && ! kill -0 $brew_pid2 2>/dev/null; then
                    core_debug_log "Homebrew search completed in $i seconds"
                    break
                fi
                sleep 1
            done

            # Kill both if still running
            if kill -0 $brew_pid1 2>/dev/null || kill -0 $brew_pid2 2>/dev/null; then
                kill $brew_pid1 $brew_pid2 2>/dev/null
                wait $brew_pid1 $brew_pid2 2>/dev/null || true
                core_debug_log "Brew search took too long, using fallback values"
                core_fallback_php_versions > "$temp_cache_file"
            else
                # Command finished, combine results
                if [ -s "$search_file1" ] || [ -s "$search_file2" ]; then
                    cat "$search_file1" "$search_file2" 2>/dev/null | sort > "$temp_cache_file"
                else
                    # If results are empty, use the fallback
                    core_debug_log "Homebrew search returned empty results, using fallback values"
                    core_fallback_php_versions > "$temp_cache_file"
                fi
            fi
            
            # Clean up temp files
            rm -f "$search_file1" "$search_file2"
        } || {
            # In case of any error, use fallback values
            core_debug_log "Error occurred during Homebrew search, using fallback values"
            core_fallback_php_versions > "$temp_cache_file"
        }
        
        # Try to move temporary cache to final location
        if [ -d "$cache_dir" ] && [ -w "$cache_dir" ]; then
            mv "$temp_cache_file" "$cache_file" 2>/dev/null || core_debug_log "Failed to move cache file"
            core_debug_log "Updated PHP versions cache at $cache_file"
        else
            core_debug_log "Cache directory is not writable, using temporary file only"
        fi
    ) &
    
    # Show a brief spinner while we wait
    local spinner_pid=$!
    local spin='-\|/'
    local spin_length=${#spin}
    local i=0
    
    printf "  Searching for available PHP versions..."

    while kill -0 $spinner_pid 2>/dev/null; do
        i=$(( (i+1) % 4 ))
        local current_char="${spin:$i:1}"
        printf "\r  Searching for available PHP versions... %s" "$current_char"
        sleep 0.1
    done

    printf "\r  Searching for available PHP versions...          \n"
    
    # Wait for the background process
    wait
    
    # Output the results
    if [ -f "$temp_cache_file" ]; then
        cat "$temp_cache_file" 2>/dev/null
        # Clean up temp file
        rm -f "$temp_cache_file" 2>/dev/null
    elif [ -f "$cache_file" ]; then
        cat "$cache_file" 2>/dev/null
    else
        # If all else fails, output fallback versions
        core_fallback_php_versions
    fi
}

# Function to get current linked PHP version from Homebrew
function core_get_current_php_version {
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
function core_get_active_php_version {
    which_php=$(which php 2>/dev/null)
    core_debug_log "PHP binary: $which_php"
    
    if [ -n "$which_php" ]; then
        php_version=$("$which_php" -v 2>/dev/null | head -n 1 | cut -d " " -f 2)
        core_debug_log "PHP version: $php_version"
        echo "$php_version"
    else
        echo "none"
    fi
}

# Function to check for conflicting PHP installations
function core_check_php_conflicts {
    # Find all PHP binaries in the PATH
    local old_IFS="$IFS"
    IFS=:
    for dir in $PATH; do
        if [ -x "$dir/php" ]; then
            local php_ver
            php_ver=$("$dir/php" -v 2>/dev/null | head -n 1 | cut -d' ' -f2)
            printf "  Found PHP binary at: %s/php  (%s)\n" "$dir" "$php_ver"
        fi
    done
    IFS="$old_IFS"
}

# Function to check if PHP version is actually installed
function core_check_php_installed {
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

# Function to clear cache
function core_clear_cache {
    local cache_dir=$(core_get_cache_dir)
    
    if [ -d "$cache_dir" ]; then
        rm -f "$cache_dir"/*.cache "$cache_dir"/directory_cache.txt 2>/dev/null
        utils_show_status "success" "Cache cleared successfully from $cache_dir"
    else
        utils_show_status "warning" "No cache directory found at $cache_dir"
    fi
}

# Module: utils.sh
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

# Module: shell.sh
# PHPSwitch Shell Management
# Handles shell detection and configuration file updates

# Function to detect shell type with enhanced detection
function shell_detect_shell {
    # First, check if we're in a specific shell based on environment variables
    if [ -n "$ZSH_VERSION" ]; then
        echo "zsh"
    elif [ -n "$BASH_VERSION" ]; then
        echo "bash"
    elif [ -n "$FISH_VERSION" ] || [[ "$SHELL" == *"fish" ]]; then
        echo "fish"
    else
        # Fall back to checking the $SHELL variable
        case "$SHELL" in
            *zsh)
                echo "zsh"
                ;;
            *bash)
                echo "bash"
                ;;
            *fish)
                echo "fish"
                ;;
            *)
                # Default to a best guess based on OS
                if [ "$(uname)" = "Darwin" ]; then
                    echo "zsh"  # macOS defaults to zsh since Catalina
                else
                    echo "bash" # Most Linux distros default to bash
                fi
                ;;
        esac
    fi
}

# Function to determine the most appropriate RC file for the shell
function shell_get_rc_file {
    local shell_type="$1"
    local rc_file=""
    
    case "$shell_type" in
        "zsh")
            # For zsh, prefer .zshrc
            if [ -f "$HOME/.zshrc" ]; then
                rc_file="$HOME/.zshrc"
            elif [ -f "$HOME/.zprofile" ]; then
                rc_file="$HOME/.zprofile"
            else
                rc_file="$HOME/.zshrc"
                touch "$rc_file" # Create if it doesn't exist
            fi
            ;;
        "bash")
            # For bash, try multiple files in order of preference
            if [ -f "$HOME/.bashrc" ]; then
                rc_file="$HOME/.bashrc"
            elif [ -f "$HOME/.bash_profile" ]; then
                rc_file="$HOME/.bash_profile"
            elif [ -f "$HOME/.profile" ]; then
                rc_file="$HOME/.profile"
            else
                # Use .bashrc as default
                rc_file="$HOME/.bashrc"
                touch "$rc_file" # Create if it doesn't exist
            fi
            ;;
        "fish")
            # For fish, use config.fish
            fish_config_dir="$HOME/.config/fish"
            rc_file="$fish_config_dir/config.fish"
            # Ensure the directory exists
            mkdir -p "$fish_config_dir"
            if [ ! -f "$rc_file" ]; then
                touch "$rc_file" # Create if it doesn't exist
            fi
            ;;
        *)
            # For unknown shells, default to .profile
            if [ -f "$HOME/.profile" ]; then
                rc_file="$HOME/.profile"
            else
                rc_file="$HOME/.profile"
                touch "$rc_file" # Create if it doesn't exist
            fi
            ;;
    esac
    
    echo "$rc_file"
}

# Enhanced function to update shell configuration with better PATH manipulation
function shell_update_rc {
    local new_version="$1"
    local shell_type=$(shell_detect_shell)
    local rc_file=$(shell_get_rc_file "$shell_type")
    
    core_debug_log "Detected shell: $shell_type, RC file: $rc_file"
    
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
    
    # Check if file exists (should have been created in shell_get_rc_file if needed)
    if [ ! -f "$rc_file" ]; then
        utils_show_status "error" "RC file $rc_file does not exist and could not be created"
        return 1
    fi
    
    # Check if we have write permissions
    if [ ! -w "$rc_file" ]; then
        utils_show_status "error" "No write permission for $rc_file"
        exit 1
    fi
    
    # Create backup (only if enabled)
    if [ "$BACKUP_CONFIG_FILES" = "true" ]; then
        local backup_file="${rc_file}.bak.$(date +%Y%m%d%H%M%S)"
        
        # Validate backup file path
        if ! utils_validate_path "$backup_file"; then
            utils_show_status "error" "Invalid backup file path, skipping backup"
        else
            # Create backup with secure permissions
            if cp "$rc_file" "$backup_file"; then
                # Set secure permissions (readable/writable by owner only)
                chmod 600 "$backup_file" 2>/dev/null || {
                    utils_show_status "warning" "Could not set secure permissions on backup file"
                }
                utils_show_status "info" "Created secure backup at ${backup_file}"
                
                # Clean up old backups
                shell_cleanup_backups "$rc_file"
            else
                utils_show_status "error" "Failed to create backup file"
            fi
        fi
    fi
    
    utils_show_status "info" "Updating PATH in $rc_file for $shell_type shell..."
    
    # Define marker comments to help find our section later
    local begin_marker="# BEGIN PHPSWITCH MANAGED BLOCK - DO NOT EDIT MANUALLY"
    local end_marker="# END PHPSWITCH MANAGED BLOCK"
    
    # Create secure temporary file
    local temp_file
    temp_file=$(utils_create_secure_temp_file)
    
    # Function to append the appropriate path setting code for each shell
    function append_path_code {
        local target_file="$1"
        
        if [ "$shell_type" = "fish" ]; then
            # Fish shell uses a different syntax for PATH manipulation
            cat >> "$target_file" << EOL
$begin_marker
# Path configuration for PHP version: $new_version
# Last updated: $(date)

# Prepend PHP paths, filtering out stale PHP entries to avoid duplicates
set -l _phpswitch_filtered
for _p in \$PATH
    string match -qv "*php*" -- \$_p; and set -a _phpswitch_filtered \$_p
end
set -gx PATH $php_bin_path $php_sbin_path \$_phpswitch_filtered

# Refresh the command hash
if type -q rehash
    rehash
end
$end_marker

EOL
        else
            # Bash/Zsh compatible code
            cat >> "$target_file" << EOL
$begin_marker
# Path configuration for PHP version: $new_version
# Last updated: $(date)

# Prepend PHP paths to PATH to ensure they take precedence
export PATH="$php_bin_path:$php_sbin_path:\$PATH"

# Force shell to forget previous command locations
hash -r 2>/dev/null || rehash 2>/dev/null || true

# Add this function to refresh your terminal after sourcing:
phpswitch_refresh() {
    # Rehash to find new binaries
    hash -r 2>/dev/null || rehash 2>/dev/null || true
    
    # Report the active PHP version
    echo "PHP now: \$(php -v | head -n 1)"
}
$end_marker

EOL
        fi
    }
    
    # Check if our markers already exist in the file
    if grep -q "$begin_marker" "$rc_file"; then
        # Replace existing block
        awk -v begin="$begin_marker" -v end="$end_marker" '
            !found && !between {print}
            index($0, begin) > 0 {found=1; between=1}
            index($0, end) > 0 {between=0}
            END {if (found) print ""}
        ' "$rc_file" > "$temp_file"

        # Append the new block
        append_path_code "$temp_file"

        # Add the rest of the file
        awk -v begin="$begin_marker" -v end="$end_marker" '
            between {next}
            index($0, begin) > 0 {between=1; next}
            index($0, end) > 0 {between=0; next}
            !found && !between {next}
            {print}
        ' "$rc_file" >> "$temp_file"
    else
        # No existing block - add to beginning of file
        append_path_code "$temp_file"
        
        # Add the original content
        cat "$rc_file" >> "$temp_file"
    fi
    
    # Move the temp file back to the original
    mv "$temp_file" "$rc_file"
    
    # Make sure file is executable for login shells
    chmod +x "$rc_file" 2>/dev/null || true
    
    utils_show_status "success" "Updated PATH in $rc_file for $new_version"
    
    # Create instructions file for sourcing
    local instructions_file
    instructions_file=$(utils_create_secure_temp_file)
    
    if [ "$shell_type" = "fish" ]; then
        echo "source \"$rc_file\"" > "$instructions_file"
    else
        echo "source \"$rc_file\"" > "$instructions_file"
    fi
    
    chmod +x "$instructions_file"
    
    # Return the path to the instructions file so it can be used by the caller
    echo "$instructions_file"
}

# Completely redesigned shell_force_reload function for immediate effect
function shell_force_reload {
    local version="$1"
    local php_bin_path=""
    local php_sbin_path=""
    local shell_type=$(shell_detect_shell)
    
    if [ "$version" = "php@default" ]; then
        php_bin_path="$HOMEBREW_PREFIX/opt/php/bin"
        php_sbin_path="$HOMEBREW_PREFIX/opt/php/sbin"
    else
        php_bin_path="$HOMEBREW_PREFIX/opt/$version/bin"
        php_sbin_path="$HOMEBREW_PREFIX/opt/$version/sbin"
    fi
    
    # Check that the directories exist
    if [ ! -d "$php_bin_path" ] || [ ! -d "$php_sbin_path" ]; then
        utils_show_status "error" "PHP binary directories not found at $php_bin_path or $php_sbin_path"
        return 1
    fi
    
    # Log the current PATH for debugging
    core_debug_log "Before PATH update: $PATH"
    
    # Direct PATH manipulation for the current shell
    # First, remove any existing PHP paths from PATH
    local new_path=""
    local found_php=false
    
    if [ "$shell_type" = "fish" ]; then
        # For fish shell, we need to tell user to do this manually
        echo "To update PATH in current fish shell session, run:"
        echo "set --erase PATH"
        echo "fish_add_path $php_bin_path"
        echo "fish_add_path $php_sbin_path"
        echo "fish_add_path /usr/local/bin /usr/bin /bin /usr/sbin /sbin"
        echo "rehash"
        return 0
    else
        # For bash/zsh, we can directly modify the current shell's PATH
        
        # Build a new PATH with PHP paths at the beginning
        local system_paths=""
        local php_paths="$php_bin_path:$php_sbin_path"
        
        # Validate PHP paths before using them
        if ! utils_validate_path "$php_bin_path"; then
            utils_show_status "error" "Invalid PHP bin path: $php_bin_path"
            return 1
        fi
        if ! utils_validate_path "$php_sbin_path"; then
            utils_show_status "error" "Invalid PHP sbin path: $php_sbin_path"
            return 1
        fi
        
        IFS=:
        for path_component in $PATH; do
            # Validate each path component before processing
            if [[ -n "$path_component" ]]; then
                if ! utils_validate_path "$path_component" "true"; then
                    core_debug_log "Skipping invalid PATH component: $path_component"
                    continue
                fi
                
                # Skip any PHP-related paths
                if echo "$path_component" | grep -q -i "php"; then
                    found_php=true
                    continue
                fi
                
                # Add non-PHP paths
                if [ -z "$system_paths" ]; then
                    system_paths="$path_component"
                else
                    system_paths="$system_paths:$path_component"
                fi
            fi
        done
        unset IFS
        
        # Set the new PATH with PHP paths first
        export PATH="$php_bin_path:$php_sbin_path:$system_paths"
        
        # Force the shell to forget previous command locations
        hash -r 2>/dev/null || rehash 2>/dev/null || true
        
        # Log the updated PATH for debugging
        core_debug_log "After PATH update: $PATH"
        
        # Verify PHP version
        local current_php=$(which php)
        core_debug_log "PHP now resolves to: $current_php"
        
        if [[ "$current_php" == *"$version"* ]] || [[ "$current_php" == *"php/bin/php" && "$version" == "php@default" ]]; then
            core_debug_log "PATH update successful"
            return 0
        else
            core_debug_log "PATH update failed. PHP still resolves to: $current_php"
            return 1
        fi
    fi
}

# Function to cleanup old backup files
function shell_cleanup_backups {
    local file_prefix="$1"
    local max_backups="${MAX_BACKUPS:-5}"
    
    # Collect backups via glob into array (safe: no word-splitting)
    local -a backup_files=()
    local f
    for f in "${file_prefix}.bak."*; do
        [ -e "$f" ] && backup_files+=("$f")
    done
    local count=${#backup_files[@]}
    if [ "$count" -gt "$max_backups" ]; then
        local to_delete=$(( count - max_backups ))
        # Sort by mtime ascending (oldest first), remove the excess
        while IFS= read -r old_backup; do
            [ -f "$old_backup" ] || continue
            core_debug_log "Removing old backup: $old_backup"
            rm -f "$old_backup"
            (( to_delete-- ))
            [ "$to_delete" -le 0 ] && break
        done < <(stat -f '%m %N' "${backup_files[@]}" 2>/dev/null | sort -n | awk '{print $2}')
    fi
}

# Function to create a direct executable script that can be sourced to reload PHP
function shell_create_reload_script {
    local version="$1"
    local shell_type=$(shell_detect_shell)
    local php_bin_path=""
    local php_sbin_path=""
    
    if [ "$version" = "php@default" ]; then
        php_bin_path="$HOMEBREW_PREFIX/opt/php/bin"
        php_sbin_path="$HOMEBREW_PREFIX/opt/php/sbin"
    else
        php_bin_path="$HOMEBREW_PREFIX/opt/$version/bin"
        php_sbin_path="$HOMEBREW_PREFIX/opt/$version/sbin"
    fi
    
    # Create a temporary script that can be sourced to reload the PATH
    local reload_script
    reload_script=$(utils_create_secure_temp_file)
    
    if [ "$shell_type" = "fish" ]; then
        cat > "$reload_script" << EOL
#!/usr/bin/env fish
# PHPSwitch temporary reload script for fish shell
# Generated: $(date)

echo "Reloading PATH with PHP $version..."

# Prepend PHP paths, filtering out stale PHP entries to avoid duplicates
set -l _phpswitch_filtered
for _p in \$PATH
    string match -qv "*php*" -- \$_p; and set -a _phpswitch_filtered \$_p
end
set -gx PATH $php_bin_path $php_sbin_path \$_phpswitch_filtered

# Refresh command hash
if type -q rehash
    rehash
end

# Verify PHP version
echo "Active PHP version is now: "(php -v | head -n 1)
EOL
    else
        # For bash/zsh
        cat > "$reload_script" << EOL
#!/bin/bash
# PHPSwitch temporary reload script for bash/zsh shell
# Generated: $(date)

echo "Reloading PATH with PHP $version..."

# Build new PATH with PHP directories at the beginning
NEW_PATH="$php_bin_path:$php_sbin_path"

# Add back non-PHP paths
OLD_IFS=\$IFS
IFS=:
for path_component in \$PATH; do
    # Skip PHP-related paths
    if echo "\$path_component" | grep -q -i "php"; then
        continue
    fi
    
    # Add non-PHP path
    NEW_PATH="\$NEW_PATH:\$path_component"
done
IFS=\$OLD_IFS

# Set the new PATH
export PATH="\$NEW_PATH"

# Force shell to forget previous command locations
hash -r 2>/dev/null || rehash 2>/dev/null || true

# Verify PHP version
echo "Active PHP version is now: \$(php -v | head -n 1)"
EOL
    fi
    
    chmod +x "$reload_script"
    echo "$reload_script"
}
# Module: version.sh
# PHPSwitch Version Management
# Handles PHP version switching, installation, and uninstallation

# Function to properly handle the default PHP and versioned PHP
function version_resolve_php_version {
    local version="$1"
    
    # If the version directory exists, use it directly
    if [ -d "$HOMEBREW_PREFIX/opt/$version" ]; then
        echo "$version"
        return
    fi
    
    # If it's php@default, return as is
    if [ "$version" = "php@default" ]; then
        echo "$version"
        return
    fi
    
    # Check if this version matches the default php version
    # Only if the specific version folder doesn't exist (checked above)
    if [ -d "$HOMEBREW_PREFIX/opt/php" ]; then
        # Get default php version (e.g. 8.4)
        local default_version_full=$(brew list --versions php | head -n 1)
        local default_version_str=$(echo "$default_version_full" | awk '{print $2}')
        local default_version=$(echo "$default_version_str" | cut -d. -f1,2)
        
        # Check if requested version matches default version (e.g. php@8.4 == 8.4)
        local requested_num=$(echo "$version" | sed 's/php@//')
        
        if [ "$requested_num" = "$default_version" ]; then
            echo "php@default"
            return
        fi
    fi
    
    # Return the original version if no resolution found
    echo "$version"
}

# Function to check for project-specific PHP version
function version_check_project {
    local current_dir="$(pwd)"
    local php_version_file=""
    local project_version=""
    local custom_files=(".php-version" ".phpversion" ".php")
    
    # Look for version files in current directory and parent directories
    while [ "$current_dir" != "/" ] && [ "$current_dir" != "." ]; do
        # 1. Custom PHPSwitch files (Highest Priority)
        for file in "${custom_files[@]}"; do
            if [ -f "$current_dir/$file" ]; then
                php_version_file="$current_dir/$file"
                project_version=$(cat "$php_version_file" | tr -d '[:space:]')
                core_debug_log "Found PHP version file: $php_version_file"
                break 2
            fi
        done
        
        # 2. composer.json
        if [ -f "$current_dir/composer.json" ]; then
            if composer_ver=$(utils_read_composer_version "$current_dir/composer.json"); then
                if [ -n "$composer_ver" ]; then
                    php_version_file="$current_dir/composer.json"
                    project_version="$composer_ver"
                    core_debug_log "Found PHP version in composer.json: $composer_ver"
                    break
                fi
            fi
        fi
        
        # 3. .tool-versions
        if [ -f "$current_dir/.tool-versions" ]; then
            if tool_ver=$(utils_read_tool_versions "$current_dir/.tool-versions"); then
                if [ -n "$tool_ver" ]; then
                    php_version_file="$current_dir/.tool-versions"
                    project_version="$tool_ver"
                    core_debug_log "Found PHP version in .tool-versions: $tool_ver"
                    break
                fi
            fi
        fi
        
        # Move to parent directory
        current_dir="$(dirname "$current_dir")"
    done
    
    if [ -n "$php_version_file" ] && [ -n "$project_version" ]; then
        # Validate the version file path
        if ! utils_validate_path "$php_version_file"; then
            core_debug_log "Invalid version file path: $php_version_file"
            return 1
        fi
        
        # Basic validation: check length and characters
        if [[ ${#project_version} -gt 32 ]]; then
            core_debug_log "Version string too long in $php_version_file"
            return 1
        fi
        
        # Validate version string against an allowlist of safe characters.
        # Avoids $'\0' in [[ == ]] patterns which expands to empty on bash 3.2 (macOS),
        # turning *$'\0'* into ** and matching every string.
        if ! [[ "$project_version" =~ ^[a-zA-Z0-9.@_-]+$ ]]; then
            core_debug_log "Invalid characters in version string from: $php_version_file"
            return 1
        fi
        
        # Handle different version formats
        if [[ "$project_version" == php@* ]]; then
            # Already in the right format (php@8.1)
            echo "$project_version"
            return 0
        elif [[ "$project_version" == *\.* ]]; then
            # Version number only (8.1)
            echo "php@$project_version"
            return 0
        elif [[ "$project_version" =~ ^[0-9]+$ ]]; then
            # Major version only (8)
            # Find the highest installed minor version
            local highest_minor=""
            local highest_version=""
            
            while read -r version; do
                if [[ "$version" == php@"$project_version".* ]]; then
                    local minor_ver=$(echo "$version" | sed "s/php@$project_version\.\(.*\)/\1/")
                    if [ -z "$highest_minor" ] || [ "$minor_ver" -gt "$highest_minor" ]; then
                        highest_minor="$minor_ver"
                        highest_version="$version"
                    fi
                fi
            done < <(core_get_installed_php_versions)
            
            if [ -n "$highest_version" ]; then
                echo "$highest_version"
                return 0
            else
                # No matching version found, try format php@8.0
                echo "php@$project_version.0"
                return 0
            fi
        else
             core_debug_log "Unknown version format: $project_version"
             return 1
        fi
    fi
    
    return 1
}

# Function to create a project PHP version file
function version_set_project {
    local version="$1"
    local file_name=".php-version"
    
    # Extract the version number from php@X.Y format
    if [[ "$version" == php@* ]]; then
        version="${version#php@}"
    fi
    
    printf "  Create %s in the current directory with version %s? (y/n) " "$file_name" "$version"
    if [ "$(utils_validate_yes_no "" "y")" = "y" ]; then
        echo "$version" > "$file_name"
        utils_show_status "success" "Created project PHP version file: $file_name"
        utils_show_status "info" "This directory and its subdirectories will now use PHP $version"
    fi
}

# Enhanced install_php function with improved error handling
function version_install_php {
    local version="$1"
    local install_version="$version"
    
    # Handle default PHP installation
    if [ "$version" = "php@default" ]; then
        install_version="php"
    fi
    
    utils_show_status "info" "Installing $install_version... This may take a while..."
    
    # Capture both stdout and stderr from brew install
    local temp_output
    temp_output=$(utils_create_secure_temp_file) || { utils_show_status "error" "Failed to create temp file"; return 1; }
    if brew install "$install_version" > "$temp_output" 2>&1; then
        utils_show_status "success" "$version installed successfully"
        rm -f "$temp_output"
        return 0
    else
        local error_output=$(cat "$temp_output")
        rm -f "$temp_output"
        
        # Check for specific error conditions
        if echo "$error_output" | grep -q "Permission denied"; then
            utils_show_status "error" "Permission denied during installation. Try running with sudo."
        elif echo "$error_output" | grep -q "Resource busy"; then
            utils_show_status "error" "Resource busy error. Another process may be using PHP files."
            echo "Try closing applications that might be using PHP, or restart your computer."
        elif echo "$error_output" | grep -q "already installed"; then
            utils_show_status "warning" "$version appears to be already installed but may be broken"
            printf "  Reinstall it? (y/n) "
            if [ "$(utils_validate_yes_no "" "y")" = "y" ]; then
                if brew reinstall "$install_version"; then
                    utils_show_status "success" "$version reinstalled successfully"
                    return 0
                else
                    utils_show_status "error" "Reinstallation failed"
                fi
            fi
        elif echo "$error_output" | grep -q "No available formula"; then
            utils_show_status "error" "Formula not found: $install_version"
            echo "This PHP version may not be available in Homebrew."
            echo "Check available versions with: brew search php"
        elif echo "$error_output" | grep -q "Homebrew must be run under Ruby 2.6"; then
            utils_show_status "error" "Homebrew Ruby version issue detected"
            echo "This is a known Homebrew issue. Try running:"
            echo "brew update-reset"
        elif echo "$error_output" | grep -q "cannot install because it conflicts with"; then
            utils_show_status "error" "Installation conflict detected"
            echo "There appears to be a conflict with another package."
            local conflicting_package
            conflicting_package=$(echo "$error_output" | grep -o "conflicts with [^ ]*" | cut -d' ' -f3)
            # Validate before using in commands — only allow safe package name characters
            if [ -n "$conflicting_package" ] && [[ "$conflicting_package" =~ ^[a-zA-Z0-9@._-]+$ ]]; then
                echo "The conflicting package is: $conflicting_package"
                printf "  Uninstall the conflicting package? (y/n) "
                if [ "$(utils_validate_yes_no "" "n")" = "y" ]; then
                    if brew uninstall "$conflicting_package"; then
                        utils_show_status "success" "Uninstalled $conflicting_package"
                        utils_show_status "info" "Retrying installation of $version..."
                        if brew install "$install_version"; then
                            utils_show_status "success" "$version installed successfully"
                            return 0
                        fi
                    else
                        utils_show_status "error" "Failed to uninstall $conflicting_package"
                    fi
                fi
            fi
        else
            utils_show_status "error" "Failed to install $version"
        fi
        
        printf "\n  Error details:\n\n"
        echo "$error_output" | head -n 10
        if [ $(echo "$error_output" | wc -l) -gt 10 ]; then
            printf "  ... (truncated, see full log with 'brew install -v %s')\n" "$install_version"
        fi
        printf "\n  Possible solutions:\n\n"
        printf "    1  Run 'brew doctor' to check your Homebrew installation\n"
        printf "    2  Run 'brew update' and try again\n"
        printf "    3  Check conflicts with 'brew deps --tree %s'\n" "$version"
        printf "    4  Uninstall conflicting packages first\n"
        printf "    5  Try verbose output: 'brew install -v %s'\n\n" "$version"
        printf "  Try a different approach? (y/n) "

        if [ "$(utils_validate_yes_no "" "n")" = "y" ]; then
            printf "\n  Choose an option:\n\n"
            printf "    1  run 'brew doctor' then retry\n"
            printf "    2  run 'brew update' then retry\n"
            printf "    3  install with verbose output\n"
            printf "    4  force reinstall\n"
            printf "    5  exit and handle manually\n\n"

            local valid_choice=false
            local fix_option

            while [ "$valid_choice" = "false" ]; do
                read -r fix_option

                if [[ "$fix_option" =~ ^[1-5]$ ]]; then
                    valid_choice=true
                else
                    printf "  Enter a number between 1 and 5 "
                fi
            done
            
            case $fix_option in
                1)
                    utils_show_status "info" "Running 'brew doctor'..."
                    brew doctor
                    utils_show_status "info" "Retrying installation..."
                    brew install "$install_version"
                    ;;
                2)
                    utils_show_status "info" "Running 'brew update'..."
                    brew update
                    utils_show_status "info" "Retrying installation..."
                    brew install "$install_version"
                    ;;
                3)
                    utils_show_status "info" "Installing with verbose output..."
                    brew install -v "$install_version"
                    ;;
                4)
                    utils_show_status "info" "Trying force reinstall..."
                    brew install --force --build-from-source "$install_version"
                    ;;
                5)
                    utils_show_status "info" "Exiting. You can try to install manually with:"
                    echo "brew install $install_version"
                    return 1
                    ;;
            esac
            
            # Check if the retry was successful
            local _installed_list
            _installed_list=$(brew list --formula 2>/dev/null)
            if echo "$_installed_list" | grep -q "^$install_version$" || \
               ([ "$install_version" = "php" ] && echo "$_installed_list" | grep -q "^php$"); then
                utils_show_status "success" "$version installed successfully on retry"
                return 0
            else
                utils_show_status "error" "Installation still failed. Please try to install manually:"
                echo "brew install $install_version"
                return 1
            fi
        else
            return 1
        fi
    fi
}

# Function to uninstall PHP version
function version_uninstall_php {
    local version="$1"
    local service_name=$(fpm_get_service_name "$version")
    
    if ! core_check_php_installed "$version"; then
        utils_show_status "error" "$version is not installed"
        return 1
    fi
    
    # Check if it's the current active version
    local current_version=$(core_get_current_php_version)
    if [ "$current_version" = "$version" ]; then
        utils_show_status "warning" "You are attempting to uninstall the currently active PHP version"
        printf "  Continue? This may break your PHP environment. (y/n) "

        if [ "$(utils_validate_yes_no "" "n")" = "n" ]; then
            utils_show_status "info" "Uninstallation cancelled"
            return 1
        fi
    fi
    
    # Stop PHP-FPM service if running
    if brew services list | grep -q "$service_name"; then
        utils_show_status "info" "Stopping PHP-FPM service for $version..."
        brew services stop "$service_name"
        
        # Clean up service files to avoid issues on future installations
        if command -v fpm_cleanup_service &>/dev/null; then
            fpm_cleanup_service "$version"
        fi
    fi
    
    # Unlink the PHP version if it's linked
    if [ "$current_version" = "$version" ]; then
        utils_show_status "info" "Unlinking $version..."
        brew unlink "$version" &>/dev/null
    fi
    
    # Uninstall the PHP version
    utils_show_status "info" "Uninstalling $version... This may take a while"
    local uninstall_cmd="$version"
    
    if [ "$version" = "php@default" ]; then
        uninstall_cmd="php"
    fi
    
    if brew uninstall "$uninstall_cmd"; then
        utils_show_status "success" "$version has been uninstalled"
        
        # Ask about config files
        printf "  Remove configuration files as well? (y/n) "

        if [ "$(utils_validate_yes_no "" "n")" = "y" ]; then
            # Extract version number (e.g., 8.2 from php@8.2)
            local php_version="${version#php@}"
            if [ -d "$HOMEBREW_PREFIX/etc/php/$php_version" ]; then
                utils_show_status "info" "Removing configuration files..."
                sudo rm -rf "$HOMEBREW_PREFIX/etc/php/$php_version"
                utils_show_status "success" "Configuration files removed"
            else
                utils_show_status "warning" "Configuration directory not found at $HOMEBREW_PREFIX/etc/php/$php_version"
            fi
        fi
        
        # If this was the active version, suggest switching to another version
        if [ "$current_version" = "$version" ]; then
            utils_show_status "warning" "You have uninstalled the active PHP version"
            printf "  Switch to another installed PHP version? (y/n) "

            if [ "$(utils_validate_yes_no "" "y")" = "y" ]; then
                # Show menu with remaining PHP versions
                return 2
            else
                utils_show_status "info" "Please manually switch to another PHP version if needed"
            fi
        fi
        
        return 0
    else
        utils_show_status "error" "Failed to uninstall $version"
        echo "You may want to try:"
        echo "  brew uninstall --force $version"
        return 1
    fi
}

# Improved function to switch PHP version with enhanced PATH handling
function version_switch_php {
    local new_version="$1"
    local is_installed="$2"
    local current_version=$(core_get_current_php_version)
    
    # Resolve potential version confusion (php@8.4 vs php@default)
    new_version=$(version_resolve_php_version "$new_version")
    
    local brew_version="$new_version"
    
    # Handle default PHP
    if [ "$new_version" = "php@default" ]; then
        brew_version="php"
    fi
    
    # Install the version if not installed
    if [ "$is_installed" = "false" ]; then
        utils_show_status "info" "$new_version is not installed"
        printf "  Install it? (y/n) "

        if [ "$(utils_validate_yes_no "" "n")" = "y" ]; then
            if ! version_install_php "$new_version"; then
                utils_show_status "error" "Installation failed"
                exit 1
            fi
            
            # Double check that it's actually installed now
            if ! core_check_php_installed "$new_version"; then
                utils_show_status "error" "$new_version was not properly installed despite Homebrew reporting success"
                echo "Please try to install it manually with: brew install $brew_version"
                exit 1
            fi
        else
            utils_show_status "info" "Installation cancelled"
            exit 0
        fi
    else
        # Verify that the installed version is actually available
        if ! core_check_php_installed "$new_version"; then
            utils_show_status "warning" "$new_version seems to be installed according to Homebrew,"
            echo "but the PHP binary couldn't be found at expected location."
            
            # Check if the directory exists but the binary is missing
            local php_bin_path=""
            if [ "$new_version" = "php@default" ]; then
                php_bin_path="$HOMEBREW_PREFIX/opt/php/bin/php"
            else
                php_bin_path="$HOMEBREW_PREFIX/opt/$new_version/bin/php"
            fi
            
            if [ -d "$(dirname "$php_bin_path")" ] && [ ! -f "$php_bin_path" ]; then
                utils_show_status "error" "Directory exists but PHP binary is missing: $php_bin_path"
                echo "This suggests a corrupted installation."
            elif [ ! -d "$(dirname "$php_bin_path")" ]; then
                utils_show_status "error" "PHP installation directory is missing: $(dirname "$php_bin_path")"
                echo "This suggests the package is registered but files are missing."
            fi
            
            printf "  Attempt to reinstall it? (y/n) "

            if [ "$(utils_validate_yes_no "" "y")" = "y" ]; then
                if ! brew reinstall "$brew_version"; then
                    utils_show_status "error" "Reinstallation failed, trying forced reinstall..."
                    if ! brew reinstall --force "$brew_version"; then
                        utils_show_status "error" "Forced reinstallation also failed"
                        echo "Try uninstalling first: brew uninstall $brew_version"
                        exit 1
                    fi
                fi
                
                # Check if reinstall fixed the issue
                if ! core_check_php_installed "$new_version"; then
                    utils_show_status "error" "Reinstallation did not fix the issue"
                    exit 1
                else
                    utils_show_status "success" "Reinstallation successful"
                fi
            else
                utils_show_status "info" "Skipping reinstallation. Proceeding with version switch..."
            fi
        fi
    fi
    
    if [ "$current_version" = "$new_version" ]; then
        utils_show_status "info" "$new_version is already active in Homebrew"
    else
        utils_show_status "info" "Switching from $current_version to $new_version..."

        # Unlink current PHP (if any)
        if [ "$current_version" != "none" ]; then
            utils_show_status "info" "Unlinking $current_version..."
            brew unlink "$current_version" &>/dev/null
        fi

        # Link new PHP with progressive fallback strategies
        utils_show_status "info" "Linking $new_version..."

        # Strategy 1: Normal linking
        if brew link --force "$brew_version" &>/dev/null; then
            utils_show_status "success" "Linked $new_version successfully"
        # Strategy 2: Overwrite linking
        elif brew link --overwrite "$brew_version" &>/dev/null; then
            utils_show_status "success" "Linked $new_version with overwrite option"
        # Strategy 3: Manual symlinking
        else
            utils_show_status "warning" "Standard linking methods failed, trying manual symlinking..."
            
            # Try to directly create symlinks
            local php_bin_path="$HOMEBREW_PREFIX/opt/$brew_version/bin"
            local php_sbin_path="$HOMEBREW_PREFIX/opt/$brew_version/sbin"
            
            if [ ! -d "$php_bin_path" ] && [ "$new_version" = "php@default" ]; then
                php_bin_path="$HOMEBREW_PREFIX/opt/php/bin"
                php_sbin_path="$HOMEBREW_PREFIX/opt/php/sbin"
            fi
            
            if [ -d "$php_bin_path" ]; then
                for file in "$php_bin_path"/*; do
                    if [ -f "$file" ] && [ -x "$file" ]; then
                        local filename
                        filename=$(basename "$file")
                        sudo ln -sf "$file" "$HOMEBREW_PREFIX/bin/$filename" 2>/dev/null
                    fi
                done
                utils_show_status "success" "Manual linking completed"
            else
                utils_show_status "error" "Could not find PHP installation directory"
                exit 1
            fi
        fi
    fi
    
    # Create and update shell configuration
    local instructions_file=$(shell_update_rc "$new_version")
    
    # Create a reload script for immediate use
    local reload_script=$(shell_create_reload_script "$new_version")
    
    # Restart PHP-FPM if it's being used
    fpm_restart "$new_version"
    
    utils_show_status "success" "PHP version switched to $new_version"
    
    # Try to apply changes to the current shell
    if [ -z "$SOURCED" ]; then
        export SOURCED=true
        utils_show_status "info" "Applying changes to current shell..."

        if shell_force_reload "$new_version"; then
            utils_show_status "success" "Active PHP version is now: $(php -v | head -n 1 | cut -d " " -f 2)"
        else
            shell_type=$(shell_detect_shell)
            utils_show_status "warning" "Could not update PATH in current shell"
            printf "\n  To activate %s in your current terminal:\n\n" "$new_version"
            printf "    source \"%s\"\n\n" "$reload_script"
            printf "  PHP binary location: %s\n" "$(which php)"
            if [ -L "$(which php)" ]; then
                printf "  Symlinked to: %s\n" "$(readlink "$(which php)")"
            fi
            printf "\n  For permanent effect, open a new terminal or reload your shell:\n\n"

            case "$shell_type" in
                "zsh")
                    printf "    source ~/.zshrc\n"
                    ;;
                "bash")
                    if [ -f ~/.bashrc ]; then
                        printf "    source ~/.bashrc\n"
                    elif [ -f ~/.bash_profile ]; then
                        printf "    source ~/.bash_profile\n"
                    else
                        printf "    source ~/.profile\n"
                    fi
                    ;;
                "fish")
                    printf "    source ~/.config/fish/config.fish\n"
                    ;;
                *)
                    printf "    source ~/.profile\n"
                    ;;
            esac
            printf "\n"
        fi
    else
        printf "\n  To apply changes to your current terminal:\n\n"
        printf "    source \"%s\"\n\n" "$reload_script"
    fi
}

# NOTE: version_auto_switch_php is not called anywhere. Auto-switching dispatches
# through auto_switch_php in auto-switch.sh via the --auto-mode command flag.
# Retained here in case it is needed for future direct programmatic use.
function version_auto_switch_php {
    local new_version="$1"
    local brew_version="$new_version"
    local current_version=$(core_get_current_php_version)
    
    # If versions are the same, no need to switch
    if [ "$current_version" = "$new_version" ]; then
        return 0
    fi
    
    core_debug_log "Auto-switching from $current_version to $new_version"
    
    # Handle default PHP
    if [ "$new_version" = "php@default" ]; then
        brew_version="php"
    fi
    
    # Unlink current PHP
    brew unlink "$current_version" &>/dev/null
    
    # Link new PHP
    brew link --force "$brew_version" &>/dev/null
    
    # Update PATH for current session
    shell_force_reload "$new_version" &>/dev/null

    # No UI feedback for auto-switching
    return 0
}
# Module: fpm.sh
# PHPSwitch PHP-FPM Management
# Handles PHP-FPM service operations

# Function to handle PHP version for commands (handles default php)
function fpm_get_service_name {
    local version="$1"
    
    if [ "$version" = "php@default" ]; then
        echo "php"
    else
        echo "$version"
    fi
}

# Function to stop all other PHP-FPM services except the active one
function fpm_stop_other_services {
    local active_version="$1"
    local active_service=$(fpm_get_service_name "$active_version")
    
    # Get only actively running PHP services
    local running_services
    running_services=$(brew services list | grep -E "^php(@[0-9]\.[0-9])?" | awk '$2 == "started" {print $1}')

    while IFS= read -r service; do
        [ -z "$service" ] && continue
        if [ "$service" != "$active_service" ]; then
            utils_show_status "info" "Stopping PHP-FPM service for $service..."
            brew services stop "$service" >/dev/null 2>&1
        fi
    done <<< "$running_services"
}

# Function to clean up PHP-FPM service files and fix permissions
function fpm_cleanup_service {
    local version="$1"
    local service_name=$(fpm_get_service_name "$version")
    
    utils_show_status "info" "Cleaning up PHP-FPM service files for $service_name..."
    
    # Stop the service first
    brew services stop "$service_name" >/dev/null 2>&1
    
    # Find and remove LaunchAgent/LaunchDaemon files
    local launch_agent="$HOME/Library/LaunchAgents/homebrew.mxcl.$service_name.plist"
    local launch_daemon="/Library/LaunchDaemons/homebrew.mxcl.$service_name.plist"
    
    if [ -f "$launch_agent" ]; then
        utils_show_status "info" "Removing LaunchAgent file: $launch_agent"
        rm -f "$launch_agent" 2>/dev/null
    fi
    
    if [ -f "$launch_daemon" ]; then
        utils_show_status "info" "Removing LaunchDaemon file (requires sudo): $launch_daemon"
        sudo rm -f "$launch_daemon" 2>/dev/null
    fi
    
    # Reset permissions if needed
    local cellar_path="$HOMEBREW_PREFIX/Cellar/$service_name"
    local opt_path="$HOMEBREW_PREFIX/opt/$service_name"
    
    if [ -d "$cellar_path" ]; then
        utils_show_status "info" "Resetting permissions for: $cellar_path"
        # Get secure username and validate it
        local username
        username="$(id -un)"
        if utils_validate_username "$username"; then
            sudo chown -R "$username" "$cellar_path" 2>/dev/null
        else
            utils_show_status "error" "Invalid username detected, skipping permission reset"
        fi
    fi
    
    if [ -d "$opt_path" ]; then
        utils_show_status "info" "Resetting permissions for: $opt_path"
        # Get secure username and validate it
        local username
        username="$(id -un)"
        if utils_validate_username "$username"; then
            sudo chown -R "$username" "$opt_path" 2>/dev/null
        else
            utils_show_status "error" "Invalid username detected, skipping permission reset"
        fi
    fi
    
    # Run brew services cleanup to clear stale services
    utils_show_status "info" "Running brew services cleanup..."
    brew services cleanup >/dev/null 2>&1
    
    utils_show_status "success" "Service cleanup completed for $service_name"
}

# Enhanced restart_php_fpm function with better error handling
function fpm_restart {
    local version="$1"
    local service_name=$(fpm_get_service_name "$version")
    
    if [ "$AUTO_RESTART_PHP_FPM" != "true" ]; then
        core_debug_log "Auto restart PHP-FPM is disabled in config"
        return 0
    fi
    
    # First, stop all other PHP-FPM services
    fpm_stop_other_services "$version"
    
    # Check if PHP-FPM service is running (awk exact-field match avoids false positives,
    # e.g. "php" matching "php@8.1" with plain grep)
    if brew services list | awk -v svc="$service_name" '$1 == svc' | grep -q "started"; then
        utils_show_status "info" "Restarting PHP-FPM service for $service_name..."
        
        # Try normal restart first
        local restart_output=$(brew services restart "$service_name" 2>&1)
        if echo "$restart_output" | grep -q "Successfully"; then
            utils_show_status "success" "PHP-FPM service restarted successfully"
        else
            utils_show_status "warning" "Failed to restart service: $restart_output"
            
            # Check for specific error patterns
            if echo "$restart_output" | grep -q "Bootstrap failed: 5: Input/output error"; then
                utils_show_status "warning" "Detected bootstrap error. Attempting automatic service cleanup and repair..."
                fpm_cleanup_service "$version"
                utils_show_status "info" "Trying restart after cleanup..."
                local retry_output=$(brew services start "$service_name" 2>&1)

                if echo "$retry_output" | grep -q "Successfully"; then
                    utils_show_status "success" "PHP-FPM service started successfully after cleanup"
                else
                    utils_show_status "error" "Failed to start service after cleanup: $retry_output"
                    printf "  You may need to restart your computer or reinstall PHP %s\n" "$version"
                    printf "  Try running: brew reinstall %s\n" "$service_name"
                fi
            # Check for other error types
            elif echo "$restart_output" | grep -q "Permission denied"; then
                utils_show_status "warning" "Permission denied. Attempting automatic service cleanup and repair..."
                fpm_cleanup_service "$version"
                utils_show_status "info" "Trying restart after cleanup..."
                local cleanup_output=$(brew services start "$service_name" 2>&1)

                if echo "$cleanup_output" | grep -q "Successfully"; then
                    utils_show_status "success" "PHP-FPM service restarted successfully after cleanup"
                else
                    printf "  Try with sudo instead? (y/n) "
                    if [ "$(utils_validate_yes_no "" "y")" = "y" ]; then
                        utils_show_status "info" "Trying with sudo..."
                        local sudo_output=$(sudo brew services restart "$service_name" 2>&1)
                        if echo "$sudo_output" | grep -q "Successfully"; then
                            utils_show_status "success" "PHP-FPM service restarted successfully with sudo"
                            utils_show_status "warning" "Running with sudo changes file ownership. You may need to run cleanup later."
                        else
                            utils_show_status "error" "Failed to restart service with sudo: $sudo_output"
                            printf "  You may need to restart manually with:\n"
                            printf "    sudo brew services restart %s\n" "$service_name"
                        fi
                    fi
                fi
            elif echo "$restart_output" | grep -q "already started"; then
                utils_show_status "warning" "Service reports as already started. Forcing stop and restart..."
                brew services stop "$service_name" >/dev/null 2>&1
                local _i=0
                while [ $_i -lt 6 ] && brew services list | awk -v svc="$service_name" '$1 == svc' | grep -q "started"; do
                    sleep 0.5
                    _i=$(( _i + 1 ))
                done
                local force_start_output
                force_start_output=$(brew services start "$service_name" 2>&1)
                if echo "$force_start_output" | grep -q "Successfully"; then
                    utils_show_status "success" "PHP-FPM service started successfully"
                else
                    utils_show_status "error" "Failed to start service after force restart: $force_start_output"
                    printf "  Manual restart may be required: brew services restart %s\n" "$service_name"
                fi
            else
                utils_show_status "error" "Unknown error restarting service. Attempting cleanup and repair..."
                fpm_cleanup_service "$version"
                utils_show_status "info" "Trying restart after cleanup..."
                local unknown_retry=$(brew services start "$service_name" 2>&1)

                if echo "$unknown_retry" | grep -q "Successfully"; then
                    utils_show_status "success" "PHP-FPM service started successfully after cleanup"
                else
                    utils_show_status "error" "Could not recover service automatically"
                    printf "  Manual restart may be required: brew services restart %s\n" "$service_name"
                fi
            fi
        fi
    else
        utils_show_status "info" "Starting PHP-FPM service for $service_name..."
        local start_output=$(brew services start "$service_name" 2>&1)

        if echo "$start_output" | grep -q "Successfully"; then
            utils_show_status "success" "PHP-FPM service started successfully"
        else
            utils_show_status "warning" "Failed to start service: $start_output"

            # Check for bootstrap/IO error specifically
            if echo "$start_output" | grep -q "Bootstrap failed: 5: Input/output error"; then
                utils_show_status "warning" "Detected bootstrap error. Attempting automatic service cleanup and repair..."
                fpm_cleanup_service "$version"
                utils_show_status "info" "Trying restart after cleanup..."
                local retry_output=$(brew services start "$service_name" 2>&1)

                if echo "$retry_output" | grep -q "Successfully"; then
                    utils_show_status "success" "PHP-FPM service started successfully after cleanup"
                else
                    utils_show_status "error" "Failed to start service after cleanup: $retry_output"
                    printf "  Manual intervention may be required. Consider reinstalling PHP:\n"
                    printf "    brew reinstall %s\n" "$service_name"
                fi
            else
                printf "  Try with sudo? (y/n) "
                if [ "$(utils_validate_yes_no "" "y")" = "y" ]; then
                    utils_show_status "info" "Trying with sudo..."
                    sudo brew services start "$service_name"
                fi
            fi
        fi
    fi
    
    # Verify the service is running after our operations
    if brew services list | awk -v svc="$service_name" '$1 == svc' | grep -q "started"; then
        utils_show_status "success" "PHP-FPM service for $service_name is running"
    else
        utils_show_status "warning" "PHP-FPM service for $service_name may not be running correctly"
        printf "  Check status with: brew services list | grep php\n"
        printf "  PHP-FPM is only needed for web server integration.\n"
    fi
    
    return 0
}
# Module: extensions.sh
# PHPSwitch Extension Management
# Handles PHP extension operations

# Function to manage PHP extensions
function ext_manage_extensions {
    local php_version="$1"
    local service_name=$(fpm_get_service_name "$php_version")
    
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
    
    if [ "$USE_COLORS" = "true" ]; then
        printf "\n  "; utils_print_gradient "PHP Extensions for $php_version (version $numeric_version)" 192 132 252 103 232 249; printf "\n\n"
    else
        printf "\n  PHP Extensions for %s (version %s)\n\n" "$php_version" "$numeric_version"
    fi

    # List installed extensions
    if [ "$USE_COLORS" = "true" ]; then
        printf "  "; utils_print_gradient "Loaded extensions" 148 182 251 125 207 250; printf "\n\n"
    else
        printf "  Loaded extensions\n\n"
    fi
    php -m | sort | grep -v "\[" | sed 's/^/    /'

    printf "\n"
    if [ "$USE_COLORS" = "true" ]; then
        printf "  "; utils_print_gradient "Configuration files" 125 207 250 103 232 249; printf "\n\n"
    else
        printf "  Configuration files\n\n"
    fi

    if [ -d "$ini_dir" ]; then
        if [ -d "$ini_dir/conf.d" ]; then
            ls -1 "$ini_dir/conf.d" | grep -i "\.ini$" | sed 's/^/    /'
        else
            printf "    No conf.d directory found at %s/conf.d\n" "$ini_dir"
        fi
    else
        printf "    No configuration directory found at %s\n" "$ini_dir"
    fi

    if [ "$USE_COLORS" = "true" ]; then
        printf "\n  "; utils_print_gradient "Options" 103 232 249 85 245 248; printf "\n\n"
    else
        printf "\n  Options\n\n"
    fi
    printf "    1  enable/disable an extension\n"
    printf "    2  edit php.ini\n"
    printf "    3  show detailed extension information\n"
    printf "    0  back to main menu\n"
    printf "\n"
    if [ "$USE_COLORS" = "true" ]; then
        printf "  "; utils_print_gradient "Select (0-3)" 148 182 251 125 207 250; printf " "
    else
        printf "  Select (0-3) "
    fi
    
    local option
    read -r option
    
    case $option in
        1)
            printf "  Extension name "
            read -r ext_name
            # Validate: only lowercase letters, digits, underscores, hyphens
            if [[ -n "$ext_name" ]] && ! [[ "$ext_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
                utils_show_status "error" "Invalid extension name: $ext_name"
                return 1
            fi
            if [ -n "$ext_name" ]; then
                printf "\n  Action for %s\n\n" "$ext_name"
                printf "    1  enable\n"
                printf "    2  disable\n"
                printf "\n  Select (1-2) "
                
                local ext_action
                read -r ext_action
                
                if [ "$ext_action" = "1" ]; then
                    utils_show_status "info" "Enabling $ext_name..."
                    # Check if extension exists
                    if php -m | grep -q -i "^$ext_name$"; then
                        utils_show_status "info" "Extension $ext_name is already enabled"
                    else
                        # Try to enable via Homebrew
                        if brew install "$php_version-$ext_name" 2>/dev/null; then
                            utils_show_status "success" "Extension $ext_name installed via Homebrew"
                            fpm_restart "$php_version"
                        else
                            utils_show_status "warning" "Could not install via Homebrew, trying PECL..."
                            if pecl install "$ext_name"; then
                                utils_show_status "success" "Extension $ext_name installed via PECL"
                                fpm_restart "$php_version"
                            else
                                utils_show_status "error" "Failed to enable $ext_name"
                            fi
                        fi
                    fi
                elif [ "$ext_action" = "2" ]; then
                    utils_show_status "info" "Disabling $ext_name..."
                    if [ -f "$ini_dir/conf.d/ext-$ext_name.ini" ]; then
                        sudo mv "$ini_dir/conf.d/ext-$ext_name.ini" "$ini_dir/conf.d/ext-$ext_name.ini.disabled"
                        utils_show_status "success" "Extension $ext_name disabled"
                        fpm_restart "$php_version"
                    elif [ -f "$ini_dir/conf.d/$ext_name.ini" ]; then
                        sudo mv "$ini_dir/conf.d/$ext_name.ini" "$ini_dir/conf.d/$ext_name.ini.disabled"
                        utils_show_status "success" "Extension $ext_name disabled"
                        fpm_restart "$php_version"
                    else
                        utils_show_status "error" "Could not find configuration file for $ext_name"
                    fi
                fi
            fi
            ;;
        2)
            # Find and edit php.ini
            local php_ini="$ini_dir/php.ini"
            if [ -f "$php_ini" ]; then
                utils_show_status "info" "Opening php.ini for $php_version..."
                if [ -n "$EDITOR" ]; then
                    "$EDITOR" "$php_ini"
                else
                    nano "$php_ini"
                fi
                
                utils_show_status "info" "php.ini edited. Restart PHP-FPM to apply changes"
                printf "  Restart PHP-FPM now? (y/n) "
                if [ "$(utils_validate_yes_no "" "y")" = "y" ]; then
                    fpm_restart "$php_version"
                fi
            else
                utils_show_status "error" "php.ini not found at $php_ini"
            fi
            ;;
        3)
            printf "  Extension name (blank for all) "
            read -r ext_detail
            if [ -n "$ext_detail" ]; then
                php -i | grep -iF "$ext_detail" | less
            else
                php -i | less
            fi
            ;;
        0)
            return 0
            ;;
        *)
            utils_show_status "error" "Invalid option"
            ;;
    esac
    
    # Allow user to perform another extension management action
    printf "\n"
    printf "  Perform another action? (y/n) "
    if [ "$(utils_validate_yes_no "" "y")" = "y" ]; then
        ext_manage_extensions "$php_version"
    fi
}
# Module: auto-switch.sh
# PHPSwitch Auto-switching
# Handles automatic PHP version switching based on directory

# Function to install auto-switching hooks
function auto_install {
    local shell_type=$(shell_detect_shell)
    
    utils_show_status "info" "Setting up auto-switching for $shell_type shell..."
    
    case "$shell_type" in
        "zsh")
            auto_install_zsh
            ;;
        "bash")
            auto_install_bash
            ;;
        "fish")
            auto_install_fish
            ;;
        *)
            utils_show_status "error" "Unsupported shell: $SHELL"
            printf "  Auto-switching is only supported for bash, zsh, and fish shells.\n"
            return 1
            ;;
    esac
    
    # Update config file
    if [ -f "$HOME/.phpswitch.conf" ]; then
        utils_set_config_value "AUTO_SWITCH_PHP_VERSION" "true" "$HOME/.phpswitch.conf"
    fi
    
    # Create cache directory with proper permissions
    local cache_dir="$HOME/.cache/phpswitch"
    if [ ! -d "$cache_dir" ]; then
        mkdir -p "$cache_dir" 2>/dev/null
    fi
    
    # Ensure cache directory is writable
    if [ ! -w "$cache_dir" ] && [ -d "$cache_dir" ]; then
        utils_show_status "warning" "Cache directory $cache_dir is not writable"
        printf "  Fix permissions (may require sudo)? (y/n) "
        if [ "$(utils_validate_yes_no "" "y")" = "y" ]; then
            # Try to fix permissions, first without sudo
            chmod u+w "$cache_dir" 2>/dev/null
            if [ ! -w "$cache_dir" ]; then
                # If that fails, try with sudo
                utils_show_status "info" "Trying with sudo..."
                sudo chmod u+w "$cache_dir" 2>/dev/null
                if [ ! -w "$cache_dir" ]; then
                    utils_show_status "error" "Could not fix permissions on $cache_dir"
                    utils_show_status "warning" "Auto-switching will still work but will be slower without caching"
                else
                    utils_show_status "success" "Fixed permissions on $cache_dir"
                fi
            else
                utils_show_status "success" "Fixed permissions on $cache_dir"
            fi
        else
            utils_show_status "warning" "Auto-switching will still work but will be slower without caching"
        fi
    fi
    
    utils_show_status "success" "Auto-switching enabled"
    printf "  Auto-switching will take effect the next time you open a new terminal.\n"
    return 0
}

# Function to install auto-switching for zsh
function auto_install_zsh {
    local rc_file="$HOME/.zshrc"
    
    # Check if hooks are already installed
    if grep -q "phpswitch_auto_detect_project" "$rc_file" 2>/dev/null; then
        utils_show_status "info" "Auto-switching hooks already installed in $rc_file"
        return 0
    fi
    
    # Create backup before modifying
    if [ -f "$rc_file" ]; then
        local backup_file="${rc_file}.bak.$(date +%Y%m%d%H%M%S)"
        
        # Validate backup file path
        if utils_validate_path "$backup_file"; then
            if cp "$rc_file" "$backup_file" 2>/dev/null; then
                # Set secure permissions (readable/writable by owner only)
                chmod 600 "$backup_file" 2>/dev/null
                utils_show_status "info" "Created secure backup at ${backup_file}"
            fi
        fi
    fi
    
    # Add the hook function to the rc file
    cat >> "$rc_file" << 'EOL'

# PHPSwitch auto-switching
function phpswitch_auto_detect_project() {
    # Use a cache to avoid checking the same directories repeatedly
    local cache_file="$HOME/.cache/phpswitch/directory_cache.txt"
    local current_dir="$(pwd)"
    local cache_hit=false
    
    # Create cache directory if it doesn't exist
    mkdir -p "$(dirname "$cache_file")" 2>/dev/null
    
    # Check if the current directory is in the cache
    if [ -f "$cache_file" ] && [ -r "$cache_file" ]; then
        while IFS=: read -r dir version; do
            if [ "$dir" = "$current_dir" ]; then
                if [ -n "$version" ]; then
                    # Silently run auto-switching command
                    phpswitch --auto-mode > /dev/null 2>&1
                fi
                cache_hit=true
                break
            fi
        done < "$cache_file"
    fi
    
    # If not in cache, check for project file and add to cache
    if [ "$cache_hit" = "false" ]; then
        # Use a temporary file to avoid permission issues
        local temp_cache_file
        temp_cache_file=$(utils_create_secure_temp_file) || return 0

        # Copy existing cache if available
        if [ -f "$cache_file" ] && [ -r "$cache_file" ]; then
            cat "$cache_file" > "$temp_cache_file" 2>/dev/null
        fi

        # Check for PHP version file
        for file in ".php-version" ".phpversion" ".php"; do
            if [ -f "$current_dir/$file" ]; then
                local ver
                ver=$(tr -d '[:space:]' < "$current_dir/$file" 2>/dev/null)
                # Validate version string before caching
                if [[ "$ver" =~ ^[a-zA-Z0-9.@_-]*$ ]]; then
                    printf '%s:%s\n' "$current_dir" "$ver" >> "$temp_cache_file"
                fi
                phpswitch --auto-mode > /dev/null 2>&1
                mv "$temp_cache_file" "$cache_file" 2>/dev/null || rm -f "$temp_cache_file" 2>/dev/null
                return
            fi
        done

        # Check for composer.json or .tool-versions using phpswitch helper
        if [ -f "$current_dir/composer.json" ] || [ -f "$current_dir/.tool-versions" ]; then
            local version
            version=$(phpswitch --get-project-version 2>/dev/null)
            if [ -n "$version" ]; then
                printf '%s:%s\n' "$current_dir" "$version" >> "$temp_cache_file"
                phpswitch --auto-mode > /dev/null 2>&1
                mv "$temp_cache_file" "$cache_file" 2>/dev/null || rm -f "$temp_cache_file" 2>/dev/null
                return
            fi
        fi

        # No PHP version file found, add to cache with empty version
        printf '%s:\n' "$current_dir" >> "$temp_cache_file"
        mv "$temp_cache_file" "$cache_file" 2>/dev/null || rm -f "$temp_cache_file" 2>/dev/null
    fi
}

# Add the hook to chpwd (when directory changes)
autoload -U add-zsh-hook
add-zsh-hook chpwd phpswitch_auto_detect_project

# Run once when shell starts
phpswitch_auto_detect_project
EOL
    
    utils_show_status "success" "Added auto-switching hooks to $rc_file"
}

# Function to install auto-switching for bash
function auto_install_bash {
    local rc_file="$HOME/.bashrc"
    
    # If .bashrc doesn't exist, check for bash_profile
    if [ ! -f "$rc_file" ]; then
        rc_file="$HOME/.bash_profile"
    fi
    
    # If neither exists, check for profile
    if [ ! -f "$rc_file" ]; then
        rc_file="$HOME/.profile"
    fi
    
    # Check if hooks are already installed
    if grep -q "phpswitch_auto_detect_project" "$rc_file" 2>/dev/null; then
        utils_show_status "info" "Auto-switching hooks already installed in $rc_file"
        return 0
    fi
    
    # Create backup before modifying
    if [ -f "$rc_file" ]; then
        local backup_file="${rc_file}.bak.$(date +%Y%m%d%H%M%S)"
        
        # Validate backup file path
        if utils_validate_path "$backup_file"; then
            if cp "$rc_file" "$backup_file" 2>/dev/null; then
                # Set secure permissions (readable/writable by owner only)
                chmod 600 "$backup_file" 2>/dev/null
                utils_show_status "info" "Created secure backup at ${backup_file}"
            fi
        fi
    fi
    
    # Add the hook function to the rc file
    cat >> "$rc_file" << 'EOL'

# PHPSwitch auto-switching
function phpswitch_auto_detect_project() {
    # Use a cache to avoid checking the same directories repeatedly
    local cache_file="$HOME/.cache/phpswitch/directory_cache.txt"
    local current_dir="$(pwd)"
    local cache_hit=false
    
    # Create cache directory if it doesn't exist
    mkdir -p "$(dirname "$cache_file")" 2>/dev/null
    
    # Check if the current directory is in the cache
    if [ -f "$cache_file" ] && [ -r "$cache_file" ]; then
        while IFS=: read -r dir version; do
            if [ "$dir" = "$current_dir" ]; then
                if [ -n "$version" ]; then
                    # Silently run auto-switching command
                    phpswitch --auto-mode > /dev/null 2>&1
                fi
                cache_hit=true
                break
            fi
        done < "$cache_file"
    fi
    
    # If not in cache, check for project file and add to cache
    if [ "$cache_hit" = "false" ]; then
        # Use a temporary file to avoid permission issues
        local temp_cache_file
        temp_cache_file=$(mktemp 2>/dev/null) || return 0
        chmod 600 "$temp_cache_file" 2>/dev/null

        # Copy existing cache if available
        if [ -f "$cache_file" ] && [ -r "$cache_file" ]; then
            cat "$cache_file" > "$temp_cache_file" 2>/dev/null
        fi

        # Check for PHP version file
        for file in ".php-version" ".phpversion" ".php"; do
            if [ -f "$current_dir/$file" ]; then
                local ver
                ver=$(tr -d '[:space:]' < "$current_dir/$file" 2>/dev/null)
                if [[ "$ver" =~ ^[a-zA-Z0-9.@_-]*$ ]]; then
                    printf '%s:%s\n' "$current_dir" "$ver" >> "$temp_cache_file"
                fi
                phpswitch --auto-mode > /dev/null 2>&1
                mv "$temp_cache_file" "$cache_file" 2>/dev/null || rm -f "$temp_cache_file" 2>/dev/null
                return
            fi
        done

        # Check for composer.json or .tool-versions using phpswitch helper
        if [ -f "$current_dir/composer.json" ] || [ -f "$current_dir/.tool-versions" ]; then
            local version
            version=$(phpswitch --get-project-version 2>/dev/null)
            if [ -n "$version" ]; then
                printf '%s:%s\n' "$current_dir" "$version" >> "$temp_cache_file"
                phpswitch --auto-mode > /dev/null 2>&1
                mv "$temp_cache_file" "$cache_file" 2>/dev/null || rm -f "$temp_cache_file" 2>/dev/null
                return
            fi
        fi

        # No PHP version file found, add to cache with empty version
        printf '%s:\n' "$current_dir" >> "$temp_cache_file"
        mv "$temp_cache_file" "$cache_file" 2>/dev/null || rm -f "$temp_cache_file" 2>/dev/null
    fi
}

# Enable the cd hook for bash
if [[ "$PROMPT_COMMAND" != *"phpswitch_auto_detect_project"* ]]; then
    PROMPT_COMMAND="phpswitch_auto_detect_project;$PROMPT_COMMAND"
fi

# Run once when shell starts
phpswitch_auto_detect_project
EOL
    
    utils_show_status "success" "Added auto-switching hooks to $rc_file"
}

# Function to install auto-switching for fish
function auto_install_fish {
    local config_dir="$HOME/.config/fish"
    local rc_file="$config_dir/config.fish"
    
    # Ensure the directory exists
    mkdir -p "$config_dir" 2>/dev/null
    
    # Check if hooks are already installed
    if grep -q "phpswitch_auto_detect_project" "$rc_file" 2>/dev/null; then
        utils_show_status "info" "Auto-switching hooks already installed in $rc_file"
        return 0
    fi
    
    # Create backup before modifying
    if [ -f "$rc_file" ]; then
        local backup_file="${rc_file}.bak.$(date +%Y%m%d%H%M%S)"
        
        # Validate backup file path
        if utils_validate_path "$backup_file"; then
            if cp "$rc_file" "$backup_file" 2>/dev/null; then
                # Set secure permissions (readable/writable by owner only)
                chmod 600 "$backup_file" 2>/dev/null
                utils_show_status "info" "Created secure backup at ${backup_file}"
            fi
        fi
    fi
    
    # Add the hook function to the rc file
    cat >> "$rc_file" << 'EOL'

# PHPSwitch auto-switching
function phpswitch_auto_detect_project --on-variable PWD
    # Use a cache to avoid checking the same directories repeatedly
    set cache_file "$HOME/.cache/phpswitch/directory_cache.txt"
    set current_dir (pwd)
    set cache_hit false
    
    # Create cache directory if it doesn't exist
    mkdir -p (dirname "$cache_file") 2>/dev/null
    
    # Check if the current directory is in the cache
    if test -f "$cache_file"; and test -r "$cache_file"
        while read -l line
            set dir_info (string split ":" -- $line)
            set dir $dir_info[1]
            set version $dir_info[2]
            
            if test "$dir" = "$current_dir"
                if test -n "$version"
                    # Silently run auto-switching command
                    phpswitch --auto-mode > /dev/null 2>&1
                end
                set cache_hit true
                break
            end
        end < "$cache_file"
    end
    
    # If not in cache, check for project file and add to cache
    if test "$cache_hit" = "false"
        # Use a temporary file to avoid permission issues
        set temp_cache_file (mktemp 2>/dev/null)
        if test -z "$temp_cache_file"; or not test -f "$temp_cache_file"
            return
        end
        chmod 600 "$temp_cache_file" 2>/dev/null

        # Copy existing cache if available
        if test -f "$cache_file"; and test -r "$cache_file"
            cat "$cache_file" > "$temp_cache_file" 2>/dev/null
        end
        
        # Check for PHP version file
        for file in ".php-version" ".phpversion" ".php"
            if test -f "$current_dir/$file"
                # Store this in cache
                echo "$current_dir:"(cat "$current_dir/$file" | string trim) >> "$temp_cache_file"
                # Run phpswitch in auto mode
                phpswitch --auto-mode > /dev/null 2>&1
                
                # Try to update the main cache file if writable
                if test -w (dirname "$cache_file")
                    mv "$temp_cache_file" "$cache_file" 2>/dev/null
                end
                return
            end
        end
        
        # Check for composer.json or .tool-versions using phpswitch helper
        if test -f "$current_dir/composer.json"; or test -f "$current_dir/.tool-versions"
            set version (phpswitch --get-project-version 2>/dev/null)
            if test -n "$version"
                echo "$current_dir:$version" >> "$temp_cache_file"
                phpswitch --auto-mode > /dev/null 2>&1
                
                if test -w (dirname "$cache_file")
                    mv "$temp_cache_file" "$cache_file" 2>/dev/null
                end
                return
            end
        end
        
        # No PHP version file found, add to cache with empty version
        echo "$current_dir:" >> "$temp_cache_file"
        
        # Try to update the main cache file if writable
        if test -w (dirname "$cache_file")
            mv "$temp_cache_file" "$cache_file" 2>/dev/null
        else
            rm -f "$temp_cache_file" 2>/dev/null
        end
    end
end

# Run once when shell starts
phpswitch_auto_detect_project
EOL
    
    utils_show_status "success" "Added auto-switching hooks to $rc_file"
}

# Function to clear auto-switching directory cache
function auto_clear_directory_cache {
    local cache_file="$HOME/.cache/phpswitch/directory_cache.txt"
    
    if [ -f "$cache_file" ]; then
        if [ -w "$cache_file" ]; then
            rm -f "$cache_file" 2>/dev/null
            utils_show_status "success" "Directory cache cleared"
        else
            # Try with sudo if direct removal fails
            utils_show_status "warning" "No write permission for $cache_file"
            printf "  Try with sudo? (y/n) "
            if [ "$(utils_validate_yes_no "" "y")" = "y" ]; then
                sudo rm -f "$cache_file" 2>/dev/null
                if [ ! -f "$cache_file" ]; then
                    utils_show_status "success" "Directory cache cleared with sudo"
                else
                    utils_show_status "error" "Failed to clear directory cache with sudo"
                fi
            fi
        fi
    else
        utils_show_status "info" "No directory cache found at $cache_file"
    fi
}

# Function to implement auto-switching for PHP versions
function auto_switch_php {
    local new_version="$1"
    local brew_version

    if [ "$new_version" = "php@default" ]; then
        brew_version="php"
    else
        brew_version="$new_version"
    fi

    # Unlink current PHP
    brew unlink "$(core_get_current_php_version)" &>/dev/null

    # Link new PHP
    brew link --force "$brew_version" &>/dev/null

    if [ $? -ne 0 ]; then
        return 1
    fi

    # Silently restart PHP-FPM if enabled
    if [ "$AUTO_RESTART_PHP_FPM" = "true" ]; then
        local service_name=$(fpm_get_service_name "$new_version")
        # Capture once — avoids calling brew services list twice (slow) and eliminates TOCTOU
        local services_list
        services_list=$(brew services list 2>/dev/null)
        local running_services
        running_services=$(echo "$services_list" | grep -E "^php(@[0-9]\.[0-9])?" | awk '{print $1}')
        while IFS= read -r service; do
            [ -z "$service" ] && continue
            [ "$service" != "$service_name" ] && brew services stop "$service" &>/dev/null
        done <<< "$running_services"
        # awk exact field match avoids "php" matching "php@8.1" etc.
        if echo "$services_list" | awk -v svc="$service_name" '$1 == svc' | grep -q "started"; then
            brew services restart "$service_name" &>/dev/null
        else
            brew services start "$service_name" &>/dev/null
        fi
    fi

    return 0
}
# Module: commands.sh
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
        # Get version from the script
        version=$(grep "^# Version:" "$0" | cut -d":" -f2 | tr -d " ")
        echo "PHPSwitch version $version"
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
        php -v | sed 's/^/    /'
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
    local secure_username
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
            # Get the current version
            local current_version=$(grep "^# Version:" "$0" | cut -d":" -f2 | tr -d " ")
            
            # Get the downloaded version
            local new_version=$(grep "^# Version:" "$tmp_dir/php-switcher.sh" | cut -d":" -f2 | tr -d " ")
            
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
    available_versions_file=$(mktemp)
    core_get_available_php_versions > "$available_versions_file" &

    # Get current and active PHP versions
    current_version=$(core_get_current_php_version)
    active_version=$(core_get_active_php_version)

    # Check for project-specific PHP version (single call)
    local project_php_version=""
    project_php_version=$(version_check_project 2>/dev/null)

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
        if [[ "$current_version" == php@* ]] && [[ "$active_version" != *$(echo "$current_version" | grep -o "[0-9]\.[0-9]")* ]]; then
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
            printf "  "; utils_print_gradient "Project" 170 157 251 148 182 251; printf "  %s\n" "$project_php_version"
        else
            printf "  Project  %s\n" "$project_php_version"
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
        if ! echo "${versions[@]}" | grep -q "$version"; then
            available_versions+=("$version")
        fi
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
    printf "  Make additional configuration changes? (y/n) "
    if [ "$(utils_validate_yes_no "" "y")" = "y" ]; then
        cmd_configure_phpswitch
    fi
}
# Main script logic
# Load configuration
core_load_config

# Parse command line arguments
cmd_parse_arguments "$@"
