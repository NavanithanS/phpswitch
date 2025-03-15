# PHPSwitch - PHP Version Manager for macOS

A powerful command-line utility for easily switching between multiple PHP versions installed via Homebrew on macOS, with special attention to Apple Silicon (M1/M2) compatibility.

## Features

-   🔄 Switch between different PHP versions with a simple interactive menu
-   🔍 List all installed and available PHP versions from Homebrew
-   ⬇️ Install new PHP versions on demand
-   🗑️ Safely uninstall PHP versions you no longer need
-   🔄 Automatically update your shell configuration (.zshrc, .bashrc, .config/fish/config.fish)
-   🐟 Full support for Fish shell in addition to Bash and Zsh
-   📁 Project-level PHP version detection via .php-version files
-   🔌 Manage PHP-FPM services and PHP extensions
-   📜 Non-interactive mode for scripting and automation
-   ⏱️ Smart caching system for faster version lookups
-   🔄 Visual loading indicators during longer operations
-   ⏳ Timeout protection for unresponsive Homebrew commands
-   🛠️ Robust error handling with helpful troubleshooting suggestions
-   🎨 Color-coded status messages for better readability
-   ⚙️ User configuration options with ~/.phpswitch.conf
-   🔄 Self-update mechanism to stay current
-   🐞 Debug mode for troubleshooting

## Requirements

-   macOS (optimized for Apple Silicon M1/M2, works on Intel too)
-   [Homebrew](https://brew.sh/) package manager
-   Zsh, Bash, or Fish shell

## Installation

### Option 1: Quick Installation

```bash
curl -L https://raw.githubusercontent.com/NavanithanS/phpswitch/master/php-switcher.sh -o /tmp/php-switcher.sh && chmod +x /tmp/php-switcher.sh && sudo /tmp/php-switcher.sh --install
```

### Option 2: Manual Installation

1. Clone this repository:

    ```bash
    git clone https://github.com/NavanithanS/phpswitch.git
    ```

2. Navigate to the repository:

    ```bash
    cd phpswitch
    ```

3. Make the script executable:

    ```bash
    chmod +x php-switcher.sh
    ```

4. Install it as a system command (optional):
    ```bash
    sudo ./php-switcher.sh --install
    ```

## Usage

### Basic Usage

Just run the command without any arguments to see the interactive menu:

```bash
phpswitch
```

### Available Options

-   `phpswitch` - Shows the interactive menu to switch PHP versions
-   `phpswitch --install` - Installs phpswitch as a system command
-   `phpswitch --uninstall` - Removes phpswitch from your system
-   `phpswitch --update` - Checks for and installs the latest version
-   `phpswitch --switch=VERSION` - Switch to specified PHP version
-   `phpswitch --switch-force=VERSION` - Switch to PHP version, installing if needed
-   `phpswitch --install=VERSION` - Install specified PHP version
-   `phpswitch --uninstall=VERSION` - Uninstall specified PHP version
-   `phpswitch --uninstall-force=VERSION` - Force uninstall specified PHP version
-   `phpswitch --list` - List installed and available PHP versions
-   `phpswitch --json` - List PHP versions in JSON format
-   `phpswitch --current` - Show current PHP version
-   `phpswitch --project` or `-p` - Switch to the PHP version specified in project file
-   `phpswitch --clear-cache` - Clear cached data
-   `phpswitch --refresh-cache` - Refresh cache of available PHP versions
-   `phpswitch --debug` - Runs script in debug mode with additional logging
-   `phpswitch --help` or `phpswitch -h` - Displays help information

### Examples

#### Switching PHP Versions

Run `phpswitch` and follow the interactive prompts:

```
PHPSwitch - PHP Version Manager for macOS
========================================
ℹ️  INFO: Current PHP version: php@8.1

Installed PHP versions:
1) php@7.4
2) php@8.0
3) php@8.1 (current)
4) php@8.2

ℹ️  INFO: Checking for available PHP versions to install...
Searching for available PHP versions..... Done!

Available PHP versions to install:
5) php@5.6 (not installed)
6) php@7.0 (not installed)
7) php@7.1 (not installed)

u) Uninstall a PHP version
e) Manage PHP extensions
c) Configure PHPSwitch
d) Diagnose PHP environment
p) Set current PHP version as project default
0) Exit without changes

Please select PHP version to use (0-7, u, e, c, d, p):
```

#### Using Project-level PHP Versions

Create a `.php-version` file in your project directory:

```bash
echo "8.1" > .php-version
```

Then simply run:

```bash
phpswitch -p
```

PHPSwitch will detect the version specified in the file and switch to it automatically.

#### Managing PHP Extensions

Select the `e` option from the main menu to manage extensions for the current PHP version:

```
PHP Extensions for php@8.1 (version 8.1)

Currently loaded extensions:
- bcmath
- calendar
- Core
...

Extension configuration files:
- ext-opcache.ini
- ext-xdebug.ini
...

Options:
1) Enable/disable an extension
2) Edit php.ini
3) Show detailed extension information
0) Back to main menu

Please select an option (0-3):
```

#### Diagnosing PHP Environment

Select the `d` option from the main menu to diagnose PHP environment issues:

```
PATH Diagnostic
===============

Current PATH:
1  /opt/homebrew/opt/php@8.1/bin
...

PHP binaries in PATH:
1) /opt/homebrew/opt/php@8.1/bin/php
   Version: PHP 8.1.12 (cli) (built: Nov 16 2022 02:28:39)
   Type: Direct binary

Active PHP:
/opt/homebrew/opt/php@8.1/bin/php
PHP 8.1.12 (cli) (built: Nov 16 2022 02:28:39)

Expected PHP path for current version:
/opt/homebrew/opt/php@8.1/bin/php

Recommended actions:
1. Ensure the PHP version you want is first in your PATH
2. Check for conflicting PHP binaries in your PATH
3. Run 'hash -r' (bash/zsh) or 'rehash' (fish) to clear command hash table
4. Open a new terminal session to ensure PATH changes take effect
```

#### Configuring PHPSwitch

Select the `c` option from the main menu to configure PHPSwitch behavior:

```
PHPSwitch Configuration
=======================
Current Configuration:
1) Auto restart PHP-FPM: true
2) Backup config files: true
3) Maximum backups to keep: 5
4) Default PHP version: None
0) Return to main menu

Select setting to change (0-4):
```

#### Uninstalling a PHP Version

Select the `u` option from the main menu, then choose which version to uninstall.

## How It Works

This tool helps you manage multiple PHP versions by:

1. Showing you all installed and available PHP versions from Homebrew
2. Handling the Homebrew linking/unlinking process
3. Updating your shell configuration file (`.zshrc`, `.bashrc`, `.config/fish/config.fish`, etc.) to ensure proper PATH configuration
4. Managing PHP-FPM services for the selected version
5. Providing extension management capabilities
6. Supporting project-level PHP version specification
7. Supporting user preferences through a configuration file
8. Offering self-update functionality to stay current
9. Providing helpful feedback and error handling throughout the process

### Performance Optimizations (v1.2.0+)

PHPSwitch uses several techniques to ensure responsiveness:

1. **Background Processing**: The search for available PHP versions runs in the background while displaying installed versions
2. **Smart Caching**: Available PHP versions are cached for 1 hour to avoid repeated slow Homebrew searches
3. **Visual Feedback**: Loading indicators display during potentially long operations
4. **Timeout Protection**: Commands have built-in timeouts to prevent the script from hanging

## Project Structure

```
phpswitch/
├── php-switcher.sh    # Main script file
├── LICENSE            # MIT License
└── README.md          # This documentation
```

## Configuration

PHPSwitch supports user configuration through a `~/.phpswitch.conf` file:

```bash
# PHPSwitch Configuration
AUTO_RESTART_PHP_FPM=true   # Automatically restart PHP-FPM when switching versions
BACKUP_CONFIG_FILES=true    # Create backups of shell config files before modifying
DEFAULT_PHP_VERSION=""      # Default PHP version to use (empty means none)
MAX_BACKUPS=5              # Maximum number of backup files to keep
```

You can edit this file directly or use the built-in configuration menu.

## Troubleshooting

### Common Issues

#### Permission Denied

If you encounter permission issues, try running the command with `sudo`:

```bash
sudo phpswitch
```

#### PHP Version Not Applied

If the PHP version doesn't change after switching:

1. Open a new terminal tab/window
2. Run `source ~/.zshrc` (or the appropriate RC file for your shell)
3. Verify with `php -v`

#### Installation Failed

If installation of a PHP version fails:

1. Run `brew doctor` to check for Homebrew issues
2. Try `brew update` to ensure your formulae are up to date
3. Try installing manually with `brew install php@X.Y`

#### Slow Performance When Listing Available Versions

If the script seems to hang when listing available versions:

1. This is usually due to slow Homebrew search operations, which v1.2.0+ handles better with caching and visual feedback
2. Try running with `--debug` flag to see detailed information about what's happening
3. Check your internet connection, as Homebrew may need to fetch the latest formula information

#### Debug Mode

For detailed troubleshooting, use debug mode:

```bash
phpswitch --debug
```

#### Unsupported Shell

PHPSwitch now supports Bash, Zsh, and Fish shells. If you're using another shell, it will use ~/.profile.

## Contributing

Contributions are welcome! Feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch: `git checkout -b feature/amazing-feature`
3. Commit your changes: `git commit -m 'Add some amazing feature'`
4. Push to the branch: `git push origin feature/amazing-feature`
5. Open a Pull Request

### Future Enhancement Ideas

Here are some features that could be implemented next:

-   Composer version management
-   Integration with common PHP development tools (Laravel, Symfony, etc.)
-   Installation of common PHP applications (WordPress, Drupal, etc.)
-   PHP package management integration
-   Docker/container integration
-   Visual indicators for PHP version in prompt

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

-   The Homebrew project for making package management on macOS easy
-   The PHP community for maintaining multiple versions
