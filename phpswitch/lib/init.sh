#!/bin/bash
# PHPSwitch Shell Integration
# Per-shell PHP switching: `phpswitch init <shell>` prints code that is
# eval'd from the user's rc file. It defines a `phpswitch` wrapper (so
# `phpswitch use` can change PATH in the current shell) and a directory
# hook that selects the project's PHP without spawning a process in the
# common case. The binary never emits code on `cd`; it only prints a
# directory (`__php-dir`), which the shell validates before using.

# Print the opt directory for a PHP version, or for the current project
# when no version is given. Output is a bare path on stdout; all
# diagnostics go to stderr.
function init_php_dir {
    local version="$1"

    if [ -z "$version" ]; then
        version=$(version_check_project 2>/dev/null) || return 1
    else
        if ! utils_validate_version "$version"; then
            echo "phpswitch: invalid PHP version: $version" >&2
            return 1
        fi
        case "$version" in
            php@*) ;;
            php|default) version="php@default" ;;
            *) version="php@$version" ;;
        esac
    fi

    version=$(version_resolve_php_version "$version")

    if ! core_check_php_installed "$version"; then
        if [ -n "$1" ]; then
            echo "phpswitch: $version is not installed (install it with: phpswitch --install=${version#php@})" >&2
        fi
        return 1
    fi

    if [ "$version" = "php@default" ]; then
        printf '%s\n' "$HOMEBREW_PREFIX/opt/php"
    else
        printf '%s\n' "$HOMEBREW_PREFIX/opt/$version"
    fi
}

# Absolute path of the running phpswitch script
function init_self_path {
    local self="$0"
    case "$self" in
        /*) ;;
        *) self="$(cd "$(dirname "$self")" && pwd)/$(basename "$self")" ;;
    esac
    printf '%s\n' "$self"
}

# Print shell integration code for zsh, bash or fish
function init_print {
    local shell_type="$1"
    if [ -z "$shell_type" ]; then
        shell_type=$(basename "${SHELL:-zsh}")
    fi

    local self
    self=$(init_self_path)

    # Values are embedded in single quotes; refuse anything that could break out
    local value
    for value in "$self" "$HOMEBREW_PREFIX"; do
        case "$value" in
            *"'"*|*$'\n'*|*\\*)
                echo "phpswitch: cannot generate shell integration for path: $value" >&2
                return 1
                ;;
        esac
    done

    case "$shell_type" in
        zsh|bash)
            printf "# phpswitch shell integration (%s)\n" "$shell_type"
            printf "export PHPSWITCH_BIN='%s'\n" "$self"
            printf "export PHPSWITCH_PREFIX='%s'\n" "$HOMEBREW_PREFIX"
            init_print_posix
            if [ "$shell_type" = "zsh" ]; then
                cat << 'EOF'
autoload -Uz add-zsh-hook
add-zsh-hook chpwd _phpswitch_hook
# Re-evaluate even if this shell already ran the hook here (re-sourced rc)
_phpswitch_last_pwd=""
_phpswitch_hook
EOF
            else
                cat << 'EOF'
if [[ ";${PROMPT_COMMAND:-};" != *";_phpswitch_hook;"* ]]; then
    PROMPT_COMMAND="_phpswitch_hook${PROMPT_COMMAND:+;$PROMPT_COMMAND}"
fi
# Re-evaluate even if this shell already ran the hook here (re-sourced rc)
_phpswitch_last_pwd=""
_phpswitch_hook
EOF
            fi
            ;;
        fish)
            printf "# phpswitch shell integration (fish)\n"
            printf "set -gx PHPSWITCH_BIN '%s'\n" "$self"
            printf "set -gx PHPSWITCH_PREFIX '%s'\n" "$HOMEBREW_PREFIX"
            init_print_fish
            ;;
        *)
            echo "phpswitch: unsupported shell '$shell_type' (use zsh, bash or fish)" >&2
            return 1
            ;;
    esac
}

# Shared bash/zsh integration body (bash 3.2 compatible)
function init_print_posix {
    cat << 'EOF'

# Remove every exact occurrence of $1 from PATH
_phpswitch_path_remove() {
    local p=":$PATH:"
    while [[ "$p" == *":$1:"* ]]; do
        p="${p//":$1:"/:}"
    done
    p="${p#:}"
    PATH="${p%:}"
}

# A directory is usable only if it is a PHP install under the Homebrew prefix
_phpswitch_valid_dir() {
    case "$1" in
        "$PHPSWITCH_PREFIX"/opt/php*) ;;
        *) return 1 ;;
    esac
    case "$1" in
        *:*|*$'\n'*|*/..*) return 1 ;;
    esac
    [ -x "$1/bin/php" ]
}

# Put $1/bin and $1/sbin first on PATH (or remove ours when $1 is empty)
_phpswitch_apply() {
    local dir="$1"
    if [ "$dir" = "${PHPSWITCH_PHP_DIR:-}" ]; then
        if [ -z "$dir" ] || [[ "$PATH" == "$dir/bin:$dir/sbin:"* ]]; then
            return 0
        fi
    fi
    if [ -n "${PHPSWITCH_PHP_DIR:-}" ]; then
        _phpswitch_path_remove "$PHPSWITCH_PHP_DIR/bin"
        _phpswitch_path_remove "$PHPSWITCH_PHP_DIR/sbin"
    fi
    if [ -n "$dir" ]; then
        _phpswitch_path_remove "$dir/bin"
        _phpswitch_path_remove "$dir/sbin"
        PATH="$dir/bin:$dir/sbin:$PATH"
        export PHPSWITCH_PHP_DIR="$dir"
    else
        unset PHPSWITCH_PHP_DIR
    fi
    export PATH
    hash -r 2>/dev/null
}

# Ask phpswitch to resolve the project version (composer.json, .tool-versions,
# major-only versions, php@default); sets _phpswitch_found
_phpswitch_delegate() {
    _phpswitch_found=$("$PHPSWITCH_BIN" __php-dir 2>/dev/null)
    _phpswitch_valid_dir "$_phpswitch_found" || _phpswitch_found=""
}

# Find the PHP directory for $PWD; sets _phpswitch_found (empty if none).
# Mirrors version_check_project: per directory, .php-version/.phpversion,
# then composer.json/.tool-versions, walking up while inside $HOME.
_phpswitch_detect() {
    local dir="$PWD" f v n line
    _phpswitch_found=""
    while [ "$dir" != "/" ] && [[ "$dir" == "$HOME"* ]]; do
        for f in .php-version .phpversion; do
            if [ -f "$dir/$f" ]; then
                v=""
                while IFS= read -r line || [ -n "$line" ]; do
                    v="$v$line"
                done < "$dir/$f"
                v="${v//[[:space:]]/}"
                n="${v#php@}"
                if [[ "$n" =~ ^[0-9]+\.[0-9]+$ ]] && [ -x "$PHPSWITCH_PREFIX/opt/php@$n/bin/php" ]; then
                    _phpswitch_found="$PHPSWITCH_PREFIX/opt/php@$n"
                else
                    _phpswitch_delegate
                fi
                return 0
            fi
        done
        if [ -f "$dir/composer.json" ] || [ -f "$dir/.tool-versions" ]; then
            _phpswitch_delegate
            return 0
        fi
        dir="${dir%/*}"
        [ -z "$dir" ] && dir="/"
    done
}

# Directory hook: re-evaluate when $PWD changes, unless pinned by `phpswitch use`
_phpswitch_hook() {
    [ -n "${PHPSWITCH_PINNED:-}" ] && return 0
    [ "$PWD" = "${_phpswitch_last_pwd:-}" ] && return 0
    _phpswitch_last_pwd="$PWD"
    _phpswitch_detect
    _phpswitch_apply "$_phpswitch_found"
}

phpswitch() {
    local d rc
    case "${1:-}" in
        use|shell)
            if [ "${2:-}" = "auto" ] || [ "${2:-}" = "--unset" ]; then
                unset PHPSWITCH_PINNED
                _phpswitch_last_pwd=""
                _phpswitch_hook
                return 0
            fi
            if [ -z "${2:-}" ]; then
                echo "usage: phpswitch use <version>|auto" >&2
                return 1
            fi
            d=$("$PHPSWITCH_BIN" __php-dir "$2") || return 1
            if ! _phpswitch_valid_dir "$d"; then
                echo "phpswitch: refusing invalid PHP directory: $d" >&2
                return 1
            fi
            export PHPSWITCH_PINNED=1
            _phpswitch_apply "$d"
            ;;
        local|global)
            "$PHPSWITCH_BIN" "$@"
            rc=$?
            _phpswitch_last_pwd=""
            _phpswitch_hook
            return $rc
            ;;
        *)
            "$PHPSWITCH_BIN" "$@"
            ;;
    esac
}
EOF
}

# fish integration body (fish 3+)
function init_print_fish {
    cat << 'EOF'

function _phpswitch_valid_dir
    string match -q -- "$PHPSWITCH_PREFIX/opt/php*" "$argv[1]"; or return 1
    string match -q -- '*:*' "$argv[1]"; and return 1
    string match -q -- '*/..*' "$argv[1]"; and return 1
    test -x "$argv[1]/bin/php"
end

function _phpswitch_apply
    set -l dir $argv[1]
    if test "$dir" = "$PHPSWITCH_PHP_DIR"
        if test -z "$dir"; or begin; test "$PATH[1]" = "$dir/bin"; and test "$PATH[2]" = "$dir/sbin"; end
            return 0
        end
    end
    # Only ever remove our own entries; an empty dir must never expand to /bin
    set -l stale
    if test -n "$PHPSWITCH_PHP_DIR"
        set -a stale "$PHPSWITCH_PHP_DIR/bin" "$PHPSWITCH_PHP_DIR/sbin"
    end
    if test -n "$dir"
        set -a stale "$dir/bin" "$dir/sbin"
    end
    set -l i
    for e in $stale
        while set i (contains -i -- $e $PATH)
            set -e PATH[$i]
        end
    end
    if test -n "$dir"
        set -gx PATH "$dir/bin" "$dir/sbin" $PATH
        set -gx PHPSWITCH_PHP_DIR $dir
    else
        set -e PHPSWITCH_PHP_DIR
    end
end

function _phpswitch_delegate
    set -l d ($PHPSWITCH_BIN __php-dir 2>/dev/null)
    _phpswitch_valid_dir "$d"; and echo $d
end

# Mirrors version_check_project (see the bash/zsh variant)
function _phpswitch_detect
    set -l dir $PWD
    while test "$dir" != "/"; and string match -q -- "$HOME*" "$dir"
        for f in .php-version .phpversion
            if test -f "$dir/$f"
                set -l v (string replace -ra '\s' '' < "$dir/$f" | string join '')
                set -l n (string replace -r '^php@' '' -- "$v")
                if string match -qr '^[0-9]+\.[0-9]+$' -- "$n"; and test -x "$PHPSWITCH_PREFIX/opt/php@$n/bin/php"
                    echo "$PHPSWITCH_PREFIX/opt/php@$n"
                else
                    _phpswitch_delegate
                end
                return 0
            end
        end
        if test -f "$dir/composer.json"; or test -f "$dir/.tool-versions"
            _phpswitch_delegate
            return 0
        end
        set dir (string replace -r '/[^/]*$' '' -- "$dir")
        test -z "$dir"; and set dir /
    end
end

function _phpswitch_hook --on-variable PWD
    set -q PHPSWITCH_PINNED; and return 0
    test "$PWD" = "$_phpswitch_last_pwd"; and return 0
    set -g _phpswitch_last_pwd $PWD
    _phpswitch_apply (_phpswitch_detect)
end

function phpswitch
    switch "$argv[1]"
        case use shell
            if test "$argv[2]" = auto; or test "$argv[2]" = --unset
                set -e PHPSWITCH_PINNED
                set -g _phpswitch_last_pwd ""
                _phpswitch_hook
                return 0
            end
            if test -z "$argv[2]"
                echo "usage: phpswitch use <version>|auto" >&2
                return 1
            end
            set -l d ($PHPSWITCH_BIN __php-dir $argv[2]); or return 1
            if not _phpswitch_valid_dir "$d"
                echo "phpswitch: refusing invalid PHP directory: $d" >&2
                return 1
            end
            set -gx PHPSWITCH_PINNED 1
            _phpswitch_apply $d
        case local global
            $PHPSWITCH_BIN $argv
            set -l rc $status
            set -g _phpswitch_last_pwd ""
            _phpswitch_hook
            return $rc
        case '*'
            $PHPSWITCH_BIN $argv
    end
end

# Re-evaluate even if this shell already ran the hook here (re-sourced rc)
set -g _phpswitch_last_pwd ""
_phpswitch_hook
EOF
}
