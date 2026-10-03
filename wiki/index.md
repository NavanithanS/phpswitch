# Wiki Index — PHPSwitch

Content catalog. Updated on every ingest. The LLM reads this first when answering queries.

## Overview

| Page | Summary |
|------|---------|
| [[overview]] | High-level project summary: what PHPSwitch is and who it's for |

## Architecture

| Page | Summary |
|------|---------|
| [[architecture/build-system]] | How `build.sh` concatenates modules into `php-switcher.sh` |
| [[architecture/module-pipeline]] | Load order and dependency contract between lib modules |
| [[architecture/config-system]] | How `~/.phpswitch.conf` is loaded and how defaults are applied |

## Entities (modules, files, commands)

| Page | Summary |
|------|---------|
| [[entities/phpswitch-sh]] | Development entry point — sources all lib modules |
| [[entities/php-switcher-sh]] | Built artifact — single-file standalone distributable |
| [[entities/lib-core]] | Config loading, debug logging, temp file cleanup |
| [[entities/lib-utils]] | Path validation, cache, spinners, temp files |
| [[entities/lib-shell]] | Shell detection (zsh/bash/fish) and rc file patching |
| [[entities/lib-version]] | PHP version detection, install/uninstall/switch logic |
| [[entities/lib-fpm]] | PHP-FPM service management |
| [[entities/lib-extensions]] | PHP extension enable/disable/info |
| [[entities/lib-auto-switch]] | Directory-based auto-switching hooks |
| [[entities/lib-commands]] | CLI argument parsing and dispatch |
| [[concepts/shell-integration]] (`lib/init.sh`) | Per-shell integration module |

## Concepts

| Page | Summary |
|------|---------|
| [[concepts/version-format]] | How PHP versions are normalized internally (`php@X.Y`) |
| [[concepts/caching]] | Version list cache under `~/.cache/phpswitch/`, TTL and invalidation |
| [[concepts/auto-switch]] | `.php-version`, `composer.json`, `.tool-versions` detection on `cd` |
| [[concepts/shell-patching]] | How PATH exports are appended/updated in shell rc files |
| [[concepts/fpm-management]] | Starting, stopping, and restarting PHP-FPM per version |
| [[concepts/testing]] | bats harness (fake brew/curl/sudo, isolated HOME), suites, CI pipeline |
| [[concepts/shell-integration]] | v2 per-shell switching: `init`, wrapper, pure-shell hook, invariants |
| [[concepts/release-and-update]] | release.sh flow and the fail-closed, checksum-verified `--update` |

## Decisions

| Page | Summary |
|------|---------|
| [[decisions/roadmap-2026]] | Phased improvement plan (hygiene → CI → release hardening → v2 per-shell switching → features) |

## Sources

*(None yet — add summary pages here as external documents are ingested)*
