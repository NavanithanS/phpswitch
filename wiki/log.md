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

## [2026-10-04] lint | macOS bash startup file

Bash on macOS starts login shells that never read `.bashrc`, yet both the managed PATH block and the integration line went there first. Added `shell_bash_rc_file`, shared by `shell_get_rc_file` and `auto_rc_file`: it keeps any file that already holds phpswitch content, otherwise picks the login file (or `.bashrc` when the login file sources it) and never shadows `.bash_login`/`.profile`. `doctor` now also scans `.bash_login`. Updated [[concepts/shell-patching]], [[concepts/shell-integration]], AGENTS.md and [[decisions/roadmap-2026]].

## [2026-10-04] lint | Disable auto-switching removes the hook

The menu's "Disable auto-switching" only set `AUTO_SWITCH_PHP_VERSION=false`, which nothing at shell startup reads, so the hook kept running. Added `auto_uninstall` (all-or-nothing removal of the integration line and legacy blocks, with backups) and made the menu judge the state from the rc files. Config option 5 also passed `true`/`false` as the prompt default, so pressing Enter turned the setting off; it now passes `y`/`n`. Updated [[concepts/shell-integration]], [[entities/lib-auto-switch]], AGENTS.md and [[decisions/roadmap-2026]].

## [2026-10-04] lint | Legacy auto-switch no longer starts PHP-FPM

`auto_switch_php` started the target PHP-FPM on every project `cd` even when none was running. It now only moves an FPM that is actually `started`. The fake `brew` gained `FAKE_BREW_SERVICES`. Updated [[concepts/fpm-management]] and [[decisions/roadmap-2026]]. Possibly the same issue remains on the global switch path in `lib/fpm.sh` (not yet checked).

## [2026-10-04] lint | Fish runtime test now actually runs fish

The first CI run of `fish: hook detects project versions inside HOME only` failed with exit 127: under `env -i PATH="$BASE_PATH"`, `env` couldn't find Homebrew's fish. The test now resolves fish with `command -v` and runs it by absolute path. Added the gotcha to [[concepts/testing]].

## [2026-10-04] lint | Config menu options 1/2 keep their value on Enter

Like option 5 before, "auto restart PHP-FPM" and "backup config files" passed `true`/`false` as the prompt default, so pressing Enter (or `--yes`) turned them off. They now pass `y`/`n`. Still open: the closing "Make additional configuration changes?" prompt defaults to `y`, so on EOF the menu re-enters itself forever.

## [2026-10-04] lint | Global switch no longer starts PHP-FPM

`version_switch_php` called `fpm_restart` on every version change, and that starts PHP-FPM even when none was running. It now does so only when a PHP service is `started` (`fpm_any_running`) and `AUTO_RESTART_PHP_FPM=true`. The extension paths still call `fpm_restart` directly. Updated [[concepts/fpm-management]].

## [2026-10-04] lint | One rc file list, whole-line marker match

The rc files to scan were listed three times. The legacy list lacked `.zprofile` and `.bash_login`, so hooks there were never migrated or removed. All three scans now use `auto_rc_candidates`. `auto_install` and doctor also matched the integration marker as a substring while uninstall matched whole lines, so a comment containing the marker made install say "already set up" while the menu said "off". All four now use `grep -qxF`. Updated AGENTS.md, [[concepts/shell-integration]] and [[entities/lib-auto-switch]].

## [2026-10-04] lint | `--uninstall-auto-switch`

New flag, the inverse of `--install-auto-switch`: it runs `auto_uninstall` and exits with its status. It's in `--help`, `COMPLETION_FLAGS` and the README. Updated [[concepts/shell-integration]] and [[entities/lib-auto-switch]].

## [2026-10-04] lint | Per-prompt project re-check

All three hooks skipped when `$PWD` hadn't changed, so a `.php-version` created or edited in the current directory only applied after leaving and re-entering it. The hook now also runs on zsh `precmd` and the fish `fish_prompt` event (bash already ran it from `PROMPT_COMMAND`). It compares a builtin-only `_phpswitch_signature` and re-detects only when that or `$PWD` changes. It also returns the caller's exit status. Updated [[concepts/shell-integration]], AGENTS.md and [[decisions/roadmap-2026]].

## [2026-10-04] lint | Valet/Herd and PECL decided

Valet: `doctor` warns when Valet is installed (check 9b) and recommends `valet use`. phpswitch doesn't hand `global` over to Valet, because `valet use` needs sudo. Herd needs nothing new. PECL install won't be done. The README now points Valet users to `valet use` and lists every rc file the migration cleans. Updated [[concepts/doctor]] and [[decisions/roadmap-2026]].

## [2026-10-04] lint | minisign release signatures

`tools/release.sh` signs `php-switcher.sh` with minisign and uploads `php-switcher.sh.minisig`. It verifies the signature against the public key built into the artifact before tagging, and refuses to start without minisign, the key or `PHPSWITCH_MINISIGN_PUBKEY`. `--update` verifies the signature when minisign is installed, refusing a missing or bad one; otherwise it warns and relies on the checksum. CI installs minisign for a real round-trip test. The public key is still empty until the user generates the key pair. Updated AGENTS.md, [[concepts/release-and-update]] and [[decisions/roadmap-2026]].

## [2026-10-04] lint | Real minisign test re-publishes its signature

On its first CI run, the real minisign round trip verified a good signature, but the "different key" half wasn't refused. `fake_url` had copied the original valid signature, so the re-signed file was never served. The test now calls `fake_url` again, and the gotcha is in [[concepts/testing]].

## [2026-10-04] lint | Release signing key embedded

The maintainer generated the minisign key pair. Its public key (`RWTRUA0k…`) is now `PHPSWITCH_MINISIGN_PUBKEY` in `config/defaults.sh`, so `tools/release.sh` can sign 2.0.0, and builds from here on verify signatures. `tests/08_update.bats` clears the key in setup; the signature tests set their own. Updated [[concepts/release-and-update]].

## [2026-10-04] lint | README installs from the release, with checks

The curl install downloaded `php-switcher.sh` from raw master, unverified. It now downloads the script, `.sha256` and `.minisig` from the latest release (`curl -fsSLO`, so an HTTP error fails instead of running an error page). It then shows `shasum -a 256 -c` and `minisign -Vm … -P <key>`. The Homebrew section explains `brew trust --tap navanithans/phpswitch` for Homebrew's tap-trust check. Updated [[concepts/release-and-update]] (the README holds a copy of the public key; installs up to 1.4.5 update from raw master).

## [2026-10-04] lint | CHANGELOG and README for 2.0.0

Added `CHANGELOG.md` (Keep a Changelog), with a 2.0.0 section covering the upgrade steps, breaking changes, and what was added, changed and fixed since 1.4.5; older releases link to GitHub Releases. The README's feature list now describes 2.0 (per-shell switching, doctor, completions, no automatic sudo, signed updates) and links the changelog. Its sample banner shows v2.0.0, and the flag list gained `--uninstall-auto-switch`, `--yes` and `--quiet`. AGENTS.md and [[concepts/release-and-update]] now say to write the CHANGELOG section before `release.sh` and not to bump the version by hand.

## [2026-10-04] lint | 2.0.0 released; one-way branch flow

v2.0.0 was released with `tools/release.sh` from `release`. Its assets verify (checksum, and minisign with trusted comment `phpswitch v2.0.0`), and `releases/latest` is `v2.0.0`. The maintainer's rule: branches flow one way, master → `release`, never back. The CHANGELOG commit and the version bump were therefore re-applied to master as new commits. Master's `php-switcher.sh` is byte-identical to the signed asset, and installs on 1.4.5, which update from raw master only when the version differs, can now reach 2.0.0. The formula gained the `completions` line. AGENTS.md and [[concepts/release-and-update]] now say to run `release.sh` on master and then merge master into `release`.
