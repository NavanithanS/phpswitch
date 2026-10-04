#!/bin/bash
# PHPSwitch Default Configuration
# Contains default values for configuration

PHPSWITCH_VERSION="1.4.5"

# minisign public key that release assets are signed with (tools/release.sh).
# A fixed value, never read from the config file or the environment. Empty
# only in development builds: --update then verifies the checksum alone.
PHPSWITCH_MINISIGN_PUBKEY=""

# Default configuration values
DEFAULT_AUTO_RESTART_PHP_FPM=true
DEFAULT_BACKUP_CONFIG_FILES=true
DEFAULT_PHP_VERSION=""
DEFAULT_MAX_BACKUPS=5
DEFAULT_AUTO_SWITCH_PHP_VERSION=false
DEFAULT_CACHE_DIRECTORY=""  # Empty means use default location in ~/.cache/phpswitch
