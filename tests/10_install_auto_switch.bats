#!/usr/bin/env bats

load helpers/common

FIXTURES="${BATS_TEST_DIRNAME}/fixtures"

setup() {
    common_setup
    load_modules
    fake_php_install php@8.1
    fake_php_install php@8.2
    fake_php_link php@8.1
    # init_self_path uses $0; point it at the built artifact
    init_self_path() { printf '%s\n' "$REPO_ROOT/php-switcher.sh"; }
    mkdir -p "$HOME/.config/fish"
}

teardown() {
    common_teardown
}

use_shell() {
    export SHELL="/bin/$1"
}

rc_for() {
    case "$1" in
        zsh) echo "$HOME/.zshrc" ;;
        bash) echo "$HOME/.bashrc" ;;
        fish) echo "$HOME/.config/fish/config.fish" ;;
    esac
}

sum() {
    shasum -a 256 "$1" | awk '{print $1}'
}

@test "legacy hooks in other rc files are removed too" {
    use_shell zsh
    printf 'export EDITOR=vim\n' > "$HOME/.zshrc"
    cp "$FIXTURES/legacy-32bad01-bash.rc" "$HOME/.bashrc"
    cp "$FIXTURES/legacy-bfc6fa9-bash.rc" "$HOME/.profile"
    run auto_install
    [ "$status" -eq 0 ]
    grep -qx '# PHPSwitch shell integration' "$HOME/.zshrc"
    run grep -l "phpswitch_auto_detect_project" "$HOME/.bashrc" "$HOME/.profile"
    [ "$status" -ne 0 ]
    [ -n "$(find "$HOME" -maxdepth 1 -name '.bashrc.bak.*')" ]
    [ -n "$(find "$HOME" -maxdepth 1 -name '.profile.bak.*')" ]
}

@test "one unsafe legacy block leaves every rc file unchanged" {
    use_shell zsh
    cp "$FIXTURES/legacy-32bad01-zsh.rc" "$HOME/.zshrc"
    sed '$d' "$FIXTURES/legacy-32bad01-bash.rc" > "$HOME/.bashrc"
    printf 'export AFTER=1\n' >> "$HOME/.bashrc"
    local zsh_before bash_before
    zsh_before=$(sum "$HOME/.zshrc"); bash_before=$(sum "$HOME/.bashrc")
    run auto_install
    [ "$status" -ne 0 ]
    [[ "$output" =~ ".bashrc" ]]
    [ "$(sum "$HOME/.zshrc")" = "$zsh_before" ]
    [ "$(sum "$HOME/.bashrc")" = "$bash_before" ]
}

@test "a failed target backup changes no file" {
    use_shell zsh
    printf 'export EDITOR=vim\n' > "$HOME/.zshrc"
    cp "$FIXTURES/legacy-32bad01-bash.rc" "$HOME/.bashrc"
    local zsh_before bash_before
    zsh_before=$(sum "$HOME/.zshrc"); bash_before=$(sum "$HOME/.bashrc")
    auto_backup_rc() { [ "$1" = "$HOME/.zshrc" ] && return 1; command cp "$1" "$1.bak.test"; }
    run auto_install
    [ "$status" -ne 0 ]
    [ "$(sum "$HOME/.zshrc")" = "$zsh_before" ]
    [ "$(sum "$HOME/.bashrc")" = "$bash_before" ]
}

@test "unsupported login shell changes nothing" {
    export SHELL=/bin/tcsh
    run auto_install
    [ "$status" -ne 0 ]
    [ -z "$(find "$HOME" -maxdepth 1 -name '.*rc*')" ]
}

@test "fresh install adds the integration line once" {
    use_shell zsh
    printf 'export EDITOR=vim\n' > "$HOME/.zshrc"
    run auto_install
    [ "$status" -eq 0 ]
    grep -qx 'export EDITOR=vim' "$HOME/.zshrc"
    grep -qx '# PHPSwitch shell integration' "$HOME/.zshrc"
    grep -qF "init zsh)\"" "$HOME/.zshrc"
    local before
    before=$(sum "$HOME/.zshrc")
    run auto_install
    [ "$status" -eq 0 ]
    [[ "$output" =~ "already set up" ]]
    [ "$(sum "$HOME/.zshrc")" = "$before" ]
}

@test "legacy blocks from every released installer are migrated" {
    local fixture sh rc target
    for fixture in "$FIXTURES"/legacy-*.rc; do
        sh=$(basename "$fixture" .rc); sh=${sh##*-}
        use_shell "$sh"
        rc=$(rc_for "$sh")
        cp "$fixture" "$rc"
        printf 'alias after_block=1\n' >> "$rc"

        run auto_install
        [ "$status" -eq 0 ] || { echo "failed for $fixture: $output"; return 1; }
        run grep -c "phpswitch_auto_detect_project" "$rc"
        [ "$output" = "0" ] || { echo "legacy hook left in $fixture"; return 1; }
        grep -q 'EDITOR' "$rc"
        grep -qx 'alias after_block=1' "$rc"
        # macOS bash: a .bashrc nothing loads gets no integration line;
        # it goes to the login file instead
        target=$(auto_rc_file "$sh")
        grep -qx '# PHPSwitch shell integration' "$target"
        rm -f "$rc" "$rc".bak.* "$target"
    done
}

@test "migration keeps a backup identical to the original" {
    use_shell zsh
    cp "$FIXTURES/legacy-32bad01-zsh.rc" "$HOME/.zshrc"
    local original
    original=$(sum "$HOME/.zshrc")
    run auto_install
    [ "$status" -eq 0 ]
    local backup
    backup=$(find "$HOME" -maxdepth 1 -name '.zshrc.bak.*' | head -n 1)
    [ -n "$backup" ]
    [ "$(sum "$backup")" = "$original" ]
}

@test "migration preserves user content around the block exactly" {
    use_shell bash
    { printf 'line one\n'; cat "$FIXTURES/legacy-32bad01-bash.rc"; printf 'line after\n'; } > "$HOME/.bashrc"
    run auto_install
    [ "$status" -eq 0 ]
    # Expected: original minus the legacy block (and its blank separator), plus the integration block
    run awk '/^# PHPSwitch shell integration$/{exit} {print}' "$HOME/.bashrc"
    [ "$output" = "$(printf 'line one\nexport EDITOR=vim\nline after\n')" ]
}

@test "v1.4.0 block without a reliable end is left byte-identical" {
    use_shell zsh
    cat > "$HOME/.zshrc" <<'RC'
export EDITOR=vim

# PHPSwitch auto-switching hooks
function phpswitch_auto_detect_project() {
    phpswitch --auto-mode
}
autoload -U add-zsh-hook
add-zsh-hook chpwd phpswitch_auto_detect_project
RC
    local before
    before=$(sum "$HOME/.zshrc")
    run auto_install
    [ "$status" -ne 0 ]
    [[ "$output" =~ "can't be removed automatically" ]]
    [ "$(sum "$HOME/.zshrc")" = "$before" ]
}

@test "legacy block with a missing end anchor is left byte-identical" {
    use_shell zsh
    sed '$d' "$FIXTURES/legacy-32bad01-zsh.rc" > "$HOME/.zshrc"
    printf 'export AFTER=1\n' >> "$HOME/.zshrc"
    local before
    before=$(sum "$HOME/.zshrc")
    run auto_install
    [ "$status" -ne 0 ]
    [ "$(sum "$HOME/.zshrc")" = "$before" ]
}

@test "migrating twice changes nothing the second time" {
    use_shell fish
    cp "$FIXTURES/legacy-bfc6fa9-fish.rc" "$HOME/.config/fish/config.fish"
    run auto_install
    [ "$status" -eq 0 ]
    local after_first
    after_first=$(sum "$HOME/.config/fish/config.fish")
    run auto_install
    [ "$status" -eq 0 ]
    [ "$(sum "$HOME/.config/fish/config.fish")" = "$after_first" ]
}

@test "a symlinked rc file stays a symlink" {
    use_shell zsh
    mkdir -p "$HOME/dotfiles"
    cp "$FIXTURES/legacy-32bad01-zsh.rc" "$HOME/dotfiles/zshrc"
    ln -s "$HOME/dotfiles/zshrc" "$HOME/.zshrc"
    run auto_install
    [ "$status" -eq 0 ]
    [ -L "$HOME/.zshrc" ]
    grep -qx '# PHPSwitch shell integration' "$HOME/dotfiles/zshrc"
}

@test "migration removes the legacy directory cache" {
    use_shell zsh
    mkdir -p "$HOME/.cache/phpswitch"
    echo "/tmp:php@8.1" > "$HOME/.cache/phpswitch/directory_cache.txt"
    cp "$FIXTURES/legacy-32bad01-zsh.rc" "$HOME/.zshrc"
    run auto_install
    [ "$status" -eq 0 ]
    [ ! -f "$HOME/.cache/phpswitch/directory_cache.txt" ]
}

@test "bash without .bashrc uses .bash_profile" {
    use_shell bash
    printf 'export A=1\n' > "$HOME/.bash_profile"
    run auto_install
    [ "$status" -eq 0 ]
    grep -qx '# PHPSwitch shell integration' "$HOME/.bash_profile"
    [ ! -f "$HOME/.bashrc" ]
}

@test "installed rc line activates per-shell switching in a real zsh" {
    use_shell zsh
    cp "$FIXTURES/legacy-32bad01-zsh.rc" "$HOME/.zshrc"
    run auto_install
    [ "$status" -eq 0 ]
    mkdir -p "$HOME/app"
    echo "8.2" > "$HOME/app/.php-version"
    run env -i HOME="$HOME" FAKE_BREW_PREFIX="$FAKE_BREW_PREFIX" FAKE_BREW_LIST="$FAKE_BREW_LIST" \
        PATH="$FAKE_BREW_PREFIX/bin:${BATS_TEST_DIRNAME}/helpers/bin:/usr/bin:/bin" \
        zsh -f -c 'source "$HOME/.zshrc"; cd "$HOME/app"; php -v; cd "$HOME"; php -v'
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "PHP 8.2.0 (cli)" ]
    [ "${lines[1]}" = "PHP 8.1.0 (cli)" ]
}

@test "--install-auto-switch targets the login shell's rc file, not bash" {
    printf 'AUTO_RESTART_PHP_FPM=false\n' > "$HOME/.phpswitch.conf"
    run env SHELL=/bin/zsh "$REPO_ROOT/php-switcher.sh" --install-auto-switch
    [ "$status" -eq 0 ]
    grep -qx '# PHPSwitch shell integration' "$HOME/.zshrc"
    [ ! -f "$HOME/.bashrc" ]
    grep -q "AUTO_SWITCH_PHP_VERSION=\"true\"" "$HOME/.phpswitch.conf"
}
