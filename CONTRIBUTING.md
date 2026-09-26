# Contributing to cmaal

## Running from a checkout

No install needed, `bin/cmaal` finds its modules in `lib/`:

```bash
./bin/cmaal --version     # says "(git install)"
./bin/cmaal <command>
```

## Adding a command

1. Write a `cmd_<name>()` function in the module it fits (`lib/*.sh`), or add a new module. Every `lib/*.sh` file is loaded automatically.
2. Add it to the `case` in `main()` in `bin/cmaal`.
3. Add a line to the help text in `lib/help.sh`.
4. Add it to the man page (`man/cmaal.1`), the README and the three completion files in `completions/`.
5. Add a test in `tests/run.sh`. If it calls a program that changes the system, add a fake one to `tests/mocks/` that only logs the call.

User-facing text goes through `t "text"` (or `tf "format %s" args`) so it can be translated; add the German line to `share/i18n/de.txt` (English, a tab, German). `msg`, `ok`, `warn`, `die`, `section`, `ask` and `prompt` translate by themselves.

Helpers you get from `lib/core.sh`: `msg`, `ok`, `warn`, `die`, `section`, `have`, `ask "question" y|n`, `prompt`, `as_root`, `need_arch`, `need_fzf`, `page`, `notify`, and `$HELPER` for the AUR helper.

Use `$PACMAN_LOG`, `$PACMAN_CONF`, `$MIRRORLIST`, `$PACMAN_LOCK` and `$PACMAN_SYNC` instead of hardcoded paths, so the tests can swap in fake files.

## Checks

```bash
make lint    # shellcheck + bash -n on every file
make test    # the test suite (fake pacman/yay/flatpak/curl, no network)
```

CI runs both on Ubuntu, then builds and installs the real package in an Arch Linux container.

## Version numbers

cmaal uses `MAJOR.MINOR.PATCH`:

- **Small update** (new commands, improvements): bump the middle number, 1.0.0 → **1.1.0** → 1.2.0.
- **Big update** (large redesign, changed behavior people rely on): bump the first number, 1.x → **2.0.0**.
- **Quick fix** for a broken release, nothing new: bump the last number, 1.1.0 → 1.1.1.

## Making a release

1. Pick the version with the rules above.
2. Put it in `VERSION`, `pkgver=` in `packaging/PKGBUILD` and `CMAAL_VERSION=` in the legacy `cmaal` file at the repo root.
3. Add a `## x.y.z` section at the top of `CHANGELOG.md`.
4. Merge to `main`. Installed copies notice within a day, `cmaal self-update` installs it and shows the changelog entry.
5. Only if dependencies changed: copy them into `packaging/aur/cmaal-git/PKGBUILD` and run `packaging/aur/publish.sh`.

CI fails if the versions don't match.
