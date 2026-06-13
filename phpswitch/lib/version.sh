#!/bin/bash
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
    
    # Walk parent directories up to $HOME (FEAT-03: don't go beyond home)
    while [ "$current_dir" != "/" ] && [ "$current_dir" != "." ] && [[ "$current_dir" == "$HOME"* ]]; do
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
    local current_version
    current_version=$(core_get_current_php_version)
    
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
            
            if [ ! -d "$php_bin_path" ] && [ "$new_version" = "php@default" ]; then
                php_bin_path="$HOMEBREW_PREFIX/opt/php/bin"
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
    shell_update_rc "$new_version" > /dev/null

    # Create a reload script for immediate use
    local reload_script
    reload_script=$(shell_create_reload_script "$new_version")
    
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
