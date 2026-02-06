#!/bin/bash
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

# Remove old PHP paths (if any)
set --erase PATH
fish_add_path $php_bin_path
fish_add_path $php_sbin_path
fish_add_path /usr/local/bin
fish_add_path /usr/bin
fish_add_path /bin
fish_add_path /usr/sbin
fish_add_path /sbin

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
            $0 ~ begin {found=1; between=1}
            $0 ~ end {between=0}
            END {if (found) print ""}
        ' "$rc_file" > "$temp_file"
        
        # Append the new block
        append_path_code "$temp_file"
        
        # Add the rest of the file
        awk -v begin="$begin_marker" -v end="$end_marker" '
            between {next}
            $0 ~ begin {between=1; next}
            $0 ~ end {between=0; next}
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
    local instructions_file="/tmp/phpswitch_instructions_$(date +%s).sh"
    
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
    
    # List backup files sorted by modification time (oldest first)
    for old_backup in $(ls -t "${file_prefix}.bak."* 2>/dev/null | tail -n +$((max_backups+1))); do
        core_debug_log "Removing old backup: $old_backup"
        rm -f "$old_backup"
    done
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
    local reload_script="/tmp/phpswitch_reload_$(date +%s).sh"
    
    if [ "$shell_type" = "fish" ]; then
        cat > "$reload_script" << EOL
#!/usr/bin/env fish
# PHPSwitch temporary reload script for fish shell
# Generated: $(date)

echo "Reloading PATH with PHP $version..."

# Clear the PATH to remove any existing PHP paths
set --erase PATH

# Add new PHP paths first to ensure they take precedence
fish_add_path $php_bin_path
fish_add_path $php_sbin_path

# Add system paths back
fish_add_path /usr/local/bin
fish_add_path /usr/bin
fish_add_path /bin
fish_add_path /usr/sbin
fish_add_path /sbin

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