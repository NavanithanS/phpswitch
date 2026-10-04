---
title: PHP-FPM Management
category: concept
tags: [fpm, services, homebrew, launchd]
created: 2026-04-06
updated: 2026-10-04
sources: 1
---

# PHP-FPM Management

PHPSwitch can start, stop, and restart PHP-FPM services as part of a version switch.

## Mechanism

Uses Homebrew Services (`brew services`) which wraps launchd on macOS. Each PHP version has its own FPM service named after the Homebrew formula (e.g. `php@8.2`).

## Operations

- Start FPM for a version
- Stop FPM for a version
- Restart FPM (stop old version's FPM, start new version's FPM) — typically done automatically on switch

## Legacy auto-switch (`--auto-mode`)

`auto_switch_php` (called by unmigrated 1.x `cd` hooks) only acts on PHP services whose `brew services list` status is `started`: it stops the other running versions and starts the new one, or restarts it if it is already running. When no PHP-FPM was running, it starts none (before 2026-10-04 every project `cd` started one). Tests feed the fake `brew` a service list through `FAKE_BREW_SERVICES`.

## Module

All FPM logic lives in [[entities/lib-fpm]].

## macOS dependency

This feature is macOS-specific. It relies on `brew services` and launchd. There is no Linux equivalent in scope.

## See also

- [[entities/lib-fpm]]
- [[concepts/version-format]]
- [[overview]]
