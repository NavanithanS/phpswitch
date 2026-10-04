#!/usr/bin/env bats

load helpers/common

BEGIN_MARKER="# BEGIN PHPSWITCH MANAGED BLOCK - DO NOT EDIT MANUALLY"

setup() {
    common_setup
    load_modules
}

teardown() {
    common_teardown
}

# Force a shell type regardless of the shell bats runs in
use_shell() {
    eval "shell_detect_shell() { echo $1; }"
}

update_rc() {
    local instructions
    instructions=$(shell_update_rc "$1" | tail -n 1)
    rm -f "$instructions"
}

@test "rc file is created for each shell when missing" {
    run shell_get_rc_file zsh
    [ "$output" = "$HOME/.zshrc" ]
    [ -f "$HOME/.zshrc" ]
    run shell_get_rc_file bash
    [ "$output" = "$HOME/.bash_profile" ]
    [ -f "$HOME/.bash_profile" ]
    run shell_get_rc_file fish
    [ "$output" = "$HOME/.config/fish/config.fish" ]
    [ -f "$HOME/.config/fish/config.fish" ]
}

@test "bash falls back to .bash_profile when .bashrc is absent" {
    touch "$HOME/.bash_profile"
    run shell_get_rc_file bash
    [ "$output" = "$HOME/.bash_profile" ]
}

@test "zsh: managed block is added and existing content preserved" {
    use_shell zsh
    printf 'alias ll="ls -la"\n' > "$HOME/.zshrc"
    update_rc php@8.2
    grep -qF "$BEGIN_MARKER" "$HOME/.zshrc"
    grep -qF "export PATH=\"$FAKE_BREW_PREFIX/opt/php@8.2/bin:$FAKE_BREW_PREFIX/opt/php@8.2/sbin:\$PATH\"" "$HOME/.zshrc"
    grep -qF 'alias ll="ls -la"' "$HOME/.zshrc"
}

@test "zsh: switching twice replaces the block instead of duplicating it" {
    use_shell zsh
    printf 'before\n' > "$HOME/.zshrc"
    update_rc php@8.1
    printf 'after\n' >> "$HOME/.zshrc"
    update_rc php@8.3
    [ "$(grep -cF "$BEGIN_MARKER" "$HOME/.zshrc")" -eq 1 ]
    grep -qF "opt/php@8.3/bin" "$HOME/.zshrc"
    run grep -qF "opt/php@8.1/bin" "$HOME/.zshrc"
    [ "$status" -ne 0 ]
    grep -qx 'before' "$HOME/.zshrc"
    grep -qx 'after' "$HOME/.zshrc"
}

@test "php@default maps to the unversioned php prefix" {
    use_shell bash
    touch "$HOME/.bash_profile"
    update_rc php@default
    grep -qF "$FAKE_BREW_PREFIX/opt/php/bin" "$HOME/.bash_profile"
}

@test "fish: block uses fish syntax" {
    use_shell fish
    update_rc php@8.2
    local rc="$HOME/.config/fish/config.fish"
    grep -qF "set -gx PATH $FAKE_BREW_PREFIX/opt/php@8.2/bin" "$rc"
    run grep -q '^export PATH' "$rc"
    [ "$status" -ne 0 ]
}

@test "detection prefers the login shell over the shell phpswitch runs in" {
    SHELL=/bin/zsh run shell_detect_shell
    [ "$output" = "zsh" ]
    SHELL=/opt/homebrew/bin/fish run shell_detect_shell
    [ "$output" = "fish" ]
}

@test "updating a symlinked rc file keeps the symlink" {
    use_shell zsh
    mkdir -p "$HOME/dotfiles"
    printf 'alias ll="ls -la"\n' > "$HOME/dotfiles/zshrc"
    ln -s "$HOME/dotfiles/zshrc" "$HOME/.zshrc"
    update_rc php@8.2
    [ -L "$HOME/.zshrc" ]
    grep -qF "opt/php@8.2/bin" "$HOME/dotfiles/zshrc"
    grep -qF 'alias ll="ls -la"' "$HOME/dotfiles/zshrc"
}

@test "global switch writes the PATH block to the login shell's rc file" {
    SHELL=/bin/zsh
    export SHELL
    unset -f shell_detect_shell
    source "$REPO_ROOT/phpswitch/lib/shell.sh"
    touch "$HOME/.zshrc"
    update_rc php@8.2
    grep -qF "opt/php@8.2/bin" "$HOME/.zshrc"
    [ ! -f "$HOME/.bashrc" ]
}

@test "a backup is created before modifying the rc file" {
    use_shell zsh
    printf 'original\n' > "$HOME/.zshrc"
    update_rc php@8.2
    local backups
    backups=$(find "$HOME" -maxdepth 1 -name '.zshrc.bak.*' | wc -l | tr -d ' ')
    [ "$backups" -ge 1 ]
}

@test "no backup when BACKUP_CONFIG_FILES=false" {
    use_shell zsh
    BACKUP_CONFIG_FILES=false
    printf 'original\n' > "$HOME/.zshrc"
    update_rc php@8.2
    [ -z "$(find "$HOME" -maxdepth 1 -name '.zshrc.bak.*')" ]
}

@test "updating the rc block to the same version is a no-op" {
    use_shell zsh
    printf 'export A=1\n' > "$HOME/.zshrc"
    update_rc php@8.2
    local before backups
    before=$(shasum -a 256 "$HOME/.zshrc" | awk '{print $1}')
    backups=$(find "$HOME" -maxdepth 1 -name '.zshrc.bak.*' | wc -l)
    update_rc php@8.2
    [ "$(shasum -a 256 "$HOME/.zshrc" | awk '{print $1}')" = "$before" ]
    [ "$(find "$HOME" -maxdepth 1 -name '.zshrc.bak.*' | wc -l)" = "$backups" ]
    update_rc php@8.1
    grep -qF "opt/php@8.1/bin" "$HOME/.zshrc"
}

@test "same-version check only trusts the managed block itself" {
    use_shell zsh
    printf 'export A=1\n' > "$HOME/.zshrc"
    update_rc php@8.4
    # a stray copy of a header line outside the block must not count
    printf '# Path configuration for PHP version: php@8.1\n' >> "$HOME/.zshrc"
    update_rc php@8.1
    run awk '/^# BEGIN PHPSWITCH/,/^# END PHPSWITCH/' "$HOME/.zshrc"
    [[ "$output" =~ "opt/php@8.1/bin" ]]
}

# --- bash startup file selection (macOS login shells skip .bashrc) ---------

# fake_uname <name>: make `uname -s` report <name>
fake_uname() {
    mkdir -p "$TEST_ROOT/uname-bin"
    printf '#!/bin/sh\necho %s\n' "$1" > "$TEST_ROOT/uname-bin/uname"
    chmod +x "$TEST_ROOT/uname-bin/uname"
    PATH="$TEST_ROOT/uname-bin:$PATH"
}

@test "macOS bash: .bashrc alone is not read, so .bash_profile is used" {
    fake_uname Darwin
    touch "$HOME/.bashrc"
    run shell_bash_rc_file ""
    [ "$output" = "$HOME/.bash_profile" ]
}

@test "macOS bash: .bash_profile that sources .bashrc selects .bashrc" {
    fake_uname Darwin
    touch "$HOME/.bashrc"
    printf 'export A=1\n[ -f ~/.bashrc ] && . ~/.bashrc\n' > "$HOME/.bash_profile"
    run shell_bash_rc_file ""
    [ "$output" = "$HOME/.bashrc" ]
    printf 'source "$HOME/.bashrc"\n' > "$HOME/.bash_profile"
    run shell_bash_rc_file ""
    [ "$output" = "$HOME/.bashrc" ]
}

@test "macOS bash: a commented-out .bashrc source does not count" {
    fake_uname Darwin
    touch "$HOME/.bashrc"
    printf '# . ~/.bashrc\n' > "$HOME/.bash_profile"
    run shell_bash_rc_file ""
    [ "$output" = "$HOME/.bash_profile" ]
}

@test "macOS bash: existing .bash_login or .profile is never shadowed" {
    fake_uname Darwin
    touch "$HOME/.bashrc" "$HOME/.profile"
    run shell_bash_rc_file ""
    [ "$output" = "$HOME/.profile" ]
    touch "$HOME/.bash_login"
    run shell_bash_rc_file ""
    [ "$output" = "$HOME/.bash_login" ]
    [ ! -e "$HOME/.bash_profile" ]
}

@test "bash: a file that already has phpswitch's content is kept" {
    fake_uname Darwin
    printf '%s\n' "$BEGIN_MARKER" > "$HOME/.bashrc"
    touch "$HOME/.bash_profile"
    run shell_bash_rc_file "# BEGIN PHPSWITCH MANAGED BLOCK"
    [ "$output" = "$HOME/.bashrc" ]
}

@test "non-macOS bash keeps the .bashrc-first order" {
    fake_uname Linux
    touch "$HOME/.bashrc" "$HOME/.bash_profile"
    run shell_bash_rc_file ""
    [ "$output" = "$HOME/.bashrc" ]
    rm "$HOME/.bashrc"
    run shell_bash_rc_file ""
    [ "$output" = "$HOME/.bash_profile" ]
}

@test "existing integration line in .bashrc is found again, not duplicated" {
    fake_uname Darwin
    use_shell bash
    printf '\n# PHPSwitch shell integration\n[ -x /x ] && eval "$(/x init bash)"\n' > "$HOME/.bashrc"
    touch "$HOME/.bash_profile"
    run auto_rc_file bash
    [ "$output" = "$HOME/.bashrc" ]
    run auto_install
    [ "$status" -eq 0 ]
    [[ "$output" == *"already set up"* ]]
    run grep -c '# PHPSwitch shell integration' "$HOME/.bash_profile"
    [ "$output" = "0" ]
}
