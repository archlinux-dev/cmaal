# cmaal

> Pls don't be to mean, its my first project with claude code where i actualy came up with the ideas

A multitool for Arch Linux. One command instead of juggling `pacman`, `yay`, `paru` and `flatpak`, plus AUR safety checks, rollbacks, Wi-Fi and bluetooth, gaming setup, rescue, backups, SSH shortcuts and your own plugins. It installs as a real pacman package, and speaks English and German.

```
$ cmaal -S discord visual-studio-code-bin spotify
:: Looking up 3 package(s)...
   pacman   discord
   aur      visual-studio-code-bin
   flatpak  com.spotify.Client
```

## Contents

- [Install](#install)
- [Packages](#packages)
- [AUR safety](#aur-safety)
- [Rollback](#rollback)
- [System](#system)
- [Update alerts](#update-alerts)
- [Desktop](#desktop)
- [Rescue](#rescue)
- [Backup](#backup)
- [SSH](#ssh)
- [Fun](#fun)
- [Plugins](#plugins)
- [Deutsch](#deutsch)
- [Updating cmaal](#updating-cmaal)
- [Config](#config)
- [How it's built](#how-its-built)
- [Development](#development)

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/archlinux-dev/cmaal/main/install.sh | bash
```

Run it as your normal user (not root). It builds cmaal with `makepkg` and installs it with pacman, so it's a real package:

```bash
pacman -Qi cmaal     # version, size, install date
pacman -Ql cmaal     # every file it installed
man cmaal            # the full manual
```

The installer also offers the optional extras (`fzf`, `reflector`, `pacman-contrib`) and an AUR helper (`yay`) if you don't have one.

Or from the AUR (once it's published there, see [packaging/aur](packaging/aur/README.md)):

```bash
yay -S cmaal-git
```

Other ways to install:

```bash
git clone https://github.com/archlinux-dev/cmaal.git
cd cmaal
./install.sh             # same as above, builds your local checkout
./install.sh --user      # no package, no root: ~/.local
cd packaging && makepkg -si   # build the package by hand
```

**Uninstall:** `sudo pacman -Rns cmaal` (or `cmaal uninstall`).

**Coming from 0.1 / 0.2?** Just run `cmaal self-update`. It moves your old single-file install over to the package automatically.

## Packages

cmaal looks in the official repos first, then the AUR, then flatpak, and installs each package from wherever it finds it.

| Command | What it does |
| --- | --- |
| `cmaal -S <pkg>...` | install from repos, AUR or flatpak |
| `cmaal -S` | browse every package in fzf with a live preview, TAB to pick several |
| `cmaal -Ss <query>` | search repos, AUR and flatpak at once |
| `cmaal -Si <pkg>` | package info from any source |
| `cmaal -Syu` | upgrade everything: repos + AUR + flatpak |
| `cmaal -Syyu` | same, with a forced database refresh |
| `cmaal -Rns [pkg]` | remove; without a name, pick in fzf |
| `cmaal -Q`, `-Qi`, ... | any other pacman flag is passed straight through |
| `cmaal updates` | list pending updates without installing anything |
| `cmaal why <pkg>` | did you install it, or what pulled it in? |
| `cmaal files <pkg>` | files a package installs (installed or not) |
| `cmaal provides <cmd>` | "command not found"? find the package that has it |
| `cmaal owns <cmd>` | which installed package a command belongs to |
| `cmaal pkgbuild <pkg>` | read the build script first, good habit for AUR packages |
| `cmaal orphans [rm]` | dependencies nothing needs anymore |
| `cmaal big [n]` | largest installed packages |
| `cmaal helper install yay` | install an AUR helper (yay or paru) |

**Before `-Syu`** cmaal shows Arch news posted since your last upgrade (they often need manual steps) and takes a snapper or timeshift snapshot if you use one. **After** it lists `.pacnew` files, tells you when a reboot is needed for a new kernel, and sends a desktop notification if the upgrade took more than a minute.

Add `--noconfirm` to skip questions. cmaal then picks each question's default answer, like pacman does.

## AUR safety

Anyone can upload to the AUR, so cmaal looks before it installs. For every AUR package it shows votes, maintainer and last update, and warns when a package is:

- **orphaned** (nobody maintains it)
- **flagged out of date**
- **brand new with almost no votes** (read the PKGBUILD first)
- **changed**: cmaal remembers the PKGBUILD you installed and tells you when an update changes it

```
==> AUR check
   fresh-miner 0.0.1-1
      votes: 1   popularity: 0.5   maintainer: someone
      last updated 2 days ago
      ! brand new with almost no votes: read the PKGBUILD first (cmaal review)
:: There are warnings above. Install anyway? [Y/n]
```

| Command | What it does |
| --- | --- |
| `cmaal review <pkg>` | the card plus what changed in the PKGBUILD since you installed it |
| `cmaal review` | check every installed AUR package: orphaned, out of date, or removed from the AUR |
| `cmaal pkgbuild <pkg>` | read the whole PKGBUILD |

Turn the checks off with `AUR_CHECK="no"` in `cmaal config`.

## Rollback

| Command | What it does |
| --- | --- |
| `cmaal undo` | revert the last install / upgrade / removal (run again to redo) |
| `cmaal downgrade <pkg>` | pick an older version from your cache or the Arch Linux Archive |
| `cmaal hold <pkg>` | keep a package at its current version (pacman `IgnorePkg`) |
| `cmaal unhold <pkg>` | let it upgrade again |
| `cmaal holds` | list held packages |
| `cmaal snapshot [list/create/restore]` | snapper or timeshift snapshots |
| `cmaal pkglist export [file]` | save every package you installed (repo, AUR, flatpak) |
| `cmaal pkglist import [file]` | install them all again, e.g. on a fresh Arch install |
| `cmaal history [n]` | recent installs, upgrades and removals |

A new mesa broke your games? `cmaal downgrade mesa && cmaal hold mesa`, and later `cmaal unhold mesa` once it's fixed.

`hold` edits `/etc/pacman.conf` carefully: it keeps a backup (`pacman.conf.cmaal.bak`) and lets pacman validate the new file before saving it.

## System

| Command | What it does |
| --- | --- |
| `cmaal clean` | remove orphans, trim package cache, AUR build cache, flatpak runtimes, journal |
| `cmaal fix` | leftover lock file, keyring / signature errors, dead mirrors, broken database, missing files |
| `cmaal mirrors [country]` | find the fastest mirrors with reflector (backs up the old list) |
| `cmaal news [n]` | latest Arch Linux news |
| `cmaal services [--user]` | pick a systemd service, then start / stop / restart / enable / disable / logs |
| `cmaal services <name> <action>` | same without the menu, e.g. `cmaal services bluetooth restart` |
| `cmaal logs` | errors since boot (`prev` = last boot, `-f` = follow, or a service name) |
| `cmaal kernel` | running vs installed kernels, is a reboot needed? |
| `cmaal disk` | disk usage, what you can clean, biggest folders in your home |
| `cmaal ports` | which programs listen on which ports |
| `cmaal ip` | local and public IP addresses |
| `cmaal sys` | system overview |
| `cmaal doctor` | check optional tools and system health |

## Update alerts

```bash
cmaal alerts on
```

cmaal now checks in the background every 6 hours (a systemd user timer, no root) and sends a desktop notification like *"12 updates (3 AUR), 1 unread Arch news, read before upgrading"*. It never installs anything by itself, and it doesn't repeat the same message. `cmaal alerts now` checks right away, `cmaal alerts off` stops it, and `ALERTS_EVERY` in the config changes how often.

## Desktop

| Command | What it does |
| --- | --- |
| `cmaal wifi` | pick a network and join it (asks for the password when needed) |
| `cmaal wifi share` | show the Wi-Fi password and a QR code your phone can scan |
| `cmaal wifi list / status / forget / on / off` | the rest of Wi-Fi |
| `cmaal bluetooth` | status and paired devices |
| `cmaal bluetooth pair` | scan, pair, trust and connect a new device |
| `cmaal bluetooth connect / disconnect / remove` | pick a device from a list |
| `cmaal drivers` | detect CPU, GPU, Wi-Fi and audio and install missing microcode, drivers and firmware |
| `cmaal gaming` | enable multilib and set up Steam, Proton, GameMode, MangoHud and 32-bit drivers |

Wi-Fi uses NetworkManager (`nmcli`); with iwd, `cmaal wifi` opens `iwctl` instead.

## Rescue

`cmaal rescue` helps when your system doesn't boot anymore. Start the Arch USB stick, connect to the internet, and run cmaal straight from git:

```bash
pacman -Sy git
git clone https://github.com/archlinux-dev/cmaal
./cmaal/bin/cmaal rescue
```

It finds your installed system, mounts it (btrfs `@` subvolumes included), then offers the usual fixes: remove a stuck pacman lock, update everything, reinstall the kernel and initramfs, reinstall GRUB or systemd-boot, reset a password, or show the errors of the last boot. Every command is shown and confirmed before it runs. On a system that still boots, `cmaal rescue` offers the same fixes directly.

## Backup

```bash
cmaal backup init git@github.com:you/dotfiles.git   # once, use a PRIVATE repo
cmaal backup                                         # whenever you like
```

Copies your config files (kitty, shell, git, nvim, hyprland and more, see `cmaal backup list`) plus your package list into a git repository and pushes it. **Private SSH keys, GPG keys, tokens and passwords are never copied.** `cmaal backup add <path>` adds more, `cmaal backup restore` puts files back (your current versions are kept as `.cmaal-old`). On a new PC: restore, then `cmaal pkglist import` the package list from the backup.

## SSH

| Command | What it does |
| --- | --- |
| `cmaal ssh` | pick a saved host and connect (fuzzy search with fzf) |
| `cmaal ssh <host>` | connect |
| `cmaal ssh -t [host]` | connect in a new kitty tab |
| `cmaal ssh ls` | list saved hosts |
| `cmaal ssh add [alias] [user@host[:port]] [keyfile]` | save a host (asks for missing bits) |
| `cmaal ssh rm <alias>` | remove a host (makes a backup first) |
| `cmaal ssh keygen [name]` | create an ed25519 key |
| `cmaal ssh keys` | list your public keys with fingerprints |
| `cmaal ssh copy <host>` | copy your key to a server |
| `cmaal ssh test <host>` | check that key login works |
| `cmaal ssh server on/off/status` | manage the local sshd |
| `cmaal ssh edit` | open `~/.ssh/config` |

Hosts live in your normal `~/.ssh/config`, so plain `ssh` sees them too.

**kitty:** inside kitty, cmaal connects with `kitten ssh`, which copies kitty's terminfo to the server. No more `unknown terminal type xterm-kitty` or broken backspace. New tabs (`-t`, or `SSH_NEW_TAB="yes"`) need this in `~/.config/kitty/kitty.conf`, then a kitty restart:

```
allow_remote_control yes
```

## Fun

| Command | What it does |
| --- | --- |
| `cmaal fetch` | system info next to the Arch logo |
| `cmaal theme` | pick a kitty color theme (live preview) |
| `cmaal theme <name>` | switch straight to a theme, e.g. `cmaal theme Catppuccin-Mocha` |
| `cmaal weather [city]` | 3 day forecast from wttr.in |

## Plugins

Make your own cmaal commands:

```bash
cmaal plugins new hello
cmaal plugins edit hello
cmaal hello
```

A plugin is a bash file in `~/.config/cmaal/plugins/` with a `plugin_<name>` function. It can use all of cmaal's helpers (`msg`, `ok`, `warn`, `ask`, `as_root`, ...) and hook into cmaal:

```bash
PLUGIN_DESC="back up my notes after every upgrade"

plugin_notes() { cp -r ~/notes /mnt/usb/; ok "notes copied"; }

after_upgrade() { plugin_notes; }
cmaal_on post_upgrade after_upgrade
```

Events: `pre_upgrade`, `post_upgrade`, `post_install`. Plugins show up in `cmaal --help` and tab completion. A broken plugin is skipped with a warning instead of breaking cmaal, and plugins can't replace built-in commands.

## Deutsch

cmaal spricht Deutsch, wenn dein System es tut (`LANG=de_AT.UTF-8`, `de_DE`, ...): die ganze Hilfe (`cmaal help`) und die meisten Meldungen. Bei Fragen gilt `j` als Ja. Sprache erzwingen mit `LANGUAGE_UI="de"` oder `"en"` in `cmaal config`.

## Updating cmaal

cmaal checks GitHub for a new version once a day, in the background, so it never slows anything down. By default it just tells you:

```
:: cmaal v0.4.0 is available (you have v0.3.0). Run: cmaal self-update
```

`cmaal self-update` rebuilds the package with the latest code and shows what changed. `cmaal whatsnew` shows it again any time, `cmaal whatsnew all` shows the whole [changelog](CHANGELOG.md).

Set `AUTO_UPDATE="auto"` in the config to update without asking, or `"off"` to turn the check off.

## Config

`cmaal config` opens `~/.config/cmaal/config` (created from `/usr/share/cmaal/config.default`):

```bash
AUTO_UPDATE="notify"           # auto | notify | off
UPDATE_INTERVAL_HOURS=24
AUR_HELPER="auto"              # auto | yay | paru | pikaur | none
HELPER_ORDER="yay paru pikaur"
USE_FLATPAK="yes"
SHOW_NEWS_ON_UPGRADE="yes"
SSH_USE_KITTEN="auto"          # auto | yes | no
SSH_NEW_TAB="no"               # yes = cmaal ssh opens a new kitty tab
SNAPSHOT_BEFORE_UPGRADE="auto" # auto | yes | no
WEATHER_CITY=""                # empty = detect from your IP
NOTIFY_AFTER_SECONDS=60        # desktop notification after long upgrades, 0 = off
AUR_CHECK="yes"                # check AUR packages before installing / upgrading
LANGUAGE_UI="auto"             # auto | en | de
ALERTS_EVERY="6h"              # how often cmaal alerts checks
BACKUP_PATHS=""                # extra paths for cmaal backup
```

Environment variables: `NO_COLOR=1` turns colors off, `CMAAL_ASSUME_YES=1` answers yes to every question (for scripts).

## How it's built

cmaal is plain bash, split into modules:

```
/usr/bin/cmaal              entry point: finds the modules, dispatches commands
/usr/lib/cmaal/
    core.sh                 config, colors, prompts, sudo, AUR helper detection
    packages.sh             -S, -Ss, -Si, -Syu, fzf pickers
    query.sh                updates, why, files, provides, pkgbuild, orphans
    aur.sh                  AUR safety: cards, PKGBUILD changes, review
    alerts.sh               background update alerts
    rollback.sh             undo, downgrade, snapshots, pkglist
    hold.sh                 hold / unhold (pacman IgnorePkg)
    maintenance.sh          clean, mirrors, history, owns, big, fix
    system.sh               sys, doctor, services, logs, kernel, disk, ports, ip
    news.sh                 Arch news
    ssh.sh                  ssh hosts, keys, kitty integration
    fun.sh                  fetch, theme, weather
    network.sh              wifi, bluetooth
    hardware.sh             drivers, gaming
    rescue.sh               rescue
    backup.sh               backup
    plugins.sh              plugins and hooks
    selfupdate.sh           version, self-update, whatsnew, config, uninstall
    help.sh                 help text
/usr/share/cmaal/           default config, logo, changelog, translations (i18n/)
/usr/share/man/man1/cmaal.1
/usr/share/{bash-completion,zsh,fish}/...   completions
```

In the repo:

```
bin/ lib/ share/ man/ completions/   the program
packaging/PKGBUILD                   the Arch package
packaging/aur/                       the AUR package (cmaal-git) and its publish script
Makefile                             make install / test / lint
install.sh                           the installer
tests/                               test suite with fake pacman, yay, flatpak, curl
cmaal                                one-time mover for 0.1 / 0.2 installs (don't delete)
```

## Versions

`MAJOR.MINOR.PATCH`: small updates bump the middle number (1.0 → 1.1), big ones the first (1.x → 2.0), quick fixes the last (1.1.0 → 1.1.1). See the [changelog](CHANGELOG.md).

## Development

```bash
./bin/cmaal --help      # runs straight from the checkout, no install needed
make test               # test suite, never touches your real system
make lint               # shellcheck
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for adding commands and making a release.

## License

Apache 2.0, see [LICENSE](LICENSE).
