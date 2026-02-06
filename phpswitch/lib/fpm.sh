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
    local active_service=$(fpm_get_service_name "$active_version")
    
    # Get all running PHP services
    local running_services=$(brew services list | grep -E "^php(@[0-9]\.[0-9])?" | awk '{print $1}')
    
    for service in $running_services; do
        if [ "$service" != "$active_service" ]; then
            utils_show_status "info" "Stopping PHP-FPM service for $service..."
            brew services stop "$service" >/dev/null 2>&1
        fi
    done
}

# Function to clean up PHP-FPM service files and fix permissions
function fpm_cleanup_service {
    local version="$1"
    local service_name=$(fpm_get_service_name "$version")
    
    utils_show_status "info" "Cleaning up PHP-FPM service files for $service_name..."
    
    # Stop the service first
    brew services stop "$service_name" >/dev/null 2>&1
    
    # Find and remove LaunchAgent/LaunchDaemon files
    local launch_agent="$HOME/Library/LaunchAgents/homebrew.mxcl.$service_name.plist"
    local launch_daemon="/Library/LaunchDaemons/homebrew.mxcl.$service_name.plist"
    
    if [ -f "$launch_agent" ]; then
        utils_show_status "info" "Removing LaunchAgent file: $launch_agent"
        rm -f "$launch_agent" 2>/dev/null
    fi
    
    if [ -f "$launch_daemon" ]; then
        utils_show_status "info" "Removing LaunchDaemon file (requires sudo): $launch_daemon"
        sudo rm -f "$launch_daemon" 2>/dev/null
    fi
    
    # Reset permissions if needed
    local cellar_path="$HOMEBREW_PREFIX/Cellar/$service_name"
    local opt_path="$HOMEBREW_PREFIX/opt/$service_name"
    
    if [ -d "$cellar_path" ]; then
        utils_show_status "info" "Resetting permissions for: $cellar_path"
        # Get secure username and validate it
        local username
        username="$(id -un)"
        if utils_validate_username "$username"; then
            sudo chown -R "$username" "$cellar_path" 2>/dev/null
        else
            utils_show_status "error" "Invalid username detected, skipping permission reset"
        fi
    fi
    
    if [ -d "$opt_path" ]; then
        utils_show_status "info" "Resetting permissions for: $opt_path"
        # Get secure username and validate it
        local username
        username="$(id -un)"
        if utils_validate_username "$username"; then
            sudo chown -R "$username" "$opt_path" 2>/dev/null
        else
            utils_show_status "error" "Invalid username detected, skipping permission reset"
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
    local service_name=$(fpm_get_service_name "$version")
    
    if [ "$AUTO_RESTART_PHP_FPM" != "true" ]; then
        core_debug_log "Auto restart PHP-FPM is disabled in config"
        return 0
    fi
    
    # First, stop all other PHP-FPM services
    fpm_stop_other_services "$version"
    
    # Check if PHP-FPM service is running
    local is_running=false
    if brew services list | grep "$service_name" | grep -q "started"; then
        is_running=true
        utils_show_status "info" "Restarting PHP-FPM service for $service_name..."
        
        # Try normal restart first
        local restart_output=$(brew services restart "$service_name" 2>&1)
        if echo "$restart_output" | grep -q "Successfully"; then
            utils_show_status "success" "PHP-FPM service restarted successfully"
        else
            utils_show_status "warning" "Failed to restart service: $restart_output"
            
            # Check for specific error patterns
            if echo "$restart_output" | grep -q "Bootstrap failed: 5: Input/output error"; then
                utils_show_status "warning" "Detected bootstrap error. This usually indicates service configuration issues."
                echo -n "Would you like to try automatic service cleanup and repair? (y/n): "
                
                if [ "$(utils_validate_yes_no "Try service cleanup?" "y")" = "y" ]; then
                    # Run cleanup and try again
                    fpm_cleanup_service "$version"
                    utils_show_status "info" "Trying restart after cleanup..."
                    local retry_output=$(brew services start "$service_name" 2>&1)
                    
                    if echo "$retry_output" | grep -q "Successfully"; then
                        utils_show_status "success" "PHP-FPM service started successfully after cleanup"
                    else
                        utils_show_status "error" "Failed to start service after cleanup: $retry_output"
                        echo "You may need to restart your computer or reinstall PHP $version"
                        echo "Try running: brew reinstall $service_name"
                    fi
                fi
            # Check for other error types
            elif echo "$restart_output" | grep -q "Permission denied"; then
                utils_show_status "warning" "Permission denied. This could be due to file permissions or locked service files."
                echo -n "Would you like to try service cleanup and repair? (y/n): "
                
                if [ "$(utils_validate_yes_no "Try service cleanup?" "y")" = "y" ]; then
                    fpm_cleanup_service "$version"
                    utils_show_status "info" "Trying restart after cleanup..."
                    brew services start "$service_name"
                else
                    echo -n "Would you like to try with sudo instead? (y/n): "
                    if [ "$(utils_validate_yes_no "Try with sudo?" "y")" = "y" ]; then
                        utils_show_status "info" "Trying with sudo..."
                        local sudo_output=$(sudo brew services restart "$service_name" 2>&1)
                        if echo "$sudo_output" | grep -q "Successfully"; then
                            utils_show_status "success" "PHP-FPM service restarted successfully with sudo"
                            utils_show_status "warning" "Running with sudo changes file ownership. You may need to run cleanup later."
                        else
                            utils_show_status "error" "Failed to restart service with sudo: $sudo_output"
                            echo "You may need to restart manually with:"
                            echo "sudo brew services restart $service_name"
                        fi
                    fi
                fi
            elif echo "$restart_output" | grep -q "already started"; then
                utils_show_status "warning" "Service reports as already started, but may need a force restart"
                echo -n "Would you like to try stop and then start? (y/n): "
                
                if [ "$(utils_validate_yes_no "Force restart?" "y")" = "y" ]; then
                    utils_show_status "info" "Stopping service first..."
                    brew services stop "$service_name"
                    sleep 2
                    utils_show_status "info" "Starting service..."
                    brew services start "$service_name"
                fi
            else
                utils_show_status "error" "Unknown error restarting service"
                echo -n "Would you like to try service cleanup and repair? (y/n): "
                
                if [ "$(utils_validate_yes_no "Try service cleanup?" "y")" = "y" ]; then
                    fpm_cleanup_service "$version"
                    utils_show_status "info" "Trying restart after cleanup..."
                    brew services start "$service_name"
                else
                    echo "Manual restart may be required: brew services restart $service_name"
                fi
            fi
        fi
    else
        utils_show_status "info" "PHP-FPM service not active for $service_name"
        echo -n "Would you like to start it? (y/n): "
        
        if [ "$(utils_validate_yes_no "Start service?" "y")" = "y" ]; then
            utils_show_status "info" "Starting PHP-FPM service for $service_name..."
            local start_output=$(brew services start "$service_name" 2>&1)
            
            if echo "$start_output" | grep -q "Successfully"; then
                utils_show_status "success" "PHP-FPM service started successfully"
            else
                utils_show_status "warning" "Failed to start service: $start_output"
                
                # Check for bootstrap/IO error specifically
                if echo "$start_output" | grep -q "Bootstrap failed: 5: Input/output error"; then
                    utils_show_status "warning" "Detected bootstrap error. This usually indicates service configuration issues."
                    echo -n "Would you like to try automatic service cleanup and repair? (y/n): "
                    
                    if [ "$(utils_validate_yes_no "Try service cleanup?" "y")" = "y" ]; then
                        # Run cleanup and try again
                        fpm_cleanup_service "$version"
                        utils_show_status "info" "Trying restart after cleanup..."
                        local retry_output=$(brew services start "$service_name" 2>&1)
                        
                        if echo "$retry_output" | grep -q "Successfully"; then
                            utils_show_status "success" "PHP-FPM service started successfully after cleanup"
                        else
                            utils_show_status "error" "Failed to start service after cleanup: $retry_output"
                            echo "Manual intervention may be required. Consider reinstalling PHP:"
                            echo "brew reinstall $service_name"
                        fi
                    else
                        echo -n "Would you like to try with sudo? (y/n): "
                        if [ "$(utils_validate_yes_no "Try with sudo?" "y")" = "y" ]; then
                            utils_show_status "info" "Trying with sudo..."
                            sudo brew services start "$service_name"
                        fi
                    fi
                else
                    echo -n "Would you like to try with sudo? (y/n): "
                    if [ "$(utils_validate_yes_no "Try with sudo?" "y")" = "y" ]; then
                        utils_show_status "info" "Trying with sudo..."
                        sudo brew services start "$service_name"
                    fi
                fi
            fi
        fi
    fi
    
    # Verify the service is running after our operations
    if brew services list | grep "$service_name" | grep -q "started"; then
        utils_show_status "success" "PHP-FPM service for $service_name is running"
    else
        utils_show_status "warning" "PHP-FPM service for $service_name may not be running correctly"
        echo "Check status with: brew services list | grep php"
        echo "If service is not running, consider skipping PHP-FPM (it's only needed for web server integration)"
    fi
    
    return 0
}