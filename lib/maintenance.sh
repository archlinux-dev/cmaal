# shellcheck shell=bash
# cmaal: clean, mirrors, history, owns, big, fix
# Part of cmaal, sourced by /usr/bin/cmaal. https://github.com/archlinux-dev/cmaal

# ---------------------------------------------------------------------------
# Maintenance: clean, mirrors, history, owns, big
# ---------------------------------------------------------------------------
cmd_clean() {
    need_arch
    local -a orphans=()
    mapfile -t orphans < <(pacman -Qdtq 2>/dev/null)

    section "Orphaned packages"
    if (( ${#orphans[@]} )); then
        printf '   %s\n' "${orphans[*]}"
        ask "Remove ${#orphans[@]} orphan(s)?" y && as_root pacman -Rns -- "${orphans[@]}"
    else
        ok "no orphans"
    fi

    section "Package cache"
    if have paccache; then
        as_root paccache -rk2
        as_root paccache -ruk0
    else
        warn "paccache not found (pacman-contrib). Falling back to pacman -Sc"
        ask "Run pacman -Sc?" y && as_root pacman -Sc
    fi

    local d
    for d in "$HOME/.cache/yay" "$HOME/.cache/paru/clone" "$HOME/.cache/pikaur"; do
        [[ -d $d ]] || continue
        section "AUR build cache: $d ($(du -sh "$d" 2>/dev/null | cut -f1))"
        ask "Delete it?" n && rm -rf -- "$d"
    done

    if use_flatpak; then
        section "Unused flatpak runtimes"
        flatpak uninstall --unused -y
    fi

    if have journalctl; then
        section "systemd journal ($(journalctl --disk-usage 2>/dev/null | grep -o '[0-9.]*[KMGT]\?B' | head -n1))"
        ask "Shrink journal to the last 2 weeks?" y && as_root journalctl --vacuum-time=2weeks
    fi
    ok "clean done"
}

cmd_mirrors() {
    need_arch
    if ! have reflector; then
        ask "reflector is not installed. Install it?" y || return 1
        as_root pacman -S --needed reflector || return 1
    fi
    local -a args=(--latest 20 --protocol https --sort rate --save "$MIRRORLIST")
    [[ -n ${1:-} ]] && args+=(--country "$1")
    msg "Backing up mirrorlist to $MIRRORLIST.bak"
    as_root cp "$MIRRORLIST" "$MIRRORLIST.bak"
    msg "Ranking mirrors${1:+ in $1} (this takes a moment)"
    as_root reflector "${args[@]}" && ok "mirrorlist updated" && as_root pacman -Syy
}

cmd_history() {
    local n=${1:-25} log=$PACMAN_LOG
    [[ -r $log ]] || die "cannot read $log"
    grep -E '\[ALPM\] (installed|upgraded|removed|downgraded)' "$log" | tail -n "$n" \
        | sed -E "s/^\[([^]]*)\] \[ALPM\] (installed)/\1 ${C_GREEN}\2${C_RESET}/; \
                  s/^\[([^]]*)\] \[ALPM\] (upgraded|downgraded)/\1 ${C_BLUE}\2${C_RESET}/; \
                  s/^\[([^]]*)\] \[ALPM\] (removed)/\1 ${C_RED}\2${C_RESET}/"
}

cmd_owns() {
    need_arch
    (( $# )) || die "usage: cmaal owns <command|file>"
    local t path
    for t in "$@"; do
        if [[ $t == */* ]]; then path=$t; else path=$(command -v -- "$t") || { warn "$t: not found"; continue; }; fi
        pacman -Qo -- "$path" || true
    done
}

cmd_big() {
    need_arch
    local n=${1:-20}
    LC_ALL=C pacman -Qi | awk -v n="$n" '
        /^Name/ { name = $3 }
        /^Installed Size/ {
            size = $4; unit = $5
            mult = 1
            if (unit == "KiB") mult = 1024
            else if (unit == "MiB") mult = 1024 ^ 2
            else if (unit == "GiB") mult = 1024 ^ 3
            printf "%d\t%s %s\t%s\n", size * mult, size, unit, name
        }' | sort -rn | head -n "$n" | awk -F'\t' '{ printf "   %-12s %s\n", $2, $3 }'
}

# ---------------------------------------------------------------------------
# fix: common pacman problems
# ---------------------------------------------------------------------------
cmd_fix() {
    need_arch
    local lock=$PACMAN_LOCK

    section "Database lock"
    if [[ -e $lock ]]; then
        if pgrep -x 'pacman|yay|paru|pikaur|pamac|packagekitd' >/dev/null 2>&1; then
            warn "a package manager is still running, leaving the lock alone"
        else
            warn "found a leftover lock file (an earlier pacman run was interrupted)"
            ask "Remove $lock?" y && as_root rm -f -- "$lock" && ok "lock removed"
        fi
    else
        ok "no lock file"
    fi

    section "Keyring"
    msg "An outdated keyring causes most 'invalid or corrupted package (PGP signature)' errors"
    if ask "Update archlinux-keyring?" y; then
        as_root pacman -Sy --needed --noconfirm archlinux-keyring && ok "keyring up to date"
    fi
    if ask "Still getting key errors? Fully reset the pacman keyring?" n; then
        as_root rm -rf /etc/pacman.d/gnupg
        as_root pacman-key --init && as_root pacman-key --populate archlinux && ok "keyring reset"
    fi

    section "Mirrors"
    local server url synced=""
    server=$(grep -m1 -E '^[[:space:]]*Server[[:space:]]*=' "$MIRRORLIST" 2>/dev/null | sed -E 's/^[^=]*=[[:space:]]*//')
    if [[ -z $server ]]; then
        warn "no active Server line in $MIRRORLIST"
        ask "Rank mirrors now?" y && cmd_mirrors "" && synced=1
    else
        url=${server//\$repo/core}; url=${url//\$arch/$(uname -m)}
        if curl -fsI --max-time 8 -o /dev/null "$url/core.db" 2>/dev/null; then
            ok "first mirror works: ${server%%/\$repo*}"
        else
            warn "first mirror is not responding: ${server%%/\$repo*}"
            ask "Rank mirrors now?" y && cmd_mirrors "" && synced=1
        fi
    fi

    section "Package database"
    [[ -n $synced ]] || as_root pacman -Syy
    if pacman -Dk >/dev/null 2>&1; then
        ok "database is consistent"
    else
        warn "database problems found:"
        pacman -Dk 2>&1 | sed 's/^/      /' >&2
    fi

    section "Missing files"
    local broken
    broken=$(pacman -Qk 2>/dev/null | grep -v ' 0 missing files' || true)
    if [[ -n $broken ]]; then
        warn "packages with missing files (reinstall them with: cmaal -S <name>):"
        printf '%s\n' "$broken" | sed 's/^/      /' >&2
    else
        ok "no missing files"
    fi

    ok "done. Finish with a full upgrade: cmaal -Syu"
}
