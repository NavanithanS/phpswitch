#!/usr/bin/env bats

load helpers/common

setup() {
    common_setup
    load_modules
}

teardown() {
    common_teardown
}

@test "available versions are parsed from brew search output" {
    run core_get_available_php_versions
    [ "$status" -eq 0 ]
    [[ "$output" =~ php@8.1 ]]
    [[ "$output" =~ php@8.2 ]]
    [[ "$output" =~ php@8.3 ]]
    [[ "$output" =~ php@7.4 ]]
    [[ "$output" =~ php@default ]]
}

@test "available versions exclude headers, tap prefixes and status markers" {
    run core_get_available_php_versions
    [ "$status" -eq 0 ]
    [[ ! "$output" =~ "==>" ]]
    [[ ! "$output" =~ "shivammathur/" ]]
    [[ ! "$output" =~ "✔" ]]
}

@test "available versions contain no duplicates" {
    run core_get_available_php_versions
    [ "$status" -eq 0 ]
    local versions
    versions=$(printf '%s\n' "$output" | grep -Eo '^php@[0-9a-z.]+$')
    [ "$(printf '%s\n' "$versions" | sort | uniq -d)" = "" ]
}

@test "installed versions include php@default when the php formula is installed" {
    fake_php_install php@8.1
    fake_php_install php@8.2
    FAKE_BREW_LIST="$(printf '%s\nphp' "$FAKE_BREW_LIST")"
    export FAKE_BREW_LIST
    run core_get_installed_php_versions
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf 'php@8.1\nphp@8.2\nphp@default')" ]
}

@test "current version is read from the linked php binary" {
    fake_php_install php@8.1
    fake_php_link php@8.1
    run core_get_current_php_version
    [ "$output" = "php@8.1" ]
}

@test "check_php_installed reflects the opt binary" {
    fake_php_install php@8.2
    run core_check_php_installed php@8.2
    [ "$status" -eq 0 ]
    run core_check_php_installed php@8.3
    [ "$status" -ne 0 ]
}

@test "resolve maps the default formula's version to php@default" {
    mkdir -p "$FAKE_BREW_PREFIX/opt/php"
    run version_resolve_php_version php@8.4
    [ "$output" = "php@default" ]
    fake_php_install php@8.2
    run version_resolve_php_version php@8.2
    [ "$output" = "php@8.2" ]
}
