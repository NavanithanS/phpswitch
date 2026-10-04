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

# --- release signatures (minisign) --------------------------------------------

TEST_PUBKEY="RWTestKeyTestKeyTestKeyTestKeyTestKeyTestKeyTestKey00"

# publish_signature <tag> <good|bad>  -> serve php-switcher.sh.minisig
publish_signature() {
    printf '%s-signature\n' "$2" > "$TEST_ROOT/release/php-switcher.sh.minisig"
    fake_url "https://github.com/$REPO_SLUG/releases/download/$1/php-switcher.sh.minisig" \
        "$TEST_ROOT/release/php-switcher.sh.minisig"
}

# A fake minisign first on PATH: logs its arguments, accepts "good-signature"
use_fake_minisign() {
    mkdir -p "$TEST_ROOT/minisign-bin"
    cat > "$TEST_ROOT/minisign-bin/minisign" << 'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "$MINISIGN_LOG"
sig=""
while [ $# -gt 0 ]; do
    [ "$1" = "-x" ] && sig="$2"
    shift
done
[ "$(cat "$sig")" = "good-signature" ]
STUB
    chmod +x "$TEST_ROOT/minisign-bin/minisign"
    export MINISIGN_LOG="$TEST_ROOT/minisign.log"
    export PATH="$TEST_ROOT/minisign-bin:$PATH"
}

@test "signed release with a valid signature reaches the prompt" {
    PHPSWITCH_MINISIGN_PUBKEY="$TEST_PUBKEY"
    use_fake_minisign
    publish_release v1.5.0
    publish_signature v1.5.0 good
    run cmd_update_self <<< "n"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Release signature verified"* ]]
    [[ "$output" == *"Update cancelled"* ]]
    grep -qF -- "-V -q -P $TEST_PUBKEY -m " "$MINISIGN_LOG"
    grep -q -- "php-switcher.sh.minisig" "$MINISIGN_LOG"
    install_untouched
}

@test "bad signature is refused before the prompt" {
    PHPSWITCH_MINISIGN_PUBKEY="$TEST_PUBKEY"
    use_fake_minisign
    publish_release v1.5.0
    publish_signature v1.5.0 bad
    run cmd_update_self <<< "y"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Signature verification failed"* ]]
    [[ "$output" != *"Update to"* ]]
    install_untouched
}

@test "missing signature is refused when minisign is installed" {
    PHPSWITCH_MINISIGN_PUBKEY="$TEST_PUBKEY"
    use_fake_minisign
    publish_release v1.5.0
    run cmd_update_self <<< "y"
    [ "$status" -ne 0 ]
    [[ "$output" == *"is not signed"* ]]
    install_untouched
}

@test "without minisign, the checksum is used with a warning" {
    PHPSWITCH_MINISIGN_PUBKEY="$TEST_PUBKEY"
    export PATH="$INSTALL_DIR:${BATS_TEST_DIRNAME}/helpers/bin:/usr/bin:/bin"
    run command -v minisign
    [ "$status" -ne 0 ]
    publish_release v1.5.0
    run cmd_update_self <<< "n"
    [ "$status" -eq 0 ]
    [[ "$output" == *"minisign is not installed"* ]]
    [[ "$output" == *"Update cancelled"* ]]
    run grep -c 'minisig' "$FAKE_CURL_LOG"
    [ "$output" = "0" ]
}

@test "a build without a signing key never asks for a signature" {
    PHPSWITCH_MINISIGN_PUBKEY=""
    use_fake_minisign
    publish_release v1.5.0
    run cmd_update_self <<< "n"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Update cancelled"* ]]
    run grep -c 'minisig' "$FAKE_CURL_LOG"
    [ "$output" = "0" ]
    [ ! -e "$MINISIGN_LOG" ]
}

@test "the signing key can't be set from the config file or the environment" {
    printf 'PHPSWITCH_MINISIGN_PUBKEY="RWattacker"\n' > "$HOME/.phpswitch.conf"
    run env PHPSWITCH_MINISIGN_PUBKEY=RWattacker bash -c \
        "source '$REPO_ROOT/phpswitch/config/defaults.sh'; source '$REPO_ROOT/phpswitch/lib/core.sh'; core_load_config 2>/dev/null; printf 'key=%s' \"\$PHPSWITCH_MINISIGN_PUBKEY\""
    [ "$output" = "key=$(grep '^PHPSWITCH_MINISIGN_PUBKEY=' "$REPO_ROOT/phpswitch/config/defaults.sh" | cut -d'"' -f2)" ]
}

@test "real minisign: a signed release verifies, a tampered one is refused" {
    command -v minisign >/dev/null || skip "minisign not installed"
    local keys="$TEST_ROOT/keys"
    mkdir -p "$keys"
    minisign -G -W -p "$keys/test.pub" -s "$keys/test.key" > /dev/null
    PHPSWITCH_MINISIGN_PUBKEY=$(sed -n 2p "$keys/test.pub")

    publish_release v1.5.0
    minisign -S -s "$keys/test.key" -m "$TEST_ROOT/release/php-switcher.sh" \
        -x "$TEST_ROOT/release/php-switcher.sh.minisig" -t "phpswitch v1.5.0" > /dev/null
    fake_url "https://github.com/$REPO_SLUG/releases/download/v1.5.0/php-switcher.sh.minisig" \
        "$TEST_ROOT/release/php-switcher.sh.minisig"
    run cmd_update_self <<< "n"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Release signature verified"* ]]

    # A different key's signature over the same file must be refused
    minisign -G -W -p "$keys/other.pub" -s "$keys/other.key" > /dev/null
    minisign -S -s "$keys/other.key" -m "$TEST_ROOT/release/php-switcher.sh" \
        -x "$TEST_ROOT/release/php-switcher.sh.minisig" > /dev/null
    # fake_url serves a copy, so publish the new signature again
    fake_url "https://github.com/$REPO_SLUG/releases/download/v1.5.0/php-switcher.sh.minisig" \
        "$TEST_ROOT/release/php-switcher.sh.minisig"
    run cmd_update_self <<< "y"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Signature verification failed"* ]]
    install_untouched
}
