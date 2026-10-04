#!/bin/bash
# PHPSwitch Auto-switching
# Installs per-shell integration into rc files (migrating the legacy hook)
# and keeps the legacy global auto-switch (--auto-mode) for unmigrated users

# Marker for the per-shell integration line written to rc files
AUTO_INIT_MARKER="# PHPSwitch shell integration"

# Legacy hook block (v1.4.1+): starts with this exact line and ends with the
# first following line that is exactly "phpswitch_auto_detect_project".
AUTO_LEGACY_START="# PHPSwitch auto-switching"
AUTO_LEGACY_END="phpswitch_auto_detect_project"
AUTO_LEGACY_MAX_LINES=100

# rc file used for the integration line
function auto_rc_file {
    case "$1" in
        zsh) printf '%s\n' "$HOME/.zshrc" ;;
        bash) shell_bash_rc_file "$AUTO_INIT_MARKER" ;;
        fish) printf '%s\n' "$HOME/.config/fish/config.fish" ;;
        *) return 1 ;;
    esac
}

# Back up an rc file next to itself (owner-only permissions)
function auto_backup_rc {
    local rc_file="$1"
    [ -f "$rc_file" ] || return 0
    local backup_file
    backup_file="${rc_file}.bak.$(date +%Y%m%d%H%M%S)"
    utils_validate_path "$backup_file" || return 1
    cp "$rc_file" "$backup_file" || return 1
    chmod 600 "$backup_file" 2>/dev/null
    utils_show_status "info" "Created backup at $backup_file"
}

# Print rc content with legacy hook blocks removed.
# Exit 0: blocks removed (output is the new content)
# Exit 1: no legacy block present
# Exit 2: a legacy block was found that cannot be removed safely
function auto_strip_legacy_hooks {
    local rc_file="$1"
    grep -q "phpswitch_auto_detect_project" "$rc_file" 2>/dev/null || return 1

    # v1.4.0 blocks have no reliable end anchor
    if grep -qx "# PHPSwitch auto-switching hooks" "$rc_file"; then
        return 2
    fi

    local stripped
    stripped=$(awk -v start="$AUTO_LEGACY_START" -v end_line="$AUTO_LEGACY_END" -v max="$AUTO_LEGACY_MAX_LINES" '
        { lines[NR] = $0 }
        END {
            n = 0
            i = 1
            while (i <= NR) {
                if (lines[i] == start) {
                    j = i + 1
                    while (j <= NR && j - i <= max && lines[j] != end_line) j++
                    if (j > NR || j - i > max) exit 2
                    # drop the blank separator line written before the block
                    if (n > 0 && out[n] == "") n--
                    i = j + 1
                    continue
                }
                out[++n] = lines[i]
                i++
            }
            for (k = 1; k <= n; k++) print out[k]
        }
    ' "$rc_file") || return 2

    # Anything still referencing the legacy hook is an unknown variant
    if printf '%s\n' "$stripped" | grep -q "phpswitch_auto_detect_project"; then
        return 2
    fi
    printf '%s\n' "$stripped"
}

# Integration line for an rc file, using this script's absolute path
function auto_init_line {
    local shell_type="$1" self
    self=$(init_self_path)
    case "$self" in
        *"'"*|*$'\n'*|*\\*) return 1 ;;
    esac
    if [ "$shell_type" = "fish" ]; then
        printf "test -x '%s'; and '%s' init fish | source\n" "$self" "$self"
    else
        printf "[ -x '%s' ] && eval \"\$('%s' init %s)\"\n" "$self" "$self" "$shell_type"
    fi
}

# The user's login shell, or failure when it isn't zsh/bash/fish (unlike
# shell_detect_shell, which falls back to guessing)
function auto_login_shell {
    local shell_name
    shell_name=$(basename "${SHELL:-}")
    case "$shell_name" in
        zsh|bash|fish) printf '%s\n' "$shell_name" ;;
        *) return 1 ;;
    esac
}

# Every rc file a legacy installer may have written to
function auto_legacy_rc_candidates {
    local f
    for f in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile" "$HOME/.config/fish/config.fish"; do
        [ -f "$f" ] && grep -q "phpswitch_auto_detect_project" "$f" 2>/dev/null && printf '%s\n' "$f"
    done
}

# Install per-shell integration into the login shell's rc file and remove the
# legacy global-switching hook from every rc file. Every legacy block is
# checked before anything is written: on any doubt, all files stay
# byte-identical.
function auto_install {
    local shell_type
    if ! shell_type=$(auto_login_shell); then
        utils_show_status "error" "Unsupported login shell: ${SHELL:-unknown}"
        printf "  Per-shell switching supports bash, zsh and fish.\n"
        return 1
    fi
    local rc_file
    rc_file=$(auto_rc_file "$shell_type")

    local init_line
    if ! init_line=$(auto_init_line "$shell_type"); then
        utils_show_status "error" "Cannot reference phpswitch from $rc_file: unsupported characters in its path"
        return 1
    fi

    # 1. Check every legacy block before changing anything
    local legacy_files=() unsafe_files=() f
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        legacy_files+=("$f")
        auto_strip_legacy_hooks "$f" > /dev/null
        [ $? -eq 2 ] && unsafe_files+=("$f")
    done < <(auto_legacy_rc_candidates)

    if [ ${#unsafe_files[@]} -gt 0 ]; then
        utils_show_status "error" "Found an older PHPSwitch auto-switching block that can't be removed automatically"
        for f in "${unsafe_files[@]}"; do
            printf "    %s\n" "$f"
        done
        printf "  No files were changed. Remove the block containing 'phpswitch_auto_detect_project'\n"
        printf "  by hand, then run this again. Or add this line to %s yourself:\n\n    %s\n\n" "$rc_file" "$init_line"
        return 1
    fi

    for f in "${legacy_files[@]}" "$rc_file"; do
        if [ -e "$f" ] && [ ! -w "$f" ]; then
            utils_show_status "error" "No write permission for $f; no files were changed"
            return 1
        fi
    done

    # Back up the target rc now, so a failed backup can't leave legacy hooks
    # removed without the integration line added
    local needs_init=true
    if [ -f "$rc_file" ] && grep -qF "$AUTO_INIT_MARKER" "$rc_file"; then
        needs_init=false
    fi
    local migrated=false
    for f in "${legacy_files[@]}"; do
        [ "$f" = "$rc_file" ] && migrated=true
    done
    if [ "$needs_init" = "true" ] && [ "$migrated" = "false" ]; then
        auto_backup_rc "$rc_file" || {
            utils_show_status "error" "Could not back up $rc_file; no files were changed"
            return 1
        }
    fi

    # 2. Remove legacy blocks (they relink PHP globally on every cd).
    # Atomic replace that keeps symlinked rc files and their permissions.
    local content stripped_file
    for f in "${legacy_files[@]}"; do
        content=$(auto_strip_legacy_hooks "$f") || continue
        auto_backup_rc "$f" || {
            utils_show_status "error" "Could not back up $f; leaving it unchanged"
            return 1
        }
        stripped_file=$(utils_create_secure_temp_file)
        printf '%s\n' "$content" > "$stripped_file"
        if ! utils_replace_file_contents "$f" "$stripped_file"; then
            rm -f "$stripped_file"
            utils_show_status "error" "Could not update $f; it was left unchanged"
            return 1
        fi
        rm -f "$stripped_file"
        utils_show_status "success" "Removed the legacy auto-switching hook from $f"
    done
    if [ ${#legacy_files[@]} -gt 0 ]; then
        rm -f "$HOME/.cache/phpswitch/directory_cache.txt" 2>/dev/null
    fi

    # 3. Add the integration line to the login shell's rc file
    mkdir -p "$(dirname "$rc_file")" 2>/dev/null
    if [ "$needs_init" = "false" ]; then
        utils_show_status "info" "Per-shell switching is already set up in $rc_file"
    else
        printf '\n%s\n%s\n' "$AUTO_INIT_MARKER" "$init_line" >> "$rc_file"
        utils_show_status "success" "Added per-shell switching to $rc_file"
    fi

    if [ -f "$HOME/.phpswitch.conf" ]; then
        utils_set_config_value "AUTO_SWITCH_PHP_VERSION" "true" "$HOME/.phpswitch.conf"
    fi

    printf "  Open a new terminal (or reload %s) to start using it.\n" "$rc_file"
    printf "  Each shell now follows the project's PHP version on cd; use 'phpswitch use VERSION' to pin one.\n"
    return 0
}

# Every rc file holding the integration line written by auto_install
function auto_integration_rc_files {
    local f
    for f in "$HOME/.zshrc" "$HOME/.zprofile" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile" "$HOME/.config/fish/config.fish"; do
        [ -f "$f" ] && grep -qxF "$AUTO_INIT_MARKER" "$f" 2>/dev/null && printf '%s\n' "$f"
    done
}

# Whether phpswitch's auto-switching is in any rc file (v2 line or legacy hook)
function auto_is_installed {
    [ -n "$(auto_integration_rc_files)$(auto_legacy_rc_candidates)" ]
}

# Print stdin with each integration marker, the line after it and the blank
# separator before it removed. Exit 2 (and print nothing usable) when the
# line after a marker isn't a `... init <shell>` line written by auto_install.
function auto_strip_init_lines {
    awk -v marker="$AUTO_INIT_MARKER" '
        { lines[NR] = $0 }
        END {
            n = 0
            i = 1
            while (i <= NR) {
                if (lines[i] == marker) {
                    next_line = lines[i + 1]
                    if (i + 1 > NR || next_line !~ / init (zsh|bash|fish)/ ||
                        (next_line !~ /eval/ && next_line !~ /\| source$/)) exit 2
                    if (n > 0 && out[n] == "") n--
                    i += 2
                    continue
                }
                out[++n] = lines[i]
                i++
            }
            for (k = 1; k <= n; k++) print out[k]
        }
    '
}

# Remove per-shell switching (and any legacy hook) from every rc file.
# Every file is checked before anything is written: on any doubt, all files
# stay byte-identical.
function auto_uninstall {
    local files=() f
    while IFS= read -r f; do
        [ -n "$f" ] && files+=("$f")
    done < <({ auto_integration_rc_files; auto_legacy_rc_candidates; } | awk '!seen[$0]++')

    if [ ${#files[@]} -eq 0 ]; then
        utils_show_status "info" "No PHPSwitch auto-switching found in your shell config"
        if [ -n "${PHPSWITCH_BIN:-}" ]; then
            printf "  This shell loads it from a line you added yourself; remove the\n"
            printf "  'phpswitch init' line from your shell config to turn it off.\n"
        fi
        return 0
    fi

    # 1. Build the new content of every file before changing any of them
    local new_files=() content status failed=""
    for f in "${files[@]}"; do
        if [ ! -w "$f" ]; then
            failed="$f (no write permission)"
            break
        fi
        content=$(cat "$f") || { failed="$f (unreadable)"; break; }
        if grep -q "phpswitch_auto_detect_project" "$f"; then
            content=$(auto_strip_legacy_hooks "$f")
            status=$?
            if [ $status -ne 0 ]; then
                failed="$f (older auto-switching block that can't be removed safely)"
                break
            fi
        fi
        if printf '%s\n' "$content" | grep -qxF "$AUTO_INIT_MARKER"; then
            content=$(printf '%s\n' "$content" | auto_strip_init_lines)
            status=$?
            if [ $status -ne 0 ]; then
                failed="$f (the line after '$AUTO_INIT_MARKER' isn't one phpswitch wrote)"
                break
            fi
        fi
        local tmp
        tmp=$(utils_create_secure_temp_file) || { failed="$f (no temp file)"; break; }
        printf '%s\n' "$content" > "$tmp"
        new_files+=("$tmp")
    done

    if [ -n "$failed" ]; then
        rm -f "${new_files[@]}"
        utils_show_status "error" "Can't remove auto-switching from $failed"
        printf "  No files were changed. Remove the PHPSwitch lines by hand, then run this again.\n"
        return 1
    fi

    # 2. Back up and replace
    local i
    for i in "${!files[@]}"; do
        f="${files[$i]}"
        if ! auto_backup_rc "$f"; then
            rm -f "${new_files[@]}"
            utils_show_status "error" "Could not back up $f; it was left unchanged"
            return 1
        fi
        if ! utils_replace_file_contents "$f" "${new_files[$i]}"; then
            rm -f "${new_files[@]}"
            utils_show_status "error" "Could not update $f; it was left unchanged"
            return 1
        fi
        rm -f "${new_files[$i]}"
        utils_show_status "success" "Removed auto-switching from $f"
    done
    rm -f "$HOME/.cache/phpswitch/directory_cache.txt" 2>/dev/null

    if [ -f "$HOME/.phpswitch.conf" ]; then
        utils_set_config_value "AUTO_SWITCH_PHP_VERSION" "false" "$HOME/.phpswitch.conf"
    fi

    printf "  New terminals no longer follow project PHP versions, and 'phpswitch use'\n"
    printf "  is unavailable there; 'phpswitch global VERSION' still works.\n"
    printf "  Shells that are already open keep it until they exit.\n"
    return 0
}

# Function to clear auto-switching directory cache
function auto_clear_directory_cache {
    local cache_file="$HOME/.cache/phpswitch/directory_cache.txt"
    
    if [ -f "$cache_file" ]; then
        if [ -w "$cache_file" ]; then
            rm -f "$cache_file" 2>/dev/null
            utils_show_status "success" "Directory cache cleared"
        else
            utils_show_status "warning" "No write permission for $cache_file"
            printf "  Remove it yourself with:\n    sudo rm -f \"%s\"\n" "$cache_file"
        fi
    else
        utils_show_status "info" "No directory cache found at $cache_file"
    fi
}

# Function to implement auto-switching for PHP versions
function auto_switch_php {
    local new_version="$1"
    local brew_version

    if [ "$new_version" = "php@default" ]; then
        brew_version="php"
    else
        brew_version="$new_version"
    fi

    # Unlink current PHP (skip if no version is active)
    local _current_ver
    _current_ver=$(core_get_current_php_version)
    if [ -n "$_current_ver" ] && [ "$_current_ver" != "none" ]; then
        brew unlink "$_current_ver" &>/dev/null
    fi

    if ! brew link --force "$brew_version" &>/dev/null; then
        return 1
    fi

    # Silently restart PHP-FPM if enabled
    if [ "$AUTO_RESTART_PHP_FPM" = "true" ]; then
        local service_name
        service_name=$(fpm_get_service_name "$new_version")
        # Capture once — avoids calling brew services list twice (slow) and eliminates TOCTOU
        local services_list
        services_list=$(brew services list 2>/dev/null)
        local running_services
        running_services=$(echo "$services_list" | grep -E "^php(@[0-9]\.[0-9])?" | awk '{print $1}')
        while IFS= read -r service; do
            [ -z "$service" ] && continue
            [ "$service" != "$service_name" ] && brew services stop "$service" &>/dev/null
        done <<< "$running_services"
        # awk exact field match avoids "php" matching "php@8.1" etc.
        if echo "$services_list" | awk -v svc="$service_name" '$1 == svc' | grep -q "started"; then
            brew services restart "$service_name" &>/dev/null
        else
            brew services start "$service_name" &>/dev/null
        fi
    fi

    return 0
}