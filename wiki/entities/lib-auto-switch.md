---
title: lib/auto-switch.sh
category: entity
tags: [module, auto-switch, hooks, cd, directory]
created: 2026-04-06
updated: 2026-10-04
sources: 1
---

# lib/auto-switch.sh

Installs per-shell switching into rc files, migrates the legacy hook, and keeps the legacy global auto-switch for unmigrated users.

## Responsibilities

- `auto_install` (`--install-auto-switch`): writes the `phpswitch init` line into the login shell's rc file and removes 1.x `phpswitch_auto_detect_project` blocks from every rc file, all-or-nothing, with backups and atomic writes. See [[concepts/shell-integration]].
- `auto_uninstall` (`--uninstall-auto-switch`, menu "Disable auto-switching"): removes the integration line and legacy blocks from every rc file, all-or-nothing, then sets `AUTO_SWITCH_PHP_VERSION=false`. Helpers: `auto_rc_candidates` (the one rc file list, also used by doctor), `auto_integration_rc_files`, `auto_is_installed`, `auto_strip_init_lines`.
- `auto_strip_legacy_hooks`, `auto_legacy_rc_candidates`, `auto_login_shell`, `auto_rc_file`: helpers for migration, also used by [[concepts/doctor]].
- `auto_switch_php`: the legacy global relink used by `--auto-mode` (still called by unmigrated 1.x hooks).
- `auto_clear_directory_cache`: clears the legacy hook's directory cache.

## See also

- [[concepts/shell-integration]]

- [[concepts/auto-switch]]
- [[entities/lib-shell]]
- [[entities/lib-version]]
