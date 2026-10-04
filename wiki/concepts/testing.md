---
title: Testing & CI
category: concept
tags: [testing, bats, ci, shellcheck]
created: 2026-10-03
updated: 2026-10-04
sources: 0
---

# Testing & CI

## Harness

Every suite does `load helpers/common` (`tests/helpers/common.bash`). `common_setup` provides:

| Piece | Purpose |
|-------|---------|
| `HOME=$TEST_ROOT/home` | rc files, `~/.phpswitch.conf` and caches stay in a throwaway directory |
| `tests/helpers/bin/brew` placed first on `PATH` | Fake Homebrew. `search` returns realistic output (header, tap prefix, ✔ marker). `list` returns `$FAKE_BREW_LIST`. `link` and `unlink` really repoint `$FAKE_BREW_PREFIX/bin/php`. Every call is logged to `$FAKE_BREW_LOG`. `services list` prints the lines of `$FAKE_BREW_SERVICES` (a file) under its header. |
| `FAKE_BREW_PREFIX` | Fake Homebrew prefix. `core_load_config` picks it up through `brew --prefix`. |
| `tests/helpers/bin/curl`, `tests/helpers/bin/sudo` | Fake curl serves `$FAKE_CURL_DIR` fixtures by URL (`fake_url <url> <file>`). Fake sudo always refuses, so tests never escalate. |
| `load_modules` | Sources defaults and all lib modules in build order, for unit tests |
| `fake_php_install php@X.Y` / `fake_php_link php@X.Y` | Create `opt/php@X.Y/bin/php` and point `bin/php` at it |

Unit tests call module functions directly. CLI tests (`07_cli.bats`) run the built `php-switcher.sh` and the dev entry point as real processes against the same fakes.

## Suites

| File | Covers |
|------|--------|
| `01_core.bats` | Artifact smoke tests: `--version`, `--help`, `--json` |
| `02_utils.bats` | Input and path validation |
| `03_versions.bats` | `brew search` parsing, installed and current version detection, `php@default` resolution |
| `04_project_version.bats` | `.php-version`, `.phpversion`, `composer.json`, `.tool-versions`, walking up parent directories, precedence, rejection of unsafe input, the `$HOME` boundary |
| `05_shell.bats` | rc file selection, managed-block insert and replace for zsh, bash and fish, backups |
| `06_switch.bats` | unlink-before-link order, rc update, no-op when already active, `auto_switch_php` |
| `07_cli.bats` | Flag dispatch and exit codes, `--get-project-version`, `--auto-mode` |
| `09_shell_integration.bats` | `init` output (bash/zsh/fish syntax, speed), `__php-dir`, the hook in real bash 3.2/zsh: PATH hygiene, nested shells, `use` pinning, nounset, parity with `version_check_project` |
| `10_install_auto_switch.bats` | rc install and migration against real legacy fixtures (`tests/fixtures/`): backups, all-or-nothing, symlinked rc files, idempotency, login-shell targeting |
| `11_doctor.bats` | `doctor` checks and its read-only guarantee |
| `12_noninteractive.bats` | EOF-safe prompts, no menu without a TTY, unknown arguments, sudo used only with consent or for unwritable dirs |
| `13_completions.bats` | Completion words match `--help`; bash completion driven functionally; zsh registration; fish syntax (CI) |
| `14_composer_constraints.bats` | Composer constraint matrix, lowest-satisfying resolution, historical-choice preservation, platform pin |
| `08_update.bats` | `--update`: Homebrew deferral, no downgrade, checksum missing or mismatched, version mismatch, exit status |

## Gotchas

- In bats, `! cmd` never fails a test. Use `run cmd; [ "$status" -ne 0 ]`.
- Shell detection reports `bash` under bats. Override `shell_detect_shell` in the test to cover zsh and fish.
- `core_get_installed_php_versions` memoizes `brew list` per process. Calls made through `run` (a subshell) are unaffected.
- Tests that run a shell under `env -i PATH="$BASE_PATH"` only find binaries in `/usr/bin` and `/bin`. Resolve Homebrew tools such as fish with `command -v` first and call them by absolute path, otherwise `env` exits 127 with no visible output.

## CI

`.github/workflows/ci.yml` runs on `macos-latest` for pushes to master and for PRs:
1. `shellcheck -S warning` on the built artifact, `lib/*.sh`, `build.sh`, `phpswitch.sh`, `tools/release.sh` and the fake brew
2. A build-sync check: rebuild, then `git diff --exit-code php-switcher.sh`. The build is deterministic (no timestamps).
3. `bats tests/`

## See also

- [[decisions/roadmap-2026]]
- [[architecture/build-system]]
