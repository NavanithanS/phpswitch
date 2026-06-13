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
| bash | `~/.bashrc` |
| fish | `~/.config/fish/config.fish` |

## What gets written

An `export PATH=...` line (or fish equivalent) pointing to the Homebrew prefix for the selected PHP version. On subsequent switches, the line is updated in-place rather than appended again.

## Backups

Before any modification, `lib/shell.sh` creates a backup of the rc file. This is a safety net — the original is always recoverable.

## Detection

`lib/shell.sh` detects the current shell via `$SHELL` or process inspection and selects the appropriate rc file automatically.

## See also

- [[entities/lib-shell]]
- [[concepts/auto-switch]]
