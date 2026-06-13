#!/usr/bin/env bats

setup() {
    export HOME="$(mktemp -d)"
    export PHPSWITCH_TEST_MODE=1
    
    # Source the utils library directly for unit testing
    source "${BATS_TEST_DIRNAME}/../phpswitch/lib/utils.sh"
}

teardown() {
    rm -rf "$HOME"
}

@test "validate_version accepts valid versions" {
    run utils_validate_version "8.1"
    [ "$status" -eq 0 ]
    
    run utils_validate_version "7.4"
    [ "$status" -eq 0 ]
    
    run utils_validate_version "8.4"
    [ "$status" -eq 0 ]
    
    run utils_validate_version "default"
    [ "$status" -eq 0 ]
}

@test "validate_version rejects invalid versions" {
    run utils_validate_version "8.1.0"
    [ "$status" -eq 1 ]
    
    run utils_validate_version "8"
    [ "$status" -eq 1 ]
    
    run utils_validate_version "php8.1"
    [ "$status" -eq 1 ]
    
    run utils_validate_version "; rm -rf /"
    [ "$status" -eq 1 ]
}

@test "validate_path rejects directory traversal" {
    run utils_validate_path "/tmp/../etc/passwd"
    [ "$status" -eq 1 ]
    
    run utils_validate_path "/tmp/valid/path"
    [ "$status" -eq 0 ]
}
