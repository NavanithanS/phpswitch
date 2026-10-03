#!/bin/bash
# PHPSwitch Shell Completions
# `phpswitch completions <bash|zsh|fish>` prints a completion script.
# Installed versions are found by globbing the Homebrew prefix baked in at
# generation time, so completing never runs brew or phpswitch.

# Subcommands and flags offered by completion; keep in sync with --help
# (tests/13_completions.bats fails if they drift)
COMPLETION_SUBCOMMANDS="use global local init doctor completions"
COMPLETION_FLAGS="--switch= --switch-force= --install= --uninstall= --uninstall-force= --list --json --current --project --clear-cache --refresh-cache --fix-permissions --install-auto-switch --clear-directory-cache --check-dependencies --install --uninstall --update --version --debug --yes --quiet --help"

function completions_print {
    local shell_type="$1"
    if [ -z "$shell_type" ]; then
        shell_type=$(basename "${SHELL:-zsh}")
    fi

    case "$HOMEBREW_PREFIX" in
        *"'"*|*$'\n'*|*\\*)
            echo "phpswitch: cannot generate completions for prefix: $HOMEBREW_PREFIX" >&2
            return 1
            ;;
    esac

    case "$shell_type" in
        bash) completions_print_bash ;;
        zsh) completions_print_zsh ;;
        fish) completions_print_fish ;;
        *)
            echo "phpswitch: unsupported shell '$shell_type' (use zsh, bash or fish)" >&2
            return 1
            ;;
    esac
}

function completions_print_bash {
    printf "# phpswitch completions (bash)\n"
    printf "_phpswitch_completion_prefix='%s'\n" "$HOMEBREW_PREFIX"
    printf "_phpswitch_completion_words='%s %s'\n" "$COMPLETION_SUBCOMMANDS" "$COMPLETION_FLAGS"
    cat << 'EOF'
_phpswitch_completion_versions() {
    local d
    for d in "$_phpswitch_completion_prefix"/opt/php@*; do
        [ -x "$d/bin/php" ] && printf '%s\n' "${d##*/php@}"
    done
}

_phpswitch_complete() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local prev="${COMP_WORDS[COMP_CWORD-1]:-}"
    COMPREPLY=()

    # --flag=VALUE: bash splits on "=", so the value is its own word
    if [ "$prev" = "=" ] && [ "$COMP_CWORD" -ge 2 ]; then
        case "${COMP_WORDS[COMP_CWORD-2]}" in
            --switch|--switch-force|--uninstall|--uninstall-force)
                COMPREPLY=( $(compgen -W "$(_phpswitch_completion_versions)" -- "$cur") ) ;;
        esac
        return 0
    fi
    if [ "$cur" = "=" ]; then
        case "$prev" in
            --switch|--switch-force|--uninstall|--uninstall-force)
                COMPREPLY=( $(_phpswitch_completion_versions) ) ;;
        esac
        return 0
    fi

    if [ "$COMP_CWORD" -eq 1 ]; then
        COMPREPLY=( $(compgen -W "$_phpswitch_completion_words" -- "$cur") )
        # No space after "--switch=" so the version can follow (bash 4+;
        # bash 3.2 has no compopt and simply adds the space)
        if [ ${#COMPREPLY[@]} -eq 1 ] && [[ "${COMPREPLY[0]}" == *= ]] && type compopt >/dev/null 2>&1; then
            compopt -o nospace
        fi
        return 0
    fi

    case "${COMP_WORDS[1]}" in
        use) COMPREPLY=( $(compgen -W "auto $(_phpswitch_completion_versions)" -- "$cur") ) ;;
        global|local) COMPREPLY=( $(compgen -W "$(_phpswitch_completion_versions)" -- "$cur") ) ;;
        init|completions) COMPREPLY=( $(compgen -W "zsh bash fish" -- "$cur") ) ;;
    esac
    return 0
}
complete -F _phpswitch_complete phpswitch
EOF
}

function completions_print_zsh {
    printf "# phpswitch completions (zsh); load after compinit\n"
    printf "_phpswitch_completion_prefix='%s'\n" "$HOMEBREW_PREFIX"
    printf "_phpswitch_completion_flags=(%s)\n" "$COMPLETION_FLAGS"
    cat << 'EOF'
_phpswitch_completion_versions() {
    local d
    for d in "$_phpswitch_completion_prefix"/opt/php@*(N); do
        [ -x "$d/bin/php" ] && print -r -- "${d##*/php@}"
    done
}

_phpswitch_complete() {
    local -a subcmds versions
    subcmds=(
        'use:use a version in this shell only'
        'global:switch the global (Homebrew-linked) version'
        'local:write .php-version in the current directory'
        'init:print shell integration code'
        'doctor:check your PHP setup'
        'completions:print shell completions'
    )
    versions=(${(f)"$(_phpswitch_completion_versions)"})

    if (( CURRENT == 2 )); then
        if [[ "$PREFIX" == --*=* ]]; then
            local flag="${PREFIX%%=*}"
            compset -P '*='
            case "$flag" in
                --switch|--switch-force|--uninstall|--uninstall-force) compadd -a versions ;;
            esac
            return
        fi
        _describe -t commands 'phpswitch command' subcmds
        compadd -S '' -- ${(M)_phpswitch_completion_flags:#*=}
        compadd -- ${_phpswitch_completion_flags:#*=}
        return
    fi

    case "$words[2]" in
        use) compadd -- auto $versions ;;
        global|local) compadd -a versions ;;
        init|completions) compadd zsh bash fish ;;
    esac
}
(( $+functions[compdef] )) && compdef _phpswitch_complete phpswitch
EOF
}

function completions_print_fish {
    printf "# phpswitch completions (fish)\n"
    printf "set -g _phpswitch_completion_prefix '%s'\n" "$HOMEBREW_PREFIX"
    cat << 'EOF'
function __phpswitch_versions
    for d in $_phpswitch_completion_prefix/opt/php@*
        test -x "$d/bin/php"; and string replace -r '.*/php@' '' -- $d
    end
end

complete -c phpswitch -f
complete -c phpswitch -n __fish_use_subcommand -a use -d 'Use a version in this shell only'
complete -c phpswitch -n __fish_use_subcommand -a global -d 'Switch the global (Homebrew-linked) version'
complete -c phpswitch -n __fish_use_subcommand -a local -d 'Write .php-version here'
complete -c phpswitch -n __fish_use_subcommand -a init -d 'Print shell integration code'
complete -c phpswitch -n __fish_use_subcommand -a doctor -d 'Check your PHP setup'
complete -c phpswitch -n __fish_use_subcommand -a completions -d 'Print shell completions'
complete -c phpswitch -n '__fish_seen_subcommand_from use' -a 'auto (__phpswitch_versions)'
complete -c phpswitch -n '__fish_seen_subcommand_from global local' -a '(__phpswitch_versions)'
complete -c phpswitch -n '__fish_seen_subcommand_from init completions' -a 'zsh bash fish'
EOF
    local flag name
    for flag in $COMPLETION_FLAGS; do
        name="${flag#--}"
        case "$name" in
            *=) printf "complete -c phpswitch -n __fish_use_subcommand -l %s -x -a '(__phpswitch_versions)'\n" "${name%=}" ;;
            *) printf "complete -c phpswitch -n __fish_use_subcommand -l %s\n" "$name" ;;
        esac
    done
}
