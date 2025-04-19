#!/bin/bash
# Enhanced script to fix persistent permission issues with PHPSwitch cache directory

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}PHPSwitch Permission Repair Tool (Enhanced)${NC}"
echo "========================================="
echo ""

# Define the cache directory and parent directory
CACHE_DIR="$HOME/.cache/phpswitch"
PARENT_DIR="$HOME/.cache"
USERNAME=$(whoami)

# Function to check and display permissions
check_permissions() {
    local dir=$1
    echo -e "${BLUE}Checking permissions for:${NC} $dir"
    
    if [ -d "$dir" ]; then
        echo "Directory exists: Yes"
        echo "Owner: $(ls -ld "$dir" | awk '{print $3}')"
        echo "Group: $(ls -ld "$dir" | awk '{print $4}')"
        echo "Permissions: $(ls -ld "$dir" | awk '{print $1}')"
        
        if [ -w "$dir" ]; then
            echo "Writable: Yes"
            return 0
        else
            echo "Writable: No"
            return 1
        fi
    else
        echo "Directory exists: No"
        return 2
    fi
}

# First, check parent directory permissions
echo "Step 1: Checking parent directory permissions"
check_permissions "$PARENT_DIR"
parent_writable=$?

# Check phpswitch directory permissions
echo -e "\nStep 2: Checking PHPSwitch cache directory permissions"
check_permissions "$CACHE_DIR"
cache_writable=$?

# Try solution based on diagnostic results
echo -e "\nStep 3: Attempting to fix permissions..."

if [ $cache_writable -eq 0 ]; then
    echo -e "${GREEN}Cache directory is already writable. No action needed.${NC}"
else
    # Solution 1: Try standard permission fix
    echo -e "\nSolution 1: Using chmod to fix permissions..."
    chmod -v u+w "$CACHE_DIR" 2>/dev/null
    
    if [ -w "$CACHE_DIR" ]; then
        echo -e "${GREEN}Permissions fixed successfully.${NC}"
    else
        # Solution 2: Try with sudo
        echo -e "\nSolution 2: Using sudo to fix permissions..."
        sudo chmod -v u+w "$CACHE_DIR" 2>/dev/null
        
        if [ -w "$CACHE_DIR" ]; then
            echo -e "${GREEN}Permissions fixed successfully with sudo.${NC}"
        else
            # Solution 3: Try changing ownership
            echo -e "\nSolution 3: Changing ownership of the directory..."
            sudo chown -v "$USERNAME" "$CACHE_DIR" 2>/dev/null
            
            if [ -w "$CACHE_DIR" ]; then
                echo -e "${GREEN}Ownership changed successfully, directory is now writable.${NC}"
            else
                # Solution 4: Recreate the directory completely
                echo -e "\nSolution 4: Recreating the directory completely..."
                
                # Backup any existing files
                BACKUP_DIR="/tmp/phpswitch_backup_$(date +%s)"
                mkdir -p "$BACKUP_DIR"
                echo "Backing up any existing files to $BACKUP_DIR"
                
                if [ -d "$CACHE_DIR" ]; then
                    cp -r "$CACHE_DIR"/* "$BACKUP_DIR"/ 2>/dev/null
                fi
                
                # Remove and recreate
                sudo rm -rf "$CACHE_DIR" 2>/dev/null
                if sudo mkdir -p "$CACHE_DIR" && sudo chown "$USERNAME" "$CACHE_DIR" && sudo chmod 755 "$CACHE_DIR"; then
                    echo -e "${GREEN}Directory successfully recreated with proper permissions.${NC}"
                    
                    # Restore any backed up files
                    cp -r "$BACKUP_DIR"/* "$CACHE_DIR"/ 2>/dev/null
                else
                    # Solution 5: Create in a different location
                    echo -e "\nSolution 5: Creating cache directory in an alternative location..."
                    
                    # Define alternative location in user's home directory
                    ALT_CACHE_DIR="$HOME/.phpswitch_cache"
                    
                    if mkdir -p "$ALT_CACHE_DIR"; then
                        echo -e "${GREEN}Alternative cache directory created successfully at:${NC} $ALT_CACHE_DIR"
                        
                        # Create a configuration file to tell phpswitch to use this directory
                        CONFIG_FILE="$HOME/.phpswitch.conf"
                        
                        if [ -f "$CONFIG_FILE" ]; then
                            # Backup the existing config
                            cp "$CONFIG_FILE" "${CONFIG_FILE}.bak.$(date +%s)"
                            
                            # Add or update cache directory setting
                            if grep -q "CACHE_DIRECTORY=" "$CONFIG_FILE"; then
                                sed -i '' "s|CACHE_DIRECTORY=.*|CACHE_DIRECTORY=\"$ALT_CACHE_DIR\"|g" "$CONFIG_FILE"
                            else
                                echo "CACHE_DIRECTORY=\"$ALT_CACHE_DIR\"" >> "$CONFIG_FILE"
                            fi
                        else
                            # Create a new config file
                            cat > "$CONFIG_FILE" << EOL
# PHPSwitch Configuration
AUTO_RESTART_PHP_FPM=true
BACKUP_CONFIG_FILES=true
DEFAULT_PHP_VERSION=""
MAX_BACKUPS=5
AUTO_SWITCH_PHP_VERSION=false
CACHE_DIRECTORY="$ALT_CACHE_DIR"
EOL
                        fi
                        
                        echo -e "${GREEN}PHPSwitch configured to use the alternative cache directory.${NC}"
                        echo "You should now be able to run phpswitch without permission errors."
                    else
                        echo -e "${RED}Failed to create alternative cache directory.${NC}"
                        echo "This is a serious permission issue with your user account."
                        echo -e "\nEmergency solution: Update the PHPSwitch core.sh file"
                        echo "Edit the lib/core.sh file and replace the cache_dir line with:"
                        echo "local cache_dir=\"\$(mktemp -d /tmp/phpswitch.XXXXXX)\""
                    fi
                fi
            fi
        fi
    fi
fi

# Verify write access
if [ -w "$CACHE_DIR" ] || [ -n "$ALT_CACHE_DIR" -a -w "$ALT_CACHE_DIR" ]; then
    # Determine which directory to use
    TEST_DIR=${ALT_CACHE_DIR:-$CACHE_DIR}
    
    echo -e "\nStep 4: Verifying write access..."
    TEST_FILE="$TEST_DIR/test_file"
    
    if touch "$TEST_FILE" 2>/dev/null; then
        echo -e "${GREEN}Write test successful.${NC}"
        rm -f "$TEST_FILE"
        
        # Clean existing cache files to ensure a fresh start
        echo -e "\nStep 5: Cleaning existing cache files..."
        rm -f "$TEST_DIR"/*.cache "$TEST_DIR"/directory_cache.txt
        
        # Create empty cache files with correct permissions
        touch "$TEST_DIR/available_versions.cache"
        touch "$TEST_DIR/directory_cache.txt"
        
        echo -e "\n${GREEN}All permission issues have been fixed successfully!${NC}"
        
        if [ -n "$ALT_CACHE_DIR" ]; then
            echo -e "PHPSwitch will now use the alternative cache directory: ${BLUE}$ALT_CACHE_DIR${NC}"
        else
            echo -e "The standard cache directory is now usable: ${BLUE}$CACHE_DIR${NC}"
        fi
    else
        echo -e "${RED}Write test failed. Still having permission issues.${NC}"
        echo -e "\nExtreme solution: Running PHPSwitch with temporary directories"
        echo "PHPSwitch can be updated to always use temporary directories:"
        echo "1. Edit lib/core.sh"
        echo "2. Find the line that defines cache_dir"
        echo "3. Change it to: local cache_dir=\$(mktemp -d /tmp/phpswitch.XXXXXX)"
        
        echo -e "\nAdditional diagnostic information:"
        echo "Operating system: $(uname -a)"
        echo "File system for home directory:"
        df -T "$HOME" 2>/dev/null || df -h "$HOME"
        
        echo -e "\nFile system permissions in .cache directory:"
        ls -la "$HOME/.cache" | head -n 20
    fi
else
    echo -e "\n${RED}Unable to fix permission issues through automatic means.${NC}"
    echo -e "Manual intervention required. Try these commands as a system administrator:"
    echo "sudo mkdir -p $CACHE_DIR"
    echo "sudo chown -R $USERNAME $CACHE_DIR"
    echo "sudo chmod -R 755 $CACHE_DIR"
    
    echo -e "\nIf those fail, you can modify PHPSwitch to always use temporary directories:"
    echo "1. Edit the core.sh file"
    echo "2. Change the cache_dir line to use /tmp instead"
    echo "3. Example: local cache_dir=\$(mktemp -d /tmp/phpswitch.XXXXXX)"
fi

echo -e "\nIf you continue to experience issues, run phpswitch with debug mode:"
echo "phpswitch --debug"

exit 0