# shellcheck shell=bash
# cmaal: hold packages at their current version (pacman IgnorePkg)
# Part of cmaal, sourced by /usr/bin/cmaal. https://github.com/archlinux-dev/cmaal

current_holds() {
    if have pacman-conf; then
        pacman-conf --config "$PACMAN_CONF" IgnorePkg 2>/dev/null
    else
        awk '/^\[options\]/ { o = 1; next } /^\[/ { o = 0 }
             o && /^[[:space:]]*IgnorePkg[[:space:]]*=/ { sub(/^[^=]*=/, ""); for (i = 1; i <= NF; i++) print $i }' "$PACMAN_CONF"
    fi
}

# write_holds pkg... : rewrites the IgnorePkg line in [options]
write_holds() {
    local line="" tmp
    (( $# )) && line="IgnorePkg = $*"
    tmp=$(mktemp)
    awk -v line="$line" '
        /^\[options\]/ { print; if (line != "") print line; inopt = 1; next }
        /^\[/ { inopt = 0 }
        inopt && /^[[:space:]]*IgnorePkg[[:space:]]*=/ { next }
        { print }' "$PACMAN_CONF" >"$tmp"

    # let pacman itself confirm the new file is valid before we swap it in
    if have pacman-conf && ! pacman-conf --config "$tmp" >/dev/null 2>&1; then
        rm -f "$tmp"
        die "the edited pacman.conf did not validate, nothing was changed"
    fi
    grep -q '^\[options\]' "$tmp" || { rm -f "$tmp"; die "no [options] section in $PACMAN_CONF"; }

    as_root cp -- "$PACMAN_CONF" "$PACMAN_CONF.cmaal.bak"
    as_root install -m 644 -- "$tmp" "$PACMAN_CONF"
    rm -f "$tmp"
}

cmd_hold() {
    [[ -r $PACMAN_CONF ]] || die "cannot read $PACMAN_CONF"
    (( $# )) || { cmd_holds; return; }
    local -a holds=() p
    mapfile -t holds < <(current_holds)
    for p in "$@"; do
        if printf '%s\n' "${holds[@]}" | grep -qx -- "$p"; then
            msg "$p is already held"
        else
            holds+=("$p")
        fi
    done
    write_holds "${holds[@]}"
    ok "held: $* (pacman -Syu will skip them). Undo with: cmaal unhold $*"
}

cmd_unhold() {
    [[ -r $PACMAN_CONF ]] || die "cannot read $PACMAN_CONF"
    (( $# )) || die "usage: cmaal unhold <package>..."
    local -a holds=() keep=()
    local h p drop
    mapfile -t holds < <(current_holds)
    for h in "${holds[@]}"; do
        drop=""
        for p in "$@"; do [[ $h == "$p" ]] && drop=1; done
        [[ -n $drop ]] || keep+=("$h")
    done
    if (( ${#keep[@]} == ${#holds[@]} )); then
        warn "none of these are held: $*"
        return 1
    fi
    write_holds "${keep[@]}"
    ok "released: $*. They will upgrade with the next cmaal -Syu"
}

cmd_holds() {
    local -a holds=()
    mapfile -t holds < <(current_holds)
    if (( ! ${#holds[@]} )); then
        ok "no packages are held"
        return 0
    fi
    section "Held packages (skipped by -Syu)"
    local p v
    for p in "${holds[@]}"; do
        v=$(pacman -Q -- "$p" 2>/dev/null | awk '{ print $2 }')
        printf '   %-30s %s\n' "$p" "${v:-(not installed)}"
    done
}
