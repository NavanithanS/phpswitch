---
title: PHPSwitch Overview
category: overview
tags: [project, cli, php, homebrew, macos]
created: 2026-04-06
updated: 2026-04-06
sources: 1
---

# PHPSwitch Overview

PHPSwitch is a macOS CLI tool for switching between Homebrew-managed PHP versions. It is distributed as a single self-contained bash script (`php-switcher.sh`) built from a modular source tree.

## What it does

- Switch the active PHP version (symlinks, PATH) via an interactive menu or non-interactive flags
- Manage PHP-FPM services (start/stop/restart per version)
- Enable and disable PHP extensions
- Auto-switch PHP version when entering a directory (reads `.php-version`, `composer.json`, `.tool-versions`)
- Patch shell config files (`~/.zshrc`, `~/.bashrc`, `~/.config/fish/config.fish`) to export the correct PATH

## Key design choices

- **Single-file distribution**: the entire tool ships as one bash script, built by concatenating library modules. This makes installation and sharing trivial.
- **Homebrew-only**: targets PHP versions installed via Homebrew. Does not manage system PHP or versions from other package managers.
- **macOS-only**: relies on macOS conventions (Homebrew prefix, Homebrew services, launchd).
- **Test suite**: testing is automated using `bats-core` (tests are in `tests/`) and `shellcheck`. Manual testing is also supported against the development entry point (`phpswitch/phpswitch.sh`) or the built artifact.

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
