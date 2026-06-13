#!/bin/bash
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
    
    # Determine Homebrew prefix (SEC-03: deferred from global scope)
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
