#!/bin/bash
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
            echo "Auto-switching is only supported for bash, zsh, and fish shells."
            return 1
            ;;
    esac
    
    # Update config file
    sed -i.bak "s/AUTO_SWITCH_PHP_VERSION=.*/AUTO_SWITCH_PHP_VERSION=true/" "$HOME/.phpswitch.conf" 2>/dev/null
    rm -f "$HOME/.phpswitch.conf.bak" 2>/dev/null
    
    # Create cache directory with proper permissions
    local cache_dir="$HOME/.cache/phpswitch"
    if [ ! -d "$cache_dir" ]; then
        mkdir -p "$cache_dir" 2>/dev/null
    fi
    
    # Ensure cache directory is writable
    if [ ! -w "$cache_dir" ] && [ -d "$cache_dir" ]; then
        utils_show_status "warning" "Cache directory $cache_dir is not writable"
        echo -n "Would you like to fix permissions (this may require sudo)? (y/n): "
        if [ "$(utils_validate_yes_no "Fix permissions?" "y")" = "y" ]; then
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
    echo "Auto-switching will take effect the next time you open a new terminal window or source your shell configuration file."
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
        local temp_cache_file=$(mktemp)
        
        # Copy existing cache if available
        if [ -f "$cache_file" ] && [ -r "$cache_file" ]; then
            cat "$cache_file" > "$temp_cache_file" 2>/dev/null
        fi
        
        # Check for PHP version file
        for file in ".php-version" ".phpversion" ".php"; do
            if [ -f "$current_dir/$file" ]; then
                # Store this in cache
                echo "$current_dir:$(cat "$current_dir/$file" | tr -d '[:space:]')" >> "$temp_cache_file"
                # Run phpswitch in auto mode
                phpswitch --auto-mode > /dev/null 2>&1
                
                # Try to update the main cache file if writable
                if [ -w "$(dirname "$cache_file")" ]; then
                    mv "$temp_cache_file" "$cache_file" 2>/dev/null
                fi
                return
            fi
        done
        
        # No PHP version file found, add to cache with empty version
        echo "$current_dir:" >> "$temp_cache_file"
        
        # Try to update the main cache file if writable
        if [ -w "$(dirname "$cache_file")" ]; then
            mv "$temp_cache_file" "$cache_file" 2>/dev/null
        else
            rm -f "$temp_cache_file" 2>/dev/null
        fi
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
        local temp_cache_file=$(mktemp)
        
        # Copy existing cache if available
        if [ -f "$cache_file" ] && [ -r "$cache_file" ]; then
            cat "$cache_file" > "$temp_cache_file" 2>/dev/null
        fi
        
        # Check for PHP version file
        for file in ".php-version" ".phpversion" ".php"; do
            if [ -f "$current_dir/$file" ]; then
                # Store this in cache
                echo "$current_dir:$(cat "$current_dir/$file" | tr -d '[:space:]')" >> "$temp_cache_file"
                # Run phpswitch in auto mode
                phpswitch --auto-mode > /dev/null 2>&1
                
                # Try to update the main cache file if writable
                if [ -w "$(dirname "$cache_file")" ]; then
                    mv "$temp_cache_file" "$cache_file" 2>/dev/null
                fi
                return
            fi
        done
        
        # No PHP version file found, add to cache with empty version
        echo "$current_dir:" >> "$temp_cache_file"
        
        # Try to update the main cache file if writable
        if [ -w "$(dirname "$cache_file")" ]; then
            mv "$temp_cache_file" "$cache_file" 2>/dev/null
        else
            rm -f "$temp_cache_file" 2>/dev/null
        fi
    fi
}

# Enable the cd hook for bash
if [[ $PROMPT_COMMAND != *"phpswitch_auto_detect_project"* ]]; then
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
        set temp_cache_file (mktemp)
        
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
            echo -n "Would you like to try with sudo? (y/n): "
            if [ "$(utils_validate_yes_no "Try with sudo?" "y")" = "y" ]; then
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
    brew unlink $(core_get_current_php_version) &>/dev/null
    
    # Link new PHP
    brew link --force "$brew_version" &>/dev/null
    
    # If linking succeeded, return success
    if [ $? -eq 0 ]; then
        return 0
    else
        return 1
    fi
}