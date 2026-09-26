# shellcheck shell=bash
# cmaal: shared helpers: config, output, prompts, root, AUR helper detection
# Part of cmaal, sourced by /usr/bin/cmaal. https://github.com/archlinux-dev/cmaal

# ---------------------------------------------------------------------------
# Defaults (override them in ~/.config/cmaal/config, see `cmaal config`)
# ---------------------------------------------------------------------------
AUTO_UPDATE="notify"          # auto | notify | off
UPDATE_INTERVAL_HOURS=24      # how often to look for a new cmaal version
AUR_HELPER="auto"             # auto | yay | paru | pikaur | none
HELPER_ORDER="yay paru pikaur"
USE_FLATPAK="yes"             # also search/install/upgrade flatpaks
SHOW_NEWS_ON_UPGRADE="yes"    # show unread Arch news before -Syu
SSH_USE_KITTEN="auto"         # auto | yes | no  (use `kitten ssh` inside kitty)
SSH_NEW_TAB="no"              # yes: `cmaal ssh` opens hosts in a new kitty tab
SNAPSHOT_BEFORE_UPGRADE="auto" # auto | yes | no  (snapper/timeshift before -Syu)
WEATHER_CITY=""               # default city for `cmaal weather`, empty = auto
NOTIFY_AFTER_SECONDS=60       # desktop notification when an upgrade takes longer (0 = off)

# shellcheck source=/dev/null
[[ -f $CONFIG_FILE ]] && source "$CONFIG_FILE"

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
if [[ -t 1 && -z ${NO_COLOR:-} ]]; then
    C_RESET=$'\e[0m' C_BOLD=$'\e[1m' C_DIM=$'\e[2m'
    C_RED=$'\e[31m' C_GREEN=$'\e[32m' C_YELLOW=$'\e[33m'
    C_BLUE=$'\e[34m' C_MAGENTA=$'\e[35m' C_CYAN=$'\e[36m'
else
    C_RESET="" C_BOLD="" C_DIM="" C_RED="" C_GREEN="" C_YELLOW=""
    C_BLUE="" C_MAGENTA="" C_CYAN=""
fi

msg()     { printf '%s::%s %s\n' "$C_BLUE$C_BOLD" "$C_RESET" "$*"; }
ok()      { printf '%s ok%s %s\n' "$C_GREEN$C_BOLD" "$C_RESET" "$*"; }
warn()    { printf '%swarn%s %s\n' "$C_YELLOW$C_BOLD" "$C_RESET" "$*" >&2; }
die()     { printf '%serror%s %s\n' "$C_RED$C_BOLD" "$C_RESET" "$*" >&2; exit 1; }
section() { printf '\n%s==> %s%s\n' "$C_MAGENTA$C_BOLD" "$*" "$C_RESET"; }
have()    { command -v "$1" >/dev/null 2>&1; }

CMAAL_YES="${CMAAL_YES:-}"

# true when we can actually talk to a terminal (not piped, not in cron)
has_tty() { { : </dev/tty; } 2>/dev/null; }

# ask "question" [y|n]  -> returns 0 for yes
ask() {
    local question=$1 def=${2:-y} hint reply
    [[ $def == y ]] && hint="[Y/n]" || hint="[y/N]"
    # CMAAL_ASSUME_YES=1 answers yes to everything (scripts, tests)
    [[ -n ${CMAAL_ASSUME_YES:-} ]] && return 0
    # --noconfirm takes the default answer, like pacman does
    if [[ -n $CMAAL_YES ]] || ! has_tty; then
        [[ $def == y ]]
        return
    fi
    printf '%s::%s %s %s ' "$C_BLUE$C_BOLD" "$C_RESET" "$question" "$hint" >/dev/tty
    read -r reply </dev/tty || reply=""
    reply=${reply:-$def}
    [[ $reply =~ ^[Yy] ]]
}

# prompt "question" [default] -> prints the answer
prompt() {
    local question=$1 def=${2:-} reply
    if [[ -n $CMAAL_YES ]] || ! has_tty; then
        printf '%s\n' "$def"
        return
    fi
    if [[ -n $def ]]; then
        printf '%s::%s %s [%s]: ' "$C_BLUE$C_BOLD" "$C_RESET" "$question" "$def" >/dev/tty
    else
        printf '%s::%s %s: ' "$C_BLUE$C_BOLD" "$C_RESET" "$question" >/dev/tty
    fi
    read -r reply </dev/tty || reply=""
    printf '%s\n' "${reply:-$def}"
}

as_root() {
    if (( EUID == 0 )); then
        "$@"
    elif have sudo; then
        sudo "$@"
    elif have doas; then
        doas "$@"
    else
        die "need root for: $*  (install sudo or doas)"
    fi
}

need_arch() {
    have pacman || die "pacman not found. cmaal package commands only work on Arch based systems."
}

# ---------------------------------------------------------------------------
# AUR helper detection
# ---------------------------------------------------------------------------
detect_helper() {
    local h
    case $AUR_HELPER in
        none) return 1 ;;
        auto)
            for h in $HELPER_ORDER; do
                have "$h" && { printf '%s\n' "$h"; return 0; }
            done
            return 1
            ;;
        *)
            have "$AUR_HELPER" && { printf '%s\n' "$AUR_HELPER"; return 0; }
            return 1
            ;;
    esac
}
HELPER=$(detect_helper) || HELPER=""

use_flatpak() { [[ $USE_FLATPAK == yes ]] && have flatpak; }

# Build an AUR helper from source. AUR helpers refuse to run as root.
cmd_helper() {
    local sub=${1:-status}
    case $sub in
        status|"")
            if [[ -n $HELPER ]]; then
                ok "using AUR helper: $HELPER ($("$HELPER" --version 2>/dev/null | head -n1))"
            else
                warn "no AUR helper found. Install one with: cmaal helper install [yay|paru]"
            fi
            ;;
        install)
            local name=${2:-yay} tmp
            [[ $name == yay || $name == paru ]] || die "supported helpers: yay, paru"
            (( EUID != 0 )) || die "do not run this as root, makepkg refuses to build as root"
            need_arch
            have "$name" && { ok "$name is already installed"; return 0; }
            msg "Installing build dependencies (git, base-devel)"
            as_root pacman -S --needed --noconfirm git base-devel || die "could not install git/base-devel"
            tmp=$(mktemp -d)
            msg "Building $name-bin from the AUR"
            git clone --depth 1 "https://aur.archlinux.org/${name}-bin.git" "$tmp/$name" || die "git clone failed"
            (cd "$tmp/$name" && makepkg -si --noconfirm) || { rm -rf "$tmp"; die "makepkg failed"; }
            rm -rf "$tmp"
            HELPER=$name
            ok "$name installed"
            ;;
        *) die "usage: cmaal helper [status|install yay|install paru]" ;;
    esac
}

# ---------------------------------------------------------------------------
# Small shared helpers
# ---------------------------------------------------------------------------
need_fzf() {
    have fzf && return 0
    have pacman || return 1
    ask "This needs fzf. Install it now?" y && as_root pacman -S --needed fzf && have fzf
}

# true if any argument is not a flag
has_targets() {
    local a
    for a in "$@"; do [[ $a != -* ]] && return 0; done
    return 1
}

# Show long output in a pager when we're in a terminal
page() {
    if [[ -t 1 ]] && have less; then
        less -FRX
    else
        cat
    fi
}

# Desktop notification, if there is a desktop to notify
notify() {
    [[ -n ${DISPLAY:-}${WAYLAND_DISPLAY:-} ]] && have notify-send || return 0
    notify-send --app-name=cmaal "cmaal" "$*" 2>/dev/null || true
}
