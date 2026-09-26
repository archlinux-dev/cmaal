# shellcheck shell=bash
# cmaal: wifi (NetworkManager) and bluetooth (bluez) pickers
# Part of cmaal, sourced by /usr/bin/cmaal. https://github.com/archlinux-dev/cmaal

# pick "prompt" <lines> -> the chosen line (fzf, or a numbered menu)
pick() {
    local question=$1 choice i
    local -a lines=()
    mapfile -t lines
    (( ${#lines[@]} )) || return 1
    if have fzf; then
        printf '%s\n' "${lines[@]}" | fzf --prompt "$(t "$question")> " --height 50% --reverse
        return
    fi
    for i in "${!lines[@]}"; do
        printf '   %s%2d)%s %s\n' "$C_CYAN" "$((i + 1))" "$C_RESET" "${lines[i]}" >/dev/tty
    done
    choice=$(prompt "$question")
    [[ $choice =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#lines[@]} )) || return 1
    printf '%s\n' "${lines[choice - 1]}"
}

# ---------------------------------------------------------------------------
# wifi
# ---------------------------------------------------------------------------
need_nmcli() {
    have nmcli && return 0
    if have iwctl; then
        msg "You use iwd, not NetworkManager. Opening iwctl (type: station wlan0 get-networks)"
        iwctl
        exit $?
    fi
    die "NetworkManager (nmcli) is not installed: cmaal -S networkmanager"
}

# nmcli -t escapes ':' inside values as '\:'; turn fields into a clean table
# "SSID<US>SIGNAL<US>SECURITY<US>IN-USE"
wifi_scan() {
    nmcli -t -f SSID,SIGNAL,SECURITY,IN-USE dev wifi list --rescan auto 2>/dev/null \
        | sed 's/\\:/@COLON@/g' | awk -F: -v OFS=$'\x1f' '$1 != "" { gsub(/@COLON@/, ":", $1); print $1, $2, $3, $4 }' \
        | sort -t $'\x1f' -k2,2nr | awk -F $'\x1f' '!seen[$1]++'
}

cmd_wifi() {
    local sub=${1:-} ssid sig sec inuse line
    case $sub in
        ""|connect)
            need_nmcli
            ssid=${2:-}
            if [[ -z $ssid ]]; then
                msg "Scanning..."
                line=$(wifi_scan | while IFS=$'\x1f' read -r ssid sig sec inuse; do
                    printf '%-32s %3s%%  %-12s %s\n' "$ssid" "$sig" "${sec:---}" "${inuse:+$(t connected)}"
                done | pick "Network") || return 0
                ssid=$(sed -E 's/ +[0-9]+% .*$//' <<<"$line")
            fi
            msg "$(tf 'Connecting to %s' "$ssid")"
            # --ask lets nmcli ask for the password when it needs one
            nmcli --ask dev wifi connect "$ssid" && ok "$(tf 'connected to %s' "$ssid")"
            ;;
        list|ls)
            need_nmcli
            section "Wi-Fi networks"
            wifi_scan | while IFS=$'\x1f' read -r ssid sig sec inuse; do
                printf '   %s%-32s%s %3s%%  %s\n' "${inuse:+$C_GREEN}" "$ssid" "$C_RESET" "$sig" "${sec:---}"
            done
            ;;
        status)
            need_nmcli
            section "Network"
            nmcli -t -f DEVICE,TYPE,STATE,CONNECTION dev status 2>/dev/null \
                | awk -F: '$2 != "loopback" && $2 != "bridge" { printf "   %-12s %-10s %-14s %s\n", $1, $2, $3, $4 }'
            ;;
        on|off)
            need_nmcli
            nmcli radio wifi "$sub" && ok "$(tf 'Wi-Fi %s' "$(t "$sub")")"
            ;;
        forget)
            need_nmcli
            ssid=${2:-}
            [[ -n $ssid ]] || ssid=$(nmcli -t -f NAME,TYPE connection show | awk -F: '$2 ~ /wireless/ { print $1 }' | pick "Forget") || return 0
            nmcli connection delete id "$ssid" && ok "$(tf 'forgot %s' "$ssid")"
            ;;
        password|share)
            need_nmcli
            ssid=${2:-$(nmcli -t -f ACTIVE,SSID dev wifi 2>/dev/null | awk -F: '$1 == "yes" { print $2; exit }')}
            [[ -n $ssid ]] || die "not connected to Wi-Fi, give the network name: cmaal wifi $sub <name>"
            local pass
            pass=$(nmcli -s -g 802-11-wireless-security.psk connection show id "$ssid" 2>/dev/null) || pass=""
            [[ -n $pass ]] || pass=$(as_root nmcli -s -g 802-11-wireless-security.psk connection show id "$ssid" 2>/dev/null)
            [[ -n $pass ]] || die "no saved password for $ssid"
            section "$ssid"
            printf '   %s: %s%s%s\n' "$(t password)" "$C_BOLD" "$pass" "$C_RESET"
            if have qrencode; then
                msg "Scan this with your phone camera to join:"
                qrencode -t ansiutf8 "WIFI:T:WPA;S:${ssid};P:${pass};;"
            else
                msg "Install qrencode to get a QR code for phones: cmaal -S qrencode"
            fi
            ;;
        *) die "usage: cmaal wifi [connect [name]|list|status|on|off|forget [name]|share [name]]" ;;
    esac
}

# ---------------------------------------------------------------------------
# bluetooth
# ---------------------------------------------------------------------------
need_bluetooth() {
    have bluetoothctl || die "bluez is not installed: cmaal -S bluez bluez-utils"
    if have systemctl && ! systemctl is-active --quiet bluetooth 2>/dev/null; then
        ask "The bluetooth service is not running. Start it (and at boot)?" y || return 1
        as_root systemctl enable --now bluetooth || return 1
    fi
}

bt_devices() {
    # newer bluez: "devices Paired", older: "paired-devices"
    if [[ ${1:-} == paired ]]; then
        bluetoothctl devices Paired 2>/dev/null | grep '^Device' || bluetoothctl paired-devices 2>/dev/null | grep '^Device'
    else
        bluetoothctl devices 2>/dev/null | grep '^Device'
    fi
}

bt_pick() {
    local question=$1 kind=${2:-paired} line
    line=$(bt_devices "$kind" | cut -d' ' -f2- | pick "$question") || return 1
    printf '%s\n' "${line%% *}"
}

cmd_bluetooth() {
    local sub=${1:-} mac name
    case $sub in
        ""|status)
            have bluetoothctl || die "bluez is not installed: cmaal -S bluez bluez-utils"
            section "Bluetooth"
            bluetoothctl show 2>/dev/null | awk -F': ' '/Powered|Discoverable|Name:/ { printf "   %s: %s\n", $1, $2 }' | sed 's/^   \t*/   /'
            section "Paired devices"
            local any=""
            while read -r _ mac name; do
                any=1
                if bluetoothctl info "$mac" 2>/dev/null | grep -q 'Connected: yes'; then
                    printf '   %s%-30s%s %s  %s\n' "$C_GREEN" "$name" "$C_RESET" "$mac" "$(t connected)"
                else
                    printf '   %-30s %s\n' "$name" "$mac"
                fi
            done < <(bt_devices paired)
            [[ -n $any ]] || msg "none yet. Pair one with: cmaal bluetooth pair"
            ;;
        on|off)
            need_bluetooth || return 1
            have rfkill && [[ $sub == on ]] && rfkill unblock bluetooth 2>/dev/null
            bluetoothctl power "$sub" >/dev/null && ok "$(tf 'Bluetooth %s' "$(t "$sub")")"
            ;;
        pair|scan|new)
            need_bluetooth || return 1
            bluetoothctl power on >/dev/null 2>&1
            msg "Put your device in pairing mode. Scanning for 10 seconds..."
            bluetoothctl --timeout 10 scan on >/dev/null 2>&1
            mac=$(bt_pick "Pair" all) || return 0
            bluetoothctl pair "$mac" && bluetoothctl trust "$mac" >/dev/null && bluetoothctl connect "$mac" \
                && ok "paired and connected"
            ;;
        connect)
            need_bluetooth || return 1
            mac=${2:-$(bt_pick "Connect")} || return 0
            bluetoothctl power on >/dev/null 2>&1
            bluetoothctl connect "$mac" >/dev/null && ok "connected"
            ;;
        disconnect)
            mac=${2:-$(bt_pick "Disconnect")} || return 0
            bluetoothctl disconnect "$mac" >/dev/null && ok "disconnected"
            ;;
        remove|forget)
            mac=${2:-$(bt_pick "Remove")} || return 0
            bluetoothctl remove "$mac" >/dev/null && ok "removed"
            ;;
        *) die "usage: cmaal bluetooth [status|on|off|pair|connect|disconnect|remove]" ;;
    esac
}
