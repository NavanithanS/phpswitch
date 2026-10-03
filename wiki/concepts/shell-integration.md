---
title: Per-Shell Integration
category: concept
tags: [shell, path, auto-switch, init, v2]
created: 2026-10-03
updated: 2026-10-03
sources: 0
---

# Per-Shell Integration (`lib/init.sh`)

Since v2, the default model is switching **per shell**: each terminal can use a different PHP version, and nothing global changes. The global `brew link` switch (`phpswitch global` / `--switch`) remains for PHP-FPM, Valet and IDEs. Decided in [[decisions/roadmap-2026]].

## Why a shell function

A child process can't change its parent shell's `PATH`. The rc file therefore loads a function:

```sh
eval "$(phpswitch init zsh)"     # bash: init bash; fish: phpswitch init fish | source
```

## What `init` prints

| Piece | Role |
|-------|------|
| `PHPSWITCH_BIN`, `PHPSWITCH_PREFIX` | Absolute binary path and Homebrew prefix, baked in at init (single-quoted; init refuses paths containing `'`, `\` or newlines) |
| `phpswitch()` wrapper | `use <v>` / `use auto`; `local` and `global` re-run the hook afterwards; everything else is passed to the binary |
| `_phpswitch_hook` | zsh `chpwd`, bash `PROMPT_COMMAND` (returns early if `$PWD` hasn't changed), fish `--on-variable PWD` |
| `_phpswitch_detect` | Walks up from `$PWD` while inside `$HOME`. At each level: `.php-version`/`.phpversion`, then `composer.json`/`.tool-versions`. **Fast path:** an exact `X.Y` or `php@X.Y` whose `opt/php@X.Y/bin/php` exists is resolved in pure shell. Anything else is delegated to `phpswitch __php-dir`. |
| `_phpswitch_apply` | Removes its previous `bin`/`sbin` entries (exact match only), prepends the new ones, and tracks them in `PHPSWITCH_PHP_DIR` |
| `_phpswitch_valid_dir` | Accepts a directory only if it's under `$PHPSWITCH_PREFIX/opt/php*`, contains no `:` or newline, and has an executable `bin/php` |

## Precedence

`phpswitch use X` (sets `PHPSWITCH_PINNED`, exported) > project files > global Homebrew link.

Leaving a project removes the per-shell entry, so the global version shows through again.

## Invariants (tested in `tests/09_shell_integration.bats`)

- The hook gives the same result as `version_check_project` (parity test).
- PATH doesn't grow across `cd`s or in nested shells.
- The hook never links, unlinks or restarts FPM.
- `__php-dir` writes only a path to stdout and rejects invalid input.
- Generated code passes `bash -n`, `zsh -n` and, in CI, `fish -n`, and works under `set -u`.

## Relationship to the legacy hook

The old `phpswitch_auto_detect_project` hook (`lib/auto-switch.sh`) calls `--auto-mode`, which does a **global** relink plus an FPM restart on `cd`. It still works for users who haven't migrated. Migrating rc files to the `eval` line is Phase 3b.

## See also

- [[concepts/auto-switch]]
- [[concepts/shell-patching]]
- [[decisions/roadmap-2026]]
