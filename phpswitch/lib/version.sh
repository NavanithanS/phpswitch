#!/bin/bash
# PHPSwitch Version Management
# Handles PHP version switching, installation, and uninstallation

# Function to properly handle the default PHP and versioned PHP
function version_resolve_php_version {
    local version="$1"
    
    # Handle the case where php@8.4 is actually the default php
    if [ "$version" = "php@8.4" ] && [ ! -d "$HOMEBREW_PREFIX/opt/php@8.4" ] && [ -d "$HOMEBREW_PREFIX/opt/php" ]; then
        local default_version=$(php -v 2>/dev/null | head -n 1 | cut -d " " -f 2 | cut -d "." -f 1,2)
        if [ "$default_version" = "8.4" ]; then
            echo "php@default"
            return
        fi
    fi
    
    # Return the original version
    echo "$version"
}

# Function to check for project-specific PHP version
function version_check_project {
    local current_dir="$(pwd)"
    local php_version_file=""
    local supported_files=(".php-version" ".phpversion" ".php")
    
    # Look for version files in current directory and parent directories
    while [ "$current_dir" != "/" ]; do
        for file in "${supported_files[@]}"; do
            if [ -f "$current_dir/$file" ]; then
                php_version_file="$current_dir/$file"
                core_debug_log "Found PHP version file: $php_version_file"
                break 2
            fi
        done
        current_dir="$(dirname "$current_dir")"
    done
    
    if [ -n "$php_version_file" ]; then
        local project_version=$(cat "$php_version_file" | tr -d '[:space:]')
        
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
    
    echo -n "Creating $file_name in the current directory with version $version. Continue? (y/n): "
    if [ "$(utils_validate_yes_no "Create project PHP version file?" "y")" = "y" ]; then
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
    local temp_output=$(mktemp)
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
            echo -n "Would you like to reinstall it? (y/n): "
            if [ "$(utils_validate_yes_no "Reinstall?" "y")" = "y" ]; then
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
            local conflicting_package=$(echo "$error_output" | grep -o "conflicts with [^ ]*" | cut -d' ' -f3)
            if [ -n "$conflicting_package" ]; then
                echo "The conflicting package is: $conflicting_package"
                echo -n "Would you like to uninstall the conflicting package? (y/n): "
                if [ "$(utils_validate_yes_no "Uninstall conflict?" "n")" = "y" ]; then
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
        
        echo ""
        echo "Error details:"
        echo "---------------"
        echo "$error_output" | head -n 10
        if [ $(echo "$error_output" | wc -l) -gt 10 ]; then
            echo "... (truncated, see full log with 'brew install -v $install_version')"
        fi
        echo ""
        echo "Possible solutions:"
        echo "1. Run 'brew doctor' to check for any issues with your Homebrew installation"
        echo "2. Run 'brew update' and try again"
        echo "3. Check for any conflicting dependencies with 'brew deps --tree $version'"
        echo "4. You might need to uninstall conflicting packages first"
        echo "5. Try installing with verbose output: 'brew install -v $version'"
        echo ""
        echo -n "Would you like to try a different approach? (y/n): "
        
        if [ "$(utils_validate_yes_no "Would you like to try a different approach?" "n")" = "y" ]; then
            echo "Choose an option:"
            echo "1) Run 'brew doctor' first then retry"
            echo "2) Run 'brew update' first then retry"
            echo "3) Try installing with verbose output"
            echo "4) Try force reinstall"
            echo "5) Exit and let me handle it manually"
            
            local valid_choice=false
            local fix_option
            
            while [ "$valid_choice" = "false" ]; do
                read -r fix_option
                
                if [[ "$fix_option" =~ ^[1-5]$ ]]; then
                    valid_choice=true
                else
                    echo -n "Please enter a number between 1 and 5: "
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
            if brew list --formula | grep -q "^$install_version$" || 
               ([ "$install_version" = "php" ] && brew list --formula | grep -q "^php$"); then
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
        echo -n "Would you like to continue? This may break your PHP environment. (y/n): "
        
        if [ "$(utils_validate_yes_no "Continue?" "n")" = "n" ]; then
            utils_show_status "info" "Uninstallation cancelled"
            return 1
        fi
    fi
    
    # Stop PHP-FPM service if running
    if brew services list | grep -q "$service_name"; then
        utils_show_status "info" "Stopping PHP-FPM service for $version..."
        brew services stop "$service_name"
    fi
    
    # Unlink the PHP version if it's linked
    if [ "$current_version" = "$version" ]; then
        utils_show_status "info" "Unlinking $version..."
        brew unlink "$version" 2>/dev/null
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
        echo -n "Would you like to remove configuration files as well? (y/n): "
        
        if [ "$(utils_validate_yes_no "Remove config files?" "n")" = "y" ]; then
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
            echo -n "Would you like to switch to another installed PHP version? (y/n): "
            
            if [ "$(utils_validate_yes_no "Switch to another version?" "y")" = "y" ]; then
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

# Function to switch PHP version with enhanced PATH handling
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
        echo -n "Would you like to install it? (y/n): "
        
        if [ "$(utils_validate_yes_no "Install?" "n")" = "y" ]; then
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
            
            echo -n "Would you like to attempt to reinstall it? (y/n): "
            
            if [ "$(utils_validate_yes_no "Reinstall?" "y")" = "y" ]; then
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
        
        # Check for any conflicting PHP installations
        core_check_php_conflicts
        
        # Unlink current PHP (if any)
        if [ "$current_version" != "none" ]; then
            utils_show_status "info" "Unlinking $current_version..."
            brew unlink "$current_version" 2>/dev/null
        fi
        
        # Link new PHP with progressive fallback strategies
        utils_show_status "info" "Linking $new_version..."
        
        # Strategy 1: Normal linking
        if brew link --force "$brew_version" 2>/dev/null; then
            utils_show_status "success" "Linked $new_version successfully"
        # Strategy 2: Overwrite linking
        elif brew link --overwrite "$brew_version" 2>/dev/null; then
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
                    if [ -f "$file" ]; then
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
    
    # Update shell RC file
    shell_update_rc "$new_version"
    
    # Restart PHP-FPM if it's being used
    fpm_restart "$new_version"
    
    utils_show_status "success" "PHP version switched to $new_version"
    
    # Try to apply changes to the current shell
    if [ -z "$SOURCED" ]; then
        export SOURCED=true
        utils_show_status "info" "Applying changes to current shell..."
        
        # Directly modify the PATH to ensure the changes take effect immediately
        if ! shell_force_reload "$new_version"; then
            # If shell_force_reload failed, give clear instructions
            shell_type=$(shell_detect_shell)
            echo ""
            echo "To apply the changes immediately, copy-paste this command:"
            
            case "$shell_type" in
                "zsh")
                    echo "export PATH=\"$php_bin_path:$php_sbin_path:\$PATH\"; hash -r"
                    ;;
                "bash")
                    echo "export PATH=\"$php_bin_path:$php_sbin_path:\$PATH\"; hash -r"
                    ;;
                "fish")
                    echo "set -gx PATH $php_bin_path $php_sbin_path \$PATH; and rehash"
                    ;;
                *)
                    echo "export PATH=\"$php_bin_path:$php_sbin_path:\$PATH\""
                    ;;
            esac
            echo ""
        fi
        
        # Verify the active PHP version
        CURRENT_PHP_VERSION=$(php -v 2>/dev/null | head -n 1 | cut -d " " -f 2 | cut -d "." -f 1,2)
        
        if [ "$new_version" = "php@default" ]; then
            # For default PHP, we need to get the expected version from the actual binary
            DEFAULT_PHP_PATH="$HOMEBREW_PREFIX/opt/php/bin/php"
            if [ -f "$DEFAULT_PHP_PATH" ]; then
                EXPECTED_VERSION=$($DEFAULT_PHP_PATH -v 2>/dev/null | head -n 1 | cut -d " " -f 2 | cut -d "." -f 1,2)
            else
                EXPECTED_VERSION="unknown"
            fi
        else
            EXPECTED_VERSION=$(echo "$new_version" | grep -o "[0-9]\.[0-9]")
        fi
        
        if [ "$CURRENT_PHP_VERSION" = "$EXPECTED_VERSION" ]; then
            utils_show_status "success" "Active PHP version is now: $CURRENT_PHP_VERSION"
            php -v | head -n 1
            
            # Create a PATH validation command to check in new sessions
            echo ""
            echo "To verify PHP version in new terminal sessions, use this command:"
            echo "which php && php -v | head -n 1"
            
            # Show actual binary location
            echo ""
            echo "PHP binary location: $(which php)"
            if [ -L "$(which php)" ]; then
                echo "Symlinked to: $(readlink $(which php))"
            fi
        else
            utils_show_status "warning" "PHP version switch was not fully applied to the current shell"
            echo "Expected PHP version: $EXPECTED_VERSION"
            echo "Current PHP version: $(php -v | head -n 1)"
            echo ""
            
            shell_type=$(shell_detect_shell)
            
            echo "To activate the new PHP version in your current shell, run:"
            case "$shell_type" in
                "zsh")
                    echo "source ~/.zshrc"
                    ;;
                "bash")
                    if [ -f ~/.bashrc ]; then
                        echo "source ~/.bashrc"
                    elif [ -f ~/.bash_profile ]; then
                        echo "source ~/.bash_profile"
                    else
                        echo "source ~/.profile"
                    fi
                    ;;
                "fish")
                    echo "source ~/.config/fish/config.fish"
                    ;;
                *)
                    echo "source ~/.profile"
                    ;;
            esac
            
            echo ""
            echo "Or, you can directly update your PATH for this session:"
            case "$shell_type" in
                "zsh"|"bash")
                    echo "export PATH=\"$php_bin_path:$php_sbin_path:\$PATH\"; hash -r"
                    ;;
                "fish")
                    echo "set -gx PATH $php_bin_path $php_sbin_path \$PATH; and rehash"
                    ;;
                *)
                    echo "export PATH=\"$php_bin_path:$php_sbin_path:\$PATH\""
                    ;;
            esac
            
            echo ""
            echo "Or restart your terminal session to use the new PHP version."
        fi
    else
        shell_type=$(shell_detect_shell)
        
        echo "To apply the changes to your current terminal, run:"
        case "$shell_type" in
            "zsh")
                echo "source ~/.zshrc"
                ;;
            "bash")
                if [ -f ~/.bashrc ]; then
                    echo "source ~/.bashrc"
                elif [ -f ~/.bash_profile ]; then
                    echo "source ~/.bash_profile"
                else
                    echo "source ~/.profile"
                fi
                ;;
            "fish")
                echo "source ~/.config/fish/config.fish"
                ;;
            *)
                echo "source ~/.profile"
                ;;
        esac
        
        echo ""
        echo "Or, you can directly update your PATH for this session:"
        case "$shell_type" in
            "zsh"|"bash")
                echo "export PATH=\"$php_bin_path:$php_sbin_path:\$PATH\"; hash -r"
                ;;
            "fish")
                echo "set -gx PATH $php_bin_path $php_sbin_path \$PATH; and rehash"
                ;;
            *)
                echo "export PATH=\"$php_bin_path:$php_sbin_path:\$PATH\""
                ;;
        esac
        
        echo "Then verify with: php -v"
    fi
}

# Function for silent/quick PHP version switching for auto-switch
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