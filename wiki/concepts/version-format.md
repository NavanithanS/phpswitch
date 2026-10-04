---
title: Version Format
category: concept
tags: [versions, normalization, php]
created: 2026-04-06
updated: 2026-10-04
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

## Project files

`version_check_project` maps `.php-version`/`.phpversion` contents to `php@X.Y`:

- `8.2`, `php@8.2` and full patch versions such as `8.2.10` or `php@8.2.10` (phpenv style) all become `php@8.2`, because Homebrew installs are per minor series.
- A major-only `8` resolves to the highest installed `php@8.Y`.
- `.tool-versions` (`php 8.2.4`) and `composer.json` constraints are reduced to `X.Y` by their own readers (see [[concepts/auto-switch]]).

The search walks up from the current directory while it is `$HOME` or below it, comparing whole path components: `/Users/bobby` is not inside `/Users/bob`. The shell hooks use the same rule (see [[concepts/shell-integration]]).

## Where this matters

- Homebrew formula lookups use `php@X.Y`
- PATH manipulation uses the Homebrew prefix + `php@X.Y`
- PHP-FPM service names follow the same convention

## See also

- [[entities/lib-version]]
- [[concepts/caching]]
