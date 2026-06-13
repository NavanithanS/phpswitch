# AI Agents Guide for PHPSwitch

Welcome to the PHPSwitch repository. If you are an AI assistant (such as Claude, Gemini, ChatGPT, or Cursor) working on this codebase, you must adhere to the following rules:

## 1. Project Overview & Architecture
Please read `CLAUDE.md` to understand the build pipeline (`build.sh`), testing (`bats tests/`), and file structure (`lib/*.sh`).
PHPSwitch relies heavily on modular shell scripting that compiles down into a single `php-switcher.sh` executable.

## 2. The Agentic Knowledge Base (Wiki)
This repository includes a structured wiki in the `wiki/` directory that serves as the extended brain and state memory for agents.
- **Reference**: Always read `wiki/overview.md` and `wiki/index.md` when onboarding to a new task to understand architectural decisions and context.
- **Proactive Updates**: Whenever you modify the architecture, add new concepts, or make significant structural changes, you **MUST proactively update** the relevant markdown files in `wiki/` so future agents have the correct context.
- **Log Updates**: Document any major updates you make to the wiki by appending an entry to `wiki/log.md`.

## 3. Strict Rules
- Never use `ls | grep` or unsafe shell idioms. Run `shellcheck` before declaring any work done.
- Keep the `master` branch clean. If you add features, ensure tests are added to `tests/`.
