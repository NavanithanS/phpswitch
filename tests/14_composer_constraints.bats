#!/usr/bin/env bats

load helpers/common

setup() {
    common_setup
    load_modules
    PROJECT="$HOME/project"
    mkdir -p "$PROJECT"
}

teardown() {
    common_teardown
}

require_php() {
    printf '{\n    "require": {\n        "php": "%s"\n    }\n}\n' "$1" > "$PROJECT/composer.json"
}

@test "constraint matcher handles composer syntax per PHP series" {
    local row constraint series expected r
    while IFS=';' read -r constraint series expected; do
        [ -n "$constraint" ] || continue
        utils_composer_constraint_matches "$constraint" "$series" && r=yes || r=no
        [ "$r" = "$expected" ] || { echo "'$constraint' vs $series: got $r, want $expected"; return 1; }
    done <<'TABLE'
^8.1;8.1;yes
^8.1;8.4;yes
^8.1;9.0;no
^8.1;8.0;no
~8.2.0;8.2;yes
~8.2.0;8.3;no
~8.2;8.3;yes
>=8.2 <8.4;8.1;no
>=8.2 <8.4;8.3;yes
>=8.2 <8.4;8.4;no
>=8.2,<8.4;8.3;yes
^7.4 || ^8.0;8.1;yes
^7.4 | ^8.0;7.4;yes
8.1.*;8.1;yes
8.1.*;8.2;no
8.*;8.3;yes
*;7.4;yes
8.1 - 8.3;8.3;yes
8.1 - 8.3;8.4;no
<8.2.3;8.2;yes
<8.2;8.2;no
>8.1;8.1;yes
dev-master;8.1;no
^8.1@dev;8.2;yes
8.1.3;8.1;yes
v8.2;8.2;yes
TABLE
}

@test "installed series come from the prefix, including the default formula" {
    fake_php_install php@8.3
    fake_php_install php@7.4
    mkdir -p "$FAKE_BREW_PREFIX/Cellar/php/8.4.2/bin"
    cp "$FAKE_BREW_PREFIX/opt/php@8.3/bin/php" "$FAKE_BREW_PREFIX/Cellar/php/8.4.2/bin/php"
    ln -s ../Cellar/php/8.4.2 "$FAKE_BREW_PREFIX/opt/php"
    run utils_installed_php_series
    [ "$output" = "$(printf '7.4\n8.3\n8.4')" ]
}

@test "^8.1 keeps 8.1 when it is installed" {
    fake_php_install php@8.1
    fake_php_install php@8.3
    require_php "^8.1"
    run utils_read_composer_version "$PROJECT/composer.json"
    [ "$output" = "8.1" ]
}

@test "^8.1 resolves to the lowest installed match when 8.1 is missing" {
    fake_php_install php@8.3
    fake_php_install php@8.2
    require_php "^8.1"
    run utils_read_composer_version "$PROJECT/composer.json"
    [ "$output" = "8.2" ]
}

@test "ranges and OR groups pick the lowest satisfying install" {
    fake_php_install php@7.4
    fake_php_install php@8.3
    require_php ">=8.2 <8.4"
    run utils_read_composer_version "$PROJECT/composer.json"
    [ "$output" = "8.3" ]
    require_php "^7.4 || ^8.0"
    run utils_read_composer_version "$PROJECT/composer.json"
    [ "$output" = "7.4" ]
}

@test "a working project keeps the historical choice" {
    fake_php_install php@8.1
    fake_php_install php@8.2
    require_php "^8.2 || ^8.1"
    run utils_read_composer_version "$PROJECT/composer.json"
    [ "$output" = "8.2" ]
}

@test "nothing installed that matches falls back to the first X.Y" {
    fake_php_install php@7.4
    require_php "^8.1"
    run utils_read_composer_version "$PROJECT/composer.json"
    [ "$output" = "8.1" ]
}

@test "platform.php stays an exact pin" {
    fake_php_install php@8.3
    printf '{ "require": { "php": "^8.1" }, "config": { "platform": { "php": "8.1.10" } } }\n' > "$PROJECT/composer.json"
    run utils_read_composer_version "$PROJECT/composer.json"
    [ "$output" = "8.1" ]
}

@test "project detection uses the resolved constraint" {
    fake_php_install php@8.2
    fake_php_install php@8.3
    require_php "~8.3.0"
    cd "$PROJECT"
    run version_check_project
    [ "$output" = "php@8.3" ]
}
