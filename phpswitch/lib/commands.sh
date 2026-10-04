#!/bin/bash
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
    elif [ "$1" = "--uninstall-auto-switch" ]; then
        auto_uninstall
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
        printf "    phpswitch --uninstall-auto-switch    remove auto-switching from your rc files\n"
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
