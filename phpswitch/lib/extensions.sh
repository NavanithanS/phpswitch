#!/bin/bash
# PHPSwitch Extension Management
# Handles PHP extension operations

# Function to manage PHP extensions
function ext_manage_extensions {
    local php_version="$1"
    local service_name=$(fpm_get_service_name "$php_version")
    
    # Extract the numeric version from php@X.Y
    local numeric_version
    if [ "$php_version" = "php@default" ]; then
        numeric_version=$(php -v | head -n 1 | cut -d " " -f 2 | cut -d "." -f 1,2)
    else
        numeric_version=$(echo "$php_version" | grep -o "[0-9]\.[0-9]")
    fi
    
    # Determine the PHP ini directory
    local ini_dir
    if [ "$php_version" = "php@default" ]; then
        ini_dir="$HOMEBREW_PREFIX/etc/php"
    else
        ini_dir="$HOMEBREW_PREFIX/etc/php/$numeric_version"
    fi
    
    utils_show_status "info" "PHP Extensions for $php_version (version $numeric_version):"
    echo ""
    
    # List installed extensions
    echo "Currently loaded extensions:"
    php -m | sort | grep -v "\[" | sed 's/^/- /'
    
    echo ""
    echo "Extension configuration files:"
    
    if [ -d "$ini_dir" ]; then
        if [ -d "$ini_dir/conf.d" ]; then
            ls -1 "$ini_dir/conf.d" | grep -i "\.ini$" | sed 's/^/- /'
        else
            echo "No conf.d directory found at $ini_dir/conf.d"
        fi
    else
        echo "No configuration directory found at $ini_dir"
    fi
    
    echo ""
    echo "Options:"
    echo "1) Enable/disable an extension"
    echo "2) Edit php.ini"
    echo "3) Show detailed extension information"
    echo "0) Back to main menu"
    echo ""
    echo -n "Please select an option (0-3): "
    
    local option
    read -r option
    
    case $option in
        1)
            echo -n "Enter extension name: "
            read -r ext_name
            if [ -n "$ext_name" ]; then
                echo "Select action for $ext_name:"
                echo "1) Enable extension"
                echo "2) Disable extension"
                echo -n "Select (1-2): "
                
                local ext_action
                read -r ext_action
                
                if [ "$ext_action" = "1" ]; then
                    utils_show_status "info" "Enabling $ext_name..."
                    # Check if extension exists
                    if php -m | grep -q -i "^$ext_name$"; then
                        utils_show_status "info" "Extension $ext_name is already enabled"
                    else
                        # Try to enable via Homebrew
                        if brew install "$php_version-$ext_name" 2>/dev/null; then
                            utils_show_status "success" "Extension $ext_name installed via Homebrew"
                            fpm_restart "$php_version"
                        else
                            utils_show_status "warning" "Could not install via Homebrew, trying PECL..."
                            if pecl install "$ext_name"; then
                                utils_show_status "success" "Extension $ext_name installed via PECL"
                                fpm_restart "$php_version"
                            else
                                utils_show_status "error" "Failed to enable $ext_name"
                            fi
                        fi
                    fi
                elif [ "$ext_action" = "2" ]; then
                    utils_show_status "info" "Disabling $ext_name..."
                    if [ -f "$ini_dir/conf.d/ext-$ext_name.ini" ]; then
                        sudo mv "$ini_dir/conf.d/ext-$ext_name.ini" "$ini_dir/conf.d/ext-$ext_name.ini.disabled"
                        utils_show_status "success" "Extension $ext_name disabled"
                        fpm_restart "$php_version"
                    elif [ -f "$ini_dir/conf.d/$ext_name.ini" ]; then
                        sudo mv "$ini_dir/conf.d/$ext_name.ini" "$ini_dir/conf.d/$ext_name.ini.disabled"
                        utils_show_status "success" "Extension $ext_name disabled"
                        fpm_restart "$php_version"
                    else
                        utils_show_status "error" "Could not find configuration file for $ext_name"
                    fi
                fi
            fi
            ;;
        2)
            # Find and edit php.ini
            local php_ini="$ini_dir/php.ini"
            if [ -f "$php_ini" ]; then
                utils_show_status "info" "Opening php.ini for $php_version..."
                if [ -n "$EDITOR" ]; then
                    $EDITOR "$php_ini"
                else
                    nano "$php_ini"
                fi
                
                utils_show_status "info" "php.ini edited. Restart PHP-FPM to apply changes"
                echo -n "Would you like to restart PHP-FPM now? (y/n): "
                if [ "$(utils_validate_yes_no "Restart PHP-FPM?" "y")" = "y" ]; then
                    fpm_restart "$php_version"
                fi
            else
                utils_show_status "error" "php.ini not found at $php_ini"
            fi
            ;;
        3)
            echo -n "Enter extension name (or leave blank for all): "
            read -r ext_detail
            if [ -n "$ext_detail" ]; then
                php -i | grep -i "$ext_detail" | less
            else
                php -i | less
            fi
            ;;
        0)
            return 0
            ;;
        *)
            utils_show_status "error" "Invalid option"
            ;;
    esac
    
    # Allow user to perform another extension management action
    echo ""
    echo -n "Would you like to perform another extension management action? (y/n): "
    if [ "$(utils_validate_yes_no "Another action?" "y")" = "y" ]; then
        ext_manage_extensions "$php_version"
    fi
}