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

# HOMEBREW_PREFIX is set in core_load_config after dependency validation
HOMEBREW_PREFIX=""

# Function to log debug messages
function core_debug_log {
    if [ "$DEBUG_MODE" = "true" ]; then
        echo "[DEBUG] $1" >&2
    fi
}

# Load configuration
function core_load_config {
    CONFIG_FILE="$HOME/.phpswitch.conf"
    
    # Default settings — sourced from defaults.sh values
    AUTO_RESTART_PHP_FPM="${DEFAULT_AUTO_RESTART_PHP_FPM:-true}"
    BACKUP_CONFIG_FILES="${DEFAULT_BACKUP_CONFIG_FILES:-true}"
    DEFAULT_PHP_VERSION="${DEFAULT_PHP_VERSION:-}"
    MAX_BACKUPS="${DEFAULT_MAX_BACKUPS:-5}"
    AUTO_SWITCH_PHP_VERSION="${DEFAULT_AUTO_SWITCH_PHP_VERSION:-false}"
    CACHE_DIRECTORY="${DEFAULT_CACHE_DIRECTORY:-}"
    
    # Load settings if config exists — parse as KEY=VALUE without sourcing
    if [ -f "$CONFIG_FILE" ]; then
        core_debug_log "Loading configuration from $CONFIG_FILE"
        while IFS='=' read -r _key _value; do
            [[ "$_key" =~ ^[[:space:]]*# ]] && continue
            [[ -z "$_key" ]] && continue
            _key="${_key// /}"
            _value="${_value%%#*}"
            _value="${_value#\"}" ; _value="${_value%\"}"
            _value="${_value#\'}" ; _value="${_value%\'}"
            # shellcheck disable=SC2034
            case "$_key" in
                AUTO_RESTART_PHP_FPM)  AUTO_RESTART_PHP_FPM="$_value"  ;;
                BACKUP_CONFIG_FILES)   BACKUP_CONFIG_FILES="$_value"    ;;
                DEFAULT_PHP_VERSION)   DEFAULT_PHP_VERSION="$_value"    ;;
                MAX_BACKUPS)           MAX_BACKUPS="$_value"             ;;
                AUTO_SWITCH_PHP_VERSION) AUTO_SWITCH_PHP_VERSION="$_value" ;;
                CACHE_DIRECTORY)       CACHE_DIRECTORY="$_value"        ;;
                *) core_debug_log "Unknown config key: $_key" ;;
            esac
        done < "$CONFIG_FILE"
    else
        core_debug_log "No configuration file found at $CONFIG_FILE"
    fi
    
    # Determine Homebrew prefix (SEC-03: deferred from global scope).
    # `phpswitch init` runs from rc files, possibly before `brew shellenv`
    # has put brew on PATH, so fall back to the standard install locations.
    if ! command -v brew >/dev/null 2>&1; then
        local brew_candidate
        for brew_candidate in ${PHPSWITCH_BREW_CANDIDATES:-/opt/homebrew/bin/brew /usr/local/bin/brew}; do
            if [ -x "$brew_candidate" ]; then
                PATH="$(dirname "$brew_candidate"):$PATH"
                export PATH
                break
            fi
        done
    fi
    if command -v brew >/dev/null 2>&1; then
        HOMEBREW_PREFIX=$(brew --prefix)
    else
        echo "Error: Homebrew is not installed or not in PATH" >&2
        exit 1
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
        local tmp_conf
        tmp_conf=$(mktemp) || { utils_show_status "error" "Failed to create temp file for config"; return 1; }
        if ! cat > "$tmp_conf" <<EOL
# PHPSwitch Configuration
AUTO_RESTART_PHP_FPM=true
BACKUP_CONFIG_FILES=true
DEFAULT_PHP_VERSION=""
MAX_BACKUPS=5
AUTO_SWITCH_PHP_VERSION=false
CACHE_DIRECTORY=""
EOL
        then
            rm -f "$tmp_conf"
            utils_show_status "error" "Failed to write config content"
            return 1
        fi
        if [ ! -s "$tmp_conf" ]; then
            rm -f "$tmp_conf"
            utils_show_status "error" "Failed to write config content"
            return 1
        fi
        mv "$tmp_conf" "$HOME/.phpswitch.conf" || { rm -f "$tmp_conf"; utils_show_status "error" "Failed to write config file"; return 1; }
        utils_show_status "success" "Created default configuration at ~/.phpswitch.conf"
    fi
}

# Cache variable for brew list
_PHPSWITCH_BREW_LIST_CACHE=""

# Function to get all installed PHP versions
function core_get_installed_php_versions {
    # PERF-01: Cache brew list to avoid repeated slow calls
    local brew_list
    if [ -n "$_PHPSWITCH_BREW_LIST_CACHE" ]; then
        brew_list="$_PHPSWITCH_BREW_LIST_CACHE"
    else
        brew_list=$(brew list 2>/dev/null)
        _PHPSWITCH_BREW_LIST_CACHE="$brew_list"
    fi
    
    local versions
    versions=$(echo "$brew_list" | grep "^php@" || true)

    # Check if the "php" formula is installed and get its version
    if echo "$brew_list" | grep -q "^php$"; then
        # Add php@default for internal logic
        # Do NOT also add php@$major_minor here — it creates duplicate menu entries
        # when the default formula version matches an explicitly installed php@X.Y.
        # version_resolve_php_version handles the mapping from php@X.Y -> php@default.
        versions="$versions"$'\n'"php@default"
    fi
    
    echo "$versions" | sort | uniq
}

# Function to get and manage the cache directory with better error handling
function core_get_cache_dir {
    # Check if custom cache directory is set in config
    if [ -n "$CACHE_DIRECTORY" ]; then
        # FEAT-01: Validate custom cache directory path
        if ! utils_validate_path "$CACHE_DIRECTORY"; then
            core_debug_log "CACHE_DIRECTORY failed path validation: $CACHE_DIRECTORY"
            CACHE_DIRECTORY=""
        elif [[ "$CACHE_DIRECTORY" != "$HOME"* ]] && [[ "$CACHE_DIRECTORY" != "/tmp"* ]]; then
            core_debug_log "CACHE_DIRECTORY must be under \$HOME or /tmp: $CACHE_DIRECTORY"
            CACHE_DIRECTORY=""
        fi
    fi
    
    if [ -n "$CACHE_DIRECTORY" ]; then
        # Use custom location from config
        local cache_dir="$CACHE_DIRECTORY"
        
        # Try to create it if it doesn't exist
        if [ ! -d "$cache_dir" ]; then
            if ! mkdir -p "$cache_dir" 2>/dev/null; then
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

# Fallback list of known PHP versions when brew search is unavailable
function core_fallback_php_versions {
    echo "php@8.1"
    echo "php@8.2"
    echo "php@8.3"
    echo "php@8.4"
    echo "php@8.5"
    echo "php@default"
}

# Check if a version cache file is fresh within the given timeout (seconds)
function core_is_cache_fresh {
    local cache_file="$1"
    local timeout="$2"
    [ -f "$cache_file" ] || return 1
    local mod_time
    if [ "$(uname)" = "Darwin" ]; then
        mod_time=$(stat -f %m "$cache_file" 2>/dev/null) || return 1
    else
        mod_time=$(stat -c %Y "$cache_file" 2>/dev/null) || return 1
    fi
    local current_time
    current_time=$(date +%s)
    [ $(( current_time - mod_time )) -lt "$timeout" ]
}

# Enhanced get_available_php_versions function with persistent caching and better error handling
function core_get_available_php_versions {
    local cache_dir
    cache_dir=$(core_get_cache_dir)
    local cache_file="$cache_dir/available_versions.cache"
    local cache_timeout=3600  # Cache expires after 1 hour (in seconds)

    # Check if cache exists and is recent
    if core_is_cache_fresh "$cache_file" "$cache_timeout"; then
        core_debug_log "Using cached available PHP versions from $cache_file"
        cat "$cache_file" 2>/dev/null || core_fallback_php_versions
        return
    fi

    core_debug_log "Cache is stale or doesn't exist. Refreshing PHP versions..."

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
            brew search /php@[0-9]/ 2>/dev/null | grep -Eo 'php@[0-9]+\.[0-9]+' | sort -u > "$search_file1" &
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
    local cache_dir
    cache_dir=$(core_get_cache_dir)
    
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

# Security: Setup trap for automatic cleanup (chains with existing traps)
function utils_setup_temp_cleanup_trap {
    local _existing_exit_trap
    _existing_exit_trap=$(trap -p EXIT | sed "s/^trap -- '\(.*\)' EXIT$/\1/")
    if [ -n "$_existing_exit_trap" ]; then
        # shellcheck disable=SC2064
        trap "utils_cleanup_temp_files; $_existing_exit_trap; exit" INT TERM EXIT
    else
        trap 'utils_cleanup_temp_files; exit' INT TERM EXIT
    fi
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
    local output=""
    while [ "$i" -lt "$len" ]; do
        local char="${text:$i:1}"
        local r=$(( r1 + (r2 - r1) * i / (len - 1) ))
        local g=$(( g1 + (g2 - g1) * i / (len - 1) ))
        local b=$(( b1 + (b2 - b1) * i / (len - 1) ))
        output+=$(printf "\033[38;2;%d;%d;%dm%s" "$r" "$g" "$b" "$char")
        i=$(( i + 1 ))
    done
    printf "%s\033[0m" "$output"
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
    # $1 (prompt) is unused; $2 is the default answer
    local default="$2"

    # Non-interactive confirmation: honor the global --yes/-y flag (ARCH-04).
    # Auto-answer with the prompt's default, falling back to "y".
    if [ "${PHPSWITCH_YES:-false}" = "true" ]; then
        echo "${default:-y}"
        return 0
    fi

    while true; do
        # EOF (no terminal / closed stdin): never loop; fall back to the
        # default, or "n" so nothing is done without an explicit yes
        if ! read -r response && [ -z "$response" ]; then
            echo "${default:-n}"
            return 0
        fi

        
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

# Function to validate system dependencies
function utils_check_dependencies {
    # Only problems are reported; a passing check prints nothing.
    # ($1 "silent" is still accepted for callers.)
    
    # Check for Homebrew
    if ! command -v brew >/dev/null 2>&1; then
        utils_show_status "error" "Homebrew is not installed"
        echo "PHPSwitch requires Homebrew to manage PHP versions."
        echo "Please install Homebrew first: https://brew.sh"
        return 1
    fi

    # Check Homebrew version
    local brew_version
    brew_version=$(brew --version | head -n 1 | grep -o "[0-9]\+\.[0-9]\+\.[0-9]\+" 2>/dev/null || echo "0.0.0")
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
    local shell_type
    shell_type=$(shell_detect_shell)
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
    local brew_prefix
    brew_prefix="$(brew --prefix)"
    if [ ! -w "$brew_prefix/bin" ] && [ ! -w "/usr/local/bin" ]; then
        utils_show_status "warning" "Limited write permissions detected"
        echo "You may need to use sudo for some operations."
    fi
    
    # Enhanced cache directory check - using the core_get_cache_dir function
    local cache_dir
    cache_dir=$(core_get_cache_dir)
    
    # If the function returned a temporary directory, we've already fallen back
    if [[ "$cache_dir" == /tmp/* ]]; then
        utils_show_status "warning" "Using temporary cache directory: $cache_dir"
        echo "Cache will be lost on system reboot. To fix permanently, run:"
        echo "phpswitch --fix-permissions"
    elif [ "$cache_dir" = "$HOME/.cache/phpswitch" ] && [ ! -w "$cache_dir" ]; then
        utils_show_status "warning" "Cache directory is not writable: $cache_dir"
        printf "  Run 'phpswitch --fix-permissions' to resolve this.\n"
    fi
    
    return 0
}

# CQ-07: Extracted permission-fix logic into its own function
function utils_ensure_cache_writable {
    local cache_dir="$1"
    
    if [ -w "$cache_dir" ]; then
        return 0
    fi
    
    utils_show_status "info" "Attempting to fix permissions for $cache_dir..."
    
    # Strategy 1: chmod
    chmod u+w "$cache_dir" 2>/dev/null
    if [ -w "$cache_dir" ]; then
        utils_show_status "success" "Permissions fixed"
        return 0
    fi
    
    # Never escalate automatically; tell the user how to fix ownership
    utils_show_status "warning" "$cache_dir is not writable (it may be owned by root)"
    printf "  To fix it yourself, run:\n    sudo chown -R %s \"%s\"\n" "$(id -un)" "$cache_dir"
    
    # Strategy 5: Alternative directory
    local alt_cache="$HOME/.phpswitch_cache"
    mkdir -p "$alt_cache" 2>/dev/null
    if [ -d "$alt_cache" ] && [ -w "$alt_cache" ]; then
        utils_show_status "success" "Created alternative cache directory: $alt_cache"
        if [ -f "$HOME/.phpswitch.conf" ]; then
            utils_set_config_value "CACHE_DIRECTORY" "$alt_cache" "$HOME/.phpswitch.conf"
        else
            core_create_default_config
            echo "CACHE_DIRECTORY=\"$alt_cache\"" >> "$HOME/.phpswitch.conf"
        fi
        return 0
    fi
    
    utils_show_status "error" "All attempts to fix cache permissions failed"
    echo "PHPSwitch will fall back to using temporary directories for this session."
    return 1
}

# Resolve a path through any chain of symlinks (capped so a cycle can't hang)
function utils_resolve_symlinks {
    local path="$1"
    local target hops=0
    while [ -L "$path" ] && [ "$hops" -lt 40 ]; do
        hops=$((hops + 1))
        target=$(readlink "$path")
        case "$target" in
            /*) path="$target" ;;
            # Relative targets (e.g. Homebrew's ../Cellar/...) are normalized via cd
            *) path="$(cd "$(dirname "$path")/$(dirname "$target")" 2>/dev/null && pwd)/$(basename "$target")" ;;
        esac
    done
    printf '%s\n' "$path"
}

# Atomically replace the contents of a file with those of $2.
# Follows symlinks (dotfile managers stay intact) and keeps the file mode;
# a failed write never leaves a truncated file behind.
function utils_replace_file_contents {
    local target="$1" source="$2"
    local real
    real=$(utils_resolve_symlinks "$target")
    local tmp
    tmp=$(mktemp "$(dirname "$real")/.phpswitch.XXXXXX") || return 1
    if ! cat "$source" > "$tmp"; then
        rm -f "$tmp"
        return 1
    fi
    if [ -e "$real" ]; then
        chmod "$(stat -f '%Lp' "$real")" "$tmp" 2>/dev/null
    fi
    mv "$tmp" "$real" || { rm -f "$tmp"; return 1; }
}

# Run a command for an explicit user request (install/uninstall/update),
# escalating with sudo only when the target directory isn't writable.
function utils_run_for_dir {
    local dir="$1"
    shift
    if [ -w "$dir" ]; then
        "$@"
    else
        utils_show_status "info" "$dir is not writable; using sudo"
        sudo "$@"
    fi
}

# Function to compare semantic versions (returns true if version1 >= version2)
function utils_compare_versions {
    local version1="$1"
    local version2="$2"
    
    # Extract major, minor, patch versions
    IFS="." read -ra v1_parts <<< "$version1"
    IFS="." read -ra v2_parts <<< "$version2"
    
    # Compare major version
    if (( v1_parts[0] > v2_parts[0] )); then
        return 0
    elif (( v1_parts[0] < v2_parts[0] )); then
        return 1
    fi
    
    # Compare minor version
    if (( v1_parts[1] > v2_parts[1] )); then
        return 0
    elif (( v1_parts[1] < v2_parts[1] )); then
        return 1
    fi
    
    # Compare patch version
    if (( v1_parts[2] >= v2_parts[2] )); then
        return 0
    else
        return 1
    fi
}

# Installed PHP series (X.Y), ascending, from the Homebrew prefix.
# Uses a glob rather than `brew list`: this runs on cd via the shell hook.
function utils_installed_php_series {
    local d target
    {
        for d in "$HOMEBREW_PREFIX"/opt/php@*; do
            [ -x "$d/bin/php" ] && printf '%s\n' "${d##*/php@}"
        done
        # The unversioned formula links opt/php -> ../Cellar/php/X.Y.Z
        if [ -x "$HOMEBREW_PREFIX/opt/php/bin/php" ]; then
            target=$(readlink "$HOMEBREW_PREFIX/opt/php" 2>/dev/null)
            [[ "$target" =~ /php/([0-9]+)\.([0-9]+) ]] && printf '%s.%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
        fi
    } | grep -E '^[0-9]+\.[0-9]+$' | sort -t. -k1,1n -k2,2n -u
}

# Does PHP series X.Y (any patch release) satisfy a composer constraint?
# Supports ||, |, AND via spaces/commas, ^, ~, >=, >, <=, <, =, !=,
# wildcards (8.*, 8.1.*, *), bare versions and hyphen ranges (8.1 - 8.3).
# Unparseable constraints never match.
function utils_composer_constraint_matches {
    local constraint="$1" series="$2"
    [[ "$series" =~ ^[0-9]+\.[0-9]+$ ]] || return 1
    local m=$(( ${series%%.*} * 100 + ${series#*.} ))
    local group atom

    constraint="${constraint//||/|}"
    local IFS='|'
    local -a groups
    read -ra groups <<< "$constraint"
    for group in "${groups[@]}"; do
        # Hyphen range: "A.B - C.D"
        group=$(printf '%s' "$group" | sed -E 's/([0-9.*]+) +- +([0-9.*]+)/>=\1 <=\2/g; s/,/ /g')
        local ok=true seen=false
        local -a atoms
        # read -a splits without glob expansion (a bare "*" must stay "*")
        IFS=' ' read -ra atoms <<< "$group"
        for atom in "${atoms[@]}"; do
            seen=true
            utils_composer_atom_matches "$atom" "$m" || { ok=false; break; }
        done
        if [ "$seen" = "true" ] && [ "$ok" = "true" ]; then
            return 0
        fi
    done
    return 1
}

# One constraint atom against series number m (X*100+Y); 2 = unparseable
function utils_composer_atom_matches {
    local atom="$1" m="$2" op
    # Callers may have changed IFS; bash 3.2 then mangles "|" in regexes
    local IFS=$' \t\n'
    local atom_re='^(\^|~|>=|<=|>|<|==|=|!=)?v?([0-9]+|\*)(\.([0-9]+|\*))?(\.([0-9]+|\*))?$'
    atom="${atom%@*}"          # stability flags (@dev)
    if [[ "$atom" =~ $atom_re ]]; then
        op="${BASH_REMATCH[1]}"
        local maj="${BASH_REMATCH[2]}" min="${BASH_REMATCH[4]}" pat="${BASH_REMATCH[6]}"
    else
        return 2
    fi
    [ "$maj" = "*" ] && return 0
    local major=$(( m / 100 ))
    local base=$(( maj * 100 + ${min//\*/0} ))
    [ -z "$min" ] && base=$(( maj * 100 ))

    case "$op" in
        "^")
            [ "$m" -ge "$base" ] && [ "$major" -eq "$maj" ] ;;
        "~")
            if [ -n "$pat" ] || [ -z "$min" ]; then
                # ~8.1.2 -> 8.1.x ; ~8 -> 8.x
                if [ -z "$min" ]; then [ "$major" -eq "$maj" ]; else [ "$m" -eq "$base" ]; fi
            else
                [ "$m" -ge "$base" ] && [ "$major" -eq "$maj" ]
            fi ;;
        ">="|">")
            [ "$m" -ge "$base" ] ;;
        "<=")
            if [ -z "$min" ]; then [ "$major" -le "$maj" ]; else [ "$m" -le "$base" ]; fi ;;
        "<")
            # < 8.2 / < 8.2.0 excludes the whole 8.2 series; < 8.2.3 includes 8.2.0
            if [ -z "$min" ]; then
                [ "$major" -lt "$maj" ]
            elif [ -n "$pat" ] && [ "$pat" != "0" ] && [ "$pat" != "*" ]; then
                [ "$m" -le "$base" ]
            else
                [ "$m" -lt "$base" ]
            fi ;;
        "!=")
            return 0 ;;
        *)
            # =, == or bare: 8 -> 8.x, 8.1 / 8.1.3 / 8.1.* -> 8.1
            if [ -z "$min" ] || [ "$min" = "*" ]; then [ "$major" -eq "$maj" ]; else [ "$m" -eq "$base" ]; fi ;;
    esac
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
    local platform_php
    platform_php=$(grep -A 10 '"platform"' "$composer_file" 2>/dev/null | grep '"php"' | head -n 1)
    
    if [ -n "$platform_php" ]; then
        # Extract version: "php": "8.1.0" -> 8.1.0
        local version
        version=$(echo "$platform_php" | sed -E 's/.*"php": *"([^"]+)".*/\1/')
        # extract major.minor
        echo "$version" | grep -oE '[0-9]+\.[0-9]+' | head -n 1
        return 0
    fi
    
    # 2. Check require.php
    local require_php
    require_php=$(grep -A 20 '"require"' "$composer_file" 2>/dev/null | grep '"php"' | head -n 1)
    
    if [ -n "$require_php" ]; then
        # Extract constraint: "php": "^8.1 || ^8.2" -> ^8.1 || ^8.2
        local version
        version=$(echo "$require_php" | sed -E 's/.*"php": *"([^"]+)".*/\1/')
        # 1. Keep the historical answer (first X.Y in the constraint) when it is
        #    installed and satisfies the constraint, so working projects never move
        # 2. Otherwise use the lowest installed series that satisfies it
        # 3. Otherwise fall back to the historical answer
        local first series installed
        first=$(echo "$version" | grep -oE '[0-9]+\.[0-9]+' | head -n 1)
        installed=$(utils_installed_php_series)
        if [ -n "$first" ] && printf '%s\n' "$installed" | grep -qx "$first" &&
           utils_composer_constraint_matches "$version" "$first"; then
            echo "$first"
            return 0
        fi
        while IFS= read -r series; do
            [ -n "$series" ] || continue
            if utils_composer_constraint_matches "$version" "$series"; then
                echo "$series"
                return 0
            fi
        done <<< "$installed"
        echo "$first"
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
    local php_line
    php_line=$(grep "^php " "$tool_file" 2>/dev/null | head -n 1)
    
    if [ -n "$php_line" ]; then
        # Extract version: php 8.1.0 -> 8.1.0
        local version
        version=$(echo "$php_line" | awk '{print $2}')
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
    # The user's login shell comes first: phpswitch itself runs under bash,
    # so $BASH_VERSION below is always set and says nothing about the user
    case "$(basename "${SHELL:-}")" in
        zsh|bash|fish)
            basename "$SHELL"
            return 0
            ;;
    esac

    # Fall back to the shell we are running in
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

# Bash startup file that the user's terminals actually read.
# $1: fixed string marking phpswitch's own content; a file that already
# contains it is kept, so existing setups never get a second copy.
# On macOS, Terminal starts login shells, which read only the first of
# .bash_profile, .bash_login and .profile (never .bashrc). An existing
# login file is never shadowed by creating .bash_profile.
function shell_bash_rc_file {
    local marker="$1" f login=""
    if [ -n "$marker" ]; then
        for f in .bashrc .bash_profile .bash_login .profile; do
            if [ -f "$HOME/$f" ] && grep -qF -- "$marker" "$HOME/$f" 2>/dev/null; then
                printf '%s\n' "$HOME/$f"
                return 0
            fi
        done
    fi

    if [ "$(uname -s 2>/dev/null)" != "Darwin" ]; then
        if [ -f "$HOME/.bashrc" ]; then
            printf '%s\n' "$HOME/.bashrc"
        elif [ -f "$HOME/.bash_profile" ]; then
            printf '%s\n' "$HOME/.bash_profile"
        elif [ -f "$HOME/.profile" ]; then
            printf '%s\n' "$HOME/.profile"
        else
            printf '%s\n' "$HOME/.bashrc"
        fi
        return 0
    fi

    for f in .bash_profile .bash_login .profile; do
        if [ -f "$HOME/$f" ]; then
            login="$HOME/$f"
            break
        fi
    done
    if [ -z "$login" ]; then
        printf '%s\n' "$HOME/.bash_profile"
    elif [ -f "$HOME/.bashrc" ] &&
         grep -qE '^[[:space:]]*[^#]*(\.|source)[[:space:]]+[^#]*\.bashrc' "$login" 2>/dev/null; then
        # The login file loads .bashrc, which also covers non-login shells
        printf '%s\n' "$HOME/.bashrc"
    else
        printf '%s\n' "$login"
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
            rc_file=$(shell_bash_rc_file "# BEGIN PHPSWITCH MANAGED BLOCK")
            [ -f "$rc_file" ] || touch "$rc_file" # Create if it doesn't exist
            ;;
        "fish")
            # For fish, use config.fish
            local fish_config_dir="$HOME/.config/fish"
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
    local shell_type
    shell_type=$(shell_detect_shell)
    local rc_file
    rc_file=$(shell_get_rc_file "$shell_type")
    if [ -z "$rc_file" ]; then
        utils_show_status "error" "Could not determine shell RC file"
        return 1
    fi
    
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

    # Already configured for this version (judged only by the managed block's
    # own header line): no rewrite, no backup churn
    local managed_version
    managed_version=$(awk '
        /^# BEGIN PHPSWITCH MANAGED BLOCK/ { inside = 1; next }
        inside && /^# END PHPSWITCH MANAGED BLOCK/ { exit }
        inside && sub(/^# Path configuration for PHP version: /, "") { print; exit }
    ' "$rc_file")
    if [ -n "$managed_version" ] && [ "$managed_version" = "$new_version" ]; then
        utils_show_status "info" "$rc_file already points at $new_version"
        return 0
    fi
    
    # Create backup (only if enabled)
    if [ "$BACKUP_CONFIG_FILES" = "true" ]; then
        local backup_file
        backup_file="${rc_file}.bak.$(date +%Y%m%d%H%M%S)"
        
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
        # Print everything before the begin marker
        awk -v begin="$begin_marker" '
            index($0, begin) > 0 {exit}
            {print}
        ' "$rc_file" > "$temp_file"

        # Append the new block
        append_path_code "$temp_file"

        # Print everything after the end marker
        awk -v end="$end_marker" '
            past_end {print}
            index($0, end) > 0 {past_end=1}
        ' "$rc_file" >> "$temp_file"
    else
        # No existing block - add to beginning of file
        append_path_code "$temp_file"
        
        # Add the original content
        cat "$rc_file" >> "$temp_file"
    fi
    
    # Atomic, symlink- and mode-preserving replace
    if ! utils_replace_file_contents "$rc_file" "$temp_file"; then
        rm -f "$temp_file"
        utils_show_status "error" "Could not update $rc_file; it was left unchanged"
        return 1
    fi
    rm -f "$temp_file"
    
    utils_show_status "success" "Updated PATH in $rc_file for $new_version"
    
    # Create instructions file for sourcing.
    # Use plain mktemp so the file persists after phpswitch exits (EXIT trap would delete it).
    local instructions_file
    instructions_file=$(mktemp)
    chmod 600 "$instructions_file"
    
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
    local shell_type
    shell_type=$(shell_detect_shell)
    
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
    
    # Direct PATH manipulation for the current shell:
    # rebuild PATH with PHP paths first, dropping any existing PHP entries
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

        # Validate PHP paths before using them
        if ! utils_validate_path "$php_bin_path"; then
            utils_show_status "error" "Invalid PHP bin path: $php_bin_path"
            return 1
        fi
        if ! utils_validate_path "$php_sbin_path"; then
            utils_show_status "error" "Invalid PHP sbin path: $php_sbin_path"
            return 1
        fi
        
        local old_IFS="$IFS"
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
        IFS="$old_IFS"

        # Set the new PATH with PHP paths first
        export PATH="$php_bin_path:$php_sbin_path:$system_paths"
        
        # Force the shell to forget previous command locations
        hash -r 2>/dev/null || rehash 2>/dev/null || true
        
        # Log the updated PATH for debugging
        core_debug_log "After PATH update: $PATH"
        
        # Verify PHP version
        local current_php
        current_php=$(command -v php)
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
    local shell_type
    shell_type=$(shell_detect_shell)
    local php_bin_path=""
    local php_sbin_path=""
    
    if [ "$version" = "php@default" ]; then
        php_bin_path="$HOMEBREW_PREFIX/opt/php/bin"
        php_sbin_path="$HOMEBREW_PREFIX/opt/php/sbin"
    else
        php_bin_path="$HOMEBREW_PREFIX/opt/$version/bin"
        php_sbin_path="$HOMEBREW_PREFIX/opt/$version/sbin"
    fi
    
    # Create a temporary script that can be sourced to reload the PATH.
    # Use plain mktemp (not utils_create_secure_temp_file) so the file is NOT
    # tracked for cleanup on EXIT — the user needs it to persist after phpswitch exits.
    local reload_script
    reload_script=$(mktemp)
    chmod 600 "$reload_script"
    
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
        local default_version_full
        default_version_full=$(brew list --versions php 2>/dev/null | head -n 1)
        local default_version_str
        default_version_str=$(echo "$default_version_full" | awk '{print $2}')
        local default_version
        default_version=$(echo "$default_version_str" | cut -d. -f1,2)

        # Check if requested version matches default version (e.g. php@8.4 == 8.4)
        local requested_num="${version#php@}"
        
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
    local current_dir
    current_dir="$(pwd)"
    local php_version_file=""
    local project_version=""
    local custom_files=(".php-version" ".phpversion")
    local home="${HOME%/}"
    
    # Walk parent directories up to $HOME (FEAT-03: don't go beyond home).
    # Match whole path components so /Users/bobby isn't inside /Users/bob.
    while [ "$current_dir" != "/" ] && [ "$current_dir" != "." ] &&
          { [ "$current_dir" = "$home" ] || [[ "$current_dir" == "$home"/* ]]; }; do
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
        
        # Move to parent directory (pure bash, no subprocess)
        current_dir="${current_dir%/*}"
        [ -z "$current_dir" ] && current_dir="/"
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
        if [[ "${project_version#php@}" =~ ^([0-9]+)\.([0-9]+)(\.[0-9]+)?$ ]]; then
            # X.Y or a full patch version (8.2.10, phpenv style): Homebrew
            # installs are per minor, so use php@X.Y
            echo "php@${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
            return 0
        elif [[ "$project_version" == php@* ]]; then
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
                    local minor_ver
                    minor_ver="${version#"php@$project_version."}"
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
    
    # ARCH-04: Detect non-interactive mode (stdin is not a terminal)
    local _interactive=true
    [ ! -t 0 ] && _interactive=false
    
    utils_show_status "info" "Installing $install_version... This may take a while..."
    
    # FEAT-04: Set up SIGINT trap during brew operations
    local _prev_trap
    _prev_trap=$(trap -p INT)
    trap 'utils_show_status "warning" "Installation interrupted. Cleaning up..."; brew cleanup 2>/dev/null; eval "$_prev_trap"; return 1' INT
    
    # Capture both stdout and stderr from brew install
    local temp_output
    temp_output=$(utils_create_secure_temp_file) || { utils_show_status "error" "Failed to create temp file"; return 1; }
    if brew install "$install_version" > "$temp_output" 2>&1; then
        utils_show_status "success" "$version installed successfully"
        rm -f "$temp_output"
        return 0
    else
        local error_output
        error_output=$(cat "$temp_output")
        rm -f "$temp_output"
        
        # Check for specific error conditions
        if echo "$error_output" | grep -q "Permission denied"; then
            utils_show_status "error" "Permission denied during installation. Try running with sudo."
        elif echo "$error_output" | grep -q "Resource busy"; then
            utils_show_status "error" "Resource busy error. Another process may be using PHP files."
            echo "Try closing applications that might be using PHP, or restart your computer."
        elif echo "$error_output" | grep -q "already installed"; then
            utils_show_status "warning" "$version appears to be already installed but may be broken"
            if [ "$_interactive" = "true" ]; then
                printf "  Reinstall it? (y/n) "
                if [ "$(utils_validate_yes_no "" "y")" = "y" ]; then
                    if brew reinstall "$install_version"; then
                        utils_show_status "success" "$version reinstalled successfully"
                        eval "$_prev_trap"
                        return 0
                    else
                        utils_show_status "error" "Reinstallation failed"
                    fi
                fi
            else
                utils_show_status "info" "Skipping reinstall prompt (non-interactive mode)"
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
        if [ "$(echo "$error_output" | wc -l | tr -d ' ')" -gt 10 ]; then
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
            if echo "$_installed_list" | grep -qxF "$install_version" || \
               ([ "$install_version" = "php" ] && echo "$_installed_list" | grep -qxF "php"); then
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
    local service_name
    service_name=$(fpm_get_service_name "$version")
    
    if ! core_check_php_installed "$version"; then
        utils_show_status "error" "$version is not installed"
        return 1
    fi
    
    # Check if it's the current active version
    local current_version
    current_version=$(core_get_current_php_version)
    if [ "$current_version" = "$version" ]; then
        utils_show_status "warning" "You are attempting to uninstall the currently active PHP version"
        printf "  Continue? This may break your PHP environment. (y/n) "

        if [ "$(utils_validate_yes_no "" "n")" = "n" ]; then
            utils_show_status "info" "Uninstallation cancelled"
            return 1
        fi
    fi
    
    # Stop PHP-FPM service if running
    if brew services list | awk -v svc="$service_name" '$1 == svc' | grep -q .; then
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
            # Validate before rm -rf: must be non-empty and numeric X.Y form only
            if [[ -z "$php_version" ]] || ! [[ "$php_version" =~ ^[0-9]+\.[0-9]+$ ]]; then
                utils_show_status "warning" "Cannot determine config directory for '$version'; skipping"
            elif [ -d "$HOMEBREW_PREFIX/etc/php/$php_version" ]; then
                utils_show_status "info" "Removing configuration files..."
                if rm -rf "$HOMEBREW_PREFIX/etc/php/$php_version"; then
                    utils_show_status "success" "Configuration files removed"
                else
                    utils_show_status "error" "Could not remove $HOMEBREW_PREFIX/etc/php/$php_version"
                    printf "  If it is owned by root, run:\n    sudo rm -rf \"%s\"\n" "$HOMEBREW_PREFIX/etc/php/$php_version"
                fi
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
    local current_version
    current_version=$(core_get_current_php_version)
    
    # Whether anything FPM depends on changed (a relink or a reinstall)
    local version_changed=false

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
                    version_changed=true
                fi
            else
                utils_show_status "info" "Skipping reinstallation. Proceeding with version switch..."
            fi
        fi
    fi
    
    if [ "$current_version" = "$new_version" ]; then
        utils_show_status "info" "$new_version is already active in Homebrew"
    else
        version_changed=true
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
            
            if [ ! -d "$php_bin_path" ] && [ "$new_version" = "php@default" ]; then
                php_bin_path="$HOMEBREW_PREFIX/opt/php/bin"
            fi
            
            if [ -d "$php_bin_path" ]; then
                local link_failed=false
                for file in "$php_bin_path"/*; do
                    if [ -f "$file" ] && [ -x "$file" ]; then
                        local filename
                        filename=$(basename "$file")
                        ln -sf "$file" "$HOMEBREW_PREFIX/bin/$filename" 2>/dev/null || link_failed=true
                    fi
                done
                if [ "$link_failed" = "true" ]; then
                    utils_show_status "error" "Could not link into $HOMEBREW_PREFIX/bin (it may contain root-owned files)"
                    printf "  Fix ownership with:\n    sudo chown -R %s \"%s/bin\"\n" "$(id -un)" "$HOMEBREW_PREFIX"
                    printf "  then run: brew link --overwrite %s\n" "$brew_version"
                    exit 1
                fi
                utils_show_status "success" "Manual linking completed"
            else
                utils_show_status "error" "Could not find PHP installation directory"
                exit 1
            fi
        fi
    fi
    
    # Create and update shell configuration
    shell_update_rc "$new_version" > /dev/null

    # Create a reload script for immediate use
    local reload_script
    reload_script=$(shell_create_reload_script "$new_version")
    
    # Move PHP-FPM to the new version only if one is running (not when
    # nothing changed, and never start one that wasn't running)
    if [ "$version_changed" = "true" ] && [ "$AUTO_RESTART_PHP_FPM" = "true" ] && fpm_any_running; then
        fpm_restart "$new_version"
    fi
    
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

# Whether any PHP-FPM service is started (exact field matches avoid "php"
# matching "php@8.1")
function fpm_any_running {
    brew services list 2>/dev/null |
        awk '$1 ~ /^php(@[0-9]+\.[0-9]+)?$/ && $2 == "started" { found = 1 } END { exit !found }'
}

# Function to stop all other PHP-FPM services except the active one
function fpm_stop_other_services {
    local active_version="$1"
    local active_service
    active_service=$(fpm_get_service_name "$active_version")
    
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
    local service_name
    service_name=$(fpm_get_service_name "$version")
    
    utils_show_status "info" "Cleaning up PHP-FPM service files for $service_name..."
    
    # Stop the service first
    brew services stop "$service_name" >/dev/null 2>&1
    
    # Find and remove LaunchAgent/LaunchDaemon files
    local launch_agent="$HOME/Library/LaunchAgents/homebrew.mxcl.$service_name.plist"
    local launch_daemon="${PHPSWITCH_LAUNCH_DAEMONS_DIR:-/Library/LaunchDaemons}/homebrew.mxcl.$service_name.plist"
    
    if [ -f "$launch_agent" ]; then
        utils_show_status "info" "Removing LaunchAgent file: $launch_agent"
        rm -f "$launch_agent" 2>/dev/null
    fi
    
    # Root-owned leftovers (from `sudo brew services`) need administrator
    # rights; show the exact commands and only run them with explicit consent
    local cellar_path="$HOMEBREW_PREFIX/Cellar/$service_name"
    local opt_path="$HOMEBREW_PREFIX/opt/$service_name"
    local username
    username="$(id -un)"
    local -a root_cmds=()
    if [ -f "$launch_daemon" ]; then
        root_cmds+=("rm -f \"$launch_daemon\"")
    fi
    if utils_validate_username "$username"; then
        if [ -d "$cellar_path" ] && [ -n "$(find "$cellar_path" -maxdepth 3 -user root -print -quit 2>/dev/null)" ]; then
            root_cmds+=("chown -R \"$username\" \"$cellar_path\"")
        fi
        if [ -d "$opt_path" ] && [ -n "$(find "$opt_path/" -maxdepth 3 -user root -print -quit 2>/dev/null)" ]; then
            root_cmds+=("chown -R \"$username\" \"$opt_path\"")
        fi
    fi
    if [ ${#root_cmds[@]} -gt 0 ]; then
        utils_show_status "warning" "These root-owned leftovers need administrator rights to fix:"
        local root_cmd
        for root_cmd in "${root_cmds[@]}"; do
            printf "    sudo %s\n" "$root_cmd"
        done
        printf "  Run them now with sudo? (y/N) "
        if [ "$(utils_validate_yes_no "" "n")" = "y" ]; then
            [ -f "$launch_daemon" ] && sudo rm -f "$launch_daemon"
            if utils_validate_username "$username"; then
                [ -d "$cellar_path" ] && sudo chown -R "$username" "$cellar_path"
                [ -d "$opt_path" ] && sudo chown -R "$username" "$opt_path/"
            fi
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
    local service_name
    service_name=$(fpm_get_service_name "$version")

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
        
        # Try user-mode restart first (SEC-04: avoid sudo for brew services)
        local restart_output
        restart_output=$(brew services restart "$service_name" 2>&1)
        if echo "$restart_output" | grep -q "Successfully"; then
            utils_show_status "success" "PHP-FPM service restarted successfully"
        else
            utils_show_status "warning" "Failed to restart service: $restart_output"
            
            # Check for specific error patterns
            if echo "$restart_output" | grep -q "Bootstrap failed: 5: Input/output error"; then
                utils_show_status "warning" "Detected bootstrap error. Attempting automatic service cleanup and repair..."
                fpm_cleanup_service "$version"
                utils_show_status "info" "Trying restart after cleanup..."
                local retry_output
                retry_output=$(brew services start "$service_name" 2>&1)

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
                local cleanup_output
                cleanup_output=$(brew services start "$service_name" 2>&1)

                if echo "$cleanup_output" | grep -q "Successfully"; then
                    utils_show_status "success" "PHP-FPM service restarted successfully after cleanup"
                else
                    utils_show_status "error" "Failed to restart PHP-FPM: $cleanup_output"
                    printf "  Check the service with: brew services info %s\n" "$service_name"
                    printf "  Avoid 'sudo brew services': it makes Homebrew files root-owned.\n"
                fi
            elif echo "$restart_output" | grep -q "already started"; then
                utils_show_status "warning" "Service reports as already started. Forcing stop and restart..."
                brew services stop "$service_name" >/dev/null 2>&1
                local _i=0
                while [ $_i -lt 12 ] && brew services list | awk -v svc="$service_name" '$1 == svc' | grep -q "started"; do
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
                local unknown_retry
                unknown_retry=$(brew services start "$service_name" 2>&1)

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
        local start_output
        start_output=$(brew services start "$service_name" 2>&1)

        if echo "$start_output" | grep -q "Successfully"; then
            utils_show_status "success" "PHP-FPM service started successfully"
        else
            utils_show_status "warning" "Failed to start service: $start_output"

            # Check for bootstrap/IO error specifically
            if echo "$start_output" | grep -q "Bootstrap failed: 5: Input/output error"; then
                utils_show_status "warning" "Detected bootstrap error. Attempting automatic service cleanup and repair..."
                fpm_cleanup_service "$version"
                utils_show_status "info" "Trying restart after cleanup..."
                local retry_output
                retry_output=$(brew services start "$service_name" 2>&1)

                if echo "$retry_output" | grep -q "Successfully"; then
                    utils_show_status "success" "PHP-FPM service started successfully after cleanup"
                else
                    utils_show_status "error" "Failed to start service after cleanup: $retry_output"
                    printf "  Manual intervention may be required. Consider reinstalling PHP:\n"
                    printf "    brew reinstall %s\n" "$service_name"
                fi
            else
                utils_show_status "error" "Failed to start PHP-FPM: $start_output"
                printf "  Check the service with: brew services info %s\n" "$service_name"
                printf "  Avoid 'sudo brew services': it makes Homebrew files root-owned.\n"
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
            for f in "$ini_dir/conf.d/"*.ini; do
                [ -e "$f" ] || continue
                echo "    $(basename "$f")"
            done
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
                        # SEC-05: Re-validate php_version before passing to brew
                        if ! utils_validate_version "$php_version"; then
                            utils_show_status "error" "Invalid PHP version format: $php_version"
                            return 1
                        fi
                        # Try to enable via Homebrew
                        if brew install "$php_version-$ext_name" 2>/dev/null; then
                            utils_show_status "success" "Extension $ext_name installed via Homebrew"
                            fpm_restart "$php_version"
                        else
                            utils_show_status "warning" "Could not install via Homebrew, trying PECL..."
                            utils_show_status "warning" "PECL will download and compile C code from pecl.php.net"
                            printf "  Continue with PECL install? (y/n) "
                            if [ "$(utils_validate_yes_no "" "y")" = "y" ]; then
                                if pecl install "$ext_name"; then
                                    utils_show_status "success" "Extension $ext_name installed via PECL"
                                    fpm_restart "$php_version"
                                else
                                    utils_show_status "error" "Failed to enable $ext_name"
                                fi
                            fi
                        fi
                    fi
                elif [ "$ext_action" = "2" ]; then
                    utils_show_status "info" "Disabling $ext_name..."
                    if [ -f "$ini_dir/conf.d/ext-$ext_name.ini" ]; then
                        if mv "$ini_dir/conf.d/ext-$ext_name.ini" "$ini_dir/conf.d/ext-$ext_name.ini.disabled"; then
                            utils_show_status "success" "Extension $ext_name disabled"
                            fpm_restart "$php_version"
                        else
                            utils_show_status "error" "Could not rename $ini_dir/conf.d/ext-$ext_name.ini"
                            printf "  If it is owned by root, run:\n    sudo mv \"%s\" \"%s.disabled\"\n" "$ini_dir/conf.d/ext-$ext_name.ini" "$ini_dir/conf.d/ext-$ext_name.ini"
                        fi
                    elif [ -f "$ini_dir/conf.d/$ext_name.ini" ]; then
                        if mv "$ini_dir/conf.d/$ext_name.ini" "$ini_dir/conf.d/$ext_name.ini.disabled"; then
                            utils_show_status "success" "Extension $ext_name disabled"
                            fpm_restart "$php_version"
                        else
                            utils_show_status "error" "Could not rename $ini_dir/conf.d/$ext_name.ini"
                            printf "  If it is owned by root, run:\n    sudo mv \"%s\" \"%s.disabled\"\n" "$ini_dir/conf.d/$ext_name.ini" "$ini_dir/conf.d/$ext_name.ini"
                        fi
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
# Installs per-shell integration into rc files (migrating the legacy hook)
# and keeps the legacy global auto-switch (--auto-mode) for unmigrated users

# Marker for the per-shell integration line written to rc files
AUTO_INIT_MARKER="# PHPSwitch shell integration"

# Legacy hook block (v1.4.1+): starts with this exact line and ends with the
# first following line that is exactly "phpswitch_auto_detect_project".
AUTO_LEGACY_START="# PHPSwitch auto-switching"
AUTO_LEGACY_END="phpswitch_auto_detect_project"
AUTO_LEGACY_MAX_LINES=100

# rc file used for the integration line
function auto_rc_file {
    case "$1" in
        zsh) printf '%s\n' "$HOME/.zshrc" ;;
        bash) shell_bash_rc_file "$AUTO_INIT_MARKER" ;;
        fish) printf '%s\n' "$HOME/.config/fish/config.fish" ;;
        *) return 1 ;;
    esac
}

# Back up an rc file next to itself (owner-only permissions)
function auto_backup_rc {
    local rc_file="$1"
    [ -f "$rc_file" ] || return 0
    local backup_file
    backup_file="${rc_file}.bak.$(date +%Y%m%d%H%M%S)"
    utils_validate_path "$backup_file" || return 1
    cp "$rc_file" "$backup_file" || return 1
    chmod 600 "$backup_file" 2>/dev/null
    utils_show_status "info" "Created backup at $backup_file"
}

# Print rc content with legacy hook blocks removed.
# Exit 0: blocks removed (output is the new content)
# Exit 1: no legacy block present
# Exit 2: a legacy block was found that cannot be removed safely
function auto_strip_legacy_hooks {
    local rc_file="$1"
    grep -q "phpswitch_auto_detect_project" "$rc_file" 2>/dev/null || return 1

    # v1.4.0 blocks have no reliable end anchor
    if grep -qx "# PHPSwitch auto-switching hooks" "$rc_file"; then
        return 2
    fi

    local stripped
    stripped=$(awk -v start="$AUTO_LEGACY_START" -v end_line="$AUTO_LEGACY_END" -v max="$AUTO_LEGACY_MAX_LINES" '
        { lines[NR] = $0 }
        END {
            n = 0
            i = 1
            while (i <= NR) {
                if (lines[i] == start) {
                    j = i + 1
                    while (j <= NR && j - i <= max && lines[j] != end_line) j++
                    if (j > NR || j - i > max) exit 2
                    # drop the blank separator line written before the block
                    if (n > 0 && out[n] == "") n--
                    i = j + 1
                    continue
                }
                out[++n] = lines[i]
                i++
            }
            for (k = 1; k <= n; k++) print out[k]
        }
    ' "$rc_file") || return 2

    # Anything still referencing the legacy hook is an unknown variant
    if printf '%s\n' "$stripped" | grep -q "phpswitch_auto_detect_project"; then
        return 2
    fi
    printf '%s\n' "$stripped"
}

# Integration line for an rc file, using this script's absolute path
function auto_init_line {
    local shell_type="$1" self
    self=$(init_self_path)
    case "$self" in
        *"'"*|*$'\n'*|*\\*) return 1 ;;
    esac
    if [ "$shell_type" = "fish" ]; then
        printf "test -x '%s'; and '%s' init fish | source\n" "$self" "$self"
    else
        printf "[ -x '%s' ] && eval \"\$('%s' init %s)\"\n" "$self" "$self" "$shell_type"
    fi
}

# The user's login shell, or failure when it isn't zsh/bash/fish (unlike
# shell_detect_shell, which falls back to guessing)
function auto_login_shell {
    local shell_name
    shell_name=$(basename "${SHELL:-}")
    case "$shell_name" in
        zsh|bash|fish) printf '%s\n' "$shell_name" ;;
        *) return 1 ;;
    esac
}

# Every shell startup file phpswitch may have written to, one per line
function auto_rc_candidates {
    printf '%s\n' "$HOME/.zshrc" "$HOME/.zprofile" "$HOME/.bashrc" "$HOME/.bash_profile" \
        "$HOME/.bash_login" "$HOME/.profile" "$HOME/.config/fish/config.fish"
}

# Every rc file a legacy installer may have written to
function auto_legacy_rc_candidates {
    local f
    while IFS= read -r f; do
        [ -f "$f" ] && grep -q "phpswitch_auto_detect_project" "$f" 2>/dev/null && printf '%s\n' "$f"
    done < <(auto_rc_candidates)
}

# Install per-shell integration into the login shell's rc file and remove the
# legacy global-switching hook from every rc file. Every legacy block is
# checked before anything is written: on any doubt, all files stay
# byte-identical.
function auto_install {
    local shell_type
    if ! shell_type=$(auto_login_shell); then
        utils_show_status "error" "Unsupported login shell: ${SHELL:-unknown}"
        printf "  Per-shell switching supports bash, zsh and fish.\n"
        return 1
    fi
    local rc_file
    rc_file=$(auto_rc_file "$shell_type")

    local init_line
    if ! init_line=$(auto_init_line "$shell_type"); then
        utils_show_status "error" "Cannot reference phpswitch from $rc_file: unsupported characters in its path"
        return 1
    fi

    # 1. Check every legacy block before changing anything
    local legacy_files=() unsafe_files=() f
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        legacy_files+=("$f")
        auto_strip_legacy_hooks "$f" > /dev/null
        [ $? -eq 2 ] && unsafe_files+=("$f")
    done < <(auto_legacy_rc_candidates)

    if [ ${#unsafe_files[@]} -gt 0 ]; then
        utils_show_status "error" "Found an older PHPSwitch auto-switching block that can't be removed automatically"
        for f in "${unsafe_files[@]}"; do
            printf "    %s\n" "$f"
        done
        printf "  No files were changed. Remove the block containing 'phpswitch_auto_detect_project'\n"
        printf "  by hand, then run this again. Or add this line to %s yourself:\n\n    %s\n\n" "$rc_file" "$init_line"
        return 1
    fi

    for f in "${legacy_files[@]}" "$rc_file"; do
        if [ -e "$f" ] && [ ! -w "$f" ]; then
            utils_show_status "error" "No write permission for $f; no files were changed"
            return 1
        fi
    done

    # Back up the target rc now, so a failed backup can't leave legacy hooks
    # removed without the integration line added
    local needs_init=true
    if [ -f "$rc_file" ] && grep -qxF "$AUTO_INIT_MARKER" "$rc_file"; then
        needs_init=false
    fi
    local migrated=false
    for f in "${legacy_files[@]}"; do
        [ "$f" = "$rc_file" ] && migrated=true
    done
    if [ "$needs_init" = "true" ] && [ "$migrated" = "false" ]; then
        auto_backup_rc "$rc_file" || {
            utils_show_status "error" "Could not back up $rc_file; no files were changed"
            return 1
        }
    fi

    # 2. Remove legacy blocks (they relink PHP globally on every cd).
    # Atomic replace that keeps symlinked rc files and their permissions.
    local content stripped_file
    for f in "${legacy_files[@]}"; do
        content=$(auto_strip_legacy_hooks "$f") || continue
        auto_backup_rc "$f" || {
            utils_show_status "error" "Could not back up $f; leaving it unchanged"
            return 1
        }
        stripped_file=$(utils_create_secure_temp_file)
        printf '%s\n' "$content" > "$stripped_file"
        if ! utils_replace_file_contents "$f" "$stripped_file"; then
            rm -f "$stripped_file"
            utils_show_status "error" "Could not update $f; it was left unchanged"
            return 1
        fi
        rm -f "$stripped_file"
        utils_show_status "success" "Removed the legacy auto-switching hook from $f"
    done
    if [ ${#legacy_files[@]} -gt 0 ]; then
        rm -f "$HOME/.cache/phpswitch/directory_cache.txt" 2>/dev/null
    fi

    # 3. Add the integration line to the login shell's rc file
    mkdir -p "$(dirname "$rc_file")" 2>/dev/null
    if [ "$needs_init" = "false" ]; then
        utils_show_status "info" "Per-shell switching is already set up in $rc_file"
    else
        printf '\n%s\n%s\n' "$AUTO_INIT_MARKER" "$init_line" >> "$rc_file"
        utils_show_status "success" "Added per-shell switching to $rc_file"
    fi

    if [ -f "$HOME/.phpswitch.conf" ]; then
        utils_set_config_value "AUTO_SWITCH_PHP_VERSION" "true" "$HOME/.phpswitch.conf"
    fi

    printf "  Open a new terminal (or reload %s) to start using it.\n" "$rc_file"
    printf "  Each shell now follows the project's PHP version on cd; use 'phpswitch use VERSION' to pin one.\n"
    return 0
}

# Every rc file holding the integration line written by auto_install
function auto_integration_rc_files {
    local f
    while IFS= read -r f; do
        [ -f "$f" ] && grep -qxF "$AUTO_INIT_MARKER" "$f" 2>/dev/null && printf '%s\n' "$f"
    done < <(auto_rc_candidates)
}

# Whether phpswitch's auto-switching is in any rc file (v2 line or legacy hook)
function auto_is_installed {
    [ -n "$(auto_integration_rc_files)$(auto_legacy_rc_candidates)" ]
}

# Print stdin with each integration marker, the line after it and the blank
# separator before it removed. Exit 2 (and print nothing usable) when the
# line after a marker isn't a `... init <shell>` line written by auto_install.
function auto_strip_init_lines {
    awk -v marker="$AUTO_INIT_MARKER" '
        { lines[NR] = $0 }
        END {
            n = 0
            i = 1
            while (i <= NR) {
                if (lines[i] == marker) {
                    next_line = lines[i + 1]
                    if (i + 1 > NR || next_line !~ / init (zsh|bash|fish)/ ||
                        (next_line !~ /eval/ && next_line !~ /\| source$/)) exit 2
                    if (n > 0 && out[n] == "") n--
                    i += 2
                    continue
                }
                out[++n] = lines[i]
                i++
            }
            for (k = 1; k <= n; k++) print out[k]
        }
    '
}

# Remove per-shell switching (and any legacy hook) from every rc file.
# Every file is checked before anything is written: on any doubt, all files
# stay byte-identical.
function auto_uninstall {
    local files=() f
    while IFS= read -r f; do
        [ -n "$f" ] && files+=("$f")
    done < <({ auto_integration_rc_files; auto_legacy_rc_candidates; } | awk '!seen[$0]++')

    if [ ${#files[@]} -eq 0 ]; then
        utils_show_status "info" "No PHPSwitch auto-switching found in your shell config"
        if [ -n "${PHPSWITCH_BIN:-}" ]; then
            printf "  This shell loads it from a line you added yourself; remove the\n"
            printf "  'phpswitch init' line from your shell config to turn it off.\n"
        fi
        return 0
    fi

    # 1. Build the new content of every file before changing any of them
    local new_files=() content status failed=""
    for f in "${files[@]}"; do
        if [ ! -w "$f" ]; then
            failed="$f (no write permission)"
            break
        fi
        content=$(cat "$f") || { failed="$f (unreadable)"; break; }
        if grep -q "phpswitch_auto_detect_project" "$f"; then
            content=$(auto_strip_legacy_hooks "$f")
            status=$?
            if [ $status -ne 0 ]; then
                failed="$f (older auto-switching block that can't be removed safely)"
                break
            fi
        fi
        if printf '%s\n' "$content" | grep -qxF "$AUTO_INIT_MARKER"; then
            content=$(printf '%s\n' "$content" | auto_strip_init_lines)
            status=$?
            if [ $status -ne 0 ]; then
                failed="$f (the line after '$AUTO_INIT_MARKER' isn't one phpswitch wrote)"
                break
            fi
        fi
        local tmp
        tmp=$(utils_create_secure_temp_file) || { failed="$f (no temp file)"; break; }
        printf '%s\n' "$content" > "$tmp"
        new_files+=("$tmp")
    done

    if [ -n "$failed" ]; then
        rm -f "${new_files[@]}"
        utils_show_status "error" "Can't remove auto-switching from $failed"
        printf "  No files were changed. Remove the PHPSwitch lines by hand, then run this again.\n"
        return 1
    fi

    # 2. Back up and replace
    local i
    for i in "${!files[@]}"; do
        f="${files[$i]}"
        if ! auto_backup_rc "$f"; then
            rm -f "${new_files[@]}"
            utils_show_status "error" "Could not back up $f; it was left unchanged"
            return 1
        fi
        if ! utils_replace_file_contents "$f" "${new_files[$i]}"; then
            rm -f "${new_files[@]}"
            utils_show_status "error" "Could not update $f; it was left unchanged"
            return 1
        fi
        rm -f "${new_files[$i]}"
        utils_show_status "success" "Removed auto-switching from $f"
    done
    rm -f "$HOME/.cache/phpswitch/directory_cache.txt" 2>/dev/null

    if [ -f "$HOME/.phpswitch.conf" ]; then
        utils_set_config_value "AUTO_SWITCH_PHP_VERSION" "false" "$HOME/.phpswitch.conf"
    fi

    printf "  New terminals no longer follow project PHP versions, and 'phpswitch use'\n"
    printf "  is unavailable there; 'phpswitch global VERSION' still works.\n"
    printf "  Shells that are already open keep it until they exit.\n"
    return 0
}

# Function to clear auto-switching directory cache
function auto_clear_directory_cache {
    local cache_file="$HOME/.cache/phpswitch/directory_cache.txt"
    
    if [ -f "$cache_file" ]; then
        if [ -w "$cache_file" ]; then
            rm -f "$cache_file" 2>/dev/null
            utils_show_status "success" "Directory cache cleared"
        else
            utils_show_status "warning" "No write permission for $cache_file"
            printf "  Remove it yourself with:\n    sudo rm -f \"%s\"\n" "$cache_file"
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

    # Unlink current PHP (skip if no version is active)
    local _current_ver
    _current_ver=$(core_get_current_php_version)
    if [ -n "$_current_ver" ] && [ "$_current_ver" != "none" ]; then
        brew unlink "$_current_ver" &>/dev/null
    fi

    if ! brew link --force "$brew_version" &>/dev/null; then
        return 1
    fi

    # Move a running PHP-FPM over to the new version, if enabled. Only
    # services that are actually started are touched: when no PHP-FPM was
    # running, none is started.
    if [ "$AUTO_RESTART_PHP_FPM" = "true" ]; then
        local service_name running_services service
        service_name=$(fpm_get_service_name "$new_version")
        # One `brew services list` call (slow); exact field matches avoid
        # "php" matching "php@8.1"
        running_services=$(brew services list 2>/dev/null |
            awk '$1 ~ /^php(@[0-9]+\.[0-9]+)?$/ && $2 == "started" { print $1 }')
        if [ -n "$running_services" ]; then
            while IFS= read -r service; do
                [ "$service" != "$service_name" ] && brew services stop "$service" &>/dev/null
            done <<< "$running_services"
            if printf '%s\n' "$running_services" | grep -qxF "$service_name"; then
                brew services restart "$service_name" &>/dev/null
            else
                brew services start "$service_name" &>/dev/null
            fi
        fi
    fi

    return 0
}
# Module: init.sh
# PHPSwitch Shell Integration
# Per-shell PHP switching: `phpswitch init <shell>` prints code that is
# eval'd from the user's rc file. It defines a `phpswitch` wrapper (so
# `phpswitch use` can change PATH in the current shell) and a directory
# hook that selects the project's PHP without spawning a process in the
# common case. The binary never emits code on `cd`; it only prints a
# directory (`__php-dir`), which the shell validates before using.

# Print the opt directory for a PHP version, or for the current project
# when no version is given. Output is a bare path on stdout; all
# diagnostics go to stderr.
function init_php_dir {
    local version="$1"

    if [ -z "$version" ]; then
        version=$(version_check_project 2>/dev/null) || return 1
    else
        if ! utils_validate_version "$version"; then
            echo "phpswitch: invalid PHP version: $version" >&2
            return 1
        fi
        case "$version" in
            php@*) ;;
            php|default) version="php@default" ;;
            *) version="php@$version" ;;
        esac
    fi

    version=$(version_resolve_php_version "$version")

    if ! core_check_php_installed "$version"; then
        if [ -n "$1" ]; then
            echo "phpswitch: $version is not installed (install it with: phpswitch --install=${version#php@})" >&2
        fi
        return 1
    fi

    if [ "$version" = "php@default" ]; then
        printf '%s\n' "$HOMEBREW_PREFIX/opt/php"
    else
        printf '%s\n' "$HOMEBREW_PREFIX/opt/$version"
    fi
}

# Absolute path of the running phpswitch script
function init_self_path {
    local self="$0"
    case "$self" in
        /*) ;;
        *) self="$(cd "$(dirname "$self")" && pwd)/$(basename "$self")" ;;
    esac
    printf '%s\n' "$self"
}

# Print shell integration code for zsh, bash or fish
function init_print {
    local shell_type="$1"
    if [ -z "$shell_type" ]; then
        shell_type=$(basename "${SHELL:-zsh}")
    fi

    local self
    self=$(init_self_path)

    # Values are embedded in single quotes; refuse anything that could break out
    local value
    for value in "$self" "$HOMEBREW_PREFIX"; do
        case "$value" in
            *"'"*|*$'\n'*|*\\*)
                echo "phpswitch: cannot generate shell integration for path: $value" >&2
                return 1
                ;;
        esac
    done

    case "$shell_type" in
        zsh|bash)
            printf "# phpswitch shell integration (%s)\n" "$shell_type"
            printf "export PHPSWITCH_BIN='%s'\n" "$self"
            printf "export PHPSWITCH_PREFIX='%s'\n" "$HOMEBREW_PREFIX"
            init_print_posix
            if [ "$shell_type" = "zsh" ]; then
                cat << 'EOF'
autoload -Uz add-zsh-hook
add-zsh-hook chpwd _phpswitch_hook
# Re-evaluate even if this shell already ran the hook here (re-sourced rc)
_phpswitch_last_pwd=""
_phpswitch_hook
EOF
            else
                cat << 'EOF'
if [[ ";${PROMPT_COMMAND:-};" != *";_phpswitch_hook;"* ]]; then
    PROMPT_COMMAND="_phpswitch_hook${PROMPT_COMMAND:+;$PROMPT_COMMAND}"
fi
# Re-evaluate even if this shell already ran the hook here (re-sourced rc)
_phpswitch_last_pwd=""
_phpswitch_hook
EOF
            fi
            ;;
        fish)
            printf "# phpswitch shell integration (fish)\n"
            printf "set -gx PHPSWITCH_BIN '%s'\n" "$self"
            printf "set -gx PHPSWITCH_PREFIX '%s'\n" "$HOMEBREW_PREFIX"
            init_print_fish
            ;;
        *)
            echo "phpswitch: unsupported shell '$shell_type' (use zsh, bash or fish)" >&2
            return 1
            ;;
    esac
}

# Shared bash/zsh integration body (bash 3.2 compatible)
function init_print_posix {
    cat << 'EOF'

# Remove every exact occurrence of $1 from PATH
_phpswitch_path_remove() {
    local p=":$PATH:"
    while [[ "$p" == *":$1:"* ]]; do
        p="${p//":$1:"/:}"
    done
    p="${p#:}"
    PATH="${p%:}"
}

# A directory is usable only if it is a PHP install under the Homebrew prefix
_phpswitch_valid_dir() {
    case "$1" in
        "$PHPSWITCH_PREFIX"/opt/php*) ;;
        *) return 1 ;;
    esac
    case "$1" in
        *:*|*$'\n'*|*/..*) return 1 ;;
    esac
    [ -x "$1/bin/php" ]
}

# Put $1/bin and $1/sbin first on PATH (or remove ours when $1 is empty)
_phpswitch_apply() {
    local dir="$1"
    if [ "$dir" = "${PHPSWITCH_PHP_DIR:-}" ]; then
        if [ -z "$dir" ] || [[ "$PATH" == "$dir/bin:$dir/sbin:"* ]]; then
            return 0
        fi
    fi
    if [ -n "${PHPSWITCH_PHP_DIR:-}" ]; then
        _phpswitch_path_remove "$PHPSWITCH_PHP_DIR/bin"
        _phpswitch_path_remove "$PHPSWITCH_PHP_DIR/sbin"
    fi
    if [ -n "$dir" ]; then
        _phpswitch_path_remove "$dir/bin"
        _phpswitch_path_remove "$dir/sbin"
        PATH="$dir/bin:$dir/sbin:$PATH"
        export PHPSWITCH_PHP_DIR="$dir"
    else
        unset PHPSWITCH_PHP_DIR
    fi
    export PATH
    hash -r 2>/dev/null
}

# Ask phpswitch to resolve the project version (composer.json, .tool-versions,
# major-only versions, php@default); sets _phpswitch_found
_phpswitch_delegate() {
    _phpswitch_found=$("$PHPSWITCH_BIN" __php-dir 2>/dev/null)
    _phpswitch_valid_dir "$_phpswitch_found" || _phpswitch_found=""
}

# Find the PHP directory for $PWD; sets _phpswitch_found (empty if none).
# Mirrors version_check_project: per directory, .php-version/.phpversion,
# then composer.json/.tool-versions, walking up while inside $HOME
# (whole path components: /Users/bobby is not inside /Users/bob).
_phpswitch_detect() {
    local dir="$PWD" home="${HOME%/}" f v n line
    _phpswitch_found=""
    while [ "$dir" != "/" ] && { [ "$dir" = "$home" ] || [[ "$dir" == "$home"/* ]]; }; do
        for f in .php-version .phpversion; do
            if [ -f "$dir/$f" ]; then
                v=""
                while IFS= read -r line || [ -n "$line" ]; do
                    v="$v$line"
                done < "$dir/$f"
                v="${v//[[:space:]]/}"
                n="${v#php@}"
                if [[ "$n" =~ ^[0-9]+\.[0-9]+$ ]] && [ -x "$PHPSWITCH_PREFIX/opt/php@$n/bin/php" ]; then
                    _phpswitch_found="$PHPSWITCH_PREFIX/opt/php@$n"
                else
                    _phpswitch_delegate
                fi
                return 0
            fi
        done
        if [ -f "$dir/composer.json" ] || [ -f "$dir/.tool-versions" ]; then
            _phpswitch_delegate
            return 0
        fi
        dir="${dir%/*}"
        [ -z "$dir" ] && dir="/"
    done
}

# Directory hook: re-evaluate when $PWD changes, unless pinned by `phpswitch use`
_phpswitch_hook() {
    [ -n "${PHPSWITCH_PINNED:-}" ] && return 0
    [ "$PWD" = "${_phpswitch_last_pwd:-}" ] && return 0
    _phpswitch_last_pwd="$PWD"
    _phpswitch_detect
    _phpswitch_apply "$_phpswitch_found"
}

phpswitch() {
    local d rc
    case "${1:-}" in
        use|shell)
            if [ "${2:-}" = "auto" ] || [ "${2:-}" = "--unset" ]; then
                unset PHPSWITCH_PINNED
                _phpswitch_last_pwd=""
                _phpswitch_hook
                if [ -n "${PHPSWITCH_PHP_DIR:-}" ]; then
                    echo "phpswitch: following project files again (now ${PHPSWITCH_PHP_DIR##*/})"
                else
                    echo "phpswitch: following project files again (now global PHP)"
                fi
                return 0
            fi
            if [ -z "${2:-}" ]; then
                echo "usage: phpswitch use <version>|auto" >&2
                return 1
            fi
            d=$("$PHPSWITCH_BIN" __php-dir "$2") || return 1
            if ! _phpswitch_valid_dir "$d"; then
                echo "phpswitch: refusing invalid PHP directory: $d" >&2
                return 1
            fi
            export PHPSWITCH_PINNED=1
            _phpswitch_apply "$d"
            echo "phpswitch: this shell now uses ${d##*/} (until 'phpswitch use auto')"
            ;;
        local|global)
            "$PHPSWITCH_BIN" "$@"
            rc=$?
            _phpswitch_last_pwd=""
            _phpswitch_hook
            return $rc
            ;;
        *)
            "$PHPSWITCH_BIN" "$@"
            ;;
    esac
}
EOF
}

# fish integration body (fish 3+)
function init_print_fish {
    cat << 'EOF'

function _phpswitch_valid_dir
    string match -q -- "$PHPSWITCH_PREFIX/opt/php*" "$argv[1]"; or return 1
    string match -q -- '*:*' "$argv[1]"; and return 1
    string match -q -- '*/..*' "$argv[1]"; and return 1
    test -x "$argv[1]/bin/php"
end

function _phpswitch_apply
    set -l dir $argv[1]
    if test "$dir" = "$PHPSWITCH_PHP_DIR"
        if test -z "$dir"; or begin; test "$PATH[1]" = "$dir/bin"; and test "$PATH[2]" = "$dir/sbin"; end
            return 0
        end
    end
    # Only ever remove our own entries; an empty dir must never expand to /bin
    set -l stale
    if test -n "$PHPSWITCH_PHP_DIR"
        set -a stale "$PHPSWITCH_PHP_DIR/bin" "$PHPSWITCH_PHP_DIR/sbin"
    end
    if test -n "$dir"
        set -a stale "$dir/bin" "$dir/sbin"
    end
    set -l i
    for e in $stale
        while set i (contains -i -- $e $PATH)
            set -e PATH[$i]
        end
    end
    if test -n "$dir"
        set -gx PATH "$dir/bin" "$dir/sbin" $PATH
        set -gx PHPSWITCH_PHP_DIR $dir
    else
        set -e PHPSWITCH_PHP_DIR
    end
end

function _phpswitch_delegate
    set -l d ($PHPSWITCH_BIN __php-dir 2>/dev/null)
    _phpswitch_valid_dir "$d"; and echo $d
end

# Mirrors version_check_project (see the bash/zsh variant)
function _phpswitch_detect
    set -l dir $PWD
    set -l home (string replace -r '/$' '' -- "$HOME")
    while test "$dir" != "/"; and begin; test "$dir" = "$home"; or string match -q -- "$home/*" "$dir"; end
        for f in .php-version .phpversion
            if test -f "$dir/$f"
                set -l v (string replace -ra '\s' '' < "$dir/$f" | string join '')
                set -l n (string replace -r '^php@' '' -- "$v")
                if string match -qr '^[0-9]+\.[0-9]+$' -- "$n"; and test -x "$PHPSWITCH_PREFIX/opt/php@$n/bin/php"
                    echo "$PHPSWITCH_PREFIX/opt/php@$n"
                else
                    _phpswitch_delegate
                end
                return 0
            end
        end
        if test -f "$dir/composer.json"; or test -f "$dir/.tool-versions"
            _phpswitch_delegate
            return 0
        end
        set dir (string replace -r '/[^/]*$' '' -- "$dir")
        test -z "$dir"; and set dir /
    end
end

function _phpswitch_hook --on-variable PWD
    set -q PHPSWITCH_PINNED; and return 0
    test "$PWD" = "$_phpswitch_last_pwd"; and return 0
    set -g _phpswitch_last_pwd $PWD
    _phpswitch_apply (_phpswitch_detect)
end

function phpswitch
    switch "$argv[1]"
        case use shell
            if test "$argv[2]" = auto; or test "$argv[2]" = --unset
                set -e PHPSWITCH_PINNED
                set -g _phpswitch_last_pwd ""
                _phpswitch_hook
                if set -q PHPSWITCH_PHP_DIR
                    echo "phpswitch: following project files again (now "(string replace -r '.*/' '' -- $PHPSWITCH_PHP_DIR)")"
                else
                    echo "phpswitch: following project files again (now global PHP)"
                end
                return 0
            end
            if test -z "$argv[2]"
                echo "usage: phpswitch use <version>|auto" >&2
                return 1
            end
            set -l d ($PHPSWITCH_BIN __php-dir $argv[2]); or return 1
            if not _phpswitch_valid_dir "$d"
                echo "phpswitch: refusing invalid PHP directory: $d" >&2
                return 1
            end
            set -gx PHPSWITCH_PINNED 1
            _phpswitch_apply $d
            echo "phpswitch: this shell now uses "(string replace -r '.*/' '' -- $d)" (until 'phpswitch use auto')"
        case local global
            $PHPSWITCH_BIN $argv
            set -l rc $status
            set -g _phpswitch_last_pwd ""
            _phpswitch_hook
            return $rc
        case '*'
            $PHPSWITCH_BIN $argv
    end
end

# Re-evaluate even if this shell already ran the hook here (re-sourced rc)
set -g _phpswitch_last_pwd ""
_phpswitch_hook
EOF
}

# Module: completions.sh
# PHPSwitch Shell Completions
# `phpswitch completions <bash|zsh|fish>` prints a completion script.
# Installed versions are found by globbing the Homebrew prefix baked in at
# generation time, so completing never runs brew or phpswitch.

# Subcommands and flags offered by completion; keep in sync with --help
# (tests/13_completions.bats fails if they drift)
COMPLETION_SUBCOMMANDS="use global local init doctor completions"
COMPLETION_FLAGS="--switch= --switch-force= --install= --uninstall= --uninstall-force= --list --json --current --project --clear-cache --refresh-cache --fix-permissions --install-auto-switch --clear-directory-cache --check-dependencies --install --uninstall --update --version --debug --yes --quiet --help"

function completions_print {
    local shell_type="$1"
    if [ -z "$shell_type" ]; then
        shell_type=$(basename "${SHELL:-zsh}")
    fi

    case "$HOMEBREW_PREFIX" in
        *"'"*|*$'\n'*|*\\*)
            echo "phpswitch: cannot generate completions for prefix: $HOMEBREW_PREFIX" >&2
            return 1
            ;;
    esac

    case "$shell_type" in
        bash) completions_print_bash ;;
        zsh) completions_print_zsh ;;
        fish) completions_print_fish ;;
        *)
            echo "phpswitch: unsupported shell '$shell_type' (use zsh, bash or fish)" >&2
            return 1
            ;;
    esac
}

function completions_print_bash {
    printf "# phpswitch completions (bash)\n"
    printf "_phpswitch_completion_prefix='%s'\n" "$HOMEBREW_PREFIX"
    printf "_phpswitch_completion_words='%s %s'\n" "$COMPLETION_SUBCOMMANDS" "$COMPLETION_FLAGS"
    cat << 'EOF'
_phpswitch_completion_versions() {
    local d
    for d in "$_phpswitch_completion_prefix"/opt/php@*; do
        [ -x "$d/bin/php" ] && printf '%s\n' "${d##*/php@}"
    done
}

_phpswitch_complete() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local prev="${COMP_WORDS[COMP_CWORD-1]:-}"
    COMPREPLY=()

    # --flag=VALUE: bash splits on "=", so the value is its own word
    if [ "$prev" = "=" ] && [ "$COMP_CWORD" -ge 2 ]; then
        case "${COMP_WORDS[COMP_CWORD-2]}" in
            --switch|--switch-force|--uninstall|--uninstall-force)
                COMPREPLY=( $(compgen -W "$(_phpswitch_completion_versions)" -- "$cur") ) ;;
        esac
        return 0
    fi
    if [ "$cur" = "=" ]; then
        case "$prev" in
            --switch|--switch-force|--uninstall|--uninstall-force)
                COMPREPLY=( $(_phpswitch_completion_versions) ) ;;
        esac
        return 0
    fi

    if [ "$COMP_CWORD" -eq 1 ]; then
        COMPREPLY=( $(compgen -W "$_phpswitch_completion_words" -- "$cur") )
        # No space after "--switch=" so the version can follow (bash 4+;
        # bash 3.2 has no compopt and simply adds the space)
        if [ ${#COMPREPLY[@]} -eq 1 ] && [[ "${COMPREPLY[0]}" == *= ]] && type compopt >/dev/null 2>&1; then
            compopt -o nospace
        fi
        return 0
    fi

    case "${COMP_WORDS[1]}" in
        use) COMPREPLY=( $(compgen -W "auto $(_phpswitch_completion_versions)" -- "$cur") ) ;;
        global|local) COMPREPLY=( $(compgen -W "$(_phpswitch_completion_versions)" -- "$cur") ) ;;
        init|completions) COMPREPLY=( $(compgen -W "zsh bash fish" -- "$cur") ) ;;
    esac
    return 0
}
complete -F _phpswitch_complete phpswitch
EOF
}

function completions_print_zsh {
    printf "# phpswitch completions (zsh); load after compinit\n"
    printf "_phpswitch_completion_prefix='%s'\n" "$HOMEBREW_PREFIX"
    printf "_phpswitch_completion_flags=(%s)\n" "$COMPLETION_FLAGS"
    cat << 'EOF'
_phpswitch_completion_versions() {
    local d
    for d in "$_phpswitch_completion_prefix"/opt/php@*(N); do
        [ -x "$d/bin/php" ] && print -r -- "${d##*/php@}"
    done
}

_phpswitch_complete() {
    local -a subcmds versions
    subcmds=(
        'use:use a version in this shell only'
        'global:switch the global (Homebrew-linked) version'
        'local:write .php-version in the current directory'
        'init:print shell integration code'
        'doctor:check your PHP setup'
        'completions:print shell completions'
    )
    versions=(${(f)"$(_phpswitch_completion_versions)"})

    if (( CURRENT == 2 )); then
        if [[ "$PREFIX" == --*=* ]]; then
            local flag="${PREFIX%%=*}"
            compset -P '*='
            case "$flag" in
                --switch|--switch-force|--uninstall|--uninstall-force) compadd -a versions ;;
            esac
            return
        fi
        _describe -t commands 'phpswitch command' subcmds
        compadd -S '' -- ${(M)_phpswitch_completion_flags:#*=}
        compadd -- ${_phpswitch_completion_flags:#*=}
        return
    fi

    case "$words[2]" in
        use) compadd -- auto $versions ;;
        global|local) compadd -a versions ;;
        init|completions) compadd zsh bash fish ;;
    esac
}
(( $+functions[compdef] )) && compdef _phpswitch_complete phpswitch
EOF
}

function completions_print_fish {
    printf "# phpswitch completions (fish)\n"
    printf "set -g _phpswitch_completion_prefix '%s'\n" "$HOMEBREW_PREFIX"
    cat << 'EOF'
function __phpswitch_versions
    for d in $_phpswitch_completion_prefix/opt/php@*
        test -x "$d/bin/php"; and string replace -r '.*/php@' '' -- $d
    end
end

complete -c phpswitch -f
complete -c phpswitch -n __fish_use_subcommand -a use -d 'Use a version in this shell only'
complete -c phpswitch -n __fish_use_subcommand -a global -d 'Switch the global (Homebrew-linked) version'
complete -c phpswitch -n __fish_use_subcommand -a local -d 'Write .php-version here'
complete -c phpswitch -n __fish_use_subcommand -a init -d 'Print shell integration code'
complete -c phpswitch -n __fish_use_subcommand -a doctor -d 'Check your PHP setup'
complete -c phpswitch -n __fish_use_subcommand -a completions -d 'Print shell completions'
complete -c phpswitch -n '__fish_seen_subcommand_from use' -a 'auto (__phpswitch_versions)'
complete -c phpswitch -n '__fish_seen_subcommand_from global local' -a '(__phpswitch_versions)'
complete -c phpswitch -n '__fish_seen_subcommand_from init completions' -a 'zsh bash fish'
EOF
    local flag name
    for flag in $COMPLETION_FLAGS; do
        name="${flag#--}"
        case "$name" in
            *=) printf "complete -c phpswitch -n __fish_use_subcommand -l %s -x -a '(__phpswitch_versions)'\n" "${name%=}" ;;
            *) printf "complete -c phpswitch -n __fish_use_subcommand -l %s\n" "$name" ;;
        esac
    done
}

# Module: doctor.sh
# PHPSwitch Doctor
# Read-only health checks: no network, no sudo, no writes, no service calls.
# Exit status is non-zero when any check fails (warnings don't fail).

# Where root-run PHP-FPM LaunchDaemons live (overridable for tests)
DOCTOR_LAUNCH_DAEMONS_DIR="${PHPSWITCH_LAUNCH_DAEMONS_DIR:-/Library/LaunchDaemons}"

_doctor_failures=0
_doctor_warnings=0

function doctor_ok {
    printf "  [ok]   %s\n" "$1"
}

function doctor_warn {
    _doctor_warnings=$((_doctor_warnings + 1))
    printf "  [warn] %s\n" "$1"
    [ -n "$2" ] && printf "         -> %s\n" "$2"
    return 0
}

function doctor_fail {
    _doctor_failures=$((_doctor_failures + 1))
    printf "  [fail] %s\n" "$1"
    [ -n "$2" ] && printf "         -> %s\n" "$2"
    return 0
}

# Installed PHP opt dirs, without calling brew
function doctor_installed_dirs {
    local d
    for d in "$HOMEBREW_PREFIX"/opt/php "$HOMEBREW_PREFIX"/opt/php@*; do
        [ -x "$d/bin/php" ] && printf '%s\n' "$d"
    done
}

function doctor_php_version_of {
    "$1" -v 2>/dev/null | head -n 1 | cut -d ' ' -f 2
}

function doctor_run {
    _doctor_failures=0
    _doctor_warnings=0

    printf "\n  PHPSwitch doctor\n\n"

    # 1. Homebrew and installed versions
    local installed
    installed=$(doctor_installed_dirs)
    if [ -z "$installed" ]; then
        doctor_fail "No Homebrew PHP installed under $HOMEBREW_PREFIX/opt" "Install one with: phpswitch --install=8.3"
    else
        doctor_ok "Installed: $(printf '%s\n' "$installed" | sed "s|$HOMEBREW_PREFIX/opt/||" | tr '\n' ' ' | sed 's/ $//')"
    fi

    # 2. Global (Homebrew-linked) version
    local linked
    linked=$(core_get_current_php_version)
    if [ -z "$linked" ] || [ "$linked" = "none" ]; then
        doctor_warn "No PHP is linked globally" "Set one with: phpswitch global VERSION"
    else
        doctor_ok "Global (linked) version: $linked"
    fi

    # 3. Which php runs, and what was expected
    local active expected expected_reason
    active=$(command -v php 2>/dev/null)
    if [ -n "${PHPSWITCH_PHP_DIR:-}" ]; then
        expected="$PHPSWITCH_PHP_DIR/bin/php"
        expected_reason="this shell's per-shell version"
    else
        expected="$HOMEBREW_PREFIX/bin/php"
        expected_reason="the global version"
    fi

    if [ -z "$active" ]; then
        doctor_fail "No php found on PATH" "Open a new terminal, or run: phpswitch global VERSION"
    elif [ "$active" -ef "$expected" ]; then
        doctor_ok "php on PATH: $active ($(doctor_php_version_of "$active")), matching $expected_reason"
    else
        doctor_warn "php on PATH is $active ($(doctor_php_version_of "$active")), expected $expected for $expected_reason" \
            "Another PHP is ahead on PATH; check your shell config or remove the other install"
    fi

    # 4. Other PHP binaries on PATH (MAMP, Herd, system, ...)
    local dir others="" old_IFS="$IFS"
    IFS=:
    for dir in $PATH; do
        [ -x "$dir/php" ] || continue
        [ -n "$active" ] && [ "$dir/php" -ef "$active" ] && continue
        others="$others $dir/php"
    done
    IFS="$old_IFS"
    if [ -n "$others" ]; then
        doctor_warn "Other PHP binaries on PATH:$others" "Only the first one on PATH is used"
    fi

    # 5. Per-shell integration
    local login_shell rc_file
    if login_shell=$(auto_login_shell); then
        rc_file=$(auto_rc_file "$login_shell")
        if [ -f "$rc_file" ] && grep -qxF "$AUTO_INIT_MARKER" "$rc_file"; then
            if [ -n "${PHPSWITCH_BIN:-}" ]; then
                doctor_ok "Per-shell switching is installed in $rc_file and loaded in this shell"
            else
                doctor_warn "Per-shell switching is in $rc_file but not loaded in this shell" "Open a new terminal or run: source $rc_file"
            fi
        elif [ -n "${PHPSWITCH_BIN:-}" ]; then
            doctor_ok "Per-shell switching is loaded in this shell"
        else
            doctor_warn "Per-shell switching is not set up" "Run: phpswitch --install-auto-switch"
        fi
    else
        doctor_warn "Login shell ${SHELL:-unknown} isn't supported for per-shell switching"
    fi

    if [ -n "${PHPSWITCH_PINNED:-}" ]; then
        doctor_warn "This shell is pinned with 'phpswitch use'; project files are ignored" "Run: phpswitch use auto"
    fi

    # 6. Legacy global auto-switch hook
    local legacy
    legacy=$(auto_legacy_rc_candidates | tr '\n' ' ')
    if [ -n "$legacy" ]; then
        doctor_warn "Legacy auto-switch hook found in: $legacy" \
            "It relinks PHP globally on every cd. Run: phpswitch --install-auto-switch"
    fi

    # 6b. PHP PATH entries in rc files that phpswitch doesn't manage
    local rc unmanaged
    while IFS= read -r rc; do
        [ -f "$rc" ] || continue
        unmanaged=$(awk '
            /^# BEGIN PHPSWITCH MANAGED BLOCK/ { inside = 1; next }
            /^# END PHPSWITCH MANAGED BLOCK/   { inside = 0; next }
            !inside && /^[ \t]*(export[ \t]+PATH=|PATH=|set[ \t]+(-[a-zA-Z]+[ \t]+)*PATH[ \t]|fish_add_path[ \t])/ && /\/opt\/php/ { printf "%s%d", sep, NR; sep = "," }
        ' "$rc")
        if [ -n "$unmanaged" ]; then
            doctor_warn "PHP PATH entry not managed by phpswitch in $rc (line $unmanaged)" \
                "It pins a PHP version in every new shell; remove it if per-shell or global switching should decide"
        fi
    done < <(auto_rc_candidates)

    # 7. Project version for the current directory
    local project project_dir
    if project=$(version_check_project 2>/dev/null) && [ -n "$project" ]; then
        if project_dir=$(init_php_dir 2>/dev/null); then
            if [ -n "${PHPSWITCH_PHP_DIR:-}" ] && [ "$PHPSWITCH_PHP_DIR" != "$project_dir" ] && [ -z "${PHPSWITCH_PINNED:-}" ]; then
                doctor_warn "Project wants $project but this shell uses $PHPSWITCH_PHP_DIR" "cd out and back in, or run: phpswitch use auto"
            else
                doctor_ok "Project version: $project"
            fi
        else
            doctor_fail "Project wants $project, which isn't installed" "Install it with: phpswitch --install=${project#php@}"
        fi
    fi

    # 8. PHP-FPM running as root (left behind by 'sudo brew services')
    local plist roots=""
    for plist in "$DOCTOR_LAUNCH_DAEMONS_DIR"/homebrew.mxcl.php*.plist; do
        [ -f "$plist" ] && roots="$roots $(basename "$plist" .plist)"
    done
    if [ -n "$roots" ]; then
        doctor_warn "PHP-FPM is registered to run as root:$roots" \
            "Root services change file ownership; use the FPM menu's cleanup, then 'brew services start' without sudo"
    fi

    # 9. Root-owned files in PHP kegs (bounded search)
    local root_owned
    root_owned=$(find "$HOMEBREW_PREFIX/Cellar" -maxdepth 3 -path "*/Cellar/php*" -user root -print 2>/dev/null | head -n 1)
    if [ -n "$root_owned" ]; then
        doctor_warn "Root-owned files in Homebrew PHP (e.g. $root_owned)" \
            "Fix with: sudo chown -R $(id -un) $HOMEBREW_PREFIX/Cellar/php*"
    fi

    printf "\n"
    if [ "$_doctor_failures" -gt 0 ]; then
        printf "  %d problem(s), %d warning(s)\n\n" "$_doctor_failures" "$_doctor_warnings"
        return 1
    fi
    printf "  No problems found (%d warning(s))\n\n" "$_doctor_warnings"
    return 0
}

# Module: self-manage.sh
# PHPSwitch Self-Management
# Installs, uninstalls and updates the phpswitch command itself

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
            utils_run_for_dir "/usr/local" mkdir -p "/usr/local/bin"
        fi
    fi
    
    utils_show_status "info" "Installing phpswitch command to $destination..."
    
    # Copy this script to the destination
    local dest_dir
    dest_dir=$(dirname "$destination")
    if utils_run_for_dir "$dest_dir" cp "$0" "$destination"; then
        utils_run_for_dir "$dest_dir" chmod +x "$destination"
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
            utils_run_for_dir "$(dirname "$location")" rm "$location"
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

# Function to resolve a path through any chain of symlinks
function cmd_resolve_script_path {
    utils_resolve_symlinks "$1"
}

# Function to update self from the latest GitHub release.
# Fails closed: the download must match the release's published SHA-256.
function cmd_update_self {
    local repo="NavanithanS/phpswitch"

    # Find the current script's location
    local script_path
    script_path=$(command -v phpswitch 2>/dev/null || echo "$0")

    # Homebrew-managed installs must be upgraded through Homebrew
    local resolved_path
    resolved_path=$(cmd_resolve_script_path "$script_path")
    if [ -n "$HOMEBREW_PREFIX" ] && [[ "$resolved_path" == "$HOMEBREW_PREFIX/Cellar/"* ]]; then
        utils_show_status "info" "PHPSwitch is managed by Homebrew"
        printf "  Update it with:\n\n    brew upgrade phpswitch\n\n"
        return 0
    fi

    if ! command -v shasum >/dev/null 2>&1; then
        utils_show_status "error" "shasum is required to verify updates"
        return 1
    fi

    utils_show_status "info" "Checking for updates..."

    local tmp_dir
    tmp_dir=$(mktemp -d 2>/dev/null) || { utils_show_status "error" "Failed to create temp directory for update"; return 1; }

    # Look up the latest release
    if ! curl -fsSL "https://api.github.com/repos/$repo/releases/latest" -o "$tmp_dir/release.json"; then
        utils_show_status "error" "Failed to connect to GitHub. Check your internet connection."
        rm -rf "$tmp_dir"
        return 1
    fi

    local tag
    tag=$(grep -o '"tag_name": *"[^"]*"' "$tmp_dir/release.json" | head -n 1 | sed -E 's/.*"([^"]*)"$/\1/')
    if ! [[ "$tag" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        utils_show_status "error" "Could not determine the latest release version; update aborted"
        rm -rf "$tmp_dir"
        return 1
    fi

    local new_version="${tag#v}"
    local current_version="$PHPSWITCH_VERSION"

    if utils_compare_versions "$current_version" "$new_version"; then
        utils_show_status "success" "You are already using the latest version: $current_version"
        rm -rf "$tmp_dir"
        return 0
    fi

    utils_show_status "info" "New version available: $new_version (current: $current_version)"

    # Download the release asset and its checksum
    local base_url="https://github.com/$repo/releases/download/$tag"
    if ! curl -fsSL "$base_url/php-switcher.sh" -o "$tmp_dir/php-switcher.sh" || [ ! -s "$tmp_dir/php-switcher.sh" ]; then
        utils_show_status "error" "Failed to download php-switcher.sh from release $tag"
        rm -rf "$tmp_dir"
        return 1
    fi
    if ! curl -fsSL "$base_url/php-switcher.sh.sha256" -o "$tmp_dir/php-switcher.sh.sha256"; then
        utils_show_status "error" "Release $tag does not publish a checksum; refusing to update"
        printf "  Download it manually from https://github.com/%s/releases\n" "$repo"
        rm -rf "$tmp_dir"
        return 1
    fi

    # SEC-01: Verify the download against the published checksum
    local expected_sha256 actual_sha256
    expected_sha256=$(awk '{print $1; exit}' "$tmp_dir/php-switcher.sh.sha256")
    actual_sha256=$(shasum -a 256 "$tmp_dir/php-switcher.sh" | awk '{print $1}')
    if ! [[ "$expected_sha256" =~ ^[0-9a-f]{64}$ ]] || [ "$actual_sha256" != "$expected_sha256" ]; then
        utils_show_status "error" "Checksum verification failed! File may be compromised."
        printf "  Expected: %s\n" "$expected_sha256"
        printf "  Actual:   %s\n" "$actual_sha256"
        rm -rf "$tmp_dir"
        return 1
    fi

    # The verified file must be the version the release claims to be
    local downloaded_version
    downloaded_version=$(grep "^PHPSWITCH_VERSION=" "$tmp_dir/php-switcher.sh" | cut -d'"' -f2)
    if [ "$downloaded_version" != "$new_version" ]; then
        utils_show_status "error" "Downloaded script reports version '$downloaded_version', expected $new_version; update aborted"
        rm -rf "$tmp_dir"
        return 1
    fi

    printf "  Update to %s? (y/n) " "$new_version"
    if [ "$(utils_validate_yes_no "" "y")" = "y" ]; then
        # Create backup
        local backup_path
        backup_path="${script_path}.bak.$(date +%Y%m%d%H%M%S)"
        utils_show_status "info" "Creating backup at $backup_path..."
        cp "$script_path" "$backup_path" || { utils_show_status "error" "Failed to create backup"; rm -rf "$tmp_dir"; return 1; }

        # Install the new version
        chmod +x "$tmp_dir/php-switcher.sh"
        if [ -f "/usr/local/bin/phpswitch" ] || [ -f "$HOMEBREW_PREFIX/bin/phpswitch" ]; then
            # Update the system command
            utils_show_status "info" "Updating system command..."

            # Copy to all known installation locations
            if [ -f "/usr/local/bin/phpswitch" ]; then
                utils_run_for_dir "/usr/local/bin" cp "$tmp_dir/php-switcher.sh" "/usr/local/bin/phpswitch" || { utils_show_status "error" "Failed to update. Try with sudo"; rm -rf "$tmp_dir"; return 1; }
            fi

            if [ -f "$HOMEBREW_PREFIX/bin/phpswitch" ]; then
                utils_run_for_dir "$HOMEBREW_PREFIX/bin" cp "$tmp_dir/php-switcher.sh" "$HOMEBREW_PREFIX/bin/phpswitch" || { utils_show_status "error" "Failed to update. Try with sudo"; rm -rf "$tmp_dir"; return 1; }
            fi
        else
            # Just update the current script
            utils_run_for_dir "$(dirname "$script_path")" cp "$tmp_dir/php-switcher.sh" "$script_path" || { utils_show_status "error" "Failed to update. Try with sudo"; rm -rf "$tmp_dir"; return 1; }
        fi

        utils_show_status "success" "Updated to version $new_version"
        printf "  Please restart phpswitch to use the new version.\n"

        # Clean up
        rm -rf "$tmp_dir"
        exit 0
    else
        utils_show_status "info" "Update cancelled"
    fi

    # Clean up
    rm -rf "$tmp_dir"
}

# Module: menu.sh
# PHPSwitch Interactive Menu
# Main menu, uninstall menu and configuration screens

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
            doctor_run
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

    # Judge by what the rc files contain, not the config flag (an
    # integration line added before ~/.phpswitch.conf existed leaves it false)
    if auto_is_installed; then
        utils_show_status "info" "Auto-switching is currently enabled"

        printf "  Disable auto-switching? This removes it from your shell config (y/n) "
        if [ "$(utils_validate_yes_no "" "n")" = "y" ]; then
            auto_uninstall
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
            if [ "$(utils_validate_yes_no "" "$([ "$AUTO_RESTART_PHP_FPM" = "true" ] && echo y || echo n)")" = "y" ]; then
                AUTO_RESTART_PHP_FPM=true
            else
                AUTO_RESTART_PHP_FPM=false
            fi
            ;;
        2)
            printf "  Create backups of config files before modifying? (y/n) "
            if [ "$(utils_validate_yes_no "" "$([ "$BACKUP_CONFIG_FILES" = "true" ] && echo y || echo n)")" = "y" ]; then
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
            # The default must be y/n: the prompt echoes it back unchanged
            local auto_default="n"
            if auto_is_installed; then
                auto_default="y"
            fi
            printf "  Enable automatic PHP switching based on directory? (y/n) "
            if [ "$(utils_validate_yes_no "" "$auto_default")" = "y" ]; then
                AUTO_SWITCH_PHP_VERSION=true
                
                # Ask to set up per-shell switching if not already done
                local hook_exists=false
                local login_shell hook_file
                if login_shell=$(auto_login_shell); then
                    hook_file=$(auto_rc_file "$login_shell")
                    if [ -f "$hook_file" ] && grep -qF "$AUTO_INIT_MARKER" "$hook_file"; then
                        hook_exists=true
                    fi
                fi

                if [ "$hook_exists" = "false" ]; then
                    printf "  Install shell hooks for auto-switching? (y/n) "
                    if [ "$(utils_validate_yes_no "" "y")" = "y" ]; then
                        auto_install
                    else
                        utils_show_status "warning" "Auto-switching is enabled but shell hooks are not installed"
                        printf "  Run 'phpswitch --install-auto-switch' to install the hooks later.\n"
                    fi
                fi
            elif auto_is_installed; then
                # Turning it off removes the hook; keep the setting on if that fails
                if auto_uninstall; then
                    AUTO_SWITCH_PHP_VERSION=false
                else
                    AUTO_SWITCH_PHP_VERSION=true
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
    if ! cat > "$_tmp_conf" <<EOL
# PHPSwitch Configuration
AUTO_RESTART_PHP_FPM=$AUTO_RESTART_PHP_FPM
BACKUP_CONFIG_FILES=$BACKUP_CONFIG_FILES
DEFAULT_PHP_VERSION="$DEFAULT_PHP_VERSION"
MAX_BACKUPS=$MAX_BACKUPS
AUTO_SWITCH_PHP_VERSION=$AUTO_SWITCH_PHP_VERSION
CACHE_DIRECTORY="$CACHE_DIRECTORY"
EOL
    then
        rm -f "$_tmp_conf"
        utils_show_status "error" "Failed to write configuration"
        return 1
    fi
    if [ ! -s "$_tmp_conf" ]; then
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

# Module: commands.sh
# PHPSwitch Command Line Parsing
# Handles command line arguments and menu display

# Main command line argument parser
function cmd_parse_arguments {
    # Debug mode detection
    if [ "$1" = "--debug" ]; then
        # shellcheck disable=SC2034
        DEBUG_MODE=true
        shift
    fi
    
    # ARCH-04: --yes flag for non-interactive confirmation
    if [ "$1" = "--yes" ] || [ "$1" = "-y" ]; then
        # shellcheck disable=SC2034
        PHPSWITCH_YES=true
        shift
    fi
    
    # FEAT-07: --quiet flag to suppress non-essential output
    if [ "$1" = "--quiet" ] || [ "$1" = "-q" ]; then
        PHPSWITCH_QUIET=true
        shift
    fi
    
    # Print header for all interactive/visible commands
    local _silent_flag=false
    case "$1" in
        --auto-mode|--get-project-version|--version|-v|--help|-h|--quiet|-q|--json|init|completions|__php-dir|use|shell) _silent_flag=true ;;
    esac
    if [ "$_silent_flag" = "false" ] && [ "$PHPSWITCH_QUIET" != "true" ]; then
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
       [ "$1" != "--check-dependencies" ] && [ "$1" != "--fix-permissions" ] &&
       [ "$1" != "init" ] && [ "$1" != "completions" ] && [ "$1" != "__php-dir" ] &&
       [ "$1" != "use" ] && [ "$1" != "shell" ]; then
        # Check dependencies
        utils_check_dependencies "$_silent_flag" || {
            utils_show_status "error" "Dependency check failed. Please resolve issues before proceeding."
            exit 1
        }
    fi
    
    # Per-shell integration and v2 subcommands
    case "$1" in
        init)
            init_print "$2"
            exit $?
            ;;
        __php-dir)
            init_php_dir "$2"
            exit $?
            ;;
        completions)
            completions_print "$2"
            exit $?
            ;;
        use|shell)
            # Reaching the binary means the shell wrapper is not loaded
            echo "phpswitch: '$1' changes PATH in the current shell and needs shell integration." >&2
            echo "  Add this to your shell config, then open a new terminal:" >&2
            echo "    eval \"\$(phpswitch init $(basename "${SHELL:-zsh}"))\"" >&2
            echo "  Or switch globally instead: phpswitch global ${2:-VERSION}" >&2
            exit 1
            ;;
        global)
            if [ -z "$2" ] || ! utils_validate_version "$2"; then
                utils_show_status "error" "Usage: phpswitch global <version>  (e.g. 8.2)"
                exit 1
            fi
            cmd_non_interactive_switch "$2" "false"
            exit $?
            ;;
        doctor)
            doctor_run
            exit $?
            ;;
        local)
            # .php-version must hold X.Y (or php@X.Y) for detection to read it back
            if ! [[ "${2:-}" =~ ^(php@)?[0-9]+\.[0-9]+$ ]]; then
                utils_show_status "error" "Usage: phpswitch local <version>  (e.g. 8.2)"
                exit 1
            fi
            version_set_project "$2"
            exit $?
            ;;
    esac

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
        exit $?
    elif [ "$1" = "--version" ] || [ "$1" = "-v" ]; then
        printf "PHPSwitch version %s\n" "$PHPSWITCH_VERSION"
        exit 0
    elif [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
        printf "\n  PHPSwitch  PHP Version Manager for macOS\n\n"
        printf "  Usage\n\n"
        printf "    phpswitch                            interactive menu\n"
        printf "    phpswitch use VERSION|auto           use a version in this shell only (needs shell integration)\n"
        printf "    phpswitch global VERSION             switch the global (Homebrew-linked) version\n"
        printf "    phpswitch local VERSION              write .php-version in the current directory\n"
        printf "    phpswitch doctor                     check your PHP setup (read-only)\n"
        printf "    phpswitch completions zsh|bash|fish  print shell completions\n"
        printf "    phpswitch init zsh|bash|fish         print shell integration; add to your rc file:\n"
        printf "                                           eval \"\$(phpswitch init zsh)\"\n"
        printf "    phpswitch --switch=VERSION           switch to version (same as global)\n"
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
        printf "    phpswitch --install-auto-switch      add per-shell switching to your rc file\n"
        printf "    phpswitch --clear-directory-cache    clear legacy auto-switching cache\n"
        printf "    phpswitch --check-dependencies       check system dependencies\n"
        printf "    phpswitch --install                  install as a system command\n"
        printf "    phpswitch --uninstall                remove from system\n"
        printf "    phpswitch --update                   update to the latest version\n"
        printf "    phpswitch --version, -v              show version\n"
        printf "    phpswitch --debug                    enable debug logging\n"
        printf "    phpswitch --yes, -y                  auto-confirm prompts (non-interactive)\n"
        printf "    phpswitch --quiet, -q                suppress the banner / non-essential output\n"
        printf "    phpswitch --help, -h                 show this help\n\n"
        exit 0
    else
        # Unknown arguments used to fall through to the menu
        if [ -n "${1:-}" ]; then
            utils_show_status "error" "Unknown command or option: $1"
            printf "  Run 'phpswitch --help' for usage.\n"
            exit 2
        fi
        # The menu needs a terminal; without one it would wait forever
        if [ ! -t 0 ]; then
            utils_show_status "error" "The interactive menu needs a terminal"
            printf "  Use a command instead, e.g. 'phpswitch global 8.3'. Run 'phpswitch --help' for usage.\n"
            exit 1
        fi

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
    
    if [ "$format" != "json" ]; then
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
    fi
    
    if [ "$format" = "json" ]; then
        # Provide JSON format for scripting
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

# Function to execute the fix-permissions logic (CQ-03)
function cmd_fix_permissions {
    utils_show_status "info" "Running permission fix tool..."
    
    local cache_dir
    cache_dir=$(core_get_cache_dir)
    
    # Delegate to the centralized utils function
    if utils_ensure_cache_writable "$cache_dir"; then
        return 0
    else
        printf "  Manually create a config file at %s and set CACHE_DIRECTORY to a writable location.\n" "$HOME/.phpswitch.conf"
        return 1
    fi
}

# Add cache management functions
function cmd_clear_phpswitch_cache {
    local cache_dir
    cache_dir=$(core_get_cache_dir)
    
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

# Main script logic
# REL-04: Serialize concurrent auto-switch invocations only.
# Auto-switch hooks can fire rapidly on quick directory changes; the lock
# prevents overlapping --auto-mode switches. Interactive and read-only
# commands are intentionally NOT locked, so they never block each other.
# The trap is set before core_load_config so the temp-cleanup trap it
# installs chains this rm rather than clobbering it.
if [ "$1" = "--auto-mode" ]; then
    LOCKFILE="/tmp/phpswitch_$(id -u).lock"
    # Atomic create; fails if the lockfile already exists
    if ! ( set -o noclobber; echo "$$" > "$LOCKFILE" ) 2>/dev/null; then
        _pid=$(cat "$LOCKFILE" 2>/dev/null)
        if kill -0 "$_pid" 2>/dev/null; then
            # Another auto-switch is in progress; stay silent and yield.
            exit 0
        fi
        # Stale lock from a dead process: take it over.
        echo "$$" > "$LOCKFILE"
    fi
    trap 'rm -f "$LOCKFILE"' EXIT INT TERM
fi

# Load configuration
core_load_config

# Parse command line arguments
cmd_parse_arguments "$@"
