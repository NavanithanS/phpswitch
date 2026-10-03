---
title: Auto-Switch
category: concept
tags: [auto-switch, cd, hooks, directory, php-version]
created: 2026-04-06
updated: 2026-10-03
sources: 1
---

# Auto-Switch

> **v2:** per-shell switching via `eval "$(phpswitch init <shell>)"` replaces this legacy global hook. See [[concepts/shell-integration]]. The legacy hook below still works for users who haven't migrated. `--install-auto-switch` now installs the v2 integration and migrates this hook away.

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
| `composer.json` | `config.platform.php` (exact pin), else `require.php` constraint, resolved as described below |
| `.tool-versions` | `php X.Y` line (asdf format) |

If a declaration is found, PHPSwitch switches to that version automatically. If none is found, no switch occurs (it does not revert to a default).

## Installation

The hook is installed by patching the shell rc file ([[concepts/shell-patching]]). Run `phpswitch --auto-switch` or the equivalent setup command to install.

## See also

- [[entities/lib-auto-switch]]
- [[entities/lib-shell]]
- [[concepts/shell-patching]]
- [[concepts/version-format]]

## composer.json constraints (2026-10-03)

`require.php` is a composer constraint (`^8.1`, `>=8.2 <8.4`, `^7.4 || ^8.0`, `8.1.*`, `8.1 - 8.3`, …), resolved against the installed PHP series in this order:

1. The **historical answer** (the first `X.Y` in the constraint), if it's installed and satisfies the constraint, so projects that already worked never move.
2. Otherwise, the **lowest installed series** that satisfies the constraint.
3. Otherwise, the historical answer (which may not be installed).

Installed series come from globbing `$HOMEBREW_PREFIX/opt/php@*` and `opt/php` → `Cellar/php/X.Y.Z` (`utils_installed_php_series`). It never runs `brew list`, because the per-shell hook triggers this on `cd`. Matching is done per series (`utils_composer_constraint_matches` / `utils_composer_atom_matches`): a series matches if any patch release in it would. Implementation notes: atoms are split with `read -a` (a bare `*` must not glob), and the matcher resets `IFS` because bash 3.2 mangles `|` in regexes otherwise. See `tests/14_composer_constraints.bats`.

