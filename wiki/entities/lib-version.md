---
title: lib/version.sh
category: entity
tags: [module, version, switch, install, uninstall, homebrew]
created: 2026-04-06
updated: 2026-04-06
sources: 1
---

# lib/version.sh

Core PHP version management logic.

## Responsibilities

- Detect installed Homebrew PHP versions (using cache via [[entities/lib-utils]])
- Detect the currently active PHP version
- Switch the active version: update symlinks, patch PATH via [[entities/lib-shell]]
- Surface install/uninstall operations (delegated to Homebrew)

## Version format

All versions normalized to `php@X.Y`. See [[concepts/version-format]].

## See also

- [[concepts/version-format]]
- [[concepts/caching]]
- [[entities/lib-commands]]
