# PHPSwitch

PHP version manager for macOS. Switch between Homebrew-managed PHP versions from the terminal — interactively or via flags.

## Features

- Interactive menu and full non-interactive CLI flag support
- Switch, install, and uninstall PHP versions
- Automatic shell configuration updates (`.zshrc`, `.bashrc`, `config.fish`)
- Project-level PHP version detection at startup via `.php-version`, `composer.json`, or `.tool-versions`
- Auto-switching when changing directories (shell hook)
- PHP-FPM service management
- PHP extension enable/disable
- Smart caching for available version lookups (1-hour TTL)
- Permission repair tools and automatic fallbacks
- Self-update from GitHub
- Bash, Zsh, and Fish shell support
- Apple Silicon (M1/M2/M3) and Intel compatible

## Requirements

- macOS
- [Homebrew](https://brew.sh/)
- Bash, Zsh, or Fish shell

## Installation

### Homebrew (recommended)

```bash
brew tap NavanithanS/phpswitch
brew install phpswitch
```

### Curl

```bash
curl -L https://raw.githubusercontent.com/NavanithanS/phpswitch/master/php-switcher.sh \
  -o /tmp/php-switcher.sh && chmod +x /tmp/php-switcher.sh && /tmp/php-switcher.sh --install
```

`--install` asks for your password only if the install directory isn't writable. Don't run the whole script with `sudo`: that leaves root-owned files in your home directory.

### Manual

```bash
git clone https://github.com/NavanithanS/phpswitch.git
cd phpswitch
chmod +x php-switcher.sh
./php-switcher.sh --install
```

## Usage

### Interactive menu

```bash
phpswitch
```

On startup, PHPSwitch checks your project directory for a `.php-version`, `composer.json` (`require.php`), or `.tool-versions` file and shows a notice if the active PHP version doesn't match.

```
PHPSwitch  PHP Version Manager for macOS  v1.4.5

  Current  php@8.2  (8.2.30)
  Project  php@8.1  composer.json

  Installed

    1  php@7.4
    2  php@8.1
    3  php@8.2  active
    4  php@8.3

  Available to install

    5  php@8.4
    6  php@8.5

  u  uninstall a version
  e  manage extensions
  c  configure PHPSwitch
  d  diagnose environment
  p  set project PHP version
  a  configure auto-switching
  0  exit

  Select (0-6, u, e, c, d, p, a)
```

### CLI flags

```
phpswitch                            interactive menu
phpswitch use VERSION|auto           use a version in this shell only (needs shell integration)
phpswitch global VERSION             switch the global (Homebrew-linked) version
phpswitch local VERSION              write .php-version in the current directory
phpswitch init zsh|bash|fish         print shell integration code
phpswitch doctor                     check your PHP setup (read-only)
phpswitch completions zsh|bash|fish  print shell completions
phpswitch --switch=VERSION           switch to version (same as global)
phpswitch --switch-force=VERSION     switch, installing if needed
phpswitch --install=VERSION          install a version
phpswitch --uninstall=VERSION        uninstall a version
phpswitch --uninstall-force=VERSION  force uninstall a version
phpswitch --list                     list installed and available versions
phpswitch --json                     list versions in JSON format
phpswitch --current                  show current version
phpswitch --project, -p              switch to project version
phpswitch --clear-cache              clear cached data
phpswitch --refresh-cache            refresh available versions cache
phpswitch --fix-permissions          fix cache directory permissions
phpswitch --install-auto-switch      add per-shell switching to your rc file
phpswitch --clear-directory-cache    clear legacy auto-switching cache
phpswitch --check-dependencies       check system dependencies
phpswitch --install                  install as a system command
phpswitch --uninstall                remove from system
phpswitch --update                   update to the latest version
phpswitch --version, -v              show version
phpswitch --debug                    enable debug logging
phpswitch --help, -h                 show this help
```

### Per-shell switching (recommended)

Add one line to your shell config so each terminal can use its own PHP version:

```bash
# ~/.zshrc  (bash: "init bash" in ~/.bash_profile on macOS, ~/.bashrc elsewhere)
eval "$(phpswitch init zsh)"

# ~/.config/fish/config.fish
phpswitch init fish | source
```

Then:

```bash
phpswitch use 8.2      # this shell only
phpswitch use auto     # back to directory-based selection
phpswitch local 8.3    # write .php-version here
```

When you `cd`, the current shell switches to the project's PHP version (`.php-version`, `composer.json`, `.tool-versions`) and switches back when you leave. Other terminals, PHP-FPM and your IDE are not affected. Changes made by hand to `.php-version` take effect on the next `cd`.

`phpswitch --install-auto-switch` adds this line for you (for bash on macOS, to the login file Terminal actually reads). To turn it off again, run `phpswitch --uninstall-auto-switch` or choose "Disable auto-switching" in the interactive menu (`a`): it removes the line, with a backup.

### Shell completions

```bash
# ~/.zshrc (after compinit)
eval "$(phpswitch completions zsh)"
# ~/.bash_profile (macOS) or ~/.bashrc
eval "$(phpswitch completions bash)"
# fish
phpswitch completions fish > ~/.config/fish/completions/phpswitch.fish
```

### Switching versions globally

```bash
phpswitch --switch=8.3
phpswitch --switch-force=8.4   # installs if not present
```

### Project version detection

PHPSwitch checks the following files (in order) when the menu opens or `--project` is used:

| File             | Field                            |
| ---------------- | -------------------------------- |
| `.php-version`   | plain version string, e.g. `8.2` |
| `composer.json`  | `require.php`, e.g. `>=8.1`      |
| `.tool-versions` | `php 8.2.x`                      |

For `composer.json`, `config.platform.php` is used as an exact pin. Otherwise the `require.php` constraint (`^8.1`, `>=8.2 <8.4`, `^7.4 || ^8.0`, …) resolves to an installed version that satisfies it: the constraint's own first version if that's installed, else the lowest installed match.

```bash
echo "8.1" > .php-version
phpswitch -p        # switch to the project version
```

### Auto-switching

Set up per-shell switching in your shell config automatically:

```bash
phpswitch --install-auto-switch
```

This adds the `phpswitch init` line (see [Per-shell switching](#per-shell-switching-recommended)) to the rc file of your login shell (`$SHELL`), after making a backup. Each terminal then follows the project's PHP version when you `cd`, and other terminals, PHP-FPM and your IDE are unaffected.

**Upgrading from 1.x:** the old auto-switch hook relinked PHP globally (and restarted PHP-FPM) on every `cd`. `--install-auto-switch` removes it from `.zshrc`, `.zprofile`, `.bashrc`, `.bash_profile`, `.bash_login`, `.profile` and `config.fish`, backing each file up first. If a block can't be identified safely, no file is changed and you're asked to remove it by hand. To change the global version (for PHP-FPM, Valet or your IDE), use `phpswitch global VERSION`.

### Managing extensions

Select `e` from the menu to enable or disable extensions for the active PHP version, edit `php.ini`, or view detailed extension info.

### PHP-FPM

PHPSwitch automatically stops the old PHP-FPM service and starts the new one when switching versions. Manual control is available through the menu.

## Configuration

PHPSwitch reads `~/.phpswitch.conf` on startup. Create it with defaults:

```bash
# ~/.phpswitch.conf
AUTO_RESTART_PHP_FPM=true       # restart PHP-FPM on version switch
BACKUP_CONFIG_FILES=true        # back up shell RC files before modifying
DEFAULT_PHP_VERSION=""          # preferred version (empty = none)
MAX_BACKUPS=5                   # number of RC file backups to keep
AUTO_SWITCH_PHP_VERSION=false   # enable directory-based auto-switching
CACHE_DIRECTORY=""              # custom cache path (empty = ~/.cache/phpswitch)
```

Edit directly or use the `c` option in the interactive menu.

## Project structure

```
phpswitch/
├── build.sh              # concatenates modules into php-switcher.sh
├── phpswitch.sh          # development entry point
├── config/
│   └── defaults.sh       # default config values
└── lib/
    ├── core.sh           # config loading, debug logging
    ├── utils.sh          # path validation, temp files, display
    ├── shell.sh          # shell detection, RC file updates
    ├── version.sh        # version switching, install, uninstall
    ├── fpm.sh            # PHP-FPM service management
    ├── extensions.sh     # extension enable/disable
    ├── auto-switch.sh    # legacy directory-based auto-switching hooks
    ├── init.sh           # per-shell integration (phpswitch init / use)
    ├── completions.sh    # shell completions (phpswitch completions)
    ├── doctor.sh         # read-only health checks (phpswitch doctor)
    ├── self-manage.sh    # --install / --uninstall / --update
    ├── menu.sh           # interactive menu and configuration screens
    └── commands.sh       # CLI argument parsing and dispatch
```

The root `php-switcher.sh` is the built single-file distributable. Edit the modules under `phpswitch/lib/` and run `./phpswitch/build.sh` to regenerate it.

## Troubleshooting

### PHP version not applied after switch

Open a new terminal, or source your shell config:

```bash
source ~/.zshrc      # zsh
source ~/.bashrc     # bash
```

### Permission errors on cache directory

```bash
phpswitch --fix-permissions
```

Or set a custom cache path in `~/.phpswitch.conf`:

```bash
CACHE_DIRECTORY="$HOME/.phpswitch_cache"
```

### Installation failed

```bash
brew doctor
brew update
brew install php@8.3   # try manually
```

### Auto-switching not working

1. Run `phpswitch --install-auto-switch` to add the integration line (and remove any legacy hook)
2. Open a new terminal, or `source` your shell config
3. Check that `echo $PHPSWITCH_BIN` prints a path. If it doesn't, the `phpswitch init` line isn't being loaded. On macOS, bash login shells read `~/.bash_profile`, so source `~/.bashrc` from it.
4. Make sure `phpswitch use` isn't pinning a version: `phpswitch use auto`
5. A hand-edited `.php-version` takes effect on the next `cd`

### Debug mode

```bash
phpswitch --debug
```

Prints internal state to stderr at each step.

## Contributing

Pull requests are welcome.

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Commit your changes and open a Pull Request

## License

MIT — see [LICENSE](LICENSE).
