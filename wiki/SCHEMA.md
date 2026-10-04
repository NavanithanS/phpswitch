# Wiki Schema — PHPSwitch

This file defines how the wiki is structured and how it should be maintained. The LLM reads this at the start of every session that touches the wiki.

## Purpose

A persistent, LLM-maintained knowledge base for the PHPSwitch project. Not a substitute for code comments or README — this captures design intent, decision history, cross-cutting concerns, and synthesized understanding that lives nowhere in the codebase itself.

## Directory layout

```
wiki/
├── SCHEMA.md          # This file — conventions and workflows
├── index.md           # Content catalog: every page, one-line summary, category
├── log.md             # Append-only chronological record of all wiki activity
├── overview.md        # High-level project summary (the "front door")
├── architecture/      # How the system is built
├── entities/          # Named things: modules, commands, config keys, files
├── concepts/          # Ideas and mechanisms: caching, auto-switch, FPM, etc.
├── decisions/         # Why things are the way they are (ADR-style)
└── sources/           # Summaries of ingested external documents
```

## Page format

Every wiki page must have a YAML frontmatter block:

```yaml
---
title: Page Title
category: overview | architecture | entity | concept | decision | source
tags: [tag1, tag2]
created: YYYY-MM-DD
updated: YYYY-MM-DD
sources: 0          # number of source documents this page draws from
---
```

Body: plain markdown. Use `[[WikiLink]]` style links for cross-references (Obsidian-compatible). At the bottom, add a `## See also` section with links to related pages.

## Workflows

### Ingest
When a new source (doc, article, PR, issue, design note) is added:
1. Read the source.
2. Write a summary page under `wiki/sources/`.
3. Update or create relevant entity/concept pages.
4. Update `index.md` with any new pages.
5. Append an entry to `log.md`: `## [YYYY-MM-DD] ingest | <title>`.

### Query
When answering a question against the wiki:
1. Read `index.md` to find relevant pages.
2. Read those pages.
3. Synthesize an answer with citations (e.g. `[[page-name]]`).
4. If the answer is reusable, file it as a new page and update `index.md`.
5. Append to `log.md`: `## [YYYY-MM-DD] query | <question summary>`.

### Lint
When asked to health-check the wiki:
1. Scan for orphan pages (no inbound links from index or other pages).
2. Flag contradictions between pages.
3. Note concepts mentioned but lacking their own page.
4. Suggest gaps that could be filled (questions to investigate, missing cross-refs).
5. Append to `log.md`: `## [YYYY-MM-DD] lint | <summary of findings>`.

## Conventions

- The LLM writes and maintains all wiki content. The human sources documents and asks questions.
- Raw sources (if stored) go outside `wiki/` — they are immutable inputs.
- `log.md` is append-only. Never edit past entries.
- `index.md` is updated on every ingest. It is the LLM's navigation map.
- When new information contradicts an existing page, update the page and note the contradiction inline with a `> **Revision:** ...` blockquote.
- Keep pages focused. A page that tries to cover everything covers nothing. Prefer many small, well-linked pages over a few large ones.
