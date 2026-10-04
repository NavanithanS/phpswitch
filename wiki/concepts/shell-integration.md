---
title: Per-Shell Integration
category: concept
tags: [shell, path, auto-switch, init, v2]
created: 2026-10-03
updated: 2026-10-04
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
| `phpswitch()` wrapper | `use <v>` / `use auto` (each prints what the shell now uses); `local` and `global` re-run the hook afterwards; everything else is passed to the binary |
| `_phpswitch_hook` | zsh `chpwd` and `precmd`, bash `PROMPT_COMMAND`, fish `--on-variable PWD` and the `fish_prompt` event (`_phpswitch_prompt_hook`). Returns early unless `$PWD` or the signature changed, and always returns the caller's exit status, for status-aware prompts. |
| `_phpswitch_signature` | Per-prompt change check using builtins only (no processes). It finds the first directory `_phpswitch_detect` would stop at, records which of the four files it holds, and includes the contents of `.php-version`, `.phpversion` and `.tool-versions`. So a version file created, edited or deleted in the current tree applies at the next prompt. Not seen until `phpswitch use auto` or re-entering the directory: edits inside `composer.json` (only its presence counts) and PHP versions installed later. |
| `_phpswitch_detect` | Walks up from `$PWD` while it is `$HOME` or below it (whole path components, as in `version_check_project`). At each level: `.php-version`/`.phpversion`, then `composer.json`/`.tool-versions`. **Fast path:** an exact `X.Y` or `php@X.Y` whose `opt/php@X.Y/bin/php` exists is resolved in pure shell. Anything else (including a full patch `8.2.10`) is delegated to `phpswitch __php-dir`. |
| `_phpswitch_apply` | Removes its previous `bin`/`sbin` entries (exact match only), prepends the new ones, and tracks them in `PHPSWITCH_PHP_DIR` |
| `_phpswitch_valid_dir` | Accepts a directory only if it's under `$PHPSWITCH_PREFIX/opt/php*`, contains no `:` or newline, and has an executable `bin/php` |

## Precedence

`phpswitch use X` (sets `PHPSWITCH_PINNED`, exported) > project files > global Homebrew link.

Leaving a project removes the per-shell entry, so the global version shows through again.

## Startup details

- The init epilogue clears `_phpswitch_last_pwd` before its first hook call. That way re-sourcing the rc file inside a project re-applies the project's PHP, even though the global PATH block near the top of the rc file has just put the global version first again.
- `init` runs from rc files, possibly before `brew shellenv`. If `brew` isn't on PATH, `core_load_config` falls back to `/opt/homebrew/bin/brew`, then `/usr/local/bin/brew`, overridable for tests with `PHPSWITCH_BREW_CANDIDATES`.
- `_phpswitch_valid_dir` also rejects paths containing `/..`.

## Invariants (tested in `tests/09_shell_integration.bats`)

- The hook gives the same result as `version_check_project` (parity test).
- PATH doesn't grow across `cd`s or in nested shells.
- The hook never links, unlinks or restarts FPM.
- `__php-dir` writes only a path to stdout and rejects invalid input.
- Generated code passes `bash -n`, `zsh -n` and, in CI, `fish -n`, and works under `set -u`.

## Installing and migrating (`--install-auto-switch` → `auto_install`)

- **Target rc file:** chosen from the **login shell** (`$SHELL`): `.zshrc`, the bash file from `shell_bash_rc_file` (on macOS the login file bash actually reads; see [[concepts/shell-patching]]), or `config.fish`. `auto_login_shell` is the strict form: it fails for unsupported shells instead of guessing.
- **Written line:** `# PHPSwitch shell integration`, followed by `[ -x '<bin>' ] && eval "$('<bin>' init zsh)"` (fish: `test -x '<bin>'; and '<bin>' init fish | source`). The `# PHPSwitch shell integration` marker makes the install idempotent.
- **Legacy hook:** `phpswitch_auto_detect_project`, written by 1.x. It calls `--auto-mode`, which relinks PHP globally and restarts FPM on `cd`. Migration:
  1. Collect every rc file that mentions it (`.zshrc`, `.bashrc`, `.bash_profile`, `.profile`, `config.fish`). Because of the `shell_detect_shell` bug, 1.x often wrote zsh users' hooks into `.bashrc`.
  2. **Validate all of them before writing anything.** A block is removed only if it starts with the exact line `# PHPSwitch auto-switching` and has a bare `phpswitch_auto_detect_project` line within 100 lines. The v1.4.0 variant (`… hooks`), a missing end line, or any leftover reference after stripping makes it an *unsafe* file. If any file is unsafe, **no file is changed** and manual instructions are printed.
  3. Back up each file (`<rc>.bak.<timestamp>`, mode 600), then replace it atomically with `utils_replace_file_contents`, so symlinked dotfiles stay symlinks.
  4. Delete `~/.cache/phpswitch/directory_cache.txt`.
- **Fixtures:** `tests/fixtures/legacy-<commit>-<shell>.rc` are the real output of the historical installers (v1.4.1 `bfc6fa9`, last 1.x `32bad01`), produced by sourcing those modules.
- `--auto-mode` and `--clear-directory-cache` remain for users who haven't migrated.

## Disabling (`auto_uninstall`)

`phpswitch --uninstall-auto-switch`, or "Disable auto-switching" in the menu (main menu `a`, or answering no to config option 5), removes phpswitch from the shell config instead of only flipping `AUTO_SWITCH_PHP_VERSION`, which nothing at shell startup reads.

- Whether auto-switching is on is judged by the rc files (`auto_is_installed`: the integration marker as a whole line, or a legacy hook, in any file from `auto_rc_candidates`: `.zshrc`, `.zprofile`, `.bashrc`, `.bash_profile`, `.bash_login`, `.profile`, `config.fish`), not by the config flag. The flag stays `false` when the line was installed before `~/.phpswitch.conf` existed.
- From every such file it removes the marker, the `… init <shell>` line after it and the blank separator before it (`auto_strip_init_lines`), plus any legacy block (`auto_strip_legacy_hooks`). Uninstalling right after installing restores the file byte for byte.
- Same rules as installing: every file's new content is built and validated first; if a line after the marker isn't an init line phpswitch wrote, a legacy block is unsafe, or a file isn't writable, **no file is changed**. Each file is backed up and replaced atomically.
- Then the config flag is set to `false`. `phpswitch use` disappears with the hook in new terminals; `phpswitch global` keeps working. A line the user added by hand (no marker) is left alone, with instructions.

## See also

- [[concepts/auto-switch]]
- [[concepts/shell-patching]]
- [[decisions/roadmap-2026]]

## Completions (`lib/completions.sh`)

`phpswitch completions <bash|zsh|fish>` prints a completion script. It's kept separate from `init` so shell startup stays fast. Installed versions come from globbing the prefix baked in at generation time, so completing never runs `brew` or phpswitch. Subcommands and flags live in `COMPLETION_SUBCOMMANDS` and `COMPLETION_FLAGS`, and `tests/13_completions.bats` fails if they drift from `--help`. In bash, "no trailing space" applies only to `--flag=` completions, and only where `compopt` exists (bash 4+).

