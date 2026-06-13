---
title: lib/auto-switch.sh
category: entity
tags: [module, auto-switch, hooks, cd, directory]
created: 2026-04-06
updated: 2026-04-06
sources: 1
---

# lib/auto-switch.sh

Directory-based PHP version auto-switching.

## Responsibilities

- Install shell hooks (`chpwd` for zsh, `cd` wrapper for bash/fish) via [[entities/lib-shell]]
- On directory change: scan for `.php-version`, `composer.json`, `.tool-versions`
- If a version declaration is found, trigger a version switch

## See also

- [[concepts/auto-switch]]
- [[entities/lib-shell]]
- [[entities/lib-version]]
