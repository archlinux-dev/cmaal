# shellcheck shell=bash
# cmaal: your Arch history from the pacman log
# Part of cmaal, sourced by /usr/bin/cmaal. https://github.com/femboyss/cmaal

cmd_stats() {
    local log=$PACMAN_LOG
    [[ -r $log ]] || die "cannot read $log"
    local first last_upgrade now days
    now=$(date +%s)

    # log lines start with [2026-09-25T09:00:00+0200] (older logs: [2019-01-01 10:00])
    first=$(grep -m1 -o '^\[[0-9-]\{10\}' "$log" | tr -d '[')
    last_upgrade=$(grep -E 'starting full system upgrade|Running .pacman -Syu|Running .pacman -Syyu|Running .(yay|paru) -Syu' "$log" \
        | tail -n1 | grep -o '^\[[0-9-]\{10\}' | tr -d '[')

    section "Your Arch"
    if [[ -n $first ]]; then
        days=$(( (now - $(date -d "$first" +%s)) / 86400 ))
        printf '   %-22s %s  %s\n' "$(t 'first log entry')" "$first" "$(tf '(%s days ago)' "$days")"
    fi
    if have pacman; then
        printf '   %-22s %s  %s\n' "$(t 'packages installed')" "$(pacman -Qq 2>/dev/null | wc -l)" \
            "$(tf '(%s by you, %s from the AUR)' "$(pacman -Qqe 2>/dev/null | wc -l)" "$(pacman -Qqm 2>/dev/null | wc -l)")"
    fi
    if [[ -n $last_upgrade ]]; then
        days=$(( (now - $(date -d "$last_upgrade" +%s)) / 86400 ))
        printf '   %-22s %s  %s\n' "$(t 'last full upgrade')" "$last_upgrade" "$(tf '(%s days ago)' "$days")"
        (( days > 14 )) && warn "more than two weeks without upgrading: cmaal -Syu"
    fi
    awk '/\[ALPM\] (installed|upgraded|removed|downgraded) / {
            for (i = 1; i <= NF; i++) if ($i ~ /^(installed|upgraded|removed|downgraded)$/) { c[$i]++; break }
         }
         END { printf "   %-22s %d / %d / %d\n", "installs/upgrades/removals", c["installed"], c["upgraded"] + c["downgraded"], c["removed"] }' "$log"

    section "Changes per month"
    awk '/\[ALPM\] (installed|upgraded|removed|downgraded) / { m[substr($1, 2, 7)]++ }
         END { for (k in m) print k, m[k] }' "$log" | sort | tail -n 12 | awk -v c="$C_CYAN" -v r="$C_RESET" '
        { month[NR] = $1; n[NR] = $2; if ($2 > max) max = $2 }
        END {
            for (i = 1; i <= NR; i++) {
                w = max ? int(n[i] * 40 / max) : 0
                if (w == 0 && n[i] > 0) w = 1
                bar = ""; for (j = 0; j < w; j++) bar = bar "#"
                printf "   %s  %s%-40s%s %d\n", month[i], c, bar, r, n[i]
            }
        }'

    section "Most upgraded packages"
    awk '/\[ALPM\] upgraded / { for (i = 1; i <= NF; i++) if ($i == "upgraded") { u[$(i + 1)]++; break } }
         END { for (p in u) print u[p], p }' "$log" | sort -rn | head -n 10 \
        | awk '{ printf "   %4d  %s\n", $1, $2 }'

    section "Biggest single change"
    awk '/transaction started/ { n = 0; d = substr($1, 2, 10); next }
         /\[ALPM\] (installed|upgraded|removed|downgraded) / { n++ }
         /transaction completed/ { if (n > best) { best = n; bd = d } }
         END { if (best) printf "   %d packages on %s\n", best, bd }' "$log"
}
