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
  -o /tmp/php-switcher.sh && chmod +x /tmp/php-switcher.sh && sudo /tmp/php-switcher.sh --install
```

### Manual

```bash
git clone https://github.com/NavanithanS/phpswitch.git
cd phpswitch
chmod +x php-switcher.sh
sudo ./php-switcher.sh --install
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
phpswitch --switch=VERSION           switch to version
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
phpswitch --install-auto-switch      enable directory-based auto-switching
phpswitch --clear-directory-cache    clear auto-switching directory cache
phpswitch --check-dependencies       check system dependencies
phpswitch --install                  install as a system command
phpswitch --uninstall                remove from system
phpswitch --update                   update to the latest version
phpswitch --version, -v              show version
phpswitch --debug                    enable debug logging
phpswitch --help, -h                 show this help
```

### Switching versions

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

```bash
echo "8.1" > .php-version
phpswitch -p        # switch to the project version
```

### Auto-switching

Enable automatic PHP switching when you change directories:

```bash
phpswitch --install-auto-switch
```

Once enabled, opening a directory that contains a `.php-version` file automatically switches to that version. Uses a cache to avoid redundant checks.

```bash
phpswitch --clear-directory-cache   # force rescan
```

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
    ├── auto-switch.sh    # directory-based auto-switching hooks
    └── commands.sh       # CLI argument parsing and menu
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

1. Run `phpswitch --install-auto-switch` to (re)install the shell hook
2. Restart your terminal or source your shell config
3. Check `AUTO_SWITCH_PHP_VERSION=true` in `~/.phpswitch.conf`
4. Run `phpswitch --clear-directory-cache` to clear stale cache

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
