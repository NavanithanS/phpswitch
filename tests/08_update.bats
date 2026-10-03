#!/usr/bin/env bats

load helpers/common

REPO_SLUG="NavanithanS/phpswitch"
API_URL="https://api.github.com/repos/$REPO_SLUG/releases/latest"

setup() {
    common_setup
    load_modules
    PHPSWITCH_VERSION="1.4.5"

    # A non-Homebrew install of phpswitch, first on PATH
    INSTALL_DIR="$TEST_ROOT/bin"
    mkdir -p "$INSTALL_DIR"
    printf '#!/bin/bash\nPHPSWITCH_VERSION="1.4.5"\n' > "$INSTALL_DIR/phpswitch"
    chmod +x "$INSTALL_DIR/phpswitch"
    export PATH="$INSTALL_DIR:$PATH"
    ORIGINAL_SUM=$(shasum -a 256 "$INSTALL_DIR/phpswitch" | awk '{print $1}')
}

teardown() {
    common_teardown
}

# publish_release <tag> [embedded-version] [checksum-mode: good|bad|none]
publish_release() {
    local tag="$1" embedded="${2:-${1#v}}" mode="${3:-good}"
    local work="$TEST_ROOT/release"
    mkdir -p "$work"
    printf '{\n  "tag_name": "%s",\n  "name": "Version %s"\n}\n' "$tag" "${tag#v}" > "$work/release.json"
    fake_url "$API_URL" "$work/release.json"

    printf '#!/bin/bash\nPHPSWITCH_VERSION="%s"\n' "$embedded" > "$work/php-switcher.sh"
    fake_url "https://github.com/$REPO_SLUG/releases/download/$tag/php-switcher.sh" "$work/php-switcher.sh"

    case "$mode" in
        good) (cd "$work" && shasum -a 256 php-switcher.sh > php-switcher.sh.sha256) ;;
        bad)  printf '%064d  php-switcher.sh\n' 0 > "$work/php-switcher.sh.sha256" ;;
        none) return 0 ;;
    esac
    fake_url "https://github.com/$REPO_SLUG/releases/download/$tag/php-switcher.sh.sha256" "$work/php-switcher.sh.sha256"
}

install_untouched() {
    [ "$(shasum -a 256 "$INSTALL_DIR/phpswitch" | awk '{print $1}')" = "$ORIGINAL_SUM" ]
    [ -z "$(find "$INSTALL_DIR" -name 'phpswitch.bak.*')" ]
}

@test "Homebrew-managed install defers to brew upgrade without network calls" {
    # Homebrew links with relative symlinks: bin/phpswitch -> ../Cellar/...
    local cellar="$FAKE_BREW_PREFIX/Cellar/phpswitch/1.4.4/bin"
    mkdir -p "$cellar"
    mv "$INSTALL_DIR/phpswitch" "$cellar/phpswitch"
    rm -rf "$INSTALL_DIR"
    ln -s ../Cellar/phpswitch/1.4.4/bin/phpswitch "$FAKE_BREW_PREFIX/bin/phpswitch"
    export PATH="$FAKE_BREW_PREFIX/bin:$PATH"
    run cmd_update_self
    [ "$status" -eq 0 ]
    [[ "$output" =~ "brew upgrade phpswitch" ]]
    [ ! -s "$FAKE_CURL_LOG" ]
}

@test "already on the latest release" {
    publish_release 1.4.5
    run cmd_update_self < /dev/null
    [ "$status" -eq 0 ]
    [[ "$output" =~ "already using the latest version" ]]
    run grep -c . "$FAKE_CURL_LOG"
    [ "$output" -eq 1 ]
}

@test "an older latest release never downgrades" {
    publish_release v1.4.4
    run cmd_update_self < /dev/null
    [ "$status" -eq 0 ]
    [[ "$output" =~ "already using the latest version" ]]
    install_untouched
}

@test "release without a checksum asset is refused" {
    publish_release v1.5.0 1.5.0 none
    run cmd_update_self < /dev/null
    [ "$status" -ne 0 ]
    [[ "$output" =~ "does not publish a checksum" ]]
    install_untouched
}

@test "checksum mismatch is refused" {
    publish_release v1.5.0 1.5.0 bad
    run cmd_update_self < /dev/null
    [ "$status" -ne 0 ]
    [[ "$output" =~ "Checksum verification failed" ]]
    install_untouched
}

@test "verified file reporting a different version is refused" {
    publish_release v1.5.0 1.4.9 good
    run cmd_update_self < /dev/null
    [ "$status" -ne 0 ]
    [[ "$output" =~ "expected 1.5.0" ]]
    install_untouched
}

@test "unparseable release metadata is refused" {
    printf '{ "message": "API rate limit exceeded" }\n' > "$TEST_ROOT/limit.json"
    fake_url "$API_URL" "$TEST_ROOT/limit.json"
    run cmd_update_self < /dev/null
    [ "$status" -ne 0 ]
    [[ "$output" =~ "Could not determine the latest release version" ]]
}

@test "verified newer release prompts, and declining leaves the install untouched" {
    publish_release v1.5.0
    run cmd_update_self <<< "n"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "New version available: 1.5.0" ]]
    [[ "$output" =~ "Update cancelled" ]]
    grep -q "releases/download/v1.5.0/php-switcher.sh.sha256" "$FAKE_CURL_LOG"
    install_untouched
}

@test "tags without a v prefix resolve to the same download path" {
    publish_release 1.5.0
    run cmd_update_self <<< "n"
    [[ "$output" =~ "Update cancelled" ]]
    grep -q "releases/download/1.5.0/php-switcher.sh" "$FAKE_CURL_LOG"
}

@test "--update exits non-zero when the update is refused" {
    publish_release v1.5.0 1.5.0 bad
    printf 'AUTO_RESTART_PHP_FPM=false\n' > "$HOME/.phpswitch.conf"
    run "$REPO_ROOT/php-switcher.sh" --update < /dev/null
    [ "$status" -ne 0 ]
    [[ "$output" =~ "Checksum verification failed" ]]
}

@test "symlink cycles do not hang path resolution" {
    ln -s "$TEST_ROOT/loop-b" "$TEST_ROOT/loop-a"
    ln -s "$TEST_ROOT/loop-a" "$TEST_ROOT/loop-b"
    run cmd_resolve_script_path "$TEST_ROOT/loop-a"
    [ "$status" -eq 0 ]
}
