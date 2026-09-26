# shellcheck shell=bash
# cmaal: hardware drivers and gaming setup
# Part of cmaal, sourced by /usr/bin/cmaal. https://github.com/archlinux-dev/cmaal

# gpu_vendors -> nvidia / amd / intel, one per line (hybrid laptops have two)
gpu_vendors() {
    have lspci || return 0
    lspci 2>/dev/null | grep -Ei 'vga|3d controller|display controller' | tr '[:upper:]' '[:lower:]' | while read -r line; do
        case $line in
            *nvidia*) echo nvidia ;;
            *amd*|*ati*|*radeon*) echo amd ;;
            *intel*) echo intel ;;
        esac
    done | sort -u
}

cpu_vendor() {
    case $(grep -m1 vendor_id /proc/cpuinfo 2>/dev/null) in
        *GenuineIntel*) echo intel ;;
        *AuthenticAMD*) echo amd ;;
    esac
}

pkg_installed() { pacman -Q -- "$1" >/dev/null 2>&1; }

multilib_enabled() {
    [[ -r $PACMAN_CONF ]] && grep -q '^\[multilib\]' "$PACMAN_CONF"
}

# Uncomment [multilib] and its Include line, validated and backed up like hold
enable_multilib() {
    multilib_enabled && return 0
    grep -q '^#\[multilib\]' "$PACMAN_CONF" || die "no #[multilib] section in $PACMAN_CONF to enable, add it by hand"
    local tmp
    tmp=$(mktemp)
    awk '
        /^#\[multilib\]/ { print "[multilib]"; on = 1; next }
        on && /^#Include/ { sub(/^#/, ""); print; on = 0; next }
        on && /^\[/ { on = 0 }
        { print }' "$PACMAN_CONF" >"$tmp"
    if have pacman-conf && ! pacman-conf --config "$tmp" >/dev/null 2>&1; then
        rm -f "$tmp"
        die "the edited pacman.conf did not validate, nothing was changed"
    fi
    as_root cp -- "$PACMAN_CONF" "$PACMAN_CONF.cmaal.bak"
    as_root install -m 644 -- "$tmp" "$PACMAN_CONF"
    rm -f "$tmp"
    ok "multilib enabled (backup: $PACMAN_CONF.cmaal.bak)"
}

# driver_plan -> "component<US>detected<US>packages<US>note" lines
driver_plan() {
    local US=$'\x1f' cpu g
    cpu=$(cpu_vendor)
    [[ -n $cpu ]] && printf '%s%s%s%s%s-ucode%s%s\n' "CPU microcode" "$US" "$cpu" "$US" "$cpu" "$US" "$(t 'security and stability fixes for your CPU')"
    for g in $(gpu_vendors); do
        case $g in
            amd) printf '%s\n' "GPU${US}AMD${US}mesa vulkan-radeon${US}$(t 'open source, works out of the box')" ;;
            intel) printf '%s\n' "GPU${US}Intel${US}mesa vulkan-intel intel-media-driver${US}$(t 'open source, video decoding included')" ;;
            nvidia) printf '%s\n' "GPU${US}NVIDIA${US}nvidia-open-dkms nvidia-utils${US}$(t 'RTX 20 and newer. GTX 10 and older: check wiki.archlinux.org/title/NVIDIA')" ;;
        esac
    done
    if have lspci && lspci 2>/dev/null | grep -Eiq 'network controller.*broadcom'; then
        printf '%s\n' "Wi-Fi${US}Broadcom${US}broadcom-wl-dkms${US}$(t 'most Broadcom chips need this driver')"
    fi
    if have lspci && lspci 2>/dev/null | grep -Eiq 'audio.*(smart sound|cannon lake|tiger lake|alder lake|raptor lake|meteor lake)'; then
        printf '%s\n' "Audio${US}Intel SOF${US}sof-firmware${US}$(t 'needed for sound on most newer laptops')"
    fi
    printf '%s\n' "Firmware${US}-${US}linux-firmware${US}$(t 'firmware for many devices')"
}

cmd_drivers() {
    need_arch
    local comp det pkgs note p missing_here
    local -a missing=()
    section "Hardware and drivers"
    while IFS=$'\x1f' read -r comp det pkgs note; do
        missing_here=()
        for p in $pkgs; do pkg_installed "$p" || missing_here+=("$p")
        done
        if (( ${#missing_here[@]} )); then
            printf '   %s%-14s%s %-10s %smissing: %s%s\n' "$C_BOLD" "$(t "$comp")" "$C_RESET" "$det" "$C_YELLOW" "${missing_here[*]}" "$C_RESET"
            missing+=("${missing_here[@]}")
        else
            printf '   %s%-14s%s %-10s %s%s%s\n' "$C_BOLD" "$(t "$comp")" "$C_RESET" "$det" "$C_GREEN" "$(t ok)" "$C_RESET"
        fi
        printf '      %s%s%s\n' "$C_DIM" "$note" "$C_RESET"
    done < <(driver_plan)

    if [[ $(gpu_vendors | wc -l) -gt 1 ]]; then
        msg "Two GPUs found (hybrid laptop). Tools like envycontrol or supergfxctl can switch between them."
    fi
    (( ${#missing[@]} )) || { ok "all recommended drivers are installed"; return 0; }
    printf '\n'
    if printf '%s\n' "${missing[@]}" | grep -q nvidia; then
        warn "NVIDIA drivers change often. If your GPU is older than RTX 20, read the Arch wiki before installing."
        ask "Install the missing packages (${missing[*]})?" n || return 0
    else
        ask "Install the missing packages (${missing[*]})?" y || return 0
    fi
    as_root pacman -S --needed -- "${missing[@]}"
    msg "Reboot to load new drivers and microcode."
}

cmd_gaming() {
    need_arch
    local g
    local -a pkgs=(steam gamemode lib32-gamemode mangohud lib32-mangohud) extra=()
    section "Gaming setup"
    msg "This sets up Steam, Proton, GameMode and MangoHud. Every step asks first."

    # 1. multilib: Steam and 32-bit drivers live there
    if ! multilib_enabled; then
        msg "Steam needs the multilib repository (32-bit libraries)."
        ask "Enable multilib in $PACMAN_CONF?" y || { warn "gaming setup needs multilib, stopping"; return 1; }
        enable_multilib
        # a full upgrade, not just -Sy: partial upgrades break Arch
        as_root pacman -Syu || return 1
    else
        ok "multilib is enabled"
    fi

    # 2. 32-bit graphics drivers for your GPU
    for g in $(gpu_vendors); do
        case $g in
            amd) pkgs+=(lib32-mesa vulkan-radeon lib32-vulkan-radeon) ;;
            intel) pkgs+=(lib32-mesa vulkan-intel lib32-vulkan-intel) ;;
            nvidia) pkgs+=(nvidia-utils lib32-nvidia-utils) ;;
        esac
    done

    # 3. optional launchers
    ask "Also install Lutris (Epic, GOG, emulators)?" n && extra+=(lutris)
    ask "Also install Heroic Games Launcher (Epic, GOG, Amazon, AUR)?" n && extra+=(heroic-games-launcher-bin)
    ask "Also install ProtonUp-Qt (install GE-Proton versions, AUR)?" n && extra+=(protonup-qt)

    section "Installing"
    printf '   %s\n' "${pkgs[*]} ${extra[*]}"
    ask "Go?" y || return 1
    cmd_install --needed "${pkgs[@]}" "${extra[@]}" || warn "some packages did not install, see above"

    # 4. gamemode wants its group
    if getent group gamemode >/dev/null 2>&1 && ! id -nG "$USER" | grep -qw gamemode; then
        as_root usermod -aG gamemode "$USER" && ok "added you to the gamemode group (log out and in once)"
    fi

    section "Tips"
    msg "In Steam: Settings > Compatibility > enable Steam Play for all titles (Proton)"
    msg "Launch options for a game: gamemoderun mangohud %command%"
    msg "Check drivers any time with: cmaal drivers"
}
