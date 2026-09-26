# shellcheck shell=bash
# cmaal: kitty theme, weather, fetch
# Part of cmaal, sourced by /usr/bin/cmaal. https://github.com/archlinux-dev/cmaal

# ---------------------------------------------------------------------------
# kitty theme / weather / fetch
# ---------------------------------------------------------------------------
cmd_theme() {
    if ! in_kitty || ! have kitten; then die "cmaal theme only works inside the kitty terminal"; fi
    if (( $# )); then
        kitten themes --reload-in=all "$*"
    else
        kitten themes
    fi
}

cmd_weather() {
    have curl || die "curl is required"
    local city="${*:-$WEATHER_CITY}"
    city=${city// /+}
    curl -fsS --max-time 10 "https://wttr.in/${city}?F" || die "could not reach wttr.in"
}

cmd_fetch() {
    local -a logo=() info=()
    if [[ -r $CMAAL_SHARE/logo.txt ]]; then
        mapfile -t logo <"$CMAAL_SHARE/logo.txt"
    fi
    local title k v i n
    title="$(whoami)@${HOSTNAME:-$(uname -n)}"
    info+=("$C_CYAN$C_BOLD$title$C_RESET")
    info+=("$(printf '%*s' "${#title}" '' | tr ' ' '-')")
    while IFS=$'\t' read -r k v; do
        info+=("$C_CYAN$C_BOLD$k$C_RESET: $v")
    done < <(sys_info_lines)
    info+=("")
    local blocks="" c
    for c in 0 1 2 3 4 5 6 7; do blocks+=$'\e[4'"$c"'m   '; done
    [[ -n $C_RESET ]] && info+=("$blocks$C_RESET")

    n=$(( ${#logo[@]} > ${#info[@]} ? ${#logo[@]} : ${#info[@]} ))
    printf '\n'
    for (( i = 0; i < n; i++ )); do
        printf '%s%-40s%s %s\n' "$C_CYAN$C_BOLD" "${logo[i]:-}" "$C_RESET" "${info[i]:-}"
    done
    printf '\n'
}
