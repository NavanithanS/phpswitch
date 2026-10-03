#!/usr/bin/env bats

load helpers/common

setup() {
    common_setup
    load_modules
    fake_php_install php@8.1
    fake_php_install php@8.2
    fake_php_link php@8.1
    printf 'AUTO_RESTART_PHP_FPM=false\n' > "$HOME/.phpswitch.conf"
    BIN="$REPO_ROOT/php-switcher.sh"
}

teardown() {
    chmod -R u+w "$TEST_ROOT" 2>/dev/null
    common_teardown
}

# Run with a hard 10s limit (macOS has no `timeout`)
run_bounded() {
    run perl -e 'alarm 10; exec @ARGV' "$@"
}

sudo_calls() {
    grep -c '^sudo ' "$FAKE_BREW_LOG" || true
}

# --- hangs ------------------------------------------------------------------

@test "no arguments without a terminal exits instead of waiting for the menu" {
    run_bounded "$BIN" < /dev/null
    [ "$status" -eq 1 ]
    [[ "$output" =~ "needs a terminal" ]]
}

@test "unknown arguments are rejected instead of opening the menu" {
    run_bounded "$BIN" --bogus < /dev/null
    [ "$status" -eq 2 ]
    [[ "$output" =~ "Unknown command or option: --bogus" ]]
}

@test "yes/no prompt on EOF answers no when there is no default" {
    run_bounded bash -c "source '$REPO_ROOT/phpswitch/lib/utils.sh'; utils_validate_yes_no '' '' < /dev/null"
    [ "$status" -eq 0 ]
    [ "$output" = "n" ]
}

@test "yes/no prompt on EOF uses the default" {
    run_bounded bash -c "source '$REPO_ROOT/phpswitch/lib/utils.sh'; utils_validate_yes_no '' 'y' < /dev/null"
    [ "$output" = "y" ]
}

@test "yes/no prompt accepts a final answer without a trailing newline" {
    run_bounded bash -c "source '$REPO_ROOT/phpswitch/lib/utils.sh'; printf 'y' | utils_validate_yes_no '' 'n'"
    [ "$output" = "y" ]
}

# --- sudo reduction --------------------------------------------------------

@test "unwritable directory cache prints a command instead of using sudo" {
    mkdir -p "$HOME/.cache/phpswitch"
    touch "$HOME/.cache/phpswitch/directory_cache.txt"
    chmod 444 "$HOME/.cache/phpswitch/directory_cache.txt"
    run auto_clear_directory_cache
    [[ "$output" =~ "sudo rm -f" ]]
    [ "$(sudo_calls)" -eq 0 ]
}

@test "unwritable cache dir falls back to an alternative without sudo" {
    mkdir -p "$TEST_ROOT/locked"
    chmod 555 "$TEST_ROOT/locked"
    run utils_ensure_cache_writable "$TEST_ROOT/locked"
    [[ "$output" =~ "sudo chown -R" ]]
    [[ "$output" =~ "alternative cache directory" ]]
    [ "$(sudo_calls)" -eq 0 ]
}

@test "manual linking fallback works without sudo" {
    export FAKE_BREW_LINK_FAIL=1
    fpm_restart() { :; }
    shell_force_reload() { return 0; }
    export SOURCED=true SHELL=/bin/zsh
    touch "$HOME/.bashrc"
    run version_switch_php php@8.2 true
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Manual linking completed" ]]
    [ "$(readlink "$FAKE_BREW_PREFIX/bin/php")" = "$FAKE_BREW_PREFIX/opt/php@8.2/bin/php" ]
    [ "$(sudo_calls)" -eq 0 ]
}

@test "FPM cleanup shows root commands and does nothing without consent" {
    export PHPSWITCH_LAUNCH_DAEMONS_DIR="$TEST_ROOT/LaunchDaemons"
    mkdir -p "$PHPSWITCH_LAUNCH_DAEMONS_DIR"
    touch "$PHPSWITCH_LAUNCH_DAEMONS_DIR/homebrew.mxcl.php@8.2.plist"
    run fpm_cleanup_service php@8.2 < /dev/null
    [[ "$output" =~ "sudo rm -f \"$PHPSWITCH_LAUNCH_DAEMONS_DIR/homebrew.mxcl.php@8.2.plist\"" ]]
    [ "$(sudo_calls)" -eq 0 ]
    [ -f "$PHPSWITCH_LAUNCH_DAEMONS_DIR/homebrew.mxcl.php@8.2.plist" ]
}

@test "FPM cleanup uses sudo only after an explicit yes" {
    export PHPSWITCH_LAUNCH_DAEMONS_DIR="$TEST_ROOT/LaunchDaemons"
    mkdir -p "$PHPSWITCH_LAUNCH_DAEMONS_DIR"
    touch "$PHPSWITCH_LAUNCH_DAEMONS_DIR/homebrew.mxcl.php@8.2.plist"
    run fpm_cleanup_service php@8.2 <<< "y"
    grep -q "^sudo rm -f $PHPSWITCH_LAUNCH_DAEMONS_DIR/homebrew.mxcl.php@8.2.plist" "$FAKE_BREW_LOG"
}

@test "explicit install actions use sudo only for unwritable directories" {
    mkdir -p "$TEST_ROOT/open" "$TEST_ROOT/closed"
    chmod 555 "$TEST_ROOT/closed"
    run utils_run_for_dir "$TEST_ROOT/open" touch "$TEST_ROOT/open/file"
    [ "$status" -eq 0 ]
    [ -f "$TEST_ROOT/open/file" ]
    [ "$(sudo_calls)" -eq 0 ]
    run utils_run_for_dir "$TEST_ROOT/closed" touch "$TEST_ROOT/closed/file"
    [ "$status" -ne 0 ]
    grep -q "^sudo touch $TEST_ROOT/closed/file" "$FAKE_BREW_LOG"
}
