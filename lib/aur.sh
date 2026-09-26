# shellcheck shell=bash
# cmaal: AUR safety: package cards, warnings, PKGBUILD changes, audits
# Part of cmaal, sourced by /usr/bin/cmaal. https://github.com/archlinux-dev/cmaal
#
# Anyone can upload to the AUR. The usual warning signs of a bad or
# abandoned package: no maintainer, flagged out of date, brand new with no
# votes, or a PKGBUILD that suddenly changed what it downloads or runs.
# cmaal shows those before installing and before AUR upgrades.

PKGBUILD_STORE="$CACHE_DIR/pkgbuilds"

# aur_json name... -> raw RPC answer for the packages (one request)
aur_json() {
    local url="https://aur.archlinux.org/rpc/v5/info?" p
    for p in "$@"; do url+="arg%5B%5D=${p//+/%2B}&"; done
    curl -fsSL --max-time 15 "$url" 2>/dev/null
}

# aur_fields <json -> one line per package, fields separated by $US:
# Name Version Votes Popularity Maintainer OutOfDate LastModified FirstSubmitted
# ($US is the ASCII unit separator: unlike a tab, `read` never merges two of
# them, so an empty field like a missing maintainer stays in its column.)
# Uses jq when there, a small parser otherwise.
US=$'\x1f'
aur_fields() {
    if have jq; then
        jq -r '.results[] | [.Name, .Version, (.NumVotes // 0), (.Popularity // 0), (.Maintainer // ""),
               (.OutOfDate // ""), (.LastModified // 0), (.FirstSubmitted // 0)] | map(tostring) | join("\u001f")' 2>/dev/null
        return
    fi
    # no jq: split the results into one object per line, then pick fields
    # (the echo puts back a final newline, or read would drop the last object)
    { tr -d '\n'; echo; } | sed 's/},{/}\n{/g' | while IFS= read -r obj; do
        local f out=""
        for f in Name Version NumVotes Popularity Maintainer OutOfDate LastModified FirstSubmitted; do
            local v
            v=$(grep -o "\"$f\":\(\"[^\"]*\"\|[^,}]*\)" <<<"$obj" | head -n1 | cut -d: -f2- | tr -d '"')
            [[ $v == null ]] && v=""
            out+="${v}${US}"
        done
        [[ -n ${out%%"$US"*} ]] && printf '%s\n' "${out%"$US"}"
    done
}

days_ago() {
    local ts=$1
    if [[ ! $ts =~ ^[0-9]+$ ]] || (( ts == 0 )); then
        printf '?'
        return
    fi
    printf '%s' $(( ($(date +%s) - ts) / 86400 ))
}

# aur_card <tsv line> -> prints a card, returns 1 if there are warnings
aur_card() {
    local name ver votes pop maint ood lastmod first warns=0
    IFS=$US read -r name ver votes pop maint ood lastmod first <<<"$1"
    printf '   %s%s%s %s\n' "$C_BOLD" "$name" "$C_RESET" "$ver"
    printf '      %s: %s   %s: %s   %s: %s\n' "$(t votes)" "${votes:-0}" "$(t popularity)" "${pop:-0}" \
        "$(t maintainer)" "${maint:-$(t none)}"
    printf '      %s\n' "$(tf 'last updated %s days ago' "$(days_ago "$lastmod")")"
    if [[ -z $maint ]]; then
        printf '      %s%s%s\n' "$C_YELLOW" "$(t '! orphaned: nobody maintains this package')" "$C_RESET"
        warns=1
    fi
    if [[ -n $ood ]]; then
        printf '      %s%s%s\n' "$C_YELLOW" "$(tf '! flagged out of date %s days ago' "$(days_ago "$ood")")" "$C_RESET"
        warns=1
    fi
    if [[ $first =~ ^[0-9]+$ ]] && (( first > 0 )) && (( $(days_ago "$first") < 14 )) && (( ${votes:-0} < 5 )); then
        printf '      %s%s%s\n' "$C_RED" "$(t '! brand new with almost no votes: read the PKGBUILD first (cmaal review)')" "$C_RESET"
        warns=1
    fi
    return "$warns"
}

aur_pkgbuild() {
    curl -fsSL --max-time 15 "https://aur.archlinux.org/cgit/aur.git/plain/PKGBUILD?h=${1//+/%2B}" 2>/dev/null
}

# Remember the PKGBUILD you installed, to spot changes next time
aur_remember() {
    local p content
    mkdir -p "$PKGBUILD_STORE"
    for p in "$@"; do
        content=$(aur_pkgbuild "$p") && [[ -n $content ]] && printf '%s\n' "$content" >"$PKGBUILD_STORE/$p.PKGBUILD"
    done
    return 0
}

# aur_changed pkg -> prints a unified diff if the PKGBUILD changed since last time
aur_changed() {
    local p=$1 old="$PKGBUILD_STORE/$1.PKGBUILD" new
    [[ -f $old ]] || return 1
    new=$(aur_pkgbuild "$p") || return 1
    [[ -n $new ]] || return 1
    diff -u --label "$p (installed)" --label "$p (now in the AUR)" "$old" <(printf '%s\n' "$new")
    [[ $? -eq 1 ]]
}

colordiff_lines() {
    sed -e "s/^+[^+].*/${C_GREEN}&${C_RESET}/" -e "s/^-[^-].*/${C_RED}&${C_RESET}/" -e "s/^@@.*/${C_CYAN}&${C_RESET}/"
}

# Called before installing AUR packages. Returns 1 to cancel.
aur_precheck() {
    [[ $AUR_CHECK == yes ]] && have curl || return 0
    (( $# )) || return 0
    local json line warn=0 d
    json=$(aur_json "$@") || return 0
    section "AUR check"
    while IFS= read -r line; do
        [[ -n $line ]] || continue
        aur_card "$line" || warn=1
    done < <(aur_fields <<<"$json")
    for d in "$@"; do
        if aur_changed "$d" >/dev/null; then
            printf '      %s%s%s\n' "$C_YELLOW" "$(tf '! %s: PKGBUILD changed since you last installed it (cmaal review %s)' "$d" "$d")" "$C_RESET"
            warn=1
        fi
    done
    if (( warn )); then
        ask "There are warnings above. Install anyway?" y || return 1
    fi
    return 0
}

# Before -Syu: which AUR updates changed their PKGBUILD?
aur_upgrade_check() {
    [[ $AUR_CHECK == yes && -n $HELPER ]] && have curl || return 0
    local -a pending=() changed=()
    local p
    mapfile -t pending < <("$HELPER" -Qua 2>/dev/null | awk '{ print $1 }')
    (( ${#pending[@]} )) || return 0
    for p in "${pending[@]}"; do
        aur_changed "$p" >/dev/null && changed+=("$p")
    done
    (( ${#changed[@]} )) || return 0
    section "AUR updates with a changed PKGBUILD"
    for p in "${changed[@]}"; do
        printf '   %s  %s(%s)%s\n' "$p" "$C_DIM" "$(tf 'see: cmaal review %s' "$p")" "$C_RESET"
    done
    msg "Changes are normal for new versions. Look for new download URLs or odd commands."
    ask "Continue with the upgrade?" y
}

# cmaal review [pkg]
cmd_review() {
    have curl || die "curl is required"
    local p=${1:-} json line diffout
    if [[ -z $p ]]; then
        aur_audit
        return
    fi
    json=$(aur_json "$p") || die "could not reach the AUR"
    line=$(aur_fields <<<"$json")
    [[ -n $line ]] || die "$p is not in the AUR"
    section "AUR: $p"
    aur_card "$line"
    if diffout=$(aur_changed "$p"); then
        section "What changed since you installed it"
        printf '%s\n' "$diffout" | colordiff_lines | page
    elif [[ -f $PKGBUILD_STORE/$p.PKGBUILD ]]; then
        ok "the PKGBUILD is the same as when you installed it"
    else
        section "PKGBUILD"
        aur_pkgbuild "$p" | page
    fi
    if ask "Mark this PKGBUILD as reviewed?" y; then
        aur_remember "$p" && ok "saved, next time you'll only see new changes"
    fi
}

# cmaal review (no name): check every installed AUR package
aur_audit() {
    need_arch
    local -a foreign=() found=()
    local line name ver votes pop maint ood lastmod first p problems=0
    mapfile -t foreign < <(pacman -Qqm 2>/dev/null)
    (( ${#foreign[@]} )) || { ok "no AUR packages installed"; return 0; }
    msg "$(tf 'Checking %s AUR packages...' "${#foreign[@]}")"
    local json
    json=$(aur_json "${foreign[@]}") || die "could not reach the AUR"
    section "AUR health"
    while IFS= read -r line; do
        [[ -n $line ]] || continue
        IFS=$US read -r name ver votes pop maint ood lastmod first <<<"$line"
        found+=("$name")
        if [[ -z $maint ]]; then
            printf '   %s%-30s%s %s\n' "$C_YELLOW" "$name" "$C_RESET" "$(t 'orphaned (no maintainer)')"
            problems=$((problems + 1))
        fi
        if [[ -n $ood ]]; then
            printf '   %s%-30s%s %s\n' "$C_YELLOW" "$name" "$C_RESET" "$(tf 'flagged out of date %s days ago' "$(days_ago "$ood")")"
            problems=$((problems + 1))
        fi
    done < <(aur_fields <<<"$json")
    for p in "${foreign[@]}"; do
        if ! printf '%s\n' "${found[@]}" | grep -qx -- "$p"; then
            printf '   %s%-30s%s %s\n' "$C_RED" "$p" "$C_RESET" "$(t 'not in the AUR anymore (removed or renamed)')"
            problems=$((problems + 1))
        fi
    done
    if (( problems )); then
        printf '\n'
        msg "Details for one package: cmaal review <name>"
    else
        ok "all AUR packages look healthy"
    fi
}
