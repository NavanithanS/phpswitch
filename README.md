# PHPSwitch - PHP Version Manager for macOS

A powerful command-line utility for easily switching between multiple PHP versions installed via Homebrew on macOS, with special attention to Apple Silicon (M1/M2) compatibility.

## Features

-   🔄 Switch between different PHP versions with a simple interactive menu
-   🔍 List all installed and available PHP versions from Homebrew
-   ⬇️ Install new PHP versions on demand
-   🗑️ Safely uninstall PHP versions you no longer need
-   🔄 Automatically update your shell configuration (.zshrc, .bashrc)
-   🔌 Manage PHP-FPM services and PHP extensions
-   🛠️ Robust error handling with helpful troubleshooting suggestions
-   🎨 Color-coded status messages for better readability
-   ⚙️ User configuration options with ~/.phpswitch.conf
-   🔄 Self-update mechanism to stay current
-   🐞 Debug mode for troubleshooting

## Requirements

-   macOS (optimized for Apple Silicon M1/M2, works on Intel too)
-   [Homebrew](https://brew.sh/) package manager
-   Zsh or Bash shell

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

Available PHP versions to install:
5) php@5.6 (not installed)
6) php@7.0 (not installed)
7) php@7.1 (not installed)

u) Uninstall a PHP version
e) Manage PHP extensions
c) Configure PHPSwitch
0) Exit without changes

Please select PHP version to use (0-7, u, e, c):
```

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

#### Configuring PHPSwitch

Select the `c` option from the main menu to configure PHPSwitch behavior:

```
PHPSwitch Configuration
=======================
Current Configuration:
1) Auto restart PHP-FPM: true
2) Backup config files: true
3) Default PHP version: None
0) Return to main menu

Select setting to change (0-3):
```

#### Uninstalling a PHP Version

Select the `u` option from the main menu, then choose which version to uninstall.

## How It Works

This tool helps you manage multiple PHP versions by:

1. Showing you all installed and available PHP versions from Homebrew
2. Handling the Homebrew linking/unlinking process
3. Updating your shell configuration file (`.zshrc`, `.bashrc`, etc.) to ensure proper PATH configuration
4. Managing PHP-FPM services for the selected version
5. Providing extension management capabilities
6. Supporting user preferences through a configuration file
7. Offering self-update functionality to stay current
8. Providing helpful feedback and error handling throughout the process

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

#### Debug Mode

For detailed troubleshooting, use debug mode:

```bash
phpswitch --debug
```

#### Unsupported Shell

If you're using a shell other than Bash or Zsh, the script will use ~/.profile. You may need to manually source this file or consider contributing support for your shell!

## Contributing

Contributions are welcome! Feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch: `git checkout -b feature/amazing-feature`
3. Commit your changes: `git commit -m 'Add some amazing feature'`
4. Push to the branch: `git push origin feature/amazing-feature`
5. Open a Pull Request

### Future Enhancement Ideas

Here are some features that could be implemented next:

-   Support for additional shells (fish, etc.)
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
