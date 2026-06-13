---
title: Version Format
category: concept
tags: [versions, normalization, php]
created: 2026-04-06
updated: 2026-04-06
sources: 1
---

# Version Format

PHPSwitch normalizes all PHP version identifiers to a canonical internal format.

## Internal format

`php@X.Y` — e.g. `php@8.2`, `php@8.1`, `php@7.4`

This matches Homebrew's own naming convention for versioned formula taps.

## User-facing input

The CLI accepts both:
- Bare version: `8.2`
- Full format: `php@8.2`

Both are accepted and normalized internally before use.

## Where this matters

- Homebrew formula lookups use `php@X.Y`
- PATH manipulation uses the Homebrew prefix + `php@X.Y`
- PHP-FPM service names follow the same convention

## See also

- [[entities/lib-version]]
- [[concepts/caching]]
