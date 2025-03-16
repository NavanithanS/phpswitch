#!/bin/bash
# PHPSwitch Shell Management
# Handles shell detection and configuration file updates

# Function to detect shell type with fish support
function shell_detect_shell {
    if [ -n "$ZSH_VERSION" ]; then
        echo "zsh"
    elif [ -n "$BASH_VERSION" ]; then
        echo "bash"
    elif [ -n "$FISH_VERSION" ] || [[ "$SHELL" == *"fish" ]]; then
        echo "fish"
    else
        echo "unknown"
    fi
}

# Update the shell RC file function to support fish
function shell_update_rc {
    local new_version="$1"
    local shell_type=$(shell_detect_shell)
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
        "fish")
            rc_file="$HOME/.config/fish/config.fish"
            # Ensure the directory exists
            mkdir -p "$(dirname "$rc_file")"
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
            utils_show_status "info" "$file does not exist. Creating it..."
            touch "$file"
        fi
        
        # Check if we have write permissions
        if [ ! -w "$file" ]; then
            utils_show_status "error" "No write permission for $file"
            exit 1
        fi
        
        # Create backup (only if enabled)
        if [ "$BACKUP_CONFIG_FILES" = "true" ]; then
            local backup_file="${file}.bak.$(date +%Y%m%d%H%M%S)"
            cp "$file" "$backup_file"
            utils_show_status "info" "Created backup at ${backup_file}"
            
            # Clean up old backups
            shell_cleanup_backups "$file"
        fi
        
        utils_show_status "info" "Updating PATH in $file for $shell_type shell..."
        
        if [ "$shell_type" = "fish" ]; then
            # Fish shell uses a different syntax for PATH manipulation
            
            # Remove old PHP paths from fish_user_paths
            sed -i.tmp '/set -g fish_user_paths.*opt\/homebrew\/opt\/php/d' "$file"
            sed -i.tmp '/set -g fish_user_paths.*usr\/local\/opt\/php/d' "$file"
            rm -f "$file.tmp"
            
            # Add the new PHP paths to the beginning of the file
            temp_file=$(mktemp)
            
            cat > "$temp_file" << EOL
# PHP version paths - Added by phpswitch
fish_add_path $php_bin_path
fish_add_path $php_sbin_path

EOL
            
            # Concatenate the original file to the temp file
            cat "$file" >> "$temp_file"
            
            # Move the temp file back to the original
            mv "$temp_file" "$file"
            
        else
            # Bash/Zsh path handling (existing code)
            
            # Remove old PHP paths from PATH variable
            sed -i.tmp 's|^export PATH=".*opt/homebrew/opt/php@[0-9]\.[0-9]/bin:\$PATH"|#&|' "$file"
            sed -i.tmp 's|^export PATH=".*opt/homebrew/opt/php@[0-9]\.[0-9]/sbin:\$PATH"|#&|' "$file"
            sed -i.tmp 's|^export PATH=".*opt/homebrew/opt/php/bin:\$PATH"|#&|' "$file"
            sed -i.tmp 's|^export PATH=".*opt/homebrew/opt/php/sbin:\$PATH"|#&|' "$file"
            sed -i.tmp 's|^export PATH=".*usr/local/opt/php@[0-9]\.[0-9]/bin:\$PATH"|#&|' "$file"
            sed -i.tmp 's|^export PATH=".*usr/local/opt/php@[0-9]\.[0-9]/sbin:\$PATH"|#&|' "$file"
            sed -i.tmp 's|^export PATH=".*usr/local/opt/php/bin:\$PATH"|#&|' "$file"
            sed -i.tmp 's|^export PATH=".*usr/local/opt/php/sbin:\$PATH"|#&|' "$file"
            rm -f "$file.tmp"
            
            # Remove our added "force path reload" section if it exists
            sed -i.tmp '/# Added by phpswitch script - force path reload/,+5d' "$file"
            rm -f "$file.tmp"
            
            # Clean up any empty lines at the end
            perl -i -pe 'END{if(/^\n+$/){$_=""}}' "$file" 2>/dev/null || true
            
            # Add the new PHP PATH entries at the top of the file
            temp_file=$(mktemp)
            
            cat > "$temp_file" << EOL
# PHP version paths - Added by phpswitch
export PATH="$php_bin_path:$php_sbin_path:\$PATH"

EOL
            
            # Concatenate the original file to the temp file
            cat "$file" >> "$temp_file"
            
            # Move the temp file back to the original
            mv "$temp_file" "$file"
        fi
        
        utils_show_status "success" "Updated PATH in $file for $new_version"
    }
    
    # Update only the appropriate RC file for the current shell
    update_single_rc_file "$rc_file"
    
    # Check for any other potential conflicting PATH settings
    for file in "$HOME/.path" "$HOME/.config/fish/config.fish"; do
        if [ -f "$file" ] && [ "$file" != "$rc_file" ]; then
            if grep -q "PATH.*php" "$file"; then
                utils_show_status "warning" "Found PHP PATH settings in $file that might conflict"
                echo -n "Would you like to update this file too? (y/n): "
                
                if [ "$(utils_validate_yes_no "Update this file?" "y")" = "y" ]; then
                    update_single_rc_file "$file"
                else
                    utils_show_status "warning" "Skipping $file - this might cause version conflicts"
                fi
            fi
        fi
    done
    
    # Also update force_reload_php function to handle fish shell
    if [ "$shell_type" = "fish" ]; then
        utils_show_status "info" "For immediate effect in fish shell, run:"
        echo "set -gx PATH $php_bin_path $php_sbin_path \$PATH; and rehash"
    fi
}

# Enhanced force_reload_php function with fish support
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
    
    core_debug_log "Before PATH update: $PATH"
    
    if [ "$shell_type" = "fish" ]; then
        # For fish shell, we need different commands
        # But we can't directly manipulate fish's PATH from bash/zsh
        # So we'll just inform the user how to do it
        echo "To update PATH in current fish shell session, run:"
        echo "set -gx PATH $php_bin_path $php_sbin_path \$PATH; and rehash"
        return 0
    else
        # First, remove any existing PHP paths from the PATH
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
            core_debug_log "After PATH update: $PATH"
            
            # Force the shell to forget previous command locations
            hash -r 2>/dev/null || rehash 2>/dev/null || true
            
            # Verify the PHP binary now in use
            core_debug_log "PHP now resolves to: $(which php)"
            core_debug_log "PHP version now: $(php -v | head -n 1)"
            
            return 0
        else
            utils_show_status "error" "PHP binary directories not found at $php_bin_path or $php_sbin_path"
            return 1
        fi
    fi
}

# Function to cleanup old backup files
function shell_cleanup_backups {
    local file_prefix="$1"
    local max_backups="${MAX_BACKUPS:-5}"
    
    # List backup files sorted by modification time (oldest first)
    for old_backup in $(ls -t "${file_prefix}.bak."* 2>/dev/null | tail -n +$((max_backups+1))); do
        core_debug_log "Removing old backup: $old_backup"
        rm -f "$old_backup"
    done
}