---
title: Build System
category: architecture
tags: [build, concatenation, single-file, distribution]
created: 2026-04-06
updated: 2026-04-06
sources: 1
---

# Build System

PHPSwitch's build system is a single script (`phpswitch/build.sh`) that concatenates library modules into a standalone distributable.

## What it produces

`php-switcher.sh` at the repo root — a self-contained bash script with no external dependencies beyond Homebrew.

## How it works

1. Strips the shebang (`#!/bin/bash`) from each module.
2. Concatenates modules in a fixed order (see [[architecture/module-pipeline]]).
3. Appends a two-line `main` block at the end.
4. Prints the SHA256 checksum of the output — required when updating the Homebrew formula.

## Usage

```bash
cd phpswitch
./build.sh              # Outputs php-switcher.sh to repo root
./build.sh --dev-copy   # Also copies to phpswitch/php-switcher.sh for local testing
./build.sh --help       # Show all options
```

## Do not edit the artifact directly

`php-switcher.sh` is a build output. All changes go into `phpswitch/lib/` modules. After editing, rebuild.

## See also

- [[architecture/module-pipeline]]
- [[entities/php-switcher-sh]]
- [[entities/phpswitch-sh]]
