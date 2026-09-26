# cmaal

> Pls don't be to mean, its my first project with claude code where i actualy came up with the ideas

A multitool for Arch Linux. One command instead of juggling `pacman`, `yay`, `paru` and `flatpak`, plus rollbacks, SSH shortcuts, system care and self updating. It installs as a real pacman package.

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
- [Rollback](#rollback)
- [System](#system)
- [SSH](#ssh)
- [Fun](#fun)
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
    rollback.sh             undo, downgrade, snapshots, pkglist
    hold.sh                 hold / unhold (pacman IgnorePkg)
    maintenance.sh          clean, mirrors, history, owns, big, fix
    system.sh               sys, doctor, services, logs, kernel, disk, ports, ip
    news.sh                 Arch news
    ssh.sh                  ssh hosts, keys, kitty integration
    fun.sh                  fetch, theme, weather
    selfupdate.sh           version, self-update, whatsnew, config, uninstall
    help.sh                 help text
/usr/share/cmaal/           default config, logo
/usr/share/man/man1/cmaal.1
/usr/share/{bash-completion,zsh,fish}/...   completions
```

In the repo:

```
bin/ lib/ share/ man/ completions/   the program
packaging/PKGBUILD                   the Arch package
Makefile                             make install / test / lint
install.sh                           the installer
tests/                               test suite with fake pacman, yay, flatpak, curl
cmaal                                one-time mover for 0.1 / 0.2 installs (don't delete)
```

## Development

```bash
./bin/cmaal --help      # runs straight from the checkout, no install needed
make test               # test suite, never touches your real system
make lint               # shellcheck
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for adding commands and making a release.

## License

Apache 2.0, see [LICENSE](LICENSE).
