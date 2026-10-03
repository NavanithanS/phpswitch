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
