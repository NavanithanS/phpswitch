# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PHPSwitch is a macOS CLI tool for switching between Homebrew-managed PHP versions. It supports interactive menus, non-interactive flags, auto-switching by directory, PHP-FPM management, and extension management.

## Repository Structure

The source lives under `phpswitch/` and is **built** into the distributable `php-switcher.sh` at the repo root:

```
phpswitch/
├── phpswitch.sh          # Entry point for development (sources lib modules)
├── build.sh              # Build script that concatenates modules into php-switcher.sh
├── config/defaults.sh    # Default config values
└── lib/
    ├── core.sh           # Config loading, debug logging, temp file cleanup
    ├── utils.sh          # Path validation, cache, spinners, temp files
    ├── shell.sh          # Shell detection (zsh/bash/fish), rc file updates
    ├── version.sh        # PHP version detection, install/uninstall/switch
    ├── fpm.sh            # PHP-FPM service management
    ├── extensions.sh     # PHP extension enable/disable/info
    ├── auto-switch.sh    # Directory-based auto-switching hooks
    └── commands.sh       # CLI argument parsing and dispatch
```

The root `php-switcher.sh` is the **built artifact** — a single-file standalone script created by concatenating all modules. Do not edit it directly; edit the source modules under `phpswitch/lib/` and rebuild.

## Build

```bash
cd phpswitch
./build.sh              # Outputs php-switcher.sh to the repo root
./build.sh --dev-copy   # Also creates phpswitch/php-switcher.sh for local testing
./build.sh --help       # Show all options
```

After building, the SHA256 checksum is printed — needed when updating the Homebrew formula.

## Running / Testing

**Automated Testing**
The project uses `bats-core` for automated testing. Tests are located in the `tests/` directory.

```bash
# Install bats-core via Homebrew (if not already installed)
brew install bats-core

# Run all tests
bats tests/
```

**Manual Testing**
Manual testing can be done by running the development entry point directly:

```bash
./phpswitch/phpswitch.sh             # Interactive menu
./phpswitch/phpswitch.sh --debug     # Debug mode (verbose logging to stderr)
./phpswitch/phpswitch.sh --list      # Non-interactive: list versions
./phpswitch/phpswitch.sh --current   # Show active PHP version
```

Or test the built artifact:

```bash
./php-switcher.sh --debug
```

## Architecture Notes

- **Single-file distribution**: `build.sh` strips shebangs from each module and concatenates them in order (`defaults → core → utils → shell → version → fpm → extensions → auto-switch → commands`) with a two-line main block appended at the end. The result is a self-contained script.
- **Configuration**: Loaded from `~/.phpswitch.conf` at startup via `core_load_config`. Missing keys fall back to defaults defined in `config/defaults.sh`.
- **Caching**: Available PHP versions are cached under `~/.cache/phpswitch/` (or a user-configured path). Cache TTL is 1 hour. The `--clear-cache` / `--refresh-cache` flags manage this.
- **Shell config patching**: `lib/shell.sh` detects the user's shell and appends/updates `export PATH=...` lines in `~/.zshrc`, `~/.bashrc`, or `~/.config/fish/config.fish`. Backups are created before modification.
- **Auto-switching**: `lib/auto-switch.sh` installs `chpwd` hooks (zsh) or `cd` wrappers (bash/fish) that read `.php-version` files when directories change. Supports `.php-version`, `composer.json` (`require.php`), and `.tool-versions`.
- **PHP version format**: Internally versions are normalized to `php@X.Y` (e.g. `php@8.2`). User-facing input accepts bare `8.2` or `php@8.2`.

## Project Documentation (Wiki)

This repository includes a structured wiki in the `wiki/` directory that serves as the extended brain and state memory for agents.
- **Reference**: Always read `wiki/overview.md` and `wiki/index.md` when onboarding to a new task. The wiki contains context, architectural decisions, and an ongoing log (`wiki/log.md`).
- **Proactive Updates**: Whenever you modify the architecture, add new concepts, or make significant structural changes, you MUST proactively update the relevant markdown files in `wiki/`.
- **Log Updates**: Document any major updates you make to the wiki by appending an entry to `wiki/log.md`.
