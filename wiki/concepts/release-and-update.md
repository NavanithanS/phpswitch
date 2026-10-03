---
title: Release & Self-Update
category: concept
tags: [release, update, security, homebrew]
created: 2026-10-03
updated: 2026-10-03
sources: 0
---

# Release & Self-Update

## Releasing (`tools/release.sh`)

1. Prompts for the new version (accepts `1.5.0` or `v1.5.0`; must be `X.Y.Z`).
2. Writes it to `PHPSWITCH_VERSION` in `phpswitch/config/defaults.sh`, the single source of the version. Rebuilds, commits and pushes.
3. Writes `php-switcher.sh.sha256` (`shasum -a 256` format; the file is gitignored).
4. Tags `vX.Y.Z` and creates a GitHub Release with **both** `php-switcher.sh` and `php-switcher.sh.sha256` as assets.
5. Hashes the source tarball of the tag and patches `Formula/phpswitch.rb` (url and sha256). Copies the formula to the tap repo (`../homebrew-phpswitch` or `$TAP_REPO`).

## Release-time follow-ups

- **Formula completions:** once a release containing `phpswitch completions` is cut, add this to `Formula/phpswitch.rb` (and the tap):
  `generate_completions_from_executable(bin/"phpswitch", "completions")`
  Don't add it before then. The formula still installs v1.4.4, which opens the interactive menu on an unknown word, so `brew install` would hang.

## Self-update (`phpswitch --update` → `cmd_update_self`)

```
script on PATH ──resolve symlinks──► under $HOMEBREW_PREFIX/Cellar/ ?
        │ yes → print "brew upgrade phpswitch", exit 0 (no network)
        ▼ no
GET api.github.com/repos/NavanithanS/phpswitch/releases/latest → tag_name (v optional)
        │ current >= latest → "already latest" (never downgrades)
        ▼
download releases/download/<tag>/php-switcher.sh and php-switcher.sh.sha256
        │ checksum missing, mismatched or malformed → refuse, exit 1
        │ embedded PHPSWITCH_VERSION != tag version → refuse, exit 1
        ▼
prompt → backup → install (existing copy/sudo logic)
```

- **Fails closed.** A release without the `.sha256` asset can't be installed through `--update`. `shasum` is required.
- **Exit status:** `--update` passes through the function's status, so a refused update exits non-zero.
- **Symlinks:** Homebrew links with relative symlinks (`bin/phpswitch → ../Cellar/...`). `cmd_resolve_script_path` normalizes each hop with `cd`/`pwd` and caps the chain at 40 hops.
- **Trust model:** the checksum comes from the same release as the script. It protects against corruption and mismatched assets, but not against a compromised GitHub account. Signing is a possible future step.

## Tests

`tests/08_update.bats` uses the fake `curl` (`tests/helpers/bin/curl`, which serves fixtures by URL) and a fake `sudo` that always refuses. No test can reach the network or a real install.

## See also

- [[decisions/roadmap-2026]]
- [[concepts/testing]]
- [[architecture/build-system]]
