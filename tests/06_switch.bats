#!/usr/bin/env bats

load helpers/common

setup() {
    common_setup
    load_modules
    # Isolate from FPM and live-shell side effects
    fpm_restart() { :; }
    shell_force_reload() { return 0; }
    shell_detect_shell() { echo zsh; }
    export SOURCED=true
    touch "$HOME/.zshrc"

    fake_php_install php@8.1
    fake_php_install php@8.2
    fake_php_link php@8.1
}

teardown() {
    common_teardown
}

@test "switch unlinks the current version before linking the new one" {
    run version_switch_php php@8.2 true
    [ "$status" -eq 0 ]
    local unlink_line link_line
    unlink_line=$(grep -n '^unlink php@8.1$' "$FAKE_BREW_LOG" | cut -d: -f1)
    link_line=$(grep -n '^link --force php@8.2$' "$FAKE_BREW_LOG" | cut -d: -f1)
    [ -n "$unlink_line" ]
    [ -n "$link_line" ]
    [ "$unlink_line" -lt "$link_line" ]
}

@test "switch updates the linked binary and the rc file" {
    run version_switch_php php@8.2 true
    [ "$status" -eq 0 ]
    [ "$(core_get_current_php_version)" = "php@8.2" ]
    grep -qF "opt/php@8.2/bin" "$HOME/.zshrc"
}

@test "switching to the active version does not relink" {
    run version_switch_php php@8.1 true
    [ "$status" -eq 0 ]
    run grep -E '^(un)?link' "$FAKE_BREW_LOG"
    [ "$status" -ne 0 ]
}

@test "auto_switch_php relinks without touching services when FPM restart is off" {
    AUTO_RESTART_PHP_FPM=false
    run auto_switch_php php@8.2
    [ "$status" -eq 0 ]
    grep -q '^unlink php@8.1$' "$FAKE_BREW_LOG"
    grep -q '^link --force php@8.2$' "$FAKE_BREW_LOG"
    run grep -q '^services' "$FAKE_BREW_LOG"
    [ "$status" -ne 0 ]
}
