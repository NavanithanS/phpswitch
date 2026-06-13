---
title: Module Pipeline
category: architecture
tags: [modules, load-order, dependencies, concatenation]
created: 2026-04-06
updated: 2026-04-06
sources: 1
---

# Module Pipeline

The build concatenates modules in a specific order. This order encodes the dependency contract: each module may only call functions defined by modules earlier in the pipeline.

## Load order

```
1. config/defaults.sh     # Constants and default config values — no deps
2. lib/core.sh            # Config loading, debug logging, temp file cleanup
3. lib/utils.sh           # Path validation, cache, spinners, temp files
4. lib/shell.sh           # Shell detection and rc file patching
5. lib/version.sh         # PHP version detection, install/uninstall/switch
6. lib/fpm.sh             # PHP-FPM service management
7. lib/extensions.sh      # PHP extension enable/disable/info
8. lib/auto-switch.sh     # Directory-based auto-switching hooks
9. lib/commands.sh        # CLI argument parsing and dispatch
--- (main block appended) ---
```

## Dependency rules

- `defaults` has no dependencies.
- `core` depends on defaults (config keys must exist before loading config).
- `utils` depends on core (uses debug logging).
- Higher modules (`version`, `fpm`, `extensions`) depend on `utils` and `shell`.
- `commands` depends on everything — it is the dispatcher that calls into all other modules.
- `auto-switch` depends on `shell` (needs shell detection to install the right hook).

## In development

`phpswitch/phpswitch.sh` sources the modules at runtime in this same order, so the load order is identical between development and production.

## See also

- [[architecture/build-system]]
- [[entities/lib-core]]
- [[entities/lib-commands]]
