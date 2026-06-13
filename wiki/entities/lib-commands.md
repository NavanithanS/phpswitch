---
title: lib/commands.sh
category: entity
tags: [module, cli, dispatch, arguments]
created: 2026-04-06
updated: 2026-04-06
sources: 1
---

# lib/commands.sh

CLI entry layer. Last module in the [[architecture/module-pipeline]] (before main block).

## Responsibilities

- Parses `$@` (CLI arguments and flags)
- Dispatches to functions in other modules based on the invocation:
  - `--list` → version listing
  - `--current` → show active version
  - `--switch <ver>` / interactive menu → version switch
  - `--clear-cache` / `--refresh-cache` → cache management
  - Extension subcommands → `lib/extensions.sh`
  - FPM subcommands → `lib/fpm.sh`
  - `--auto-switch` → `lib/auto-switch.sh`

## Dependencies

All other modules (it calls into all of them).

## See also

- [[architecture/module-pipeline]]
- [[entities/lib-version]]
- [[entities/lib-fpm]]
- [[entities/lib-extensions]]
