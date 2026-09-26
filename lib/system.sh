# shellcheck shell=bash
# cmaal: sys, doctor, services, logs, ports, ip
# Part of cmaal, sourced by /usr/bin/cmaal. https://github.com/archlinux-dev/cmaal

# ---------------------------------------------------------------------------
# System info / doctor
# ---------------------------------------------------------------------------
# "Label<TAB>value" lines, shared by `cmaal sys` and `cmaal fetch`
sys_info_lines() {
    local os up pkgs aur fp="" mem disk cpu gpu term de failed
    # shellcheck source=/dev/null
    os=$(. /etc/os-release 2>/dev/null && printf '%s' "${PRETTY_NAME:-$NAME}")
    up=$(uptime -p 2>/dev/null | sed 's/^up //')
    use_flatpak && fp=$(flatpak list --app --columns=application 2>/dev/null | wc -l)
    cpu=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | sed 's/^ *//')
    have lspci && gpu=$(lspci 2>/dev/null | grep -Ei 'vga|3d|display' | head -n1 | cut -d: -f3 | sed 's/^ *//')
    mem=$(free -h 2>/dev/null | awk '/^Mem/ { print $3 " / " $2 }')
    disk=$(df -h / 2>/dev/null | awk 'NR == 2 { print $3 " / " $2 " (" $5 ")" }')
    term=${TERM_PROGRAM:-$TERM}
    [[ -n ${KITTY_WINDOW_ID:-} ]] && term="kitty"
    de=${XDG_CURRENT_DESKTOP:-${DESKTOP_SESSION:-}}

    printf 'OS\t%s\n' "$os"
    printf 'Kernel\t%s\n' "$(uname -r)"
    printf 'Uptime\t%s\n' "$up"
    if have pacman; then
        pkgs=$(pacman -Qq | wc -l)
        aur=$(pacman -Qmq | wc -l)
        printf 'Packages\t%s (pacman), %s (AUR)%s\n' "$pkgs" "$aur" "${fp:+, $fp (flatpak)}"
    fi
    printf 'AUR helper\t%s\n' "${HELPER:-none}"
    printf 'Shell\t%s\n' "$(basename "${SHELL:-?}")"
    [[ -n $de ]] && printf 'Desktop\t%s\n' "$de"
    printf 'Terminal\t%s\n' "$term"
    printf 'CPU\t%s\n' "$cpu"
    [[ -n ${gpu:-} ]] && printf 'GPU\t%s\n' "$gpu"
    printf 'Memory\t%s\n' "$mem"
    printf 'Disk /\t%s\n' "$disk"
    failed=$(systemctl --failed --no-legend 2>/dev/null | wc -l)
    (( failed > 0 )) && printf 'Failed\t%s systemd unit(s), see: systemctl --failed\n' "$failed"
    return 0
}

cmd_sys() {
    local k v color
    section "$(whoami)@${HOSTNAME:-$(uname -n)}"
    while IFS=$'\t' read -r k v; do
        color=""
        [[ $k == Failed ]] && color=$C_RED
        printf '   %s%-11s%s %s%s%s\n' "$C_CYAN$C_BOLD" "$k" "$C_RESET" "$color" "$v" "$C_RESET"
    done < <(sys_info_lines)
}

cmd_doctor() {
    local t
    section "Tools"
    for t in pacman sudo curl git "$HELPER" flatpak fzf reflector paccache ssh kitten jq snapper timeshift; do
        [[ -z $t ]] && continue
        if have "$t"; then
            printf '   %s+%s %s\n' "$C_GREEN" "$C_RESET" "$t"
        else
            printf '   %s-%s %s %s(optional)%s\n' "$C_RED" "$C_RESET" "$t" "$C_DIM" "$C_RESET"
        fi
    done
    [[ -z $HELPER ]] && printf '   %s-%s AUR helper %s(cmaal helper install)%s\n' "$C_RED" "$C_RESET" "$C_DIM" "$C_RESET"

    section "System"
    if have pacman; then
        local orphans pacnew
        orphans=$(pacman -Qdtq 2>/dev/null | wc -l)
        pacnew=$(find /etc -name '*.pacnew' 2>/dev/null | wc -l)
        printf '   orphans: %s   .pacnew files: %s\n' "$orphans" "$pacnew"
        [[ -d /usr/lib/modules/$(uname -r) ]] || warn "kernel updated since boot, reboot recommended"
    fi
    if have systemctl; then
        local failed
        failed=$(systemctl --failed --no-legend 2>/dev/null | wc -l)
        printf '   failed systemd units: %s\n' "$failed"
    fi

    section "cmaal"
    printf '   version: %s\n   installed at: %s\n   config: %s\n   auto update: %s\n' \
        "$CMAAL_VERSION" "$CMAAL_BIN" "$CONFIG_FILE" "$AUTO_UPDATE"
}

# ---------------------------------------------------------------------------
# services / logs / ports / ip
# ---------------------------------------------------------------------------
cmd_services() {
    have systemctl || die "systemctl not found"
    local -a scope=()
    if [[ ${1:-} == --user ]]; then scope=(--user); shift; fi
    local unit=${1:-} action=${2:-}

    if [[ -z $unit ]]; then
        need_fzf || die "the service picker needs fzf (or use: cmaal services <name> <action>)"
        unit=$(systemctl "${scope[@]}" list-unit-files --type=service --no-legend --no-pager 2>/dev/null \
            | awk '$1 !~ /@\.service$/ { printf "%s\t%s\n", $1, $2 }' \
            | fzf --delimiter '\t' --tabstop 45 --prompt 'service> ' --header 'ENTER pick an action' \
                  --preview "$(preview_cmd "service {1} ${scope[*]}")" --preview-window 'down,60%,wrap') || return 0
        unit=${unit%%$'\t'*}
    fi
    [[ $unit == *.* ]] || unit+=".service"

    local -a actions=(status start stop restart "enable (and start)" "disable (and stop)" logs)
    if [[ -z $action ]]; then
        if have fzf; then
            action=$(printf '%s\n' "${actions[@]}" | fzf --prompt "$unit> " --height 12 --reverse) || return 0
        else
            local i
            for i in "${!actions[@]}"; do printf '   %d) %s\n' "$((i + 1))" "${actions[i]}"; done
            i=$(prompt "Action")
            [[ $i =~ ^[0-9]+$ ]] && (( i >= 1 && i <= ${#actions[@]} )) || return 1
            action=${actions[i - 1]}
        fi
    fi
    action=${action%% *}

    local -a run=(as_root systemctl)
    (( ${#scope[@]} )) && run=(systemctl --user)
    case $action in
        status) systemctl "${scope[@]}" status --no-pager -- "$unit" ;;
        logs) journalctl "${scope[@]}" -b -u "$unit" -n 100 --no-pager ;;
        start|stop|restart)
            "${run[@]}" "$action" -- "$unit" && ok "$unit: $(systemctl "${scope[@]}" is-active -- "$unit")" ;;
        enable|disable)
            "${run[@]}" "$action" --now -- "$unit" && ok "$unit: $(systemctl "${scope[@]}" is-enabled -- "$unit"), $(systemctl "${scope[@]}" is-active -- "$unit")" ;;
        *) die "unknown action: $action (status, start, stop, restart, enable, disable, logs)" ;;
    esac
}

cmd_logs() {
    have journalctl || die "journalctl not found"
    local unit
    case ${1:-} in
        "") section "Errors since boot"; journalctl -b -p 3 -n 50 --no-pager ;;
        -f|follow) journalctl -f ;;
        prev|last|previous) section "Errors from the previous boot"; journalctl -b -1 -p 3 -n 50 --no-pager ;;
        [0-9]*) section "Errors since boot"; journalctl -b -p 3 -n "$1" --no-pager ;;
        *)
            unit=$1
            [[ $unit == *.* ]] || unit+=".service"
            journalctl -b -u "$unit" -n "${2:-50}" --no-pager
            ;;
    esac
}

cmd_ports() {
    have ss || die "ss not found (iproute2)"
    section "Listening ports"
    printf '   %s%-5s %-6s %-30s %s%s\n' "$C_BOLD" "PROTO" "PORT" "ADDRESS" "PROGRAM" "$C_RESET"
    as_root ss -tulpnH | awk '{
        proto = $1; addr = $5; prog = "?"
        if (match($0, /users:\(\("[^"]*"/)) prog = substr($0, RSTART + 9, RLENGTH - 10)
        n = split(addr, a, ":"); port = a[n]
        addr = substr(addr, 1, length(addr) - length(port) - 1)
        printf "   %-5s %-6s %-30s %s\n", proto, port, addr, prog
    }' | sort -k2,2n -k1,1
}

cmd_ip() {
    local gw dns pub4 pub6
    section "Local"
    if have ip; then
        ip -brief addr show scope global 2>/dev/null | awk 'NF >= 3 { printf "   %-14s", $1; for (i = 3; i <= NF; i++) printf " %s", $i; printf "\n" }'
        gw=$(ip route show default 2>/dev/null | awk '/default/ { print $3; exit }')
        [[ -n $gw ]] && printf '   %-14s %s\n' "gateway" "$gw"
    fi
    dns=$(awk '/^nameserver/ { printf "%s ", $2 }' /etc/resolv.conf 2>/dev/null)
    [[ -n $dns ]] && printf '   %-14s %s\n' "dns" "$dns"

    section "Public"
    if have curl; then
        pub4=$(curl -4 -fsS --max-time 5 https://api.ipify.org 2>/dev/null)
        pub6=$(curl -6 -fsS --max-time 5 https://api6.ipify.org 2>/dev/null)
        printf '   %-14s %s\n' "IPv4" "${pub4:-none}"
        printf '   %-14s %s\n' "IPv6" "${pub6:-none}"
    else
        warn "curl needed for the public IP"
    fi
}

# ---------------------------------------------------------------------------
# kernel / disk
# ---------------------------------------------------------------------------
cmd_kernel() {
    local running k v
    running=$(uname -r)
    section "Kernels"
    printf '   running:   %s%s%s\n' "$C_BOLD" "$running" "$C_RESET"
    if have pacman; then
        while read -r k v; do
            printf '   installed: %-18s %s\n' "$k" "$v"
        done < <(pacman -Q 2>/dev/null | grep -E '^linux(-lts|-zen|-hardened|-rt|-rt-lts|-cachyos[a-z-]*)? ')
    fi
    if [[ -d /usr/lib/modules/$running ]]; then
        ok "the running kernel matches what is installed"
    else
        warn "the kernel was upgraded since boot. Reboot to use the new one (some USB devices and modules may not load until then)"
    fi
}

cmd_disk() {
    section "Filesystems"
    printf '   %s%-28s %6s %6s %6s %5s%s\n' "$C_BOLD" "MOUNT" "SIZE" "USED" "FREE" "USE" "$C_RESET"
    df -h -x tmpfs -x devtmpfs -x efivarfs -x squashfs -x overlay --output=target,size,used,avail,pcent 2>/dev/null \
        | awk 'NR > 1 { printf "   %-28s %6s %6s %6s %5s\n", $1, $2, $3, $4, $5 }'

    section "Space you can win back"
    local d size
    for d in /var/cache/pacman/pkg "$HOME/.cache/yay" "$HOME/.cache/paru" "$HOME/.cache" /var/lib/flatpak "$HOME/.local/share/Trash"; do
        [[ -d $d ]] || continue
        size=$(du -sh -- "$d" 2>/dev/null | cut -f1)
        printf '   %-8s %s\n' "${size:-?}" "$d"
    done
    size=""
    have journalctl && size=$(journalctl --disk-usage 2>/dev/null | grep -o '[0-9.]*[KMGT]\?B' | head -n1)
    [[ -n $size ]] && printf '   %-8s %s\n' "$size" "systemd journal"
    printf '   %s(cmaal clean frees most of this)%s\n' "$C_DIM" "$C_RESET"

    section "Biggest folders in $HOME"
    du -xsh -- "$HOME"/* "$HOME"/.[!.]* 2>/dev/null | sort -rh | head -n "${1:-10}" | awk -F'\t' '{ printf "   %-8s %s\n", $1, $2 }'
    return 0
}
