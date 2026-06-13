---
title: Config System
category: architecture
tags: [config, defaults, runtime, core]
created: 2026-04-06
updated: 2026-04-06
sources: 1
---

# Config System

PHPSwitch uses a two-layer config system: compile-time defaults and a user runtime config file.

## Layers

| Layer | File | Purpose |
|-------|------|---------|
| Defaults | `phpswitch/config/defaults.sh` | Hardcoded fallback values for all config keys |
| User config | `~/.phpswitch.conf` | User overrides; missing keys fall back to defaults |

## Loading

`core_load_config` (in [[entities/lib-core]]) runs at startup. It reads `~/.phpswitch.conf` if it exists and applies each key. Any key absent from the user config retains its default value from `defaults.sh`.

## Notable config keys (from defaults)

- Cache path: `~/.cache/phpswitch/` (overridable)
- Cache TTL: 1 hour

## See also

- [[entities/lib-core]]
- [[concepts/caching]]
