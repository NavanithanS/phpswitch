#!/bin/bash
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
