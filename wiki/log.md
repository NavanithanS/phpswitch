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
