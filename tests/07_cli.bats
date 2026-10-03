#!/usr/bin/env bats

load helpers/common

setup() {
    common_setup
    fake_php_install php@8.1
    fake_php_install php@8.2
    fake_php_link php@8.1
    # Keep FPM out of CLI tests
    printf 'AUTO_RESTART_PHP_FPM=false\n' > "$HOME/.phpswitch.conf"
    BIN="$REPO_ROOT/php-switcher.sh"
    DEV_BIN="$REPO_ROOT/phpswitch/phpswitch.sh"
}

teardown() {
    common_teardown
}

@test "--version matches PHPSWITCH_VERSION in defaults.sh" {
    local expected
    expected=$(grep '^PHPSWITCH_VERSION=' "$REPO_ROOT/phpswitch/config/defaults.sh" | cut -d'"' -f2)
    run "$BIN" --version
    [ "$status" -eq 0 ]
    [ "$output" = "PHPSwitch version $expected" ]
}

@test "--current reports the linked version" {
    run "$BIN" --current
    [ "$status" -eq 0 ]
    [ "${lines[${#lines[@]}-1]}" = "php@8.1" ]
}

@test "dev entry point and built artifact agree on --current" {
    run "$DEV_BIN" --current
    [ "$status" -eq 0 ]
    [ "${lines[${#lines[@]}-1]}" = "php@8.1" ]
}

@test "--switch rejects an invalid version" {
    run "$BIN" --switch='8.2;id' < /dev/null
    [ "$status" -ne 0 ]
    [[ "$output" =~ "Invalid version format" ]]
}

@test "--get-project-version prints the project version" {
    mkdir -p "$HOME/app"
    echo "8.2" > "$HOME/app/.php-version"
    cd "$HOME/app"
    run "$BIN" --get-project-version
    [ "$status" -eq 0 ]
    [ "$output" = "php@8.2" ]
}

@test "--get-project-version fails outside a project" {
    cd "$HOME"
    run "$BIN" --get-project-version
    [ "$status" -ne 0 ]
}

@test "--auto-mode switches to the project version" {
    mkdir -p "$HOME/app"
    echo "8.2" > "$HOME/app/.php-version"
    cd "$HOME/app"
    run "$BIN" --auto-mode
    [ "$status" -eq 0 ]
    grep -q '^link --force php@8.2$' "$FAKE_BREW_LOG"
    [ "$(readlink "$FAKE_BREW_PREFIX/bin/php")" = "../opt/php@8.2/bin/php" ]
}

@test "--auto-mode does nothing when already on the project version" {
    mkdir -p "$HOME/app"
    echo "8.1" > "$HOME/app/.php-version"
    cd "$HOME/app"
    run "$BIN" --auto-mode
    [ "$status" -eq 0 ]
    run grep -qE '^(un)?link' "$FAKE_BREW_LOG"
    [ "$status" -ne 0 ]
}

@test "--auto-mode does not install a missing version" {
    mkdir -p "$HOME/app"
    echo "8.3" > "$HOME/app/.php-version"
    cd "$HOME/app"
    run "$BIN" --auto-mode
    [ "$status" -ne 0 ]
    run grep -qE '^(install|link)' "$FAKE_BREW_LOG"
    [ "$status" -ne 0 ]
}
