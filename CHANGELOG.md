# Changelog

All notable changes to PHPSwitch are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [2.0.0] - 2026-10-04

PHPSwitch 2.0 switches PHP per shell. Changing directory no longer relinks Homebrew's PHP for every terminal and IDE, or restarts PHP-FPM.

### Upgrading from 1.x

- Run `phpswitch --install-auto-switch` once. It removes the old auto-switch hook from `.zshrc`, `.zprofile`, `.bashrc`, `.bash_profile`, `.bash_login`, `.profile` and `config.fish` (backing each file up first), and adds the new integration line. If a block can't be identified safely, no file is changed and you're told what to remove by hand.
- To change the global (Homebrew-linked) version for PHP-FPM or your IDE, use `phpswitch global VERSION`. With Laravel Valet, use `valet use VERSION`.

### Breaking changes

- `cd` into a project no longer relinks PHP globally or restarts PHP-FPM. It changes `PATH` in the current shell only.
- Unknown arguments exit with status 2 instead of opening the interactive menu.
- The interactive menu refuses to start without a terminal (TTY), so scripts and CI can no longer hang on it.
- PHPSwitch never escalates to `sudo` automatically. It prints the command to run instead. Only explicit install, uninstall and update actions use `sudo`, and only when the target directory isn't writable.
- On macOS, new bash configuration goes to the login file Terminal reads (`.bash_profile`, `.bash_login` or `.profile`) instead of `.bashrc`. An existing PHPSwitch setup stays in the file it's already in.
- `phpswitch --update` installs only from GitHub release assets and refuses a release without a valid checksum. It no longer downloads from the `master` branch.

### Added

- Per-shell switching: `eval "$(phpswitch init zsh|bash|fish)"` and `phpswitch use VERSION|auto`. The directory hook runs in pure shell, spawns nothing on an ordinary prompt, and also picks up a `.php-version` created or edited in the current directory.
- `phpswitch global VERSION` and `phpswitch local VERSION` (writes `.php-version`).
- `phpswitch doctor`: read-only checks for which `php` runs (and other PHP binaries on PATH), shell integration, leftover 1.x hooks, the project version, PHP-FPM running as root, root-owned files in PHP kegs, and Laravel Valet.
- `phpswitch completions zsh|bash|fish`.
- `composer.json` `require.php` constraints (`^8.1`, `>=8.2 <8.4`, `^7.4 || ^8.0`, …) resolve to an installed version that satisfies them. `config.platform.php` is used as an exact pin.
- `--uninstall-auto-switch`, the inverse of `--install-auto-switch`.
- `--yes`/`-y` to auto-confirm prompts, and `--quiet`/`-q` to suppress the banner.
- Signed releases. Each release ships `php-switcher.sh.sha256` and a minisign signature, `php-switcher.sh.minisig`. When minisign is installed, `--update` refuses a missing or invalid signature. Without minisign it warns and checks the checksum only.

### Changed

- The curl install in the README downloads from the latest release and shows how to verify the checksum and signature.
- `--install-auto-switch` installs the per-shell integration and migrates the 1.x hook.
- Switching to the version that's already active doesn't rewrite rc files or restart PHP-FPM. The dependency check reports only problems.
- A global switch restarts PHP-FPM only when a PHP service is running and `AUTO_RESTART_PHP_FPM=true`. It no longer starts PHP-FPM when none was running.
- rc files are validated before any is written, backed up, and replaced atomically (symlinks and file modes are kept). PHPSwitch targets your login shell.

### Fixed

- A `.php-version` with a full version (`8.2.15`) maps to `php@8.2`.
- The project-version search compares whole path components, so `/Users/bobby` no longer counts as inside `/Users/bob`.
- Re-sourcing your rc file keeps the project's PHP version, and Homebrew is found when it isn't on `PATH`.
- Parsing of `brew search` output.
- The menu's "Disable auto-switching" removes the hook.
- The configuration menu keeps the PHP-FPM restart and backup settings when you press Enter.

## Earlier versions

Releases up to 1.4.5 are listed on [GitHub Releases](https://github.com/NavanithanS/phpswitch/releases).
