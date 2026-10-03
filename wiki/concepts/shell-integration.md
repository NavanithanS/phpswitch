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

## Installing and migrating (`--install-auto-switch` → `auto_install`)

- **Target rc file:** chosen from the **login shell** (`$SHELL`): `.zshrc`, `.bashrc` (or `.bash_profile` if only that exists), or `config.fish`. It does *not* use `shell_detect_shell`, which always says `bash` inside phpswitch because phpswitch runs under bash.
- **Written line:** `# PHPSwitch shell integration`, followed by `[ -x '<bin>' ] && eval "$('<bin>' init zsh)"` (fish: `test -x '<bin>'; and '<bin>' init fish | source`). The `# PHPSwitch shell integration` marker makes the install idempotent.
- **Legacy hook:** `phpswitch_auto_detect_project`, written by 1.x. It calls `--auto-mode`, which relinks PHP globally and restarts FPM on `cd`. Migration:
  1. Collect every rc file that mentions it (`.zshrc`, `.bashrc`, `.bash_profile`, `.profile`, `config.fish`). Because of the `shell_detect_shell` bug, 1.x often wrote zsh users' hooks into `.bashrc`.
  2. **Validate all of them before writing anything.** A block is removed only if it starts with the exact line `# PHPSwitch auto-switching` and has a bare `phpswitch_auto_detect_project` line within 100 lines. The v1.4.0 variant (`… hooks`), a missing end line, or any leftover reference after stripping makes it an *unsafe* file. If any file is unsafe, **no file is changed** and manual instructions are printed.
  3. Back up each file (`<rc>.bak.<timestamp>`, mode 600), then write through with `>` so symlinked dotfiles stay symlinks.
  4. Delete `~/.cache/phpswitch/directory_cache.txt`.
- **Fixtures:** `tests/fixtures/legacy-<commit>-<shell>.rc` are the real output of the historical installers (v1.4.1 `bfc6fa9`, last 1.x `32bad01`), produced by sourcing those modules.
- `--auto-mode` and `--clear-directory-cache` remain for users who haven't migrated.

## See also

- [[concepts/auto-switch]]
- [[concepts/shell-patching]]
- [[decisions/roadmap-2026]]
