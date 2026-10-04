---
title: php-switcher.sh
category: entity
tags: [artifact, distribution, single-file, built]
created: 2026-04-06
updated: 2026-04-06
sources: 1
---

# php-switcher.sh

The built distributable. A single self-contained bash script produced by `build.sh`.

## Key properties

- No external dependencies beyond Homebrew and standard macOS tools
- SHA256 checksum printed at build time — needed for Homebrew formula updates
- Do not edit directly; edit source modules and rebuild

## Production use

This is the file users install. When installed via Homebrew, this is what runs.

## See also

- [[entities/phpswitch-sh]]
- [[architecture/build-system]]
