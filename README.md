# cmaal

> Pls don't be to mean, its my first project with claude code where i actualy came up with the ideas

A multitool for Arch Linux. One command instead of juggling `pacman`, `yay`, `paru` and `flatpak`, plus SSH shortcuts, system cleanup and self updating.

```
cmaal -S discord visual-studio-code-bin spotify
:: Looking up 3 package(s)...
   pacman   discord
   aur      visual-studio-code-bin
   flatpak  com.spotify.Client
```

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/archlinux-dev/cmaal/main/install.sh | bash
```

Or from a clone:

```bash
git clone https://github.com/archlinux-dev/cmaal.git
cd cmaal
./install.sh           # system wide, /usr/local/bin (asks for sudo)
./install.sh --user    # just for you, ~/.local/bin (no sudo)
```

The installer also sets up bash, zsh and fish completions, writes a default config, and offers to install the optional extras (`fzf`, `reflector`, `pacman-contrib`) and an AUR helper (`yay`) if you don't have one.

Uninstall with `cmaal uninstall` or `./install.sh --uninstall`.

## Packages

cmaal looks in the official repos first, then the AUR, then flatpak, and installs each package from wherever it finds it.

| Command | What it does |
| --- | --- |
| `cmaal -S <pkg>...` | install from repos, AUR or flatpak |
| `cmaal -S` | browse every package (repos, AUR, flatpak) in fzf with a live preview, TAB to pick several |
| `cmaal -Ss <query>` | search repos, AUR and flatpak at once |
| `cmaal -Si <pkg>` | package info from any source |
| `cmaal -Syu` | upgrade everything: repos + AUR + flatpak |
| `cmaal -Syyu` | same, with a forced database refresh |
| `cmaal -Rns`, `-Q`, `-Qi`, ... | any other pacman flag is passed straight through |
| `cmaal -Rns` | no package name: pick what to remove in fzf |
| `cmaal undo` | revert the last install / upgrade / removal |
| `cmaal downgrade <pkg>` | pick an older version from your cache or the Arch Linux Archive |
| `cmaal pkglist export [file]` | save every package you installed (repo, AUR, flatpak) to a file |
| `cmaal pkglist import [file]` | install everything from that file, e.g. on a fresh Arch install |
| `cmaal install / search / remove / upgrade` | word versions of the above |

Before `-Syu`, cmaal shows any Arch news posted since your last upgrade and asks before continuing (news posts often contain manual steps). After upgrading it tells you about `.pacnew` files and whether a reboot is needed for a new kernel.

If you use **snapper** (btrfs) or **timeshift**, cmaal takes a snapshot before every `-Syu`, so a broken upgrade can be rolled back completely. It skips this if `snap-pac` or `timeshift-autosnap` already do it.

Add `--noconfirm` to skip all questions (cmaal then picks the default answer, like pacman).

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

Hosts are stored in your normal `~/.ssh/config`, so plain `ssh` sees them too.

**kitty:** when you run cmaal inside kitty, it connects with `kitten ssh`, which copies kitty's terminfo to the server. No more `unknown terminal type xterm-kitty` errors or broken backspace on remote machines.

New tabs (`-t`, or `SSH_NEW_TAB="yes"` in the config) need this line in `~/.config/kitty/kitty.conf`, then restart kitty:

```
allow_remote_control yes
```

## System

| Command | What it does |
| --- | --- |
| `cmaal clean` | remove orphans, trim package cache, AUR build cache, flatpak runtimes, journal |
| `cmaal mirrors [country]` | find the fastest mirrors with reflector (backs up the old list) |
| `cmaal news [n]` | latest Arch Linux news |
| `cmaal history [n]` | recent installs, upgrades and removals |
| `cmaal owns <cmd>` | which package a command or file belongs to |
| `cmaal big [n]` | largest installed packages |
| `cmaal fix` | fix common pacman problems: leftover lock file, keyring / signature errors, dead mirrors, broken database |
| `cmaal snapshot [list/create/restore]` | snapper or timeshift snapshots |
| `cmaal services [--user]` | pick a systemd service, then start / stop / restart / enable / disable / logs |
| `cmaal services <name> <action>` | same without the menu, e.g. `cmaal services bluetooth restart` |
| `cmaal logs` | errors since boot (`prev` = last boot, `-f` = follow, or a service name) |
| `cmaal ports` | which programs are listening on which ports |
| `cmaal ip` | local and public IP addresses |
| `cmaal sys` | system overview |
| `cmaal fetch` | system info next to the Arch logo |
| `cmaal doctor` | check tools and system health |
| `cmaal helper install yay` | install an AUR helper (yay or paru) |

## Fun

| Command | What it does |
| --- | --- |
| `cmaal theme` | pick a kitty color theme (live preview) |
| `cmaal theme <name>` | switch straight to a theme, e.g. `cmaal theme Catppuccin-Mocha` |
| `cmaal weather [city]` | 3 day forecast from wttr.in |

## Updating cmaal

cmaal checks GitHub for a new version once a day, in the background, so it never slows anything down. By default it just tells you:

```
:: cmaal v0.2.0 is available (you have v0.1.0). Run: cmaal self-update
```

Set `AUTO_UPDATE="auto"` in the config to have it update itself, or `"off"` to disable the check. `cmaal --version` shows your version.

## Config

`cmaal config` opens `~/.config/cmaal/config`:

```bash
AUTO_UPDATE="notify"          # auto | notify | off
UPDATE_INTERVAL_HOURS=24
AUR_HELPER="auto"             # auto | yay | paru | pikaur | none
HELPER_ORDER="yay paru pikaur"
USE_FLATPAK="yes"
SHOW_NEWS_ON_UPGRADE="yes"
SSH_USE_KITTEN="auto"         # auto | yes | no
SSH_NEW_TAB="no"              # yes = cmaal ssh opens a new kitty tab
SNAPSHOT_BEFORE_UPGRADE="auto" # auto | yes | no
WEATHER_CITY=""               # empty = detect from your IP
```

## Notes

- With `./install.sh --user`, zsh only picks up the completion if `~/.local/share/zsh/site-functions` is in your `fpath`. The system wide install doesn't need this.
- Releasing a new version: bump `CMAAL_VERSION` in `cmaal` and the `VERSION` file (CI checks they match), then push to `main`.

## License

Apache 2.0, see [LICENSE](LICENSE).
