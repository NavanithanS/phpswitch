#!/usr/bin/env bats

load helpers/common

setup() {
    common_setup
    fake_php_install php@8.1
    fake_php_install php@8.2
    fake_php_link php@8.1
    BIN="$REPO_ROOT/php-switcher.sh"
}

teardown() {
    common_teardown
}

# complete_bash <words...>  -- prints COMPREPLY for the last word
complete_bash() {
    "$BIN" completions bash > "$TEST_ROOT/comp.bash"
    /bin/bash --norc --noprofile -c '
        source "$1"; shift
        COMP_WORDS=("$@")
        COMP_CWORD=$(( ${#COMP_WORDS[@]} - 1 ))
        _phpswitch_complete
        printf "%s\n" "${COMPREPLY[@]}"' _ "$TEST_ROOT/comp.bash" "$@"
}

@test "completion words match --help exactly" {
    local help_words comp_words
    help_words=$("$BIN" --help | grep -oE '^ +phpswitch (--[a-z-]+=?|[a-z]+)' | awk '{print $2}' | sort -u)
    comp_words=$(bash -c "source '$REPO_ROOT/phpswitch/lib/completions.sh'; printf '%s\n' \$COMPLETION_SUBCOMMANDS \$COMPLETION_FLAGS" | sort -u)
    [ "$help_words" = "$comp_words" ] || { diff <(echo "$help_words") <(echo "$comp_words"); return 1; }
}

@test "completion scripts are valid and print no banner" {
    run "$BIN" completions bash
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "# phpswitch completions (bash)" ]
    printf '%s\n' "$output" | /bin/bash -n
    run "$BIN" completions zsh
    [ "${lines[0]}" = "# phpswitch completions (zsh); load after compinit" ]
    printf '%s\n' "$output" | zsh -n
}

@test "fish completions are valid" {
    command -v fish >/dev/null || skip "fish not installed"
    "$BIN" completions fish | fish -n
}

@test "unsupported shell is rejected" {
    run "$BIN" completions tcsh
    [ "$status" -ne 0 ]
}

@test "bash: completes subcommands" {
    run complete_bash phpswitch u
    [ "$output" = "use" ]
    run complete_bash phpswitch d
    [ "$output" = "doctor" ]
}

@test "bash: use offers auto and installed versions only" {
    run complete_bash phpswitch use ""
    [ "$output" = "$(printf 'auto\n8.1\n8.2')" ]
}

@test "bash: global and --switch= complete installed versions" {
    run complete_bash phpswitch global 8.
    [ "$output" = "$(printf '8.1\n8.2')" ]
    run complete_bash phpswitch --switch = 8.2
    [ "$output" = "8.2" ]
}

@test "bash: init completes shells" {
    run complete_bash phpswitch init z
    [ "$output" = "zsh" ]
}

@test "zsh: completion registers after compinit" {
    "$BIN" completions zsh > "$TEST_ROOT/comp.zsh"
    run env -i HOME="$HOME" PATH="/usr/bin:/bin" zsh -f -c '
        autoload -Uz compinit && compinit -u -D
        source "$1"
        print -r -- "${_comps[phpswitch]}"' _ "$TEST_ROOT/comp.zsh"
    [ "$status" -eq 0 ]
    [ "$output" = "_phpswitch_complete" ]
}

@test "completion never runs brew" {
    : > "$FAKE_BREW_LOG"
    complete_bash phpswitch use "" > /dev/null
    run grep -v -- '--prefix' "$FAKE_BREW_LOG"
    [ -z "$output" ]
}

@test "bash: completion is registered without a global nospace" {
    "$BIN" completions bash > "$TEST_ROOT/comp.bash"
    run /bin/bash --norc --noprofile -c 'source "$1"; complete -p phpswitch' _ "$TEST_ROOT/comp.bash"
    [ "$output" = "complete -F _phpswitch_complete phpswitch" ]
}
