# cmaal

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
| `cmaal -Ss <query>` | search repos, AUR and flatpak at once |
| `cmaal -Si <pkg>` | package info from any source |
| `cmaal -Syu` | upgrade everything: repos + AUR + flatpak |
| `cmaal -Syyu` | same, with a forced database refresh |
| `cmaal -Rns`, `-Q`, `-Qi`, ... | any other pacman flag is passed straight through |
| `cmaal install / search / remove / upgrade` | word versions of the above |

Before `-Syu`, cmaal shows any Arch news posted since your last upgrade and asks before continuing (news posts often contain manual steps). After upgrading it tells you about `.pacnew` files and whether a reboot is needed for a new kernel.

Add `--noconfirm` to skip all questions.

## SSH

| Command | What it does |
| --- | --- |
| `cmaal ssh` | pick a saved host and connect (fuzzy search with fzf) |
| `cmaal ssh <host>` | connect |
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

## System

| Command | What it does |
| --- | --- |
| `cmaal clean` | remove orphans, trim package cache, AUR build cache, flatpak runtimes, journal |
| `cmaal mirrors [country]` | find the fastest mirrors with reflector (backs up the old list) |
| `cmaal news [n]` | latest Arch Linux news |
| `cmaal history [n]` | recent installs, upgrades and removals |
| `cmaal owns <cmd>` | which package a command or file belongs to |
| `cmaal big [n]` | largest installed packages |
| `cmaal sys` | system overview |
| `cmaal doctor` | check tools and system health |
| `cmaal helper install yay` | install an AUR helper (yay or paru) |

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
```

## Notes

- With `./install.sh --user`, zsh only picks up the completion if `~/.local/share/zsh/site-functions` is in your `fpath`. The system wide install doesn't need this.
- Releasing a new version: bump `CMAAL_VERSION` in `cmaal` and the `VERSION` file (CI checks they match), then push to `main`.

## License

Apache 2.0, see [LICENSE](LICENSE).
