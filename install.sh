#!/usr/bin/env bash
# cmaal installer
#
#   curl -fsSL https://raw.githubusercontent.com/archlinux-dev/cmaal/main/install.sh | bash
#
# On Arch this builds cmaal as a real pacman package (makepkg -si), so
# pacman tracks every file: `pacman -Qi cmaal`, `pacman -R cmaal`.
#
#   ./install.sh               build + install the pacman package (default)
#   ./install.sh --user        no package, no root: make install to ~/.local
#   ./install.sh --manual      no package: make install to /usr/local
#   ./install.sh --uninstall   remove cmaal, however it was installed
#   ./install.sh --yes         use the default answer for every question

set -euo pipefail

REPO="${CMAAL_REPO:-archlinux-dev/cmaal}"
BRANCH="${CMAAL_BRANCH:-main}"
RAW="https://raw.githubusercontent.com/${REPO}/${BRANCH}"
TARBALL="https://github.com/${REPO}/archive/refs/heads/${BRANCH}.tar.gz"

# Only the test suite sets this, to keep its fake old installs in a sandbox
SYSROOT="${CMAAL_TEST_SYSROOT:-}"

MODE="package"
ACTION="install"
YES=""

for arg in "$@"; do
    case $arg in
        --user) MODE="user" ;;
        --manual|--system) MODE="manual" ;;
        --package) MODE="package" ;;
        --uninstall|--remove) ACTION="uninstall" ;;
        -y|--yes|--noconfirm) YES=1 ;;
        -h|--help)
            sed -n '2,15p' "$0" 2>/dev/null | sed 's/^# \{0,1\}//'
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
    else die "need sudo or doas for this (or use --user)"
    fi
}

# rm that uses root only when needed
rm_any() {
    local f
    for f in "$@"; do
        [[ -e $f || -L $f ]] || continue
        if [[ -w $(dirname "$f") ]]; then rm -rf -- "$f"; else as_root rm -rf -- "$f"; fi
    done
}

owned_by_pacman() { have pacman && pacman -Qqo -- "$1" >/dev/null 2>&1; }

# Files from installs that are not the package: the old single-file
# versions (0.1, 0.2) and `make install` copies in /usr/local or ~/.local.
# They would shadow /usr/bin/cmaal (both come first in PATH).
non_package_files() {
    local p f
    for p in "$SYSROOT/usr/local" "$HOME/.local"; do
        for f in "$p/bin/cmaal" "$p/lib/cmaal" "$p/share/cmaal" "$p/share/doc/cmaal" \
                 "$p/share/licenses/cmaal" "$p/share/man/man1/cmaal.1" \
                 "$p/share/bash-completion/completions/cmaal" "$p/share/zsh/site-functions/_cmaal" \
                 "$p/share/fish/vendor_completions.d/cmaal.fish"; do
            [[ -e $f ]] && printf '%s\n' "$f"
        done
    done
    # 0.1/0.2 system installs put completions straight into /usr/share
    for f in "$SYSROOT"/usr/share/bash-completion/completions/cmaal "$SYSROOT"/usr/share/zsh/site-functions/_cmaal \
             "$SYSROOT"/usr/share/fish/vendor_completions.d/cmaal.fish "$HOME/.config/fish/completions/cmaal.fish"; do
        [[ -e $f ]] && ! owned_by_pacman "$f" && printf '%s\n' "$f"
    done
    return 0
}

remove_non_package_files() {
    local -a old=()
    mapfile -t old < <(non_package_files)
    (( ${#old[@]} )) || return 0
    msg "Removing the old non-package install:"
    printf '      %s\n' "${old[@]}"
    rm_any "${old[@]}"
}

# ---------------------------------------------------------------------------
if [[ $ACTION == uninstall ]]; then
    if have pacman && pacman -Qq cmaal >/dev/null 2>&1; then
        msg "Removing the cmaal package"
        as_root pacman -Rns cmaal
    fi
    remove_non_package_files
    if ask "Also remove your config and cache (~/.config/cmaal, ~/.cache/cmaal)?" n; then
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

if [[ $MODE == package ]] && ! have makepkg; then
    warn "makepkg not found (not Arch, or base-devel missing), installing without a package"
    MODE="manual"
fi
if [[ $MODE == package ]] && (( EUID == 0 )); then
    die "run the installer as your normal user (makepkg refuses to build as root). It asks for sudo when needed."
fi

# Are we inside a clone of the repo?
SRC_DIR=""
self=${BASH_SOURCE[0]:-}
if [[ -n $self && -f $self ]]; then
    here=$(cd "$(dirname "$self")" && pwd)
    [[ -f $here/lib/core.sh && -f $here/packaging/PKGBUILD ]] && SRC_DIR=$here
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

install_package() {
    msg "Building the cmaal package"
    if [[ -n $SRC_DIR ]]; then
        cp "$SRC_DIR/packaging/PKGBUILD" "$TMP/PKGBUILD"
        export CMAAL_SOURCE="git+file://$SRC_DIR"
        CMAAL_BRANCH=$(git -C "$SRC_DIR" rev-parse --abbrev-ref HEAD)
        if [[ $CMAAL_BRANCH == HEAD ]]; then
            # detached checkout (a tag, a CI run): build exactly this commit
            CMAAL_GITREF="commit=$(git -C "$SRC_DIR" rev-parse HEAD)"
            export CMAAL_GITREF
            msg "  from your local checkout (commit ${CMAAL_GITREF#commit=}, committed changes only)"
        else
            export CMAAL_BRANCH
            msg "  from your local checkout ($CMAAL_BRANCH, committed changes only)"
        fi
    else
        have curl || die "curl is required"
        curl -fsSL --max-time 30 "$RAW/packaging/PKGBUILD" -o "$TMP/PKGBUILD" || die "could not download the PKGBUILD"
        export CMAAL_BRANCH="$BRANCH" CMAAL_REPO="$REPO"
        msg "  from github.com/$REPO ($BRANCH)"
    fi
    local -a flags=(-s --clean --force) yes=()
    [[ -n $YES ]] && yes=(--noconfirm)

    # build first, so a failed build leaves the old install alone
    mkdir -p "$TMP/out"
    (cd "$TMP" && PKGDEST="$TMP/out" makepkg "${flags[@]}" "${yes[@]}") || die "makepkg failed, nothing was changed"
    local -a built=("$TMP"/out/cmaal-*.pkg.tar.*)
    [[ -f ${built[0]} ]] || die "makepkg did not produce a package"

    # old copies would shadow /usr/bin/cmaal, and old completions would
    # make pacman refuse to install ("exists in filesystem")
    remove_non_package_files

    msg "Installing ${built[0]##*/}"
    as_root pacman -U "${yes[@]}" -- "${built[0]}" || die "pacman could not install the package"
    BIN=/usr/bin/cmaal
}

install_manual() {
    local prefix=$1
    have make || die "make is required (sudo pacman -S make)"
    local src=$SRC_DIR
    if [[ -z $src ]]; then
        have curl || die "curl is required"
        msg "Downloading cmaal from github.com/$REPO ($BRANCH)"
        curl -fsSL --max-time 60 "$TARBALL" | tar -xz -C "$TMP" || die "download failed"
        src=$(find "$TMP" -mindepth 1 -maxdepth 1 -type d | head -n1)
    fi
    bash -n "$src/bin/cmaal" || die "cmaal failed a syntax check, not installing"
    msg "Installing to $prefix"
    if [[ -w $prefix || ( ! -e $prefix && -w $(dirname "$prefix") ) ]] || [[ $prefix == "$HOME"* ]]; then
        make -s -C "$src" install PREFIX="$prefix"
    else
        as_root make -s -C "$src" install PREFIX="$prefix"
    fi
    BIN="$prefix/bin/cmaal"
}

case $MODE in
    package) install_package ;;
    manual)  install_manual /usr/local ;;
    user)    install_manual "$HOME/.local" ;;
esac

[[ -x $BIN ]] || die "install finished but $BIN is missing"
VERSION=$("$BIN" --version 2>/dev/null | head -n1)
ok "installed $VERSION"

# ~/.local/bin is not always on PATH
if [[ $MODE == user && ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    warn "$HOME/.local/bin is not in your PATH"
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
        msg "  fzf = pickers for packages, services, versions and ssh hosts"
        msg "  reflector = 'cmaal mirrors', pacman-contrib = 'cmaal updates' and cache cleaning"
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
ok "${B}cmaal is ready.${R} Try: ${B}cmaal --help${R}  or  ${B}man cmaal${R}"
[[ $MODE == package ]] && msg "It's a real package now: pacman -Qi cmaal"
[[ ${TERM:-} == xterm-kitty ]] && msg "kitty detected: 'cmaal ssh' will use 'kitten ssh' automatically"
msg "If 'cmaal' isn't found right away, open a new terminal or run: hash -r"
