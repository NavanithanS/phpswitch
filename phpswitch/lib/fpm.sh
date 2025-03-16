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
            
            # Check for specific errors
            if echo "$restart_output" | grep -q "Permission denied"; then
                utils_show_status "warning" "Permission denied. This could be due to file permissions or locked service files."
                echo -n "Would you like to try with sudo? (y/n): "
                
                if [ "$(utils_validate_yes_no "Try with sudo?" "y")" = "y" ]; then
                    utils_show_status "info" "Trying with sudo..."
                    local sudo_output=$(sudo brew services restart "$service_name" 2>&1)
                    if echo "$sudo_output" | grep -q "Successfully"; then
                        utils_show_status "success" "PHP-FPM service restarted successfully with sudo"
                    else
                        utils_show_status "error" "Failed to restart service with sudo: $sudo_output"
                        echo "You may need to restart manually with:"
                        echo "sudo brew services restart $service_name"
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
                echo "Manual restart may be required: brew services restart $service_name"
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
                echo -n "Would you like to try with sudo? (y/n): "
                
                if [ "$(utils_validate_yes_no "Try with sudo?" "y")" = "y" ]; then
                    utils_show_status "info" "Trying with sudo..."
                    sudo brew services start "$service_name"
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
    fi
    
    return 0
}