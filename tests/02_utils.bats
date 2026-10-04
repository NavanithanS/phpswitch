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

@test "replace_file_contents keeps symlinks and file mode" {
    mkdir -p "$HOME/dotfiles"
    printf 'old\n' > "$HOME/dotfiles/rc"
    chmod 640 "$HOME/dotfiles/rc"
    ln -s dotfiles/rc "$HOME/.rc"
    printf 'new\n' > "$HOME/src"
    run utils_replace_file_contents "$HOME/.rc" "$HOME/src"
    [ "$status" -eq 0 ]
    [ -L "$HOME/.rc" ]
    [ "$(cat "$HOME/dotfiles/rc")" = "new" ]
    [ "$(stat -f '%Lp' "$HOME/dotfiles/rc")" = "640" ]
}

@test "replace_file_contents leaves the target intact when the source can't be read" {
    printf 'keep\n' > "$HOME/rc"
    run utils_replace_file_contents "$HOME/rc" "$HOME/missing"
    [ "$status" -ne 0 ]
    [ "$(cat "$HOME/rc")" = "keep" ]
    [ -z "$(find "$HOME" -name '.phpswitch.*')" ]
}
