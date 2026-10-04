---
title: lib/utils.sh
category: entity
tags: [module, utils, cache, spinner, temp]
created: 2026-04-06
updated: 2026-04-06
sources: 1
---

# lib/utils.sh

General-purpose utilities used across all higher modules.

## Responsibilities

- Path validation (Homebrew prefix checks)
- Cache read/write for version lists ([[concepts/caching]])
- Terminal spinners for long-running operations
- Temp file creation and registration for cleanup

## See also

- [[entities/lib-core]]
- [[concepts/caching]]
- [[architecture/module-pipeline]]
