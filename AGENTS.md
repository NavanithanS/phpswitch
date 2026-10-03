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

## 4. Testing Conventions
- Tests must never touch the real machine. Start every `.bats` file with `load helpers/common` and call `common_setup` / `common_teardown`. These give each test a temporary `$HOME`, a fake Homebrew prefix (`$FAKE_BREW_PREFIX`), and the fake `brew` from `tests/helpers/bin/brew`, which logs every call to `$FAKE_BREW_LOG`.
- Use `load_modules` to source the lib modules for unit tests, and `fake_php_install` / `fake_php_link` to set up PHP versions.
- Never write `! cmd` as an assertion in bats, because it never fails a test. Use `run cmd` followed by `[ "$status" -ne 0 ]`.
- Rebuild `php-switcher.sh` (`cd phpswitch && ./build.sh`) before committing. CI fails if the committed artifact doesn't match a fresh build.
- CI (`.github/workflows/ci.yml`) runs shellcheck, the build-sync check and `bats tests/` on macOS. See `wiki/concepts/testing.md`.

## 5. Releases
- Always release with `tools/release.sh`. It bumps `PHPSWITCH_VERSION` in `config/defaults.sh`, creates a `vX.Y.Z` tag, and uploads `php-switcher.sh` together with `php-switcher.sh.sha256`, then patches the Homebrew formula.
- `phpswitch --update` **refuses** any release that doesn't include `php-switcher.sh.sha256`, so never create releases by hand without it. See `wiki/concepts/release-and-update.md`.

## 6. Per-shell integration (`lib/init.sh`)
- The code printed by `phpswitch init` is `eval`'d at **every shell startup**. It must stay valid bash 3.2, zsh and fish, print no banner, and stay fast. Commands it relies on (`init`, `__php-dir`) skip the banner and the dependency check.
- The binary must never print shell code for the hook to `eval`. `__php-dir` prints only a directory, and the shell validates it with `_phpswitch_valid_dir`.
- The hook's fast path must keep matching `version_check_project`. Any change to detection rules needs the parity test in `tests/09_shell_integration.bats` updated.
- Generated code must be safe under `set -u`, and must only ever remove its own PATH entries.
- Code that edits rc files must validate every change before writing any of them (all-or-nothing), back each file up, and replace contents only through `utils_replace_file_contents` (atomic, follows symlinks, keeps the file mode). `shell_detect_shell` returns the login shell (`$SHELL`) first; `auto_login_shell` is the strict variant. Test against the real legacy fixtures in `tests/fixtures/`.

## 7. Doctor
- `phpswitch doctor` must stay read-only (no network, sudo, writes or service calls). New checks go in `lib/doctor.sh` with a test in `tests/11_doctor.bats`. Don't add a second diagnostics path.

## 8. Privileges and prompts
- Never escalate automatically. Print the exact `sudo` command instead. The only exceptions are explicit install, uninstall and update actions, through `utils_run_for_dir` (which uses sudo only when the target directory isn't writable), and the FPM root-leftover fix, which shows the commands and asks first (default no).
- Never suggest `sudo brew services`: it makes Homebrew files root-owned.
- Every prompt must survive EOF. Use `utils_validate_yes_no` (on EOF it returns the default, or "n"). The interactive menu refuses to start without a TTY, and unknown arguments exit 2.
