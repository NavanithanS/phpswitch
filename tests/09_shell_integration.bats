#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load helpers/common

setup() {
    common_setup
    fake_php_install php@8.1
    fake_php_install php@8.2
    fake_php_install php@8.3
    fake_php_link php@8.1
    BIN="$REPO_ROOT/php-switcher.sh"
    PROJECT="$HOME/project"
    mkdir -p "$PROJECT/src/deep" "$HOME/other"
    # Minimal PATH for the shells under test: global php + fake brew + system
    BASE_PATH="$FAKE_BREW_PREFIX/bin:${BATS_TEST_DIRNAME}/helpers/bin:/usr/bin:/bin:/usr/sbin:/sbin"
}

teardown() {
    common_teardown
}

# run_shell <bash|zsh> <script>  -- evals the integration first, in a clean shell
run_shell() {
    local shell="$1" script="$2" init
    init=$("$BIN" init "$shell")
    case "$shell" in
        bash) run env -i HOME="$HOME" PATH="$BASE_PATH" FAKE_BREW_PREFIX="$FAKE_BREW_PREFIX" \
                  FAKE_BREW_LIST="$FAKE_BREW_LIST" FAKE_BREW_LOG="$FAKE_BREW_LOG" \
                  /bin/bash --norc --noprofile -c "cd \"\$HOME\"; $init
$script" ;;
        zsh)  run env -i HOME="$HOME" PATH="$BASE_PATH" FAKE_BREW_PREFIX="$FAKE_BREW_PREFIX" \
                  FAKE_BREW_LIST="$FAKE_BREW_LIST" FAKE_BREW_LOG="$FAKE_BREW_LOG" \
                  zsh -f -c "cd \"\$HOME\"; $init
$script" ;;
    esac
}

# --- generated code -------------------------------------------------------

@test "init output is valid bash and zsh with no banner" {
    run "$BIN" init bash
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "# phpswitch shell integration (bash)" ]
    printf '%s\n' "$output" | /bin/bash -n
    run "$BIN" init zsh
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "# phpswitch shell integration (zsh)" ]
    printf '%s\n' "$output" | zsh -n
}

@test "init output is valid fish" {
    command -v fish >/dev/null || skip "fish not installed"
    run "$BIN" init fish
    [ "$status" -eq 0 ]
    printf '%s\n' "$output" | fish -n
}

@test "init embeds absolute binary path and prefix" {
    run "$BIN" init zsh
    [[ "$output" == *"export PHPSWITCH_BIN='$BIN'"* ]]
    [[ "$output" == *"export PHPSWITCH_PREFIX='$FAKE_BREW_PREFIX'"* ]]
}

@test "init rejects an unsupported shell" {
    run "$BIN" init tcsh
    [ "$status" -ne 0 ]
}

@test "init is fast enough for shell startup" {
    local start end
    start=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
    "$BIN" init zsh > /dev/null
    end=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
    perl -e "exit(($end - $start) < 1.0 ? 0 : 1)"
}

# --- __php-dir ------------------------------------------------------------

@test "__php-dir prints the opt dir for an installed version" {
    run "$BIN" __php-dir 8.2
    [ "$status" -eq 0 ]
    [ "$output" = "$FAKE_BREW_PREFIX/opt/php@8.2" ]
}

@test "__php-dir fails for a missing version with the message on stderr only" {
    run --separate-stderr "$BIN" __php-dir 7.4
    [ "$status" -ne 0 ]
    [ -z "$output" ]
    [[ "$stderr" =~ "not installed" ]]
}

@test "__php-dir rejects malicious input without printing a path" {
    run --separate-stderr "$BIN" __php-dir '8.2;touch /tmp/pwned'
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

@test "__php-dir without a version resolves the project" {
    echo "8.3" > "$PROJECT/.php-version"
    cd "$PROJECT/src"
    run "$BIN" __php-dir
    [ "$output" = "$FAKE_BREW_PREFIX/opt/php@8.3" ]
}

@test "use without shell integration explains how to enable it" {
    run "$BIN" use 8.2
    [ "$status" -ne 0 ]
    [[ "$output" =~ "phpswitch init" ]]
}

# --- hook behaviour in real shells -----------------------------------------

@test "bash 3.2: cd into a project selects its PHP, leaving restores global" {
    echo "8.2" > "$PROJECT/.php-version"
    run_shell bash '
        cd "$HOME/project/src"; _phpswitch_hook; php -v
        cd "$HOME/other"; _phpswitch_hook; php -v'
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "PHP 8.2.0 (cli)" ]
    [ "${lines[1]}" = "PHP 8.1.0 (cli)" ]
}

@test "zsh: chpwd hook switches on cd without manual calls" {
    echo "8.3" > "$PROJECT/.php-version"
    run_shell zsh '
        cd "$HOME/project"; php -v
        cd "$HOME/other"; php -v'
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "PHP 8.3.0 (cli)" ]
    [ "${lines[1]}" = "PHP 8.1.0 (cli)" ]
}

@test "PATH does not grow across many directory changes" {
    echo "8.2" > "$PROJECT/.php-version"
    echo "8.3" > "$HOME/other/.php-version"
    for sh in bash zsh; do
        run_shell "$sh" '
            before=$(printf "%s" "$PATH" | tr ":" "\n" | grep -c .)
            for i in 1 2 3 4 5 6 7 8 9 10; do
                cd "$HOME/project"; _phpswitch_hook
                cd "$HOME/other"; _phpswitch_hook
                cd "$HOME"; _phpswitch_hook
            done
            after=$(printf "%s" "$PATH" | tr ":" "\n" | grep -c .)
            echo "$before $after"'
        [ "$status" -eq 0 ]
        set -- $output
        [ "$1" = "$2" ]
    done
}

@test "nested shell inheriting the state does not duplicate PATH entries" {
    echo "8.2" > "$PROJECT/.php-version"
    "$BIN" init bash > "$TEST_ROOT/init.bash"
    # Outer shell activates the project, then a child shell re-runs the rc line
    run_shell bash '
        cd "$HOME/project"; _phpswitch_hook
        /bin/bash --norc --noprofile -c "
            . \"$HOME/../init.bash\"
            _phpswitch_hook
            printf \"%s\" \"\$PATH\" | tr \":\" \"\\n\" | grep -c \"opt/php@8.2/bin\"
            php -v"'
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "1" ]
    [ "${lines[1]}" = "PHP 8.2.0 (cli)" ]
}

@test "use pins a version until 'use auto'" {
    echo "8.2" > "$PROJECT/.php-version"
    for sh in bash zsh; do
        run_shell "$sh" '
            cd "$HOME/project"; _phpswitch_hook
            phpswitch use 8.3; php -v
            cd "$HOME/other"; _phpswitch_hook; php -v
            cd "$HOME/project"; phpswitch use auto; php -v'
        [ "$status" -eq 0 ]
        [ "${lines[0]}" = "phpswitch: this shell now uses php@8.3 (until 'phpswitch use auto')" ]
        [ "${lines[1]}" = "PHP 8.3.0 (cli)" ]
        [ "${lines[2]}" = "PHP 8.3.0 (cli)" ]
        [ "${lines[3]}" = "phpswitch: following project files again (now php@8.2)" ]
        [ "${lines[4]}" = "PHP 8.2.0 (cli)" ]
    done
}

@test "use with a missing version fails and leaves PATH alone" {
    run_shell bash '
        before="$PATH"
        phpswitch use 7.4 && echo "unexpected success"
        [ "$PATH" = "$before" ] && echo "path unchanged"'
    [[ "$output" =~ "not installed" ]]
    [[ "$output" =~ "path unchanged" ]]
    [[ ! "$output" =~ "unexpected success" ]]
}

@test "hook never performs a global switch, even when delegating to the binary" {
    printf '{ "require": { "php": "^8.2" } }\n' > "$PROJECT/composer.json"
    run_shell zsh 'cd "$HOME/project"; php -v'
    [ "${lines[0]}" = "PHP 8.2.0 (cli)" ]
    # the binary did run (it asked brew for the prefix)...
    grep -q -- '--prefix' "$FAKE_BREW_LOG"
    # ...but never linked or unlinked anything
    run grep -E '^(un)?link' "$FAKE_BREW_LOG"
    [ "$status" -ne 0 ]
    [ "$(readlink "$FAKE_BREW_PREFIX/bin/php")" = "../opt/php@8.1/bin/php" ]
}

# --- parity with version_check_project --------------------------------------

# Expected opt dir via the binary's own resolution
expected_dir() {
    (cd "$1" && "$BIN" __php-dir 2>/dev/null) || true
}

hook_dir() {
    run_shell bash "cd \"$1\"; _phpswitch_hook; printf '%s' \"\${PHPSWITCH_PHP_DIR:-}\""
    printf '%s' "$output"
}

@test "hook agrees with version_check_project across project layouts" {
    # closest .php-version wins
    echo "8.1" > "$PROJECT/.php-version"
    echo "8.3" > "$PROJECT/src/.php-version"
    [ "$(hook_dir "$PROJECT/src/deep")" = "$(expected_dir "$PROJECT/src/deep")" ]
    rm "$PROJECT/src/.php-version" "$PROJECT/.php-version"

    # closer composer.json beats a .php-version higher up
    echo "8.1" > "$PROJECT/.php-version"
    printf '{ "require": { "php": "^8.3" } }\n' > "$PROJECT/src/composer.json"
    [ "$(hook_dir "$PROJECT/src/deep")" = "$FAKE_BREW_PREFIX/opt/php@8.3" ]
    [ "$(expected_dir "$PROJECT/src/deep")" = "$FAKE_BREW_PREFIX/opt/php@8.3" ]
    rm "$PROJECT/src/composer.json" "$PROJECT/.php-version"

    # composer range resolves to the lowest installed match (8.1 isn't >= 8.2)
    printf '{ "require": { "php": ">=8.2 <8.4" } }\n' > "$PROJECT/composer.json"
    [ "$(hook_dir "$PROJECT")" = "$FAKE_BREW_PREFIX/opt/php@8.2" ]
    [ "$(expected_dir "$PROJECT")" = "$FAKE_BREW_PREFIX/opt/php@8.2" ]
    rm "$PROJECT/composer.json"

    # .tool-versions
    printf 'php 8.2.4\n' > "$PROJECT/.tool-versions"
    [ "$(hook_dir "$PROJECT")" = "$FAKE_BREW_PREFIX/opt/php@8.2" ]
    rm "$PROJECT/.tool-versions"

    # major-only resolves to highest installed minor
    echo "8" > "$PROJECT/.php-version"
    [ "$(hook_dir "$PROJECT")" = "$FAKE_BREW_PREFIX/opt/php@8.3" ]
    [ "$(expected_dir "$PROJECT")" = "$FAKE_BREW_PREFIX/opt/php@8.3" ]

    # php@ prefix and whitespace
    printf '  php@8.2 \n' > "$PROJECT/.php-version"
    [ "$(hook_dir "$PROJECT")" = "$(expected_dir "$PROJECT")" ]

    # not installed -> no per-shell override
    echo "7.4" > "$PROJECT/.php-version"
    [ -z "$(hook_dir "$PROJECT")" ]
    [ -z "$(expected_dir "$PROJECT")" ]

    # unsafe content -> none
    echo '8.2;id' > "$PROJECT/.php-version"
    [ -z "$(hook_dir "$PROJECT")" ]
}

@test "wrapper works in shells with nounset enabled" {
    for sh in bash zsh; do
        run_shell "$sh" 'set -u; phpswitch use 8.2; php -v; phpswitch use; echo "rc=$?"; cd /; phpswitch use auto'
        [ "${lines[1]}" = "PHP 8.2.0 (cli)" ]
        [[ "$output" =~ "following project files again (now global PHP)" ]]
        [[ "$output" =~ "usage: phpswitch use" ]]
        [[ "$output" =~ "rc=1" ]]
    done
}

@test "local only accepts X.Y versions and writes .php-version" {
    cd "$HOME/project"
    run "$BIN" local default
    [ "$status" -ne 0 ]
    [ ! -f .php-version ]
    run "$BIN" local 8.2 <<< "y"
    [ "$status" -eq 0 ]
    [ "$(cat .php-version)" = "8.2" ]
}

@test "re-sourcing the rc inside a project keeps the project's PHP" {
    echo "8.2" > "$PROJECT/.php-version"
    for sh in bash zsh; do
        run_shell "$sh" '
            cd "$HOME/project"; _phpswitch_hook; php -v
            # what the global PATH block does when the rc is sourced again
            PATH="$PHPSWITCH_PREFIX/opt/php@8.1/bin:$PATH"
            eval "$("$PHPSWITCH_BIN" init '"$sh"')"; php -v'
        [ "$status" -eq 0 ]
        [ "${lines[0]}" = "PHP 8.2.0 (cli)" ]
        [ "${lines[1]}" = "PHP 8.2.0 (cli)" ] || { echo "$sh: $output"; return 1; }
    done
}

@test "init finds Homebrew when brew is not on PATH" {
    run env -i HOME="$HOME" PATH=/usr/bin:/bin FAKE_BREW_PREFIX="$FAKE_BREW_PREFIX" \
        PHPSWITCH_BREW_CANDIDATES="$TEST_ROOT/none/brew ${BATS_TEST_DIRNAME}/helpers/bin/brew" \
        "$BIN" init zsh
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "# phpswitch shell integration (zsh)" ]
    [[ "$output" == *"export PHPSWITCH_PREFIX='$FAKE_BREW_PREFIX'"* ]]
}

@test "valid_dir rejects paths that climb out of the prefix" {
    run_shell bash '
        mkdir -p "$PHPSWITCH_PREFIX/opt/php@8.1/../../escape/bin"
        _phpswitch_valid_dir "$PHPSWITCH_PREFIX/opt/php@8.1/../../escape" && echo accepted || echo rejected'
    [ "$output" = "rejected" ]
}
