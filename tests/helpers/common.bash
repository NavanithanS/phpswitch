# Shared bats helpers: isolated $HOME, fake brew on PATH, fake Homebrew prefix.
# Usage in a .bats file:  load helpers/common  then call common_setup / common_teardown

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"

common_setup() {
    TEST_ROOT="$(mktemp -d)"
    export HOME="$TEST_ROOT/home"
    mkdir -p "$HOME"
    export PHPSWITCH_TEST_MODE=1
    export PATH="${BATS_TEST_DIRNAME}/helpers/bin:$PATH"
    export FAKE_BREW_PREFIX="$TEST_ROOT/brew"
    export FAKE_BREW_LOG="$TEST_ROOT/brew.log"
    export FAKE_BREW_LIST=""
    mkdir -p "$FAKE_BREW_PREFIX/bin" "$FAKE_BREW_PREFIX/opt"
    : > "$FAKE_BREW_LOG"
}

common_teardown() {
    rm -rf "$TEST_ROOT"
}

# Source all modules in build order (without the main block)
load_modules() {
    source "$REPO_ROOT/phpswitch/config/defaults.sh"
    source "$REPO_ROOT/phpswitch/lib/core.sh"
    source "$REPO_ROOT/phpswitch/lib/utils.sh"
    source "$REPO_ROOT/phpswitch/lib/shell.sh"
    source "$REPO_ROOT/phpswitch/lib/version.sh"
    source "$REPO_ROOT/phpswitch/lib/fpm.sh"
    source "$REPO_ROOT/phpswitch/lib/extensions.sh"
    source "$REPO_ROOT/phpswitch/lib/auto-switch.sh"
    source "$REPO_ROOT/phpswitch/lib/commands.sh"
    HOMEBREW_PREFIX="$FAKE_BREW_PREFIX"
    BACKUP_CONFIG_FILES=true
    MAX_BACKUPS=5
}

# fake_php_install php@8.2 [8.2.10]  -> creates opt/<formula>/bin/php reporting that version
fake_php_install() {
    local formula="$1" full="${2:-${1#php@}.0}"
    mkdir -p "$FAKE_BREW_PREFIX/opt/$formula/bin" "$FAKE_BREW_PREFIX/opt/$formula/sbin"
    printf '#!/bin/bash\necho "PHP %s (cli)"\n' "$full" > "$FAKE_BREW_PREFIX/opt/$formula/bin/php"
    chmod +x "$FAKE_BREW_PREFIX/opt/$formula/bin/php"
    FAKE_BREW_LIST="$(printf '%s\n%s' "$FAKE_BREW_LIST" "$formula" | sed '/^$/d')"
    export FAKE_BREW_LIST
}

# fake_php_link php@8.1  -> points $prefix/bin/php at that formula
fake_php_link() {
    ln -sfn "../opt/$1/bin/php" "$FAKE_BREW_PREFIX/bin/php"
}
