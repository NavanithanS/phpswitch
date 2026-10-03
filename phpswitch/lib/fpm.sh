#!/bin/bash
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