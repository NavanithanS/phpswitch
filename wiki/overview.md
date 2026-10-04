---
title: PHPSwitch Overview
category: overview
tags: [project, cli, php, homebrew, macos]
created: 2026-04-06
updated: 2026-10-03
sources: 1
---

# PHPSwitch Overview

PHPSwitch is a macOS CLI tool for switching between Homebrew-managed PHP versions. It is distributed as a single self-contained bash script (`php-switcher.sh`) built from a modular source tree.

## What it does

- Switch the active PHP version (symlinks, PATH) via an interactive menu or non-interactive flags
- Manage PHP-FPM services (start/stop/restart per version)
- Enable and disable PHP extensions
- Per-shell PHP switching (v2): `eval "$(phpswitch init zsh)"` gives each terminal its own version that follows the project (`.php-version`, `composer.json` constraints, `.tool-versions`). See [[concepts/shell-integration]].
- Global switching (`phpswitch global`) via `brew link`, for PHP-FPM, Valet and IDEs
- Read-only diagnostics (`phpswitch doctor`), shell completions, and a checksum-verified `--update`
- Patch shell config files (`~/.zshrc`, the bash file bash actually reads, `~/.config/fish/config.fish`) for the integration line and the global PATH block, and remove the integration line again on "Disable auto-switching"

## Key design choices

- **Single-file distribution**: the entire tool ships as one bash script, built by concatenating library modules. This makes installation and sharing trivial.
- **Homebrew-only**: targets PHP versions installed via Homebrew. Does not manage system PHP or versions from other package managers.
- **macOS-only**: relies on macOS conventions (Homebrew prefix, Homebrew services, launchd).
- **Test suite**: testing is automated using `bats-core` (tests are in `tests/`, harness in [[concepts/testing]]) and `shellcheck`, both run in GitHub Actions CI. Manual testing is also supported against the development entry point (`phpswitch/phpswitch.sh`) or the built artifact.

## Entry points

| File | Purpose |
|------|---------|
| `phpswitch/phpswitch.sh` | Development entry point — sources lib modules at runtime |
| `php-switcher.sh` | Built artifact — standalone, for distribution and installation |
| `phpswitch/build.sh` | Build script — produces `php-switcher.sh` |

## Configuration

Runtime config lives in `~/.phpswitch.conf`. Missing keys fall back to defaults in `phpswitch/config/defaults.sh`. The config is loaded at startup via `core_load_config` ([[entities/lib-core]]).

## See also

- [[architecture/build-system]]
- [[architecture/module-pipeline]]
- [[concepts/auto-switch]]
- [[concepts/fpm-management]]
