#!/usr/bin/env bash
# cmaal installer
#
#   curl -fsSL https://raw.githubusercontent.com/archlinux-dev/cmaal/main/install.sh | bash
#
# or from a clone:
#
#   ./install.sh            install system wide to /usr/local/bin (uses sudo)
#   ./install.sh --user     install to ~/.local/bin (no sudo)
#   ./install.sh --uninstall
#   ./install.sh --yes      don't ask anything, just install

set -euo pipefail

REPO="${CMAAL_REPO:-archlinux-dev/cmaal}"
BRANCH="${CMAAL_BRANCH:-main}"
RAW="https://raw.githubusercontent.com/${REPO}/${BRANCH}"

MODE="system"
ACTION="install"
YES=""

for arg in "$@"; do
    case $arg in
        --user) MODE="user" ;;
        --system) MODE="system" ;;
        --uninstall|--remove) ACTION="uninstall" ;;
        -y|--yes|--noconfirm) YES=1 ;;
        -h|--help)
            sed -n '2,12p' "$0" 2>/dev/null | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "unknown option: $arg" >&2; exit 1 ;;
    esac
done

if [[ -t 1 ]]; then
    B=$'\e[1m' R=$'\e[0m' G=$'\e[32m' Y=$'\e[33m' RED=$'\e[31m' BL=$'\e[34m'
else
    B="" R="" G="" Y="" RED="" BL=""
fi
msg()  { printf '%s::%s %s\n' "$BL$B" "$R" "$*"; }
ok()   { printf '%s ok%s %s\n' "$G$B" "$R" "$*"; }
warn() { printf '%swarn%s %s\n' "$Y$B" "$R" "$*" >&2; }
die()  { printf '%serror%s %s\n' "$RED$B" "$R" "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

has_tty() { { : </dev/tty; } 2>/dev/null; }

# works even when this script is piped into bash
ask() {
    local reply def=${2:-y} hint
    [[ $def == y ]] && hint="[Y/n]" || hint="[y/N]"
    if [[ -n $YES ]] || ! has_tty; then
        [[ $def == y ]]
        return
    fi
    printf '%s::%s %s %s ' "$BL$B" "$R" "$1" "$hint" >/dev/tty
    read -r reply </dev/tty || reply=""
    reply=${reply:-$def}
    [[ $reply =~ ^[Yy] ]]
}

as_root() {
    if (( EUID == 0 )); then "$@"
    elif have sudo; then sudo "$@"
    elif have doas; then doas "$@"
    else die "need sudo or doas to install system wide (or use --user)"
    fi
}

if [[ $MODE == system ]]; then
    BIN_DIR="/usr/local/bin"
    BASH_COMP="/usr/share/bash-completion/completions/cmaal"
    ZSH_COMP="/usr/share/zsh/site-functions/_cmaal"
    FISH_COMP="/usr/share/fish/vendor_completions.d/cmaal.fish"
    put() { as_root install -Dm"$1" "$2" "$3"; }
    del() { as_root rm -f -- "$@"; }
else
    BIN_DIR="$HOME/.local/bin"
    BASH_COMP="${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion/completions/cmaal"
    ZSH_COMP="${XDG_DATA_HOME:-$HOME/.local/share}/zsh/site-functions/_cmaal"
    FISH_COMP="${XDG_CONFIG_HOME:-$HOME/.config}/fish/completions/cmaal.fish"
    put() { install -Dm"$1" "$2" "$3"; }
    del() { rm -f -- "$@"; }
fi
BIN="$BIN_DIR/cmaal"

# ---------------------------------------------------------------------------
if [[ $ACTION == uninstall ]]; then
    msg "Removing cmaal ($MODE install)"
    del "$BIN" "$BASH_COMP" "$ZSH_COMP" "$FISH_COMP"
    if ask "Also remove config and cache (~/.config/cmaal, ~/.cache/cmaal)?" n; then
        rm -rf -- "${XDG_CONFIG_HOME:-$HOME/.config}/cmaal" "${XDG_CACHE_HOME:-$HOME/.cache}/cmaal"
    fi
    ok "cmaal uninstalled"
    exit 0
fi

# ---------------------------------------------------------------------------
printf '%s' "$B"
cat <<'EOF'
                               _
   ___ _ __ ___   __ _  __ _ | |
  / __| '_ ` _ \ / _` |/ _` || |
 | (__| | | | | | (_| | (_| || |
  \___|_| |_| |_|\__,_|\__,_||_|

EOF
printf '%s' "$R"

if ! have pacman; then
    warn "pacman not found. cmaal is made for Arch Linux; package commands will not work here."
    ask "Install anyway?" n || exit 1
fi

# Get the files: from the local clone if we're in one, otherwise from GitHub
SRC_DIR=""
self=${BASH_SOURCE[0]:-}
if [[ -n $self && -f $self ]]; then
    here=$(cd "$(dirname "$self")" && pwd)
    [[ -f $here/cmaal && -d $here/completions ]] && SRC_DIR=$here
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

if [[ -z $SRC_DIR ]]; then
    have curl || die "curl is required (sudo pacman -S curl)"
    msg "Downloading cmaal from github.com/$REPO ($BRANCH)"
    mkdir -p "$TMP/completions"
    for f in cmaal completions/cmaal.bash completions/_cmaal completions/cmaal.fish; do
        curl -fsSL --max-time 30 "$RAW/$f" -o "$TMP/$f" || die "download failed: $f"
    done
    SRC_DIR=$TMP
fi

bash -n "$SRC_DIR/cmaal" || die "cmaal script failed a syntax check, not installing"
VERSION=$(sed -n 's/^CMAAL_VERSION="\(.*\)"/\1/p' "$SRC_DIR/cmaal")

msg "Installing cmaal v$VERSION to $BIN"
put 755 "$SRC_DIR/cmaal" "$BIN"
put 644 "$SRC_DIR/completions/cmaal.bash" "$BASH_COMP"
put 644 "$SRC_DIR/completions/_cmaal" "$ZSH_COMP"
put 644 "$SRC_DIR/completions/cmaal.fish" "$FISH_COMP"
ok "installed binary and bash/zsh/fish completions"

# ~/.local/bin is not always on PATH
if [[ $MODE == user && ":$PATH:" != *":$BIN_DIR:"* ]]; then
    warn "$BIN_DIR is not in your PATH"
    shell_name=$(basename "${SHELL:-bash}")
    case $shell_name in
        zsh)  rc="$HOME/.zshrc";  line="export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
        fish) rc="$HOME/.config/fish/config.fish"; line="fish_add_path \$HOME/.local/bin" ;;
        *)    rc="$HOME/.bashrc"; line="export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
    esac
    if ask "Add it to $rc?" y; then
        mkdir -p "$(dirname "$rc")"
        printf '\n# added by cmaal installer\n%s\n' "$line" >>"$rc"
        ok "updated $rc (open a new terminal to use it)"
    fi
fi

# Default config
CONF="${XDG_CONFIG_HOME:-$HOME/.config}/cmaal/config"
if [[ ! -f $CONF ]]; then
    "$BIN" config reset >/dev/null && ok "wrote default config to $CONF"
fi

# Optional extras
if have pacman; then
    extras=()
    have fzf || extras+=(fzf)
    have reflector || extras+=(reflector)
    have paccache || extras+=(pacman-contrib)
    if (( ${#extras[@]} )); then
        msg "Optional extras make cmaal nicer: ${extras[*]}"
        msg "  fzf = fuzzy host picker for 'cmaal ssh', reflector = 'cmaal mirrors', pacman-contrib = cache cleaning"
        if ask "Install them?" y; then
            as_root pacman -S --needed --noconfirm "${extras[@]}" || warn "could not install extras"
        fi
    fi

    if ! have yay && ! have paru && ! have pikaur; then
        msg "No AUR helper found. cmaal uses one for AUR packages."
        if (( EUID == 0 )); then
            warn "running as root, skipping (run 'cmaal helper install yay' as your user later)"
        elif ask "Install yay now?" y; then
            "$BIN" helper install yay || warn "yay install failed, try later: cmaal helper install yay"
        fi
    fi
fi

printf '\n'
ok "${B}cmaal v$VERSION is ready.${R} Try: ${B}cmaal --help${R}"
[[ ${TERM:-} == xterm-kitty ]] && msg "kitty detected: 'cmaal ssh' will use 'kitten ssh' automatically"
msg "If 'cmaal' isn't found right away, open a new terminal or run: hash -r"
