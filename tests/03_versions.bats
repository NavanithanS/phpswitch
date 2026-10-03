#!/usr/bin/env bats

setup() {
    export HOME="$(mktemp -d)"
    export PHPSWITCH_TEST_MODE=1
    export PATH="${BATS_TEST_DIRNAME}/helpers/bin:$PATH"

    source "${BATS_TEST_DIRNAME}/../phpswitch/config/defaults.sh"
    source "${BATS_TEST_DIRNAME}/../phpswitch/lib/core.sh"
    source "${BATS_TEST_DIRNAME}/../phpswitch/lib/utils.sh"
}

teardown() {
    rm -rf "$HOME"
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
