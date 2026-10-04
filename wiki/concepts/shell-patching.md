---
title: Shell Patching
category: concept
tags: [shell, rc-file, PATH, zsh, bash, fish]
created: 2026-04-06
updated: 2026-04-06
sources: 1
---

# Shell Patching

PHPSwitch modifies the user's shell config files to export the correct `PATH` for the active PHP version.

## Supported shells and their config files

| Shell | Config file |
|-------|------------|
| zsh | `~/.zshrc` |
| bash | From `shell_bash_rc_file` (see below) |
| fish | `~/.config/fish/config.fish` |

### Bash on macOS

Terminal starts **login** shells, and login bash reads only the first of `.bash_profile`, `.bash_login` and `.profile`, never `.bashrc`. `shell_bash_rc_file` (used for both the managed PATH block and the integration line) therefore picks:

1. Any bash startup file that already contains phpswitch's own content (the managed block or the integration marker), so existing setups never get a second copy.
2. On macOS: the first existing login file. If that file sources `.bashrc` (an uncommented `. …bashrc` or `source …bashrc` line), `.bashrc` instead, since it then covers non-login shells too. With no login file at all, `.bash_profile` is created. An existing `.bash_login` or `.profile` is never shadowed by creating `.bash_profile`.
3. Elsewhere: `.bashrc`, `.bash_profile`, `.profile`, else a new `.bashrc`.

## What gets written

An `export PATH=...` line (or fish equivalent) pointing to the Homebrew prefix for the selected PHP version. On subsequent switches, the line is updated in-place rather than appended again.

## Backups

Before any modification, `lib/shell.sh` creates a backup of the rc file. This is a safety net — the original is always recoverable.

## Detection

`lib/shell.sh` detects the current shell via `$SHELL` or process inspection and selects the appropriate rc file automatically.

## See also

- [[entities/lib-shell]]
- [[concepts/auto-switch]]

## Update (2026-10-03)

- The rc file is chosen from the **login shell** (`$SHELL`), because `shell_detect_shell` checks it first. Before, it always returned `bash`, since phpswitch runs under bash, so zsh users' blocks went into `.bashrc`.
- The managed block is written with `utils_replace_file_contents`: a temp file next to the resolved target, given the same mode, then `mv`. The write is atomic and symlinked dotfiles survive.
- **No-op on the same version:** if the managed block's own header (`# Path configuration for PHP version: X`, read only between the markers) already names the target version, `shell_update_rc` changes nothing and makes no backup. `version_switch_php` also skips the PHP-FPM restart unless the link changed or the version was reinstalled.
