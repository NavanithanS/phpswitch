#!/bin/bash
# PHPSwitch Self-Management
# Installs, uninstalls and updates the phpswitch command itself

# Function to install as a system command
function cmd_install_as_command {
    local destination="/usr/local/bin/phpswitch"
    local alt_destination="$HOMEBREW_PREFIX/bin/phpswitch"
    
    # Check if /usr/local/bin exists, if not try Homebrew bin
    if [ ! -d "/usr/local/bin" ]; then
        if [ -d "$HOMEBREW_PREFIX/bin" ]; then
            utils_show_status "info" "Using $HOMEBREW_PREFIX/bin directory..."
            destination=$alt_destination
        else
            utils_show_status "info" "Creating /usr/local/bin directory..."
            utils_run_for_dir "/usr/local" mkdir -p "/usr/local/bin"
        fi
    fi
    
    utils_show_status "info" "Installing phpswitch command to $destination..."
    
    # Copy this script to the destination
    local dest_dir
    dest_dir=$(dirname "$destination")
    if utils_run_for_dir "$dest_dir" cp "$0" "$destination"; then
        utils_run_for_dir "$dest_dir" chmod +x "$destination"
        utils_show_status "success" "Installation successful! You can now run 'phpswitch' from anywhere"
    else
        utils_show_status "error" "Failed to install. Try running with sudo"
        return 1
    fi
}

# Function to uninstall the system command
function cmd_uninstall_command {
    local installed_locations=()
    
    # Check common installation locations
    if [ -f "/usr/local/bin/phpswitch" ]; then
        installed_locations+=("/usr/local/bin/phpswitch")
    fi
    
    if [ -f "$HOMEBREW_PREFIX/bin/phpswitch" ]; then
        installed_locations+=("$HOMEBREW_PREFIX/bin/phpswitch")
    fi
    
    if [ ${#installed_locations[@]} -eq 0 ]; then
        utils_show_status "error" "phpswitch is not installed as a system command"
        return 1
    fi
    
    utils_show_status "info" "Found phpswitch installed at:"
    for location in "${installed_locations[@]}"; do
        printf "    - %s\n" "$location"
    done
    
    printf "  Uninstall phpswitch? (y/n) "

    if [ "$(utils_validate_yes_no "" "n")" = "y" ]; then
        for location in "${installed_locations[@]}"; do
            utils_show_status "info" "Removing $location..."
            utils_run_for_dir "$(dirname "$location")" rm "$location"
        done
        
        # Ask about config file
        if [ -f "$HOME/.phpswitch.conf" ]; then
            printf "  Remove the configuration file ~/.phpswitch.conf? (y/n) "
            if [ "$(utils_validate_yes_no "" "n")" = "y" ]; then
                rm "$HOME/.phpswitch.conf"
                utils_show_status "success" "Configuration file removed"
            fi
        fi
        
        # Ask about cache directory
        local cache_dir="$HOME/.cache/phpswitch"
        if [ -d "$cache_dir" ]; then
            printf "  Remove the cache directory? (y/n) "
            if [ "$(utils_validate_yes_no "" "n")" = "y" ]; then
                rm -rf "$cache_dir"
                utils_show_status "success" "Cache directory removed"
            fi
        fi
        
        utils_show_status "success" "phpswitch has been uninstalled successfully"
    else
        utils_show_status "info" "Uninstallation cancelled"
    fi
}

# Function to resolve a path through any chain of symlinks
function cmd_resolve_script_path {
    utils_resolve_symlinks "$1"
}

# Function to update self from the latest GitHub release.
# Fails closed: the download must match the release's published SHA-256.
function cmd_update_self {
    local repo="NavanithanS/phpswitch"

    # Find the current script's location
    local script_path
    script_path=$(command -v phpswitch 2>/dev/null || echo "$0")

    # Homebrew-managed installs must be upgraded through Homebrew
    local resolved_path
    resolved_path=$(cmd_resolve_script_path "$script_path")
    if [ -n "$HOMEBREW_PREFIX" ] && [[ "$resolved_path" == "$HOMEBREW_PREFIX/Cellar/"* ]]; then
        utils_show_status "info" "PHPSwitch is managed by Homebrew"
        printf "  Update it with:\n\n    brew upgrade phpswitch\n\n"
        return 0
    fi

    if ! command -v shasum >/dev/null 2>&1; then
        utils_show_status "error" "shasum is required to verify updates"
        return 1
    fi

    utils_show_status "info" "Checking for updates..."

    local tmp_dir
    tmp_dir=$(mktemp -d 2>/dev/null) || { utils_show_status "error" "Failed to create temp directory for update"; return 1; }

    # Look up the latest release
    if ! curl -fsSL "https://api.github.com/repos/$repo/releases/latest" -o "$tmp_dir/release.json"; then
        utils_show_status "error" "Failed to connect to GitHub. Check your internet connection."
        rm -rf "$tmp_dir"
        return 1
    fi

    local tag
    tag=$(grep -o '"tag_name": *"[^"]*"' "$tmp_dir/release.json" | head -n 1 | sed -E 's/.*"([^"]*)"$/\1/')
    if ! [[ "$tag" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        utils_show_status "error" "Could not determine the latest release version; update aborted"
        rm -rf "$tmp_dir"
        return 1
    fi

    local new_version="${tag#v}"
    local current_version="$PHPSWITCH_VERSION"

    if utils_compare_versions "$current_version" "$new_version"; then
        utils_show_status "success" "You are already using the latest version: $current_version"
        rm -rf "$tmp_dir"
        return 0
    fi

    utils_show_status "info" "New version available: $new_version (current: $current_version)"

    # Download the release asset and its checksum
    local base_url="https://github.com/$repo/releases/download/$tag"
    if ! curl -fsSL "$base_url/php-switcher.sh" -o "$tmp_dir/php-switcher.sh" || [ ! -s "$tmp_dir/php-switcher.sh" ]; then
        utils_show_status "error" "Failed to download php-switcher.sh from release $tag"
        rm -rf "$tmp_dir"
        return 1
    fi
    if ! curl -fsSL "$base_url/php-switcher.sh.sha256" -o "$tmp_dir/php-switcher.sh.sha256"; then
        utils_show_status "error" "Release $tag does not publish a checksum; refusing to update"
        printf "  Download it manually from https://github.com/%s/releases\n" "$repo"
        rm -rf "$tmp_dir"
        return 1
    fi

    # SEC-01: Verify the download against the published checksum
    local expected_sha256 actual_sha256
    expected_sha256=$(awk '{print $1; exit}' "$tmp_dir/php-switcher.sh.sha256")
    actual_sha256=$(shasum -a 256 "$tmp_dir/php-switcher.sh" | awk '{print $1}')
    if ! [[ "$expected_sha256" =~ ^[0-9a-f]{64}$ ]] || [ "$actual_sha256" != "$expected_sha256" ]; then
        utils_show_status "error" "Checksum verification failed! File may be compromised."
        printf "  Expected: %s\n" "$expected_sha256"
        printf "  Actual:   %s\n" "$actual_sha256"
        rm -rf "$tmp_dir"
        return 1
    fi

    # The verified file must be the version the release claims to be
    local downloaded_version
    downloaded_version=$(grep "^PHPSWITCH_VERSION=" "$tmp_dir/php-switcher.sh" | cut -d'"' -f2)
    if [ "$downloaded_version" != "$new_version" ]; then
        utils_show_status "error" "Downloaded script reports version '$downloaded_version', expected $new_version; update aborted"
        rm -rf "$tmp_dir"
        return 1
    fi

    # Verify the release signature against the key built into this script.
    # Without minisign, only the checksum (from the same release) is checked.
    if [ -n "$PHPSWITCH_MINISIGN_PUBKEY" ]; then
        if command -v minisign >/dev/null 2>&1; then
            if ! curl -fsSL "$base_url/php-switcher.sh.minisig" -o "$tmp_dir/php-switcher.sh.minisig"; then
                utils_show_status "error" "Release $tag is not signed; refusing to update"
                rm -rf "$tmp_dir"
                return 1
            fi
            if ! minisign -V -q -P "$PHPSWITCH_MINISIGN_PUBKEY" -m "$tmp_dir/php-switcher.sh" \
                    -x "$tmp_dir/php-switcher.sh.minisig" >/dev/null 2>&1; then
                utils_show_status "error" "Signature verification failed! File may be compromised."
                rm -rf "$tmp_dir"
                return 1
            fi
            utils_show_status "success" "Release signature verified"
        else
            utils_show_status "warning" "minisign is not installed, so only the checksum was verified"
            printf "  To also verify the release signature: brew install minisign\n"
        fi
    else
        core_debug_log "No signing key built in; verified the checksum only"
    fi

    printf "  Update to %s? (y/n) " "$new_version"
    if [ "$(utils_validate_yes_no "" "y")" = "y" ]; then
        # Create backup
        local backup_path
        backup_path="${script_path}.bak.$(date +%Y%m%d%H%M%S)"
        utils_show_status "info" "Creating backup at $backup_path..."
        cp "$script_path" "$backup_path" || { utils_show_status "error" "Failed to create backup"; rm -rf "$tmp_dir"; return 1; }

        # Install the new version
        chmod +x "$tmp_dir/php-switcher.sh"
        if [ -f "/usr/local/bin/phpswitch" ] || [ -f "$HOMEBREW_PREFIX/bin/phpswitch" ]; then
            # Update the system command
            utils_show_status "info" "Updating system command..."

            # Copy to all known installation locations
            if [ -f "/usr/local/bin/phpswitch" ]; then
                utils_run_for_dir "/usr/local/bin" cp "$tmp_dir/php-switcher.sh" "/usr/local/bin/phpswitch" || { utils_show_status "error" "Failed to update. Try with sudo"; rm -rf "$tmp_dir"; return 1; }
            fi

            if [ -f "$HOMEBREW_PREFIX/bin/phpswitch" ]; then
                utils_run_for_dir "$HOMEBREW_PREFIX/bin" cp "$tmp_dir/php-switcher.sh" "$HOMEBREW_PREFIX/bin/phpswitch" || { utils_show_status "error" "Failed to update. Try with sudo"; rm -rf "$tmp_dir"; return 1; }
            fi
        else
            # Just update the current script
            utils_run_for_dir "$(dirname "$script_path")" cp "$tmp_dir/php-switcher.sh" "$script_path" || { utils_show_status "error" "Failed to update. Try with sudo"; rm -rf "$tmp_dir"; return 1; }
        fi

        utils_show_status "success" "Updated to version $new_version"
        printf "  Please restart phpswitch to use the new version.\n"

        # Clean up
        rm -rf "$tmp_dir"
        exit 0
    else
        utils_show_status "info" "Update cancelled"
    fi

    # Clean up
    rm -rf "$tmp_dir"
}
