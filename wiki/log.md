# Wiki Log — PHPSwitch

Append-only chronological record of all wiki activity. Never edit past entries.

Format: `## [YYYY-MM-DD] <type> | <description>`
Types: `ingest`, `query`, `lint`, `init`, `schema-update`

Parse last 5 entries: `grep "^## \[" wiki/log.md | tail -5`

---

## [2026-04-06] init | Wiki bootstrapped from CLAUDE.md and llm-wiki.md

Kickstarted wiki structure from the project's CLAUDE.md (authoritative source on architecture, modules, and conventions) and the llm-wiki.md pattern document. Created SCHEMA.md, index.md, log.md, overview.md, architecture pages, entity stubs, and concept pages. No external sources ingested yet.
