# shellcheck shell=bash
# cmaal: help text
# Part of cmaal, sourced by /usr/bin/cmaal. https://github.com/archlinux-dev/cmaal

help_text() {
    cat <<EOF
${C_BOLD}cmaal${C_RESET} v$CMAAL_VERSION  a multitool for Arch Linux

${C_BOLD}PACKAGES${C_RESET}  (checks pacman, then the AUR, then flatpak)
  cmaal -S <pkg>...          install from wherever the package exists
  cmaal -S                   browse ALL packages with fzf (TAB to pick several)
  cmaal -Ss <query>          search repos, AUR and flatpak at once
  cmaal -Si <pkg>            package info from any source
  cmaal -Syu                 upgrade everything (repos, AUR, flatpak)
  cmaal -Syyu                same, but force refresh of package databases
  cmaal -Rns [pkg]           remove (no name: pick with fzf)
  cmaal -Q..., -R..., ...    any other pacman flag is passed through
  cmaal updates              list pending updates without installing
  cmaal why <pkg>            why is this installed, what needs it
  cmaal files <pkg>          files a package installs
  cmaal provides <cmd>       which package gives you a missing command
  cmaal owns <cmd|file>      which installed package a command belongs to
  cmaal pkgbuild <pkg>       read a package's build script (check AUR packages!)
  cmaal orphans [rm]         unused dependencies, and remove them
  cmaal big [n]              largest installed packages
  cmaal helper [install yay|paru]   show or install an AUR helper

${C_BOLD}ROLLBACK${C_RESET}
  cmaal undo                 revert the last install/upgrade/remove
  cmaal downgrade <pkg>      go back to an older version (cache or Arch archive)
  cmaal hold <pkg>...        keep packages at their current version
  cmaal unhold <pkg>...      let them upgrade again
  cmaal holds                list held packages
  cmaal snapshot [list|create|restore]   snapper/timeshift snapshots
  cmaal pkglist export|import [file]     save / restore all your packages
  cmaal history [n]          recent installs, upgrades and removals

${C_BOLD}SYSTEM${C_RESET}
  cmaal clean                remove orphans, trim caches and journal
  cmaal fix                  fix pacman: stale lock, keyring, dead mirrors
  cmaal mirrors [country]    rank the fastest mirrors with reflector
  cmaal news [n]             latest Arch Linux news
  cmaal services [--user] [name] [action]   manage systemd services
  cmaal logs [unit|prev|-f]  errors from the system journal
  cmaal kernel               running vs installed kernels, reboot needed?
  cmaal disk                 disk usage and what you can clean up
  cmaal ports                what is listening on which port
  cmaal ip                   local and public IP addresses
  cmaal sys                  system overview
  cmaal doctor               check tools and system health

${C_BOLD}SSH${C_RESET}
  cmaal ssh                  pick a saved host and connect (fzf if installed)
  cmaal ssh <host> [args]    connect (uses kitten ssh inside kitty)
  cmaal ssh -t [host]        connect in a new kitty tab
  cmaal ssh ls               list saved hosts
  cmaal ssh add [alias] [user@host[:port]] [keyfile]
  cmaal ssh rm <alias>       remove a saved host
  cmaal ssh keygen [name]    create an ed25519 key
  cmaal ssh keys             list your public keys
  cmaal ssh copy <host>      copy your key to a server (ssh-copy-id)
  cmaal ssh test <host>      check that key login works
  cmaal ssh server on|off|status   manage the local sshd
  cmaal ssh edit             open ~/.ssh/config

${C_BOLD}FUN${C_RESET}
  cmaal fetch                system info with the Arch logo
  cmaal theme [name]         change kitty's color theme
  cmaal weather [city]       weather forecast

${C_BOLD}CMAAL${C_RESET}
  cmaal self-update [--force]   update cmaal
  cmaal whatsnew [version|all]  what changed in this version
  cmaal config [edit|show|path|reset]
  cmaal uninstall
  cmaal help [word]          this help, or only the lines matching a word
  cmaal -V, --version

Add ${C_BOLD}--noconfirm${C_RESET} to skip questions (the default answer is used).
Full manual: ${C_BOLD}man cmaal${C_RESET}
EOF
}

usage() {
    if [[ -n ${1:-} ]]; then
        local out
        out=$(help_text | grep -i -- "$1")
        if [[ -n $out ]]; then
            printf '%s\n' "$out"
        else
            warn "nothing in the help matches '$1'"
            return 1
        fi
    else
        help_text
    fi
}

usage_ssh() {
    usage ssh
}
