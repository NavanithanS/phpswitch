# GEMINI.md

This file provides guidance to Google Gemini (and other advanced agents) when working with the PHPSwitch repository.

## Overview
PHPSwitch is a modular, single-file bash utility for macOS that manages Homebrew-installed PHP versions.
Always rely on `CLAUDE.md` and the internal `wiki/` directory for exhaustive context before executing codebase refactors.

## Knowledge Base & Wiki Integration
The `wiki/` directory serves as the centralized, append-only knowledge base for this repository. It is essential for inter-agent context sharing.

- **Initialization Phase**: At the start of any complex session, you MUST review `wiki/overview.md` and `wiki/index.md` to quickly gain context regarding design constraints, file structures, and domain entities.
- **Continuous Documentation**: You are explicitly instructed to proactively update the `wiki/` whenever you resolve architectural debt, modify testing paradigms, or introduce new sub-systems.
- **Audit Logging**: Any modifications or updates you make to the Wiki schema or its concepts should be recorded chronologically in `wiki/log.md`.

## Quality Constraints
- Adhere strictly to `ask-code-reviewer` and `ask-impact-sentinel` guidelines.
- Always validate bash modifications using `shellcheck` (e.g., `shellcheck -f json php-switcher.sh`).
- Execute tests via `bats tests/` before considering any task fully verified.
