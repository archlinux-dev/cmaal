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

Helpers you get from `lib/core.sh`: `msg`, `ok`, `warn`, `die`, `section`, `have`, `ask "question" y|n`, `prompt`, `as_root`, `need_arch`, `need_fzf`, `page`, `notify`, and `$HELPER` for the AUR helper.

Use `$PACMAN_LOG`, `$PACMAN_CONF`, `$MIRRORLIST`, `$PACMAN_LOCK` and `$PACMAN_SYNC` instead of hardcoded paths, so the tests can swap in fake files.

## Checks

```bash
make lint    # shellcheck + bash -n on every file
make test    # the test suite (fake pacman/yay/flatpak/curl, no network)
```

CI runs both on Ubuntu, then builds and installs the real package in an Arch Linux container.

## Making a release

1. Bump the version in `VERSION`, `pkgver=` in `packaging/PKGBUILD` and `CMAAL_VERSION=` in the legacy `cmaal` file at the repo root.
2. Add a `## x.y.z` section at the top of `CHANGELOG.md`.
3. Merge to `main`. Installed copies notice within a day, `cmaal self-update` installs it and shows the changelog entry.

CI fails if those versions don't match.
