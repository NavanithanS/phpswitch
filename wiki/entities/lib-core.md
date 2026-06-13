---
title: lib/core.sh
category: entity
tags: [module, config, logging, cleanup]
created: 2026-04-06
updated: 2026-04-06
sources: 1
---

# lib/core.sh

Foundation module. Loaded second in the [[architecture/module-pipeline]], after defaults.

## Responsibilities

- `core_load_config` — reads `~/.phpswitch.conf`, applies user overrides over defaults
- Debug logging — writes verbose output to stderr when `--debug` is active
- Temp file tracking and cleanup on exit

## Dependencies

- `config/defaults.sh` (must be sourced first)

## See also

- [[architecture/config-system]]
- [[architecture/module-pipeline]]
