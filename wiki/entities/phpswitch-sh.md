---
title: phpswitch/phpswitch.sh
category: entity
tags: [entry-point, development, sources]
created: 2026-04-06
updated: 2026-04-06
sources: 1
---

# phpswitch/phpswitch.sh

Development entry point. Sources all lib modules at runtime rather than concatenating them.

## Purpose

Allows editing individual modules without rebuilding. Behaves identically to the built artifact at runtime — same load order, same module contracts.

## Usage

```bash
./phpswitch/phpswitch.sh             # Interactive menu
./phpswitch/phpswitch.sh --debug     # Verbose debug output to stderr
./phpswitch/phpswitch.sh --list      # Non-interactive: list versions
./phpswitch/phpswitch.sh --current   # Show active PHP version
```

## See also

- [[entities/php-switcher-sh]]
- [[architecture/build-system]]
- [[architecture/module-pipeline]]
