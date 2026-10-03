#!/usr/bin/env bats

load helpers/common

setup() {
    common_setup
    load_modules
    PROJECT="$HOME/project"
    mkdir -p "$PROJECT/src/deep"
}

teardown() {
    common_teardown
}

detect_in() {
    cd "$1" && version_check_project
}

@test ".php-version with bare version is normalized" {
    echo "8.2" > "$PROJECT/.php-version"
    run detect_in "$PROJECT"
    [ "$status" -eq 0 ]
    [ "$output" = "php@8.2" ]
}

@test ".php-version with php@ prefix and whitespace" {
    printf '  php@8.1 \n' > "$PROJECT/.php-version"
    run detect_in "$PROJECT"
    [ "$output" = "php@8.1" ]
}

@test ".phpversion is supported" {
    echo "8.3" > "$PROJECT/.phpversion"
    run detect_in "$PROJECT"
    [ "$output" = "php@8.3" ]
}

@test "version file is found from a nested subdirectory" {
    echo "8.2" > "$PROJECT/.php-version"
    run detect_in "$PROJECT/src/deep"
    [ "$status" -eq 0 ]
    [ "$output" = "php@8.2" ]
}

@test "closest version file wins" {
    echo "8.1" > "$PROJECT/.php-version"
    echo "8.3" > "$PROJECT/src/.php-version"
    run detect_in "$PROJECT/src/deep"
    [ "$output" = "php@8.3" ]
}

@test "composer.json require.php is used" {
    cat > "$PROJECT/composer.json" <<'JSON'
{
    "require": {
        "php": "^8.1",
        "laravel/framework": "^10.0"
    }
}
JSON
    run detect_in "$PROJECT"
    [ "$output" = "php@8.1" ]
}

@test "composer.json config.platform.php takes priority over require.php" {
    cat > "$PROJECT/composer.json" <<'JSON'
{
    "require": { "php": "^8.1" },
    "config": { "platform": { "php": "8.2.5" } }
}
JSON
    run detect_in "$PROJECT"
    [ "$output" = "php@8.2" ]
}

@test ".tool-versions php entry is used" {
    printf 'nodejs 20.1.0\nphp 8.3.4\n' > "$PROJECT/.tool-versions"
    run detect_in "$PROJECT"
    [ "$output" = "php@8.3" ]
}

@test ".php-version beats composer.json in the same directory" {
    echo "8.3" > "$PROJECT/.php-version"
    printf '{ "require": { "php": "^8.1" } }\n' > "$PROJECT/composer.json"
    run detect_in "$PROJECT"
    [ "$output" = "php@8.3" ]
}

@test "major-only version resolves to highest installed minor" {
    fake_php_install php@8.1
    fake_php_install php@8.3
    echo "8" > "$PROJECT/.php-version"
    run detect_in "$PROJECT"
    [ "$output" = "php@8.3" ]
}

@test "unsafe characters in version file are rejected" {
    echo '8.2;rm -rf /' > "$PROJECT/.php-version"
    run detect_in "$PROJECT"
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

@test "no version file returns non-zero" {
    run detect_in "$PROJECT/src"
    [ "$status" -ne 0 ]
}

@test "search does not go above HOME" {
    echo "8.2" > "$TEST_ROOT/.php-version"
    run detect_in "$PROJECT"
    [ "$status" -ne 0 ]
}
