---
title: Auto-Switch
category: concept
tags: [auto-switch, cd, hooks, directory, php-version]
created: 2026-04-06
updated: 2026-10-03
sources: 1
---

# Auto-Switch

> **v2:** per-shell switching via `eval "$(phpswitch init <shell>)"` replaces this legacy global hook. See [[concepts/shell-integration]]. The legacy hook below still works for users who haven't migrated.

PHPSwitch can automatically switch the active PHP version when you `cd` into a directory that declares a PHP version requirement.

## How it works

`lib/auto-switch.sh` installs a hook into the user's shell that fires on directory change:

| Shell | Hook mechanism |
|-------|---------------|
| zsh | `chpwd` hook function |
| bash | `cd` wrapper function |
| fish | `cd` wrapper function |

On each directory change, the hook looks for a version declaration file in the current directory (or its parents).

## Version declaration files (checked in order)

| File | Key |
|------|-----|
| `.php-version` | Plain version string, e.g. `8.2` |
| `composer.json` | `require.php` field |
| `.tool-versions` | `php X.Y` line (asdf format) |

If a declaration is found, PHPSwitch switches to that version automatically. If none is found, no switch occurs (it does not revert to a default).

## Installation

The hook is installed by patching the shell rc file ([[concepts/shell-patching]]). Run `phpswitch --auto-switch` or the equivalent setup command to install.

## See also

- [[entities/lib-auto-switch]]
- [[entities/lib-shell]]
- [[concepts/shell-patching]]
- [[concepts/version-format]]
