# shellcheck shell=bash
# cmaal: version, self update, what's new, config, uninstall
# Part of cmaal, sourced by /usr/bin/cmaal. https://github.com/archlinux-dev/cmaal

# ---------------------------------------------------------------------------
# How was cmaal installed?
#   package  pacman owns the binary (installed with the PKGBUILD)
#   manual   `make install` somewhere, e.g. ~/.local
#   git      running straight from a git checkout
# ---------------------------------------------------------------------------
install_mode() {
    if [[ -n $CMAAL_ROOT ]]; then
        printf 'git\n'
    elif have pacman && pacman -Qqo -- "$CMAAL_BIN" >/dev/null 2>&1; then
        printf 'package\n'
    else
        printf 'manual\n'
    fi
}

version_gt() {
    [[ $1 != "$2" && $(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n1) == "$1" ]]
}

remote_version() {
    curl -fsSL --max-time "${1:-10}" "$CMAAL_RAW/VERSION" 2>/dev/null | head -n1 | tr -d '[:space:]'
}

# ---------------------------------------------------------------------------
# Self update
# ---------------------------------------------------------------------------
cmd_self_update() {
    local force="" remote mode
    [[ ${1:-} == --force ]] && force=1
    have curl || die "curl is required"
    remote=$(remote_version 10)
    [[ -n $remote ]] || die "could not reach $CMAAL_RAW"
    if [[ -z $force ]] && ! version_gt "$remote" "$CMAAL_VERSION"; then
        ok "cmaal is up to date (v$CMAAL_VERSION)"
        return 0
    fi

    mode=$(install_mode)
    msg "Updating cmaal v$CMAAL_VERSION -> v$remote ($mode install)"
    case $mode in
        package) update_package || die "update failed" ;;
        manual) update_manual || die "update failed" ;;
        git)
            git -C "$CMAAL_ROOT" pull --ff-only || die "git pull failed (local changes?)"
            ;;
    esac

    mkdir -p "$CACHE_DIR" && printf '%s\n' "$remote" >"$CACHE_DIR/remote_version"
    ok "updated to v$remote"
    # the new code is on disk now, let it describe itself
    "$CMAAL_BIN" whatsnew "$remote" 2>/dev/null || true
}

# Build the latest PKGBUILD from GitHub and install it with pacman
update_package() {
    (( EUID != 0 )) || die "run this as your normal user, makepkg refuses to build as root"
    have makepkg || die "makepkg not found (install base-devel)"
    local tmp rc=0
    local -a flags=(-si --clean)
    [[ -n $CMAAL_YES ]] && flags+=(--noconfirm)
    tmp=$(mktemp -d)
    curl -fsSL --max-time 30 "$CMAAL_RAW/packaging/PKGBUILD" -o "$tmp/PKGBUILD" || { rm -rf "$tmp"; die "could not download the PKGBUILD"; }
    ( cd "$tmp" && CMAAL_BRANCH="$CMAAL_BRANCH" CMAAL_REPO="$CMAAL_REPO" makepkg "${flags[@]}" ) || rc=1
    rm -rf "$tmp"
    return "$rc"
}

# Same prefix as before, fresh files from git
update_manual() {
    have git || die "git is required"
    have make || die "make is required"
    local tmp prefix rc=0
    prefix=${CMAAL_PREFIX:-$(dirname "$(dirname "$CMAAL_BIN")")}
    tmp=$(mktemp -d)
    git clone --quiet --depth 1 --branch "$CMAAL_BRANCH" "https://github.com/$CMAAL_REPO.git" "$tmp/cmaal" || { rm -rf "$tmp"; die "git clone failed"; }
    if [[ -w $prefix/bin ]]; then
        make -s -C "$tmp/cmaal" install PREFIX="$prefix" || rc=1
    else
        as_root make -s -C "$tmp/cmaal" install PREFIX="$prefix" || rc=1
    fi
    rm -rf "$tmp"
    return "$rc"
}

# Checks for updates in the background so it never slows a command down.
# The result is picked up on the next run.
auto_update_check() {
    [[ $AUTO_UPDATE == off ]] && return 0
    [[ -t 1 ]] && have curl || return 0
    mkdir -p "$CACHE_DIR" 2>/dev/null || return 0

    local stamp="$CACHE_DIR/last_update_check" now last=0 remote=""
    now=$(date +%s)
    [[ -f $stamp ]] && last=$(<"$stamp")
    [[ $last =~ ^[0-9]+$ ]] || last=0

    if (( now - last >= UPDATE_INTERVAL_HOURS * 3600 )); then
        printf '%s\n' "$now" >"$stamp"
        ( v=$(remote_version 5) && [[ -n $v ]] && printf '%s\n' "$v" >"$CACHE_DIR/remote_version" ) >/dev/null 2>&1 &
        disown 2>/dev/null || true
    fi

    [[ -f $CACHE_DIR/remote_version ]] && remote=$(<"$CACHE_DIR/remote_version")
    [[ -n $remote ]] && version_gt "$remote" "$CMAAL_VERSION" || return 0

    if [[ $AUTO_UPDATE == auto ]]; then
        msg "Auto updating cmaal to v$remote"
        cmd_self_update "" || warn "auto update failed, run: cmaal self-update"
    else
        printf '%s::%s cmaal %sv%s%s is available (you have v%s). Run: %scmaal self-update%s\n' \
            "$C_YELLOW$C_BOLD" "$C_RESET" "$C_GREEN" "$remote" "$C_RESET" "$CMAAL_VERSION" "$C_BOLD" "$C_RESET" >&2
    fi
}

cmd_version() {
    printf 'cmaal v%s (%s install)\n' "$CMAAL_VERSION" "$(install_mode)"
    local remote=""
    [[ -f $CACHE_DIR/remote_version ]] && remote=$(<"$CACHE_DIR/remote_version")
    if [[ -n $remote ]] && version_gt "$remote" "$CMAAL_VERSION"; then
        printf 'update available: v%s (cmaal self-update)\n' "$remote"
    fi
}

# ---------------------------------------------------------------------------
# What's new: the CHANGELOG.md section for a version
# ---------------------------------------------------------------------------
cmd_whatsnew() {
    local want=${1:-$CMAAL_VERSION} file="" f
    # installed: /usr/share/cmaal, git checkout: the repo root
    for f in "$CMAAL_SHARE/CHANGELOG.md" "$CMAAL_DOC/CHANGELOG.md"; do
        [[ -r $f ]] && { file=$f; break; }
    done
    [[ -n $file ]] || die "changelog not found in $CMAAL_SHARE"
    if [[ $want == all ]]; then
        page <"$file"
        return
    fi
    local out
    out=$(awk -v v="$want" '
        /^## / { if (found) exit; found = ($2 == v) }
        found' "$file")
    [[ -n $out ]] || die "no changelog entry for v$want (try: cmaal whatsnew all)"
    section "What's new in cmaal v$want"
    # drop the heading and markdown markup, it's read in a terminal
    sed -e '1d' -e 's/\*\*//g' -e 's/`//g' <<<"$out" | sed -e '/./,$!d' -e 's/^/   /'
}

# ---------------------------------------------------------------------------
# Config / uninstall
# ---------------------------------------------------------------------------
write_default_config() {
    mkdir -p "$CONFIG_DIR"
    cp -- "$CMAAL_SHARE/config.default" "$CONFIG_FILE"
}

cmd_config() {
    case ${1:-edit} in
        path) printf '%s\n' "$CONFIG_FILE" ;;
        show)
            if [[ -f $CONFIG_FILE ]]; then cat "$CONFIG_FILE"; else msg "no config yet, defaults in use"; fi
            ;;
        reset) write_default_config && ok "config reset: $CONFIG_FILE" ;;
        edit)
            [[ -f $CONFIG_FILE ]] || write_default_config
            "${EDITOR:-nano}" "$CONFIG_FILE"
            ;;
        *) die "usage: cmaal config [edit|show|path|reset]" ;;
    esac
}

cmd_uninstall() {
    local mode prefix
    mode=$(install_mode)
    case $mode in
        package)
            ask "Remove the cmaal package (pacman -Rns cmaal)?" n || return 1
            as_root pacman -Rns cmaal || return 1
            ;;
        manual)
            prefix=${CMAAL_PREFIX:-$(dirname "$(dirname "$CMAAL_BIN")")}
            ask "Remove cmaal from $prefix?" n || return 1
            local -a files=(
                "$prefix/bin/cmaal" "$prefix/lib/cmaal" "$prefix/share/cmaal" "$prefix/share/doc/cmaal"
                "$prefix/share/licenses/cmaal" "$prefix/share/man/man1/cmaal.1"
                "$prefix/share/bash-completion/completions/cmaal" "$prefix/share/zsh/site-functions/_cmaal"
                "$prefix/share/fish/vendor_completions.d/cmaal.fish"
            )
            if [[ -w $prefix/bin ]]; then rm -rf -- "${files[@]}"; else as_root rm -rf -- "${files[@]}"; fi
            ;;
        git)
            msg "You're running cmaal from a git checkout ($CMAAL_ROOT)."
            msg "Just delete that folder to remove it."
            return 0
            ;;
    esac
    ask "Also remove your config and cache ($CONFIG_DIR, $CACHE_DIR)?" n && rm -rf -- "$CONFIG_DIR" "$CACHE_DIR"
    ok "cmaal removed. Bye!"
}
