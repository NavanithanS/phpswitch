#!/usr/bin/env bats

load helpers/common

setup() {
    common_setup
    fake_php_install php@8.1
    fake_php_install php@8.2
    fake_php_link php@8.1
    printf 'AUTO_RESTART_PHP_FPM=false\n' > "$HOME/.phpswitch.conf"
    BIN="$REPO_ROOT/php-switcher.sh"
    BASE_PATH="$FAKE_BREW_PREFIX/bin:${BATS_TEST_DIRNAME}/helpers/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    export PHPSWITCH_LAUNCH_DAEMONS_DIR="$TEST_ROOT/LaunchDaemons"
    mkdir -p "$PHPSWITCH_LAUNCH_DAEMONS_DIR"
}

teardown() {
    common_teardown
}

# doctor in a clean environment; extra VAR=value pairs may be passed first
run_doctor() {
    run env -i HOME="$HOME" PWD="$PWD" SHELL=/bin/zsh PATH="${DOCTOR_PATH:-$BASE_PATH}" \
        FAKE_BREW_PREFIX="$FAKE_BREW_PREFIX" FAKE_BREW_LIST="$FAKE_BREW_LIST" FAKE_BREW_LOG="$FAKE_BREW_LOG" \
        PHPSWITCH_LAUNCH_DAEMONS_DIR="$PHPSWITCH_LAUNCH_DAEMONS_DIR" "$@" "$BIN" doctor
}

@test "healthy global setup passes" {
    run_doctor
    [ "$status" -eq 0 ]
    [[ "$output" =~ "[ok]   Installed: php@8.1 php@8.2" ]]
    [[ "$output" =~ "[ok]   Global (linked) version: php@8.1" ]]
    [[ "$output" =~ "matching the global version" ]]
    [[ "$output" =~ "No problems found" ]]
}

@test "no php on PATH fails" {
    rm "$FAKE_BREW_PREFIX/bin/php"
    run_doctor
    [ "$status" -ne 0 ]
    [[ "$output" =~ "[fail] No php found on PATH" ]]
}

@test "a conflicting php ahead on PATH is reported" {
    mkdir -p "$TEST_ROOT/mamp"
    printf '#!/bin/bash\necho "PHP 7.3.0 (cli)"\n' > "$TEST_ROOT/mamp/php"
    chmod +x "$TEST_ROOT/mamp/php"
    DOCTOR_PATH="$TEST_ROOT/mamp:$BASE_PATH" run_doctor
    [[ "$output" =~ "php on PATH is $TEST_ROOT/mamp/php (7.3.0)" ]]
    [[ "$output" =~ "Other PHP binaries on PATH: $FAKE_BREW_PREFIX/bin/php" ]]
}

@test "integration installed but not loaded, and loaded" {
    printf '\n# PHPSwitch shell integration\neval x\n' > "$HOME/.zshrc"
    run_doctor
    [[ "$output" =~ "is in $HOME/.zshrc but not loaded in this shell" ]]
    run_doctor PHPSWITCH_BIN="$BIN"
    [[ "$output" =~ "installed in $HOME/.zshrc and loaded in this shell" ]]
}

@test "missing integration and legacy hooks are reported" {
    cp "${BATS_TEST_DIRNAME}/fixtures/legacy-32bad01-bash.rc" "$HOME/.bashrc"
    run_doctor
    [[ "$output" =~ "Per-shell switching is not set up" ]]
    [[ "$output" =~ "Legacy auto-switch hook found in: $HOME/.bashrc" ]]
}

@test "per-shell expectation follows PHPSWITCH_PHP_DIR" {
    DOCTOR_PATH="$FAKE_BREW_PREFIX/opt/php@8.2/bin:$BASE_PATH" run_doctor PHPSWITCH_PHP_DIR="$FAKE_BREW_PREFIX/opt/php@8.2"
    [[ "$output" =~ "matching this shell's per-shell version" ]]
}

@test "project version that isn't installed fails" {
    mkdir -p "$HOME/app"
    echo "7.4" > "$HOME/app/.php-version"
    cd "$HOME/app"
    run_doctor
    [ "$status" -ne 0 ]
    [[ "$output" =~ "Project wants php@7.4, which isn't installed" ]]
}

@test "stale per-shell version for the project is reported" {
    mkdir -p "$HOME/app"
    echo "8.2" > "$HOME/app/.php-version"
    cd "$HOME/app"
    run_doctor PHPSWITCH_PHP_DIR="$FAKE_BREW_PREFIX/opt/php@8.1"
    [[ "$output" =~ "Project wants php@8.2 but this shell uses $FAKE_BREW_PREFIX/opt/php@8.1" ]]
}

@test "root PHP-FPM LaunchDaemon is reported" {
    touch "$PHPSWITCH_LAUNCH_DAEMONS_DIR/homebrew.mxcl.php@8.1.plist"
    run_doctor
    [[ "$output" =~ "PHP-FPM is registered to run as root: homebrew.mxcl.php@8.1" ]]
}

@test "doctor is read-only" {
    cp "${BATS_TEST_DIRNAME}/fixtures/legacy-32bad01-zsh.rc" "$HOME/.zshrc"
    local before after
    before=$(cd "$TEST_ROOT" && find home brew -print0 | sort -z | xargs -0 shasum -a 256 2>/dev/null | shasum -a 256)
    run_doctor
    after=$(cd "$TEST_ROOT" && find home brew -print0 | sort -z | xargs -0 shasum -a 256 2>/dev/null | shasum -a 256)
    [ "$before" = "$after" ]
    run grep -E '^(link|unlink|services|install|uninstall|sudo)' "$FAKE_BREW_LOG"
    [ "$status" -ne 0 ]
}
