#!/usr/bin/env bats

load helpers/common

setup() {
    common_setup
    export PHPSWITCH_BIN="$REPO_ROOT/php-switcher.sh"

    if [ ! -f "$PHPSWITCH_BIN" ]; then
        skip "Compiled php-switcher.sh not found. Run build.sh first."
    fi
}

teardown() {
    common_teardown
}

@test "phpswitch executable exists" {
    [ -f "$PHPSWITCH_BIN" ]
    [ -x "$PHPSWITCH_BIN" ]
}

@test "phpswitch --version outputs version string" {
    run "$PHPSWITCH_BIN" --version
    [ "$status" -eq 0 ]
    [[ "${lines[0]}" =~ ^PHPSwitch\ version\ [0-9]+\.[0-9]+\.[0-9]+$ ]]
}

@test "phpswitch --help outputs usage" {
    run "$PHPSWITCH_BIN" --help
    [ "$status" -eq 0 ]
    [[ "${output}" =~ "Usage" ]]
    [[ "${output}" =~ "--switch=" ]]
}

@test "phpswitch --json outputs valid json structure" {
    run "$PHPSWITCH_BIN" --json
    [ "$status" -eq 0 ]
    [[ "${lines[0]}" == "{" ]]
    [[ "${output}" =~ "\"current\":" ]]
    [[ "${output}" =~ "\"installed\":" ]]
}
