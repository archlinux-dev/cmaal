# shellcheck shell=bash
# cmaal: battery health and power profiles
# Part of cmaal, sourced by /usr/bin/cmaal. https://github.com/femboyss/cmaal

POWER_SUPPLY="${CMAAL_POWER_SUPPLY:-/sys/class/power_supply}"

# read_sys dir file -> value or empty
read_sys() { [[ -r $1/$2 ]] && tr -d '\n' <"$1/$2"; }

power_battery() {
    local b cap status cycles full design now pnow health left model found=""
    for b in "$POWER_SUPPLY"/BAT*; do
        [[ -d $b ]] || continue
        found=1
        cap=$(read_sys "$b" capacity)
        status=$(read_sys "$b" status)
        cycles=$(read_sys "$b" cycle_count)
        model="$(read_sys "$b" manufacturer) $(read_sys "$b" model_name)"
        # energy_* (µWh) on most laptops, charge_* (µAh) on some
        full=$(read_sys "$b" energy_full); design=$(read_sys "$b" energy_full_design)
        now=$(read_sys "$b" energy_now); pnow=$(read_sys "$b" power_now)
        if [[ -z $full ]]; then
            full=$(read_sys "$b" charge_full); design=$(read_sys "$b" charge_full_design)
            now=$(read_sys "$b" charge_now); pnow=$(read_sys "$b" current_now)
        fi

        section "$(tf 'Battery %s' "${b##*/}")"
        [[ -n ${model// /} ]] && printf '   %-12s %s\n' "$(t model)" "${model# }"
        printf '   %-12s %s%%  (%s)\n' "$(t charge)" "${cap:-?}" "$(t "${status:-Unknown}")"
        if [[ $full =~ ^[0-9]+$ && $design =~ ^[0-9]+$ ]] && (( design > 0 )); then
            health=$(( full * 100 / design ))
            printf '   %-12s %s%%  %s(%s)%s\n' "$(t health)" "$health" "$C_DIM" "$(t 'of the capacity it had when new')" "$C_RESET"
            if (( health < 70 )); then
                warn "the battery has lost a lot of capacity, a replacement would help"
            fi
        fi
        [[ -n $cycles && $cycles != 0 ]] && printf '   %-12s %s\n' "$(t cycles)" "$cycles"
        if [[ $status == Discharging && $now =~ ^[0-9]+$ && $pnow =~ ^[0-9]+$ ]] && (( pnow > 0 )); then
            left=$(( now * 60 / pnow ))
            printf '   %-12s %s\n' "$(t 'time left')" "$(tf '%sh %smin' $(( left / 60 )) $(( left % 60 )))"
        fi
    done
    if [[ -z $found ]]; then
        section "Battery"
        msg "No battery found (desktop PC)."
    fi
}

power_profile_status() {
    section "Power profile"
    if have powerprofilesctl; then
        local cur
        cur=$(powerprofilesctl get 2>/dev/null)
        powerprofilesctl list 2>/dev/null | awk '/^[ *]*[a-z-]+:$/ { gsub(/[* :]/, ""); print }' | while read -r p; do
            if [[ $p == "$cur" ]]; then
                printf '   %s> %s%s\n' "$C_GREEN$C_BOLD" "$p" "$C_RESET"
            else
                printf '     %s\n' "$p"
            fi
        done
        msg "Switch with: cmaal power set performance | balanced | power-saver"
    elif have tlp; then
        msg "TLP manages power on this PC (tlp-stat -s for details)."
    else
        msg "No power profile tool. For quick switching: cmaal -S power-profiles-daemon"
    fi
    if have tlp && have powerprofilesctl; then
        warn "TLP and power-profiles-daemon are both installed, they fight each other. Keep one."
    fi
}

power_set() {
    local p=${1:-}
    case $p in
        perf|performance|max) p=performance ;;
        bal|balanced|normal) p=balanced ;;
        saver|eco|power-saver|save|low) p=power-saver ;;
        *) die "usage: cmaal power set performance | balanced | power-saver" ;;
    esac
    have powerprofilesctl || die "power-profiles-daemon is not installed: cmaal -S power-profiles-daemon"
    powerprofilesctl set "$p" && ok "$(tf 'power profile: %s' "$p")"
}

cmd_power() {
    case ${1:-} in
        ""|status) power_battery; power_profile_status ;;
        set|profile) shift; power_set "$@" ;;
        battery) power_battery ;;
        *) die "usage: cmaal power [status|set <profile>|battery]" ;;
    esac
}
