#!/bin/bash
# Script to set up the tools directory and install the fix-permissions script

# Determine script location
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Create tools directory if it doesn't exist
TOOLS_DIR="$SCRIPT_DIR/tools"
mkdir -p "$TOOLS_DIR" 2>/dev/null

# Create the fix-permissions.sh script in the tools directory
FIX_SCRIPT="$TOOLS_DIR/fix-permissions.sh"

cat > "$FIX_SCRIPT" << 'EOL'
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
CONFIG_FILE="$HOME/.phpswitch.conf"
# Get secure username with validation
USERNAME=$(id -un)
# Validate username to prevent command injection
if [[ ! "$USERNAME" =~ ^[a-zA-Z0-9._-]+$ ]]; then
    echo -e "${RED}Error: Invalid username detected. Exiting for security.${NC}"
    exit 1
fi

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
                # Solution 4: Try removing extended attributes or ACLs
                echo -e "\nSolution 4: Removing extended attributes and ACLs..."
                
                if command -v xattr &>/dev/null; then
                    sudo xattr -c "$CACHE_DIR" 2>/dev/null
                fi
                
                if command -v chmod &>/dev/null; then
                    sudo chmod -N "$CACHE_DIR" 2>/dev/null # Remove ACLs on macOS
                fi
                
                if [ -w "$CACHE_DIR" ]; then
                    echo -e "${GREEN}Extended attributes/ACLs removed, directory is now writable.${NC}"
                else
                    # Solution 5: Recreate the directory completely
                    echo -e "\nSolution 5: Recreating the directory completely..."
                    
                    # Backup any existing files
                    BACKUP_DIR="/tmp/phpswitch_backup_$(date +%s)"
                    mkdir -p "$BACKUP_DIR"
                    echo "Backing up any existing files to $BACKUP_DIR"
                    
                    if [ -d "$CACHE_DIR" ]; then
                        cp -r "$CACHE_DIR"/* "$BACKUP_DIR"/ 2>/dev/null
                    fi
                    
                    # Remove and recreate
                    sudo rm -rf "$CACHE_DIR" 2>/dev/null
                    mkdir -p "$CACHE_DIR" 2>/dev/null
                    
                    if [ -d "$CACHE_DIR" ] && [ -w "$CACHE_DIR" ]; then
                        echo -e "${GREEN}Directory successfully recreated with proper permissions.${NC}"
                        
                        # Restore any backed up files
                        cp -r "$BACKUP_DIR"/* "$CACHE_DIR"/ 2>/dev/null
                    else
                        # Solution 6: Create in a different location
                        echo -e "\nSolution 6: Creating cache directory in an alternative location..."
                        
                        # Define alternative location in user's home directory
                        ALT_CACHE_DIR="$HOME/.phpswitch_cache"
                        
                        if mkdir -p "$ALT_CACHE_DIR"; then
                            echo -e "${GREEN}Alternative cache directory created successfully at:${NC} $ALT_CACHE_DIR"
                            
                            # Create or update configuration file to use this directory
                            if [ -f "$CONFIG_FILE" ]; then
                                # Backup the existing config
                                cp "$CONFIG_FILE" "${CONFIG_FILE}.bak.$(date +%s)"
                                
                                # Add or update cache directory setting
                                if grep -q "CACHE_DIRECTORY=" "$CONFIG_FILE"; then
                                    sed -i.tmp "s|CACHE_DIRECTORY=.*|CACHE_DIRECTORY=\"$ALT_CACHE_DIR\"|g" "$CONFIG_FILE"
                                    rm -f "$CONFIG_FILE.tmp"
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
                            echo -e "\nEmergency solution: Update the PHPSwitch configuration file"
                            
                            # Try to create a tmp directory as a last resort
                            TMP_CACHE_DIR="/tmp/phpswitch_cache_$USERNAME"
                            mkdir -p "$TMP_CACHE_DIR" 2>/dev/null
                            
                            if [ -d "$TMP_CACHE_DIR" ] && [ -w "$TMP_CACHE_DIR" ]; then
                                echo "Created temporary cache directory at: $TMP_CACHE_DIR"
                                
                                # Update config file to use tmp directory
                                if [ -f "$CONFIG_FILE" ]; then
                                    # Backup the existing config
                                    cp "$CONFIG_FILE" "${CONFIG_FILE}.bak.$(date +%s)"
                                    
                                    # Add or update cache directory setting
                                    if grep -q "CACHE_DIRECTORY=" "$CONFIG_FILE"; then
                                        sed -i.tmp "s|CACHE_DIRECTORY=.*|CACHE_DIRECTORY=\"$TMP_CACHE_DIR\"|g" "$CONFIG_FILE"
                                        rm -f "$CONFIG_FILE.tmp"
                                    else
                                        echo "CACHE_DIRECTORY=\"$TMP_CACHE_DIR\"" >> "$CONFIG_FILE"
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
CACHE_DIRECTORY="$TMP_CACHE_DIR"
EOL
                                fi
                                
                                echo -e "${YELLOW}PHPSwitch configured to use a temporary directory.${NC}"
                                echo "Note: Cache will be cleared on system reboot."
                            else
                                echo -e "${RED}All attempts to create a writable cache directory failed.${NC}"
                                echo "Please manually modify $CONFIG_FILE to set CACHE_DIRECTORY to a writable location."
                            fi
                        fi
                    fi
                fi
            fi
        fi
    fi
fi

# Verify write access
VERIFY_DIR=${ALT_CACHE_DIR:-${TMP_CACHE_DIR:-$CACHE_DIR}}

if [ -d "$VERIFY_DIR" ] && [ -w "$VERIFY_DIR" ]; then
    echo -e "\nStep 4: Verifying write access..."
    TEST_FILE="$VERIFY_DIR/test_file"
    
    if touch "$TEST_FILE" 2>/dev/null; then
        echo -e "${GREEN}Write test successful.${NC}"
        rm -f "$TEST_FILE"
        
        # Clean existing cache files to ensure a fresh start
        echo -e "\nStep 5: Cleaning existing cache files..."
        rm -f "$VERIFY_DIR"/*.cache "$VERIFY_DIR"/directory_cache.txt 2>/dev/null
        
        # Create empty cache files with correct permissions
        touch "$VERIFY_DIR/available_versions.cache" 2>/dev/null
        touch "$VERIFY_DIR/directory_cache.txt" 2>/dev/null
        
        echo -e "\n${GREEN}All permission issues have been fixed successfully!${NC}"
        echo -e "PHPSwitch will now use the cache directory: ${BLUE}$VERIFY_DIR${NC}"
        
        # If we're using a different directory, make sure we update the config file
        if [ "$VERIFY_DIR" != "$CACHE_DIR" ] && [ ! -f "$CONFIG_FILE" ]; then
            echo -e "\nCreating config file to use the new directory location..."
            cat > "$CONFIG_FILE" << EOL
# PHPSwitch Configuration
AUTO_RESTART_PHP_FPM=true
BACKUP_CONFIG_FILES=true
DEFAULT_PHP_VERSION=""
MAX_BACKUPS=5
AUTO_SWITCH_PHP_VERSION=false
CACHE_DIRECTORY="$VERIFY_DIR"
EOL
            echo -e "${GREEN}Configuration file created at:${NC} $CONFIG_FILE"
        fi
    else
        echo -e "${RED}Write test failed. Still having permission issues.${NC}"
        echo -e "\nExtreme solution: Using system temporary directory"
        echo "PHPSwitch can be updated to always use temporary directories:"
        echo "1. Create or edit $CONFIG_FILE"
        echo "2. Add this line: CACHE_DIRECTORY=\"\$(mktemp -d /tmp/phpswitch.XXXXXX)\""
        
        # Try to create the config file as a last resort
        echo "Attempting to create config file with temporary directory setting..."
        cat > "$CONFIG_FILE" << EOL
# PHPSwitch Configuration
AUTO_RESTART_PHP_FPM=true
BACKUP_CONFIG_FILES=true
DEFAULT_PHP_VERSION=""
MAX_BACKUPS=5
AUTO_SWITCH_PHP_VERSION=false
CACHE_DIRECTORY="/tmp/phpswitch_$(date +%s)"
EOL

        if [ -f "$CONFIG_FILE" ]; then
            echo -e "${GREEN}Created emergency configuration to use temporary directories.${NC}"
            echo "You may need to run 'mkdir -p $(grep CACHE_DIRECTORY "$CONFIG_FILE" | cut -d '"' -f2)' before using phpswitch."
        fi
    fi
else
    echo -e "\n${RED}Unable to create any writable cache directory.${NC}"
    echo -e "Manual intervention required. Try these commands as a system administrator:"
    echo "sudo mkdir -p $CACHE_DIR"
    echo "sudo chown -R $USERNAME $CACHE_DIR"
    echo "sudo chmod -R 755 $CACHE_DIR"
    
    echo -e "\nAlternatively, create a configuration file at $CONFIG_FILE with the following content:"
    echo "CACHE_DIRECTORY=\"/tmp/phpswitch_$USERNAME\""
    echo "Then create the directory with: mkdir -p /tmp/phpswitch_$USERNAME"
fi

echo -e "\nTo apply these changes, restart phpswitch or run:"
echo "phpswitch --clear-cache"

exit 0
EOL

# Make the script executable
chmod +x "$FIX_SCRIPT"

echo "Fix permissions script created at: $FIX_SCRIPT"
echo "You can run it with: $FIX_SCRIPT"
echo "Or with phpswitch: phpswitch --fix-permissions"