# Wiki Log — PHPSwitch

Append-only chronological record of all wiki activity. Never edit past entries.

Format: `## [YYYY-MM-DD] <type> | <description>`
Types: `ingest`, `query`, `lint`, `init`, `schema-update`

Parse last 5 entries: `grep "^## \[" wiki/log.md | tail -5`

---

## [2026-04-06] init | Wiki bootstrapped from CLAUDE.md and llm-wiki.md

Kickstarted wiki structure from the project's CLAUDE.md (authoritative source on architecture, modules, and conventions) and the llm-wiki.md pattern document. Created SCHEMA.md, index.md, log.md, overview.md, architecture pages, entity stubs, and concept pages. No external sources ingested yet.

## [2026-10-03] query | Improvement brainstorm → roadmap

Brainstormed improvements, verified findings against code (global brew-link switching, per-cd subprocess in hook, placeholder update checksum, TODO formula sha256, duplicated version source, tracked build outputs, thin tests). Filed phased plan as [[decisions/roadmap-2026]] and linked it from index.

## [2026-10-03] lint | Phase 0 hygiene complete; v2 per-shell default decided

Untracked build outputs, removed stale prepare-release script, made `config/defaults.sh` the single version source for `tools/release.sh`, added `tests/03_versions.bats` with a fake `brew` (regression for brew-search parsing). Recorded per-shell-by-default decision for v2 in [[decisions/roadmap-2026]].

## [2026-10-03] ingest | Phase 1 test harness and CI

Added [[concepts/testing]] (fake brew, isolated HOME, suites 03–07, CI pipeline). Marked Phase 1 done in [[decisions/roadmap-2026]] and recorded pre-existing issues found during testing. AGENTS.md gained testing conventions.

## [2026-10-03] ingest | Phase 2 release & update hardening

Added [[concepts/release-and-update]]. `--update` now uses the latest release and verifies its SHA-256 (fails closed), defers Homebrew installs to `brew upgrade`, and never downgrades. release.sh publishes the checksum asset. The repo formula is synced to the tap (v1.4.4). Marked Phase 2 done in [[decisions/roadmap-2026]].

## [2026-10-03] ingest | Phase 3a per-shell integration

Added [[concepts/shell-integration]] for `lib/init.sh` (`init`, `use`/`local`/`global`, `__php-dir`, and the pure-shell hook with parity to `version_check_project`). Updated the module pipeline, the auto-switch banner, the index and the roadmap (3a done; 3b is migration). README, CLAUDE.md and AGENTS.md updated.

## [2026-10-03] ingest | Phase 3b install and migration

`--install-auto-switch` now installs the per-shell integration for the login shell and migrates legacy hooks from every rc file (all-or-nothing, backups, write-through for symlinked rc files). Documented in [[concepts/shell-integration]]. Added legacy fixtures and `10_install_auto_switch.bats`. Recorded the pre-existing `shell_detect_shell` and `.bash_profile` issues in [[decisions/roadmap-2026]].

## [2026-10-03] ingest | Phase 4a doctor

Added [[concepts/doctor]] (`lib/doctor.sh`), which replaced the two `utils_diagnose_*` functions; menu `d` now runs it. Roadmap: `use`/`local`/`global` and `--json` marked done; Valet and PECL deferred pending a user decision. Module order updated in CLAUDE.md and [[architecture/module-pipeline]].

## [2026-10-03] lint | Phase 4b hangs and sudo reduction

Prompts are EOF-safe, the menu needs a TTY, and unknown arguments exit 2. Automatic sudo was removed everywhere except explicit install/uninstall/update (`utils_run_for_dir`) and the consent-gated FPM fix. README install no longer uses `sudo` on the whole script. Added the `shell_update_rc` cross-cutting item to [[decisions/roadmap-2026]].

## [2026-10-03] lint | Login-shell detection and atomic rc writes

`shell_detect_shell` now prefers `$SHELL`. Added `utils_replace_file_contents` (atomic, follows symlinks, keeps the mode), used by `shell_update_rc` and the 3b migration. The config menu detects the v2 integration marker. Updated [[concepts/shell-patching]], [[concepts/shell-integration]] and [[decisions/roadmap-2026]].

## [2026-10-03] ingest | Phase 4c shell completions

Added `lib/completions.sh` (`phpswitch completions bash|zsh|fish`), with a drift test against `--help`. The formula line is deferred to the next release ([[concepts/release-and-update]]). Updated the module order in CLAUDE.md and [[architecture/module-pipeline]].

## [2026-10-03] ingest | Phase 4d composer constraints

`require.php` constraints are now resolved against installed series (historical answer first, then lowest satisfying, then fallback). Documented in [[concepts/auto-switch]]; roadmap updated.

## [2026-10-03] lint | Phase 4e split commands.sh

Split `lib/commands.sh` into `commands.sh` (dispatch), `menu.sh` and `self-manage.sh` as a pure move: the sorted `declare -f` output is identical for the module set and for the built artifact. Updated the module order everywhere, [[entities/lib-commands]], and the README tree (which also gained the previously missing `doctor.sh` and `completions.sh`).

## [2026-10-03] lint | Stale page sweep after roadmap phases

Updated [[overview]], [[entities/lib-auto-switch]] and [[concepts/auto-switch]] to describe v2 behaviour and the removed 1.x installers.

## [2026-10-03] lint | Branch-wide review fixes

Fixed: re-sourcing the rc file inside a project lost the per-shell version; `init` failed when `brew` wasn't on PATH (now falls back to the standard Homebrew locations). Hardening: `_phpswitch_valid_dir` rejects `/..`, and `auto_install` backs up the target rc file before rewriting legacy files. Documented in [[concepts/shell-integration]].

## [2026-10-03] lint | Fixes from local install testing

From hands-on testing: an unchanged `global`/`--switch` no longer restarts PHP-FPM or rewrites the rc file (a reinstall still restarts FPM); `use` / `use auto` confirm what the shell uses; the dependency check prints only problems; `doctor` flags unmanaged PHP `PATH` lines in rc files. Updated [[concepts/doctor]], [[concepts/shell-patching]] and [[concepts/shell-integration]].

## [2026-10-04] lint | Project version detection fixes

A full-patch `.php-version` (`8.2.10`, `php@8.2.10`) now resolves to `php@8.2` instead of a version that never exists. The upward search compares whole path components, so a sibling such as `/Users/bobby` is no longer treated as inside `/Users/bob`; the binary and both hooks changed together. Updated [[concepts/version-format]], [[concepts/shell-integration]] and the issue table in [[decisions/roadmap-2026]].
