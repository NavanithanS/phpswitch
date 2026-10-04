---
title: Caching
category: concept
tags: [cache, performance, versions]
created: 2026-04-06
updated: 2026-04-06
sources: 1
---

# Caching

PHPSwitch caches the list of available Homebrew PHP versions to avoid slow `brew list` calls on every invocation.

## Cache location

`~/.cache/phpswitch/` by default. Overridable via `~/.phpswitch.conf`.

## TTL

1 hour. After expiry the cache is rebuilt on next use.

## Cache management flags

```bash
phpswitch --clear-cache     # Delete the cache
phpswitch --refresh-cache   # Force rebuild immediately
```

## What is cached

Available PHP versions (the output of Homebrew version detection). Not user configuration or switch state.

## See also

- [[architecture/config-system]]
- [[entities/lib-utils]]
- [[concepts/version-format]]
