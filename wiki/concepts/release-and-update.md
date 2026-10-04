---
title: Release & Self-Update
category: concept
tags: [release, update, security, homebrew]
created: 2026-10-03
updated: 2026-10-04
sources: 0
---

# Release & Self-Update

## Releasing (`tools/release.sh`)

Before running it, add the version's section to `CHANGELOG.md` (Keep a Changelog format) and commit it. Leave `PHPSWITCH_VERSION` alone: if it already equals the new version, the script skips the rebuild and the bump commit. `--generate-notes` produces only a PR list, so write the GitHub release notes from the CHANGELOG section and apply them with `gh release edit vX.Y.Z --notes-file`.

1. Prompts for the new version (accepts `1.5.0` or `v1.5.0`; must be `X.Y.Z`).
2. Writes it to `PHPSWITCH_VERSION` in `phpswitch/config/defaults.sh`, the single source of the version. Rebuilds, commits and pushes.
3. Writes `php-switcher.sh.sha256` (`shasum -a 256` format; the file is gitignored).
4. Signs the artifact with minisign (`php-switcher.sh.minisig`, trusted comment `phpswitch vX.Y.Z`; the secret key is `$MINISIGN_SECRET_KEY` or `~/.minisign/minisign.key`, and minisign asks for its password). It then verifies the signature against the public key read from the **built** artifact, and stops before tagging if they don't match. Before anything is changed, the script checks that `minisign`, a non-empty `PHPSWITCH_MINISIGN_PUBKEY` and the secret key file all exist.
5. Tags `vX.Y.Z` and creates a GitHub Release with `php-switcher.sh`, `php-switcher.sh.sha256` and `php-switcher.sh.minisig` as assets.
6. Hashes the source tarball of the tag and patches `Formula/phpswitch.rb` (url and sha256). Copies the formula to the tap repo (`../homebrew-phpswitch` or `$TAP_REPO`).

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
        │ key built in + minisign installed: .minisig missing or invalid → refuse, exit 1
        │ key built in, no minisign → warning, checksum only
        ▼
prompt → backup → install (existing copy/sudo logic)
```

- **Fails closed.** A release without the `.sha256` asset can't be installed through `--update`. `shasum` is required.
- **Exit status:** `--update` passes through the function's status, so a refused update exits non-zero.
- **Symlinks:** Homebrew links with relative symlinks (`bin/phpswitch → ../Cellar/...`). `cmd_resolve_script_path` normalizes each hop with `cd`/`pwd` and caps the chain at 40 hops.
- **Trust model:** the checksum comes from the same release as the script, so on its own it only protects against corruption and mismatched assets. The minisign signature is made with a key that never touches GitHub. An install that has the public key built in, and minisign installed, therefore rejects a release from a compromised GitHub account. Without minisign it falls back to the checksum and prints a warning (the user's choice, 2026-10-04). The public key (`RWTRUA0k…`) has been in `config/defaults.sh` since 2026-10-04. A build with an empty key skips the signature step.
- **Key custody:** back up the secret key and its password. If the key is lost, every install that has minisign refuses all later updates. Rotating the key needs one release, signed with the old key, whose script embeds the new public key. The README's manual-install section shows the public key too, so update it as well.
- **Manual install:** the README downloads `php-switcher.sh`, `.sha256` and `.minisig` from `releases/latest/download/` and checks them with `shasum -a 256 -c` and `minisign -Vm`. Installs up to 1.4.5 update from raw master instead, so master must keep a current `php-switcher.sh`.

## Tests

`tests/08_update.bats` uses the fake `curl` (`tests/helpers/bin/curl`, which serves fixtures by URL) and a fake `sudo` that always refuses. No test can reach the network or a real install.

## See also

- [[decisions/roadmap-2026]]
- [[concepts/testing]]
- [[architecture/build-system]]
