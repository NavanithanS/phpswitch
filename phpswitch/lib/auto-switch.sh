#!/bin/bash
# PHPSwitch Auto-switching
# Handles automatic PHP version switching based on directory

# Function to install auto-switching hooks
function auto_install {
    local shell_type
    shell_type=$(shell_detect_shell)
    
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
        local backup_file
        backup_file="${rc_file}.bak.$(date +%Y%m%d%H%M%S)"
        
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
    # CQ-01: Simplified hook — delegates all logic to phpswitch --auto-mode
    cat >> "$rc_file" << 'EOL'

# PHPSwitch auto-switching
function phpswitch_auto_detect_project() {
    local cache_file="$HOME/.cache/phpswitch/directory_cache.txt"
    local current_dir="$(pwd)"
    local _max_cache_lines=500
    
    mkdir -p "$(dirname "$cache_file")" 2>/dev/null
    
    # Check if in cache
    if [ -f "$cache_file" ] && [ -r "$cache_file" ]; then
        while IFS=: read -r dir version; do
            if [ "$dir" = "$current_dir" ]; then
                # SEC-06: Re-validate version from cache
                if [ -n "$version" ] && [[ "$version" =~ ^[a-zA-Z0-9.@_-]+$ ]]; then
                    phpswitch --auto-mode > /dev/null 2>&1
                fi
                return
            fi
        done < "$cache_file"
    fi
    
    # Not in cache — detect and cache
    local _detected=""
    for file in ".php-version" ".phpversion"; do
        if [ -f "$current_dir/$file" ]; then
            _detected=$(tr -d '[:space:]' < "$current_dir/$file" 2>/dev/null)
            break
        fi
    done
    if [ -z "$_detected" ] && { [ -f "$current_dir/composer.json" ] || [ -f "$current_dir/.tool-versions" ]; }; then
        _detected=$(phpswitch --get-project-version 2>/dev/null)
    fi
    
    # Append to cache (with pruning)
    if [ -n "$_detected" ] && [[ "$_detected" =~ ^[a-zA-Z0-9.@_-]+$ ]]; then
        printf '%s:%s\n' "$current_dir" "$_detected" >> "$cache_file" 2>/dev/null
        phpswitch --auto-mode > /dev/null 2>&1
    else
        printf '%s:\n' "$current_dir" >> "$cache_file" 2>/dev/null
    fi
    
    # PERF-03: Prune cache if too large
    if [ -f "$cache_file" ] && [ "$(wc -l < "$cache_file" 2>/dev/null)" -gt "$_max_cache_lines" ]; then
        tail -n "$_max_cache_lines" "$cache_file" > "$cache_file.tmp" 2>/dev/null && mv "$cache_file.tmp" "$cache_file" 2>/dev/null
    fi
}

# Hook into directory changes
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
        local backup_file
        backup_file="${rc_file}.bak.$(date +%Y%m%d%H%M%S)"
        
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
    # CQ-01: Simplified hook — delegates all logic to phpswitch --auto-mode
    cat >> "$rc_file" << 'EOL'

# PHPSwitch auto-switching
function phpswitch_auto_detect_project() {
    local cache_file="$HOME/.cache/phpswitch/directory_cache.txt"
    local current_dir="$(pwd)"
    local _max_cache_lines=500
    
    mkdir -p "$(dirname "$cache_file")" 2>/dev/null
    
    # Check if in cache
    if [ -f "$cache_file" ] && [ -r "$cache_file" ]; then
        while IFS=: read -r dir version; do
            if [ "$dir" = "$current_dir" ]; then
                if [ -n "$version" ] && [[ "$version" =~ ^[a-zA-Z0-9.@_-]+$ ]]; then
                    phpswitch --auto-mode > /dev/null 2>&1
                fi
                return
            fi
        done < "$cache_file"
    fi
    
    # Not in cache — detect and cache
    local _detected=""
    for file in ".php-version" ".phpversion"; do
        if [ -f "$current_dir/$file" ]; then
            _detected=$(tr -d '[:space:]' < "$current_dir/$file" 2>/dev/null)
            break
        fi
    done
    if [ -z "$_detected" ] && { [ -f "$current_dir/composer.json" ] || [ -f "$current_dir/.tool-versions" ]; }; then
        _detected=$(phpswitch --get-project-version 2>/dev/null)
    fi
    
    if [ -n "$_detected" ] && [[ "$_detected" =~ ^[a-zA-Z0-9.@_-]+$ ]]; then
        printf '%s:%s\n' "$current_dir" "$_detected" >> "$cache_file" 2>/dev/null
        phpswitch --auto-mode > /dev/null 2>&1
    else
        printf '%s:\n' "$current_dir" >> "$cache_file" 2>/dev/null
    fi
    
    # PERF-03: Prune cache if too large
    if [ -f "$cache_file" ] && [ "$(wc -l < "$cache_file" 2>/dev/null)" -gt "$_max_cache_lines" ]; then
        tail -n "$_max_cache_lines" "$cache_file" > "$cache_file.tmp" 2>/dev/null && mv "$cache_file.tmp" "$cache_file" 2>/dev/null
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
        local backup_file
        backup_file="${rc_file}.bak.$(date +%Y%m%d%H%M%S)"
        
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
    # CQ-01: Simplified hook — delegates all logic to phpswitch --auto-mode
    cat >> "$rc_file" << 'EOL'

# PHPSwitch auto-switching
function phpswitch_auto_detect_project --on-variable PWD
    set cache_file "$HOME/.cache/phpswitch/directory_cache.txt"
    set current_dir (pwd)
    set _max_cache_lines 500
    
    mkdir -p (dirname "$cache_file") 2>/dev/null
    
    # Check cache
    if test -f "$cache_file"; and test -r "$cache_file"
        while read -l line
            set dir_info (string split ":" -- $line)
            set dir $dir_info[1]
            set version $dir_info[2]
            if test "$dir" = "$current_dir"
                if test -n "$version"; and string match -rq '^[a-zA-Z0-9.@_-]+$' -- "$version"
                    phpswitch --auto-mode > /dev/null 2>&1
                end
                return
            end
        end < "$cache_file"
    end
    
    # Not in cache — detect and cache
    set _detected ""
    for file in ".php-version" ".phpversion"
        if test -f "$current_dir/$file"
            set _detected (cat "$current_dir/$file" | string trim)
            break
        end
    end
    if test -z "$_detected"; and begin; test -f "$current_dir/composer.json"; or test -f "$current_dir/.tool-versions"; end
        set _detected (phpswitch --get-project-version 2>/dev/null)
    end
    
    if test -n "$_detected"; and string match -rq '^[a-zA-Z0-9.@_-]+$' -- "$_detected"
        echo "$current_dir:$_detected" >> "$cache_file" 2>/dev/null
        phpswitch --auto-mode > /dev/null 2>&1
    else
        echo "$current_dir:" >> "$cache_file" 2>/dev/null
    end
    
    # Prune cache if too large
    if test -f "$cache_file"; and test (wc -l < "$cache_file" 2>/dev/null | string trim) -gt "$_max_cache_lines"
        tail -n "$_max_cache_lines" "$cache_file" > "$cache_file.tmp" 2>/dev/null; and mv "$cache_file.tmp" "$cache_file" 2>/dev/null
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

    # Unlink current PHP (skip if no version is active)
    local _current_ver
    _current_ver=$(core_get_current_php_version)
    if [ -n "$_current_ver" ] && [ "$_current_ver" != "none" ]; then
        brew unlink "$_current_ver" &>/dev/null
    fi

    if ! brew link --force "$brew_version" &>/dev/null; then
        return 1
    fi

    # Silently restart PHP-FPM if enabled
    if [ "$AUTO_RESTART_PHP_FPM" = "true" ]; then
        local service_name
        service_name=$(fpm_get_service_name "$new_version")
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