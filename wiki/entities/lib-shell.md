---
title: lib/shell.sh
category: entity
tags: [module, shell, zsh, bash, fish, rc-file, PATH]
created: 2026-04-06
updated: 2026-04-06
sources: 1
---

# lib/shell.sh

Shell detection and rc file management.

## Responsibilities

- Detect the user's shell (`$SHELL` or process inspection)
- Select the correct rc file (`~/.zshrc`, `~/.bashrc`, `~/.config/fish/config.fish`)
- Append or update `export PATH=...` lines for the active PHP version
- Create rc file backups before any modification
- Install auto-switch hooks (called by [[entities/lib-auto-switch]])

## See also

- [[concepts/shell-patching]]
- [[concepts/auto-switch]]
- [[entities/lib-auto-switch]]
