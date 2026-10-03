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
    [ "$output" = "$HOME/.bashrc" ]
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
    touch "$HOME/.bashrc"
    update_rc php@default
    grep -qF "$FAKE_BREW_PREFIX/opt/php/bin" "$HOME/.bashrc"
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
