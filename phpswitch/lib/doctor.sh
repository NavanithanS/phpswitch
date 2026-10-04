#!/bin/bash
# PHPSwitch Doctor
# Read-only health checks: no network, no sudo, no writes, no service calls.
# Exit status is non-zero when any check fails (warnings don't fail).

# Where root-run PHP-FPM LaunchDaemons live (overridable for tests)
DOCTOR_LAUNCH_DAEMONS_DIR="${PHPSWITCH_LAUNCH_DAEMONS_DIR:-/Library/LaunchDaemons}"

_doctor_failures=0
_doctor_warnings=0

function doctor_ok {
    printf "  [ok]   %s\n" "$1"
}

function doctor_warn {
    _doctor_warnings=$((_doctor_warnings + 1))
    printf "  [warn] %s\n" "$1"
    [ -n "$2" ] && printf "         -> %s\n" "$2"
    return 0
}

function doctor_fail {
    _doctor_failures=$((_doctor_failures + 1))
    printf "  [fail] %s\n" "$1"
    [ -n "$2" ] && printf "         -> %s\n" "$2"
    return 0
}

# Installed PHP opt dirs, without calling brew
function doctor_installed_dirs {
    local d
    for d in "$HOMEBREW_PREFIX"/opt/php "$HOMEBREW_PREFIX"/opt/php@*; do
        [ -x "$d/bin/php" ] && printf '%s\n' "$d"
    done
}

function doctor_php_version_of {
    "$1" -v 2>/dev/null | head -n 1 | cut -d ' ' -f 2
}

function doctor_run {
    _doctor_failures=0
    _doctor_warnings=0

    printf "\n  PHPSwitch doctor\n\n"

    # 1. Homebrew and installed versions
    local installed
    installed=$(doctor_installed_dirs)
    if [ -z "$installed" ]; then
        doctor_fail "No Homebrew PHP installed under $HOMEBREW_PREFIX/opt" "Install one with: phpswitch --install=8.3"
    else
        doctor_ok "Installed: $(printf '%s\n' "$installed" | sed "s|$HOMEBREW_PREFIX/opt/||" | tr '\n' ' ' | sed 's/ $//')"
    fi

    # 2. Global (Homebrew-linked) version
    local linked
    linked=$(core_get_current_php_version)
    if [ -z "$linked" ] || [ "$linked" = "none" ]; then
        doctor_warn "No PHP is linked globally" "Set one with: phpswitch global VERSION"
    else
        doctor_ok "Global (linked) version: $linked"
    fi

    # 3. Which php runs, and what was expected
    local active expected expected_reason
    active=$(command -v php 2>/dev/null)
    if [ -n "${PHPSWITCH_PHP_DIR:-}" ]; then
        expected="$PHPSWITCH_PHP_DIR/bin/php"
        expected_reason="this shell's per-shell version"
    else
        expected="$HOMEBREW_PREFIX/bin/php"
        expected_reason="the global version"
    fi

    if [ -z "$active" ]; then
        doctor_fail "No php found on PATH" "Open a new terminal, or run: phpswitch global VERSION"
    elif [ "$active" -ef "$expected" ]; then
        doctor_ok "php on PATH: $active ($(doctor_php_version_of "$active")), matching $expected_reason"
    else
        doctor_warn "php on PATH is $active ($(doctor_php_version_of "$active")), expected $expected for $expected_reason" \
            "Another PHP is ahead on PATH; check your shell config or remove the other install"
    fi

    # 4. Other PHP binaries on PATH (MAMP, Herd, system, ...)
    local dir others="" old_IFS="$IFS"
    IFS=:
    for dir in $PATH; do
        [ -x "$dir/php" ] || continue
        [ -n "$active" ] && [ "$dir/php" -ef "$active" ] && continue
        others="$others $dir/php"
    done
    IFS="$old_IFS"
    if [ -n "$others" ]; then
        doctor_warn "Other PHP binaries on PATH:$others" "Only the first one on PATH is used"
    fi

    # 5. Per-shell integration
    local login_shell rc_file
    if login_shell=$(auto_login_shell); then
        rc_file=$(auto_rc_file "$login_shell")
        if [ -f "$rc_file" ] && grep -qxF "$AUTO_INIT_MARKER" "$rc_file"; then
            if [ -n "${PHPSWITCH_BIN:-}" ]; then
                doctor_ok "Per-shell switching is installed in $rc_file and loaded in this shell"
            else
                doctor_warn "Per-shell switching is in $rc_file but not loaded in this shell" "Open a new terminal or run: source $rc_file"
            fi
        elif [ -n "${PHPSWITCH_BIN:-}" ]; then
            doctor_ok "Per-shell switching is loaded in this shell"
        else
            doctor_warn "Per-shell switching is not set up" "Run: phpswitch --install-auto-switch"
        fi
    else
        doctor_warn "Login shell ${SHELL:-unknown} isn't supported for per-shell switching"
    fi

    if [ -n "${PHPSWITCH_PINNED:-}" ]; then
        doctor_warn "This shell is pinned with 'phpswitch use'; project files are ignored" "Run: phpswitch use auto"
    fi

    # 6. Legacy global auto-switch hook
    local legacy
    legacy=$(auto_legacy_rc_candidates | tr '\n' ' ')
    if [ -n "$legacy" ]; then
        doctor_warn "Legacy auto-switch hook found in: $legacy" \
            "It relinks PHP globally on every cd. Run: phpswitch --install-auto-switch"
    fi

    # 6b. PHP PATH entries in rc files that phpswitch doesn't manage
    local rc unmanaged
    while IFS= read -r rc; do
        [ -f "$rc" ] || continue
        unmanaged=$(awk '
            /^# BEGIN PHPSWITCH MANAGED BLOCK/ { inside = 1; next }
            /^# END PHPSWITCH MANAGED BLOCK/   { inside = 0; next }
            !inside && /^[ \t]*(export[ \t]+PATH=|PATH=|set[ \t]+(-[a-zA-Z]+[ \t]+)*PATH[ \t]|fish_add_path[ \t])/ && /\/opt\/php/ { printf "%s%d", sep, NR; sep = "," }
        ' "$rc")
        if [ -n "$unmanaged" ]; then
            doctor_warn "PHP PATH entry not managed by phpswitch in $rc (line $unmanaged)" \
                "It pins a PHP version in every new shell; remove it if per-shell or global switching should decide"
        fi
    done < <(auto_rc_candidates)

    # 7. Project version for the current directory
    local project project_dir
    if project=$(version_check_project 2>/dev/null) && [ -n "$project" ]; then
        if project_dir=$(init_php_dir 2>/dev/null); then
            if [ -n "${PHPSWITCH_PHP_DIR:-}" ] && [ "$PHPSWITCH_PHP_DIR" != "$project_dir" ] && [ -z "${PHPSWITCH_PINNED:-}" ]; then
                doctor_warn "Project wants $project but this shell uses $PHPSWITCH_PHP_DIR" "cd out and back in, or run: phpswitch use auto"
            else
                doctor_ok "Project version: $project"
            fi
        else
            doctor_fail "Project wants $project, which isn't installed" "Install it with: phpswitch --install=${project#php@}"
        fi
    fi

    # 8. PHP-FPM running as root (left behind by 'sudo brew services')
    local plist roots=""
    for plist in "$DOCTOR_LAUNCH_DAEMONS_DIR"/homebrew.mxcl.php*.plist; do
        [ -f "$plist" ] && roots="$roots $(basename "$plist" .plist)"
    done
    if [ -n "$roots" ]; then
        doctor_warn "PHP-FPM is registered to run as root:$roots" \
            "Root services change file ownership; use the FPM menu's cleanup, then 'brew services start' without sudo"
    fi

    # 8b. Laravel Valet runs its own PHP-FPM as root and relinks PHP itself
    local valet=""
    if [ -d "$HOME/.config/valet" ]; then
        valet="$HOME/.config/valet"
    elif [ -d "$HOME/.valet" ]; then
        valet="$HOME/.valet"
    elif command -v valet >/dev/null 2>&1; then
        valet=$(command -v valet)
    fi
    if [ -n "$valet" ]; then
        doctor_warn "Laravel Valet is installed ($valet)" \
            "Change the global PHP with 'valet use VERSION' so Valet's PHP-FPM follows; 'phpswitch global' and FPM restarts don't update Valet. Per-shell 'phpswitch use' is unaffected"
    fi

    # 9. Root-owned files in PHP kegs (bounded search)
    local root_owned
    root_owned=$(find "$HOMEBREW_PREFIX/Cellar" -maxdepth 3 -path "*/Cellar/php*" -user root -print 2>/dev/null | head -n 1)
    if [ -n "$root_owned" ]; then
        doctor_warn "Root-owned files in Homebrew PHP (e.g. $root_owned)" \
            "Fix with: sudo chown -R $(id -un) $HOMEBREW_PREFIX/Cellar/php*"
    fi

    printf "\n"
    if [ "$_doctor_failures" -gt 0 ]; then
        printf "  %d problem(s), %d warning(s)\n\n" "$_doctor_failures" "$_doctor_warnings"
        return 1
    fi
    printf "  No problems found (%d warning(s))\n\n" "$_doctor_warnings"
    return 0
}
