#!/usr/bin/env bats

# Setup runs before each test
setup() {
    # Create a dummy config file in a temp directory
    export HOME="$(mktemp -d)"
    export PHPSWITCH_TEST_MODE=1
    
    # Path to the compiled script
    export PHPSWITCH_BIN="${BATS_TEST_DIRNAME}/../php-switcher.sh"
    
    if [ ! -f "$PHPSWITCH_BIN" ]; then
        skip "Compiled php-switcher.sh not found. Run build.sh first."
    fi
}

teardown() {
    rm -rf "$HOME"
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
