---
title: lib/commands.sh
category: entity
tags: [module, cli, dispatch, arguments]
created: 2026-04-06
updated: 2026-10-03
sources: 1
---

# lib/commands.sh

CLI entry layer. Last module in the [[architecture/module-pipeline]] (before main block).

> **2026-10-03:** split as a pure move (verified by identical `declare -f` output). The interactive menu and configuration screens (`cmd_show_menu`, `cmd_configure_*`, `cmd_show_uninstall_menu`) are now in `lib/menu.sh`. `--install`, `--uninstall` and `--update` (`cmd_install_as_command`, `cmd_uninstall_command`, `cmd_update_self`, `cmd_resolve_script_path`) are now in `lib/self-manage.sh`. This file keeps `cmd_parse_arguments`, the non-interactive switch/install/uninstall, listing and cache commands. v2 subcommands (`use`, `global`, `local`, `init`, `completions`, `doctor`, `__php-dir`) are dispatched at the top of `cmd_parse_arguments`.

## Responsibilities

- Parses `$@` (CLI arguments and flags)
- Dispatches to functions in other modules based on the invocation:
  - `--list` → version listing
  - `--current` → show active version
  - `--switch <ver>` / interactive menu → version switch
  - `--clear-cache` / `--refresh-cache` → cache management
  - Extension subcommands → `lib/extensions.sh`
  - FPM subcommands → `lib/fpm.sh`
  - `--install-auto-switch` → `lib/auto-switch.sh`
  - `init`/`use`/`__php-dir` → `lib/init.sh`, `completions` → `lib/completions.sh`, `doctor` → `lib/doctor.sh`
  - `--install`/`--uninstall`/`--update` → `lib/self-manage.sh`; no arguments → `lib/menu.sh`

## Dependencies

All other modules (it calls into all of them).

## See also

- [[architecture/module-pipeline]]
- [[entities/lib-version]]
- [[entities/lib-fpm]]
- [[entities/lib-extensions]]
