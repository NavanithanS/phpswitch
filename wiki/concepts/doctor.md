---
title: Doctor
category: concept
tags: [doctor, diagnostics, troubleshooting]
created: 2026-10-03
updated: 2026-10-03
sources: 0
---

# Doctor (`lib/doctor.sh`)

`phpswitch doctor` (also menu option `d`) is the single diagnostics engine. It replaced `utils_diagnose_path_issues` and the unused `utils_diagnose_php_environment`.

**Contract:** read-only. No network, no sudo, no file writes, no `brew services` calls. It exits non-zero only when a check *fails*; warnings don't affect the exit status. `tests/11_doctor.bats` checks this by hashing the whole fake tree before and after a run, and by inspecting the brew log.

## Checks

| # | Check | Level |
|---|-------|-------|
| 1 | PHP installed under `$HOMEBREW_PREFIX/opt` (glob, no `brew list`) | fail if none |
| 2 | Globally linked version | warn if none |
| 3 | `php` on PATH vs. expected: `$PHPSWITCH_PHP_DIR/bin/php` when per-shell switching is active, else `$HOMEBREW_PREFIX/bin/php` | fail if missing, warn if different |
| 4 | Other `php` binaries on PATH (MAMP, Herd, system) | warn |
| 5 | Per-shell integration in the login shell's rc file, and whether it's loaded (`PHPSWITCH_BIN` set) | warn |
| 6 | `phpswitch use` pin active | warn |
| 7 | Legacy auto-switch hook in any rc file (`auto_legacy_rc_candidates`) | warn |
| 8 | Project version: not installed (fail), or the shell is using a different one (warn) | fail / warn |
| 9 | Root PHP-FPM LaunchDaemons (`$PHPSWITCH_LAUNCH_DAEMONS_DIR`, default `/Library/LaunchDaemons`) | warn |
| 10 | Root-owned files in `Cellar/php*` (depth ≤ 3) | warn |

## See also

- [[concepts/shell-integration]]
- [[concepts/fpm-management]]
