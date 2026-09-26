# shellcheck shell=bash
# cmaal: questions about packages: updates, why, files, provides, pkgbuild, orphans
# Part of cmaal, sourced by /usr/bin/cmaal. https://github.com/archlinux-dev/cmaal

# ---------------------------------------------------------------------------
# updates: what would -Syu do? (never installs anything)
# ---------------------------------------------------------------------------
cmd_updates() {
    need_arch
    local out total=0 n

    section "Official repos"
    if have checkupdates; then
        # checkupdates syncs into a temp db, so this is current and needs no root
        out=$(checkupdates 2>/dev/null)
    else
        out=$(pacman -Qu 2>/dev/null)
        [[ -n $out ]] || printf '   %s(install pacman-contrib for a fresh check, this uses the last synced db)%s\n' "$C_DIM" "$C_RESET"
    fi
    n=$(grep -c . <<<"$out")
    (( total += n ))
    if (( n )); then printf '%s\n' "$out" | sed 's/^/   /'; else ok "up to date"; fi

    if [[ -n $HELPER ]]; then
        section "AUR ($HELPER)"
        out=$("$HELPER" -Qua 2>/dev/null)
        n=$(grep -c . <<<"$out")
        (( total += n ))
        if (( n )); then printf '%s\n' "$out" | sed 's/^/   /'; else ok "up to date"; fi
    fi

    if use_flatpak; then
        section "Flatpak"
        out=$(flatpak remote-ls --updates --app --columns=application,version 2>/dev/null)
        n=$(grep -c . <<<"$out")
        (( total += n ))
        if (( n )); then printf '%s\n' "$out" | sed 's/^/   /'; else ok "up to date"; fi
    fi

    printf '\n'
    if (( total )); then
        msg "$total update(s) available. Install them with: cmaal -Syu"
    else
        ok "everything is up to date"
    fi
}

# ---------------------------------------------------------------------------
# why: why is this package installed?
# ---------------------------------------------------------------------------
cmd_why() {
    need_arch
    local p info reason required optional
    (( $# )) || die "usage: cmaal why <package>"
    for p in "$@"; do
        info=$(LC_ALL=C pacman -Qi -- "$p" 2>/dev/null) || { warn "$p is not installed"; continue; }
        reason=$(awk -F' : ' '/^Install Reason/ { print $2 }' <<<"$info")
        required=$(awk -F' : ' '/^Required By/ { print $2 }' <<<"$info")
        optional=$(awk -F' : ' '/^Optional For/ { print $2 }' <<<"$info")

        section "$p"
        if [[ $reason == Explicitly* ]]; then
            printf '   You installed it %syourself%s.\n' "$C_GREEN$C_BOLD" "$C_RESET"
        else
            printf '   It was pulled in %sas a dependency%s.\n' "$C_YELLOW$C_BOLD" "$C_RESET"
        fi
        if [[ $required != None ]]; then
            printf '   Needed by:   %s\n' "$required"
        else
            printf '   Needed by:   nothing'
            [[ $reason != Explicitly* ]] && printf '  %s(orphan, cmaal orphans rm can remove it)%s' "$C_DIM" "$C_RESET"
            printf '\n'
        fi
        [[ $optional != None ]] && printf '   Optional for: %s\n' "$optional"
        if have pactree && [[ $required != None ]]; then
            printf '   Chain up to what you installed:\n'
            pactree -r -d 3 -- "$p" 2>/dev/null | sed 's/^/      /'
        fi
    done
}

# ---------------------------------------------------------------------------
# files / provides / owns-for-uninstalled
# ---------------------------------------------------------------------------
cmd_files() {
    need_arch
    local p=${1:-}
    [[ -n $p ]] || die "usage: cmaal files <package>"
    if pacman -Q -- "$p" >/dev/null 2>&1; then
        pacman -Qlq -- "$p" | grep -v '/$' | page
    else
        ensure_files_db || return 1
        pacman -Flq -- "$p" 2>/dev/null | grep -v '/$' | sed 's|^|/|' | page
    fi
}

# pacman -F needs its own database, fetched once with pacman -Fy
ensure_files_db() {
    compgen -G "$PACMAN_SYNC/*.files" >/dev/null && return 0
    msg "The pacman file database hasn't been downloaded yet (about 50 MB, once)."
    ask "Download it now (pacman -Fy)?" y || return 1
    as_root pacman -Fy
}

# "command not found"? find out which package would give it to you
cmd_provides() {
    need_arch
    local q=${1:-} out
    [[ -n $q ]] || die "usage: cmaal provides <command|file>"
    ensure_files_db || return 1
    if [[ $q == */* ]]; then
        out=$(pacman -F -- "${q#/}" 2>/dev/null)
    else
        # a bare name is most likely a command
        out=$(pacman -F -- "usr/bin/$q" 2>/dev/null)
        [[ -n $out ]] || out=$(pacman -F -- "$q" 2>/dev/null)
    fi
    if [[ -z $out ]]; then
        warn "nothing in the official repos provides '$q'. Try: cmaal -Ss $q"
        return 1
    fi
    printf '%s\n' "$out"
    local pkg
    pkg=$(awk 'NR == 1 { sub(/^[^\/]*\//, "", $1); print $1 }' <<<"$out")
    [[ -n $pkg ]] && msg "Install it with: cmaal -S $pkg"
}

# ---------------------------------------------------------------------------
# pkgbuild: read the build script before you install from the AUR
# ---------------------------------------------------------------------------
cmd_pkgbuild() {
    local p=${1:-} out url
    [[ -n $p ]] || die "usage: cmaal pkgbuild <package>"
    have curl || die "curl is required"
    if have pacman && pacman -Si -- "$p" >/dev/null 2>&1; then
        url="https://gitlab.archlinux.org/archlinux/packaging/packages/$p/-/raw/main/PKGBUILD"
    else
        url="https://aur.archlinux.org/cgit/aur.git/plain/PKGBUILD?h=${p//+/%2B}"
    fi
    out=$(curl -fsSL --max-time 15 "$url" 2>/dev/null)
    [[ -n $out && $out != *"<html"* ]] || die "no PKGBUILD found for $p"
    {
        printf '# %s\n# from %s\n\n' "$p" "${url%%\?*}"
        printf '%s\n' "$out"
    } | if have bat; then bat --language=bash --style=plain --paging=auto; else page; fi
}

# ---------------------------------------------------------------------------
# orphans: dependencies nothing needs anymore
# ---------------------------------------------------------------------------
cmd_orphans() {
    need_arch
    local -a orphans=()
    mapfile -t orphans < <(pacman -Qdtq 2>/dev/null)
    if (( ! ${#orphans[@]} )); then
        ok "no orphans"
        return 0
    fi
    section "${#orphans[@]} orphan(s)"
    LC_ALL=C pacman -Qi -- "${orphans[@]}" | awk -F' : ' '
        /^Name/ { n = $2 }
        /^Installed Size/ { printf "   %-30s %s\n", n, $2 }'
    case ${1:-} in
        rm|remove|clean)
            ask "Remove them?" y && as_root pacman -Rns -- "${orphans[@]}" ;;
        *) printf '\n'; msg "Remove them with: cmaal orphans rm" ;;
    esac
}
