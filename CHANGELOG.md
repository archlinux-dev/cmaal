# Changelog

All notable changes to cmaal. `cmaal whatsnew` shows the entry for your installed version.

## 0.3.0

cmaal is a real pacman package now.

- **Package:** installs with a PKGBUILD, so pacman tracks every file (`pacman -Qi cmaal`, `pacman -Rns cmaal`). Old single-file installs move over automatically on `cmaal self-update`.
- **Layout:** `/usr/bin/cmaal` plus modules in `/usr/lib/cmaal`, data in `/usr/share/cmaal`, a man page (`man cmaal`), completions and docs.
- **New:** `cmaal updates` lists pending updates without installing anything.
- **New:** `cmaal why <pkg>` explains why a package is installed and what needs it.
- **New:** `cmaal provides <cmd>` finds the package for a command you don't have yet.
- **New:** `cmaal files <pkg>` lists the files of installed and not installed packages.
- **New:** `cmaal pkgbuild <pkg>` shows a package's build script, so you can check AUR packages before installing.
- **New:** `cmaal hold / unhold / holds` keeps packages at their current version (pacman IgnorePkg, validated before saving).
- **New:** `cmaal orphans [rm]`, `cmaal kernel`, `cmaal disk`.
- **New:** `cmaal whatsnew` shows this changelog; self-update shows it after updating.
- **New:** desktop notification when an upgrade takes longer than a minute (`NOTIFY_AFTER_SECONDS`).
- **New:** `cmaal help <word>` shows only the matching help lines.
- `cmaal self-update` rebuilds the package (or updates a `make install` copy or git checkout).
- `cmaal uninstall` removes the package with pacman.
- Test suite (`make test`) and CI that builds the package in an Arch container.

## 0.2.0

- `cmaal -S` and `cmaal -Rns` without a package name open fzf pickers over repos, AUR and flatpak.
- `cmaal undo` reverts the last pacman transaction, `cmaal downgrade` picks older versions from the cache or the Arch Linux Archive.
- `cmaal pkglist export / import` saves and restores all your packages.
- Snapshots with snapper or timeshift before `-Syu`, plus `cmaal snapshot`.
- `cmaal fix`, `services`, `logs`, `ports`, `ip`, `fetch`, `theme`, `weather`.
- `cmaal ssh -t` opens hosts in a new kitty tab.
- `--noconfirm` takes each question's default answer.

## 0.1.0

- First version: `-S` across pacman, AUR and flatpak, `-Ss`, `-Si`, `-Syu`, pacman passthrough.
- SSH host manager with kitty integration.
- `clean`, `mirrors`, `news`, `history`, `owns`, `big`, `sys`, `doctor`, `helper`.
- Background update check and `cmaal self-update`.
