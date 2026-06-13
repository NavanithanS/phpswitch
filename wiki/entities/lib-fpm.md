---
title: lib/fpm.sh
category: entity
tags: [module, fpm, services, launchd, homebrew]
created: 2026-04-06
updated: 2026-04-06
sources: 1
---

# lib/fpm.sh

PHP-FPM service lifecycle management.

## Responsibilities

- Start / stop / restart PHP-FPM for a given version via `brew services`
- On version switch: stop old FPM, start new FPM

## macOS only

Relies on `brew services` and launchd. No Linux support in scope.

## See also

- [[concepts/fpm-management]]
- [[concepts/version-format]]
