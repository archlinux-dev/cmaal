# shellcheck shell=bash
# cmaal: rescue, fix a system that doesn't boot
# Part of cmaal, sourced by /usr/bin/cmaal. https://github.com/archlinux-dev/cmaal
#
# Two situations:
#   * booted from an Arch USB stick (archiso): find your installed system,
#     mount it, and run fixes inside it with arch-chroot
#   * booted normally but something is off: the same fixes, run directly
#
# From the USB stick cmaal isn't installed. Run it straight from git:
#   pacman -Sy git && git clone https://github.com/archlinux-dev/cmaal && ./cmaal/bin/cmaal rescue
#
# Every command is shown before it runs, and every step asks first.

RESCUE_MNT="${CMAAL_RESCUE_MNT:-/mnt}"

is_live_iso() { [[ -d /run/archiso || -n ${CMAAL_FORCE_LIVE:-} ]]; }

# step "what it does" command... : show, ask, run
step() {
    local what=$1
    shift
    printf '\n   %s%s%s\n   %s$ %s%s\n' "$C_BOLD" "$(t "$what")" "$C_RESET" "$C_DIM" "$*" "$C_RESET"
    ask "Run it?" y || return 1
    "$@"
}

# in_target cmd... : inside the installed system (chroot when on the USB stick)
in_target() {
    if is_live_iso; then
        as_root arch-chroot "$RESCUE_MNT" "$@"
    else
        as_root "$@"
    fi
}

target_root() { if is_live_iso; then printf '%s' "$RESCUE_MNT"; else printf ''; fi; }

rescue_mount() {
    have lsblk || die "lsblk not found"
    if mountpoint -q "$RESCUE_MNT" 2>/dev/null && [[ -f $RESCUE_MNT/etc/fstab ]]; then
        ok "$(tf 'your system is already mounted at %s' "$RESCUE_MNT")"
        return 0
    fi
    section "Find your system"
    lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS 2>/dev/null | sed 's/^/   /'
    local root fstype line
    line=$(lsblk -rpno NAME,FSTYPE,SIZE,LABEL 2>/dev/null | awk '$2 ~ /^(ext4|btrfs|xfs|f2fs)$/' \
        | pick "Which partition is your Arch root (/)") || return 1
    root=${line%% *}
    fstype=$(awk '{ print $2 }' <<<"$line")

    local -a opts=()
    if [[ $fstype == btrfs ]]; then
        # most installs keep / in a subvolume called @
        local tmp subvol="@"
        tmp=$(mktemp -d)
        as_root mount "$root" "$tmp"
        if as_root btrfs subvolume list "$tmp" 2>/dev/null | awk '{ print $NF }' | grep -qx '@'; then
            msg "btrfs with a @ subvolume found, mounting that as /"
        else
            subvol=$(prompt "btrfs subvolume for / (empty = top level)" "")
        fi
        as_root umount "$tmp"
        rmdir "$tmp"
        [[ -n $subvol ]] && opts=(-o "subvol=$subvol")
    fi

    step "Mount your system" as_root mount "${opts[@]}" "$root" "$RESCUE_MNT" || return 1
    [[ -f $RESCUE_MNT/etc/fstab ]] || { warn "that partition has no /etc/fstab, it's probably not your root"; as_root umount "$RESCUE_MNT"; return 1; }

    # mount /boot, /efi, /boot/efi the way the system's own fstab says
    local src dir type
    while read -r src dir type _; do
        [[ $src == \#* || -z $src ]] && continue
        case $dir in /boot|/efi|/boot/efi) ;; *) continue ;; esac
        step "Mount $dir" as_root mount "$src" "$RESCUE_MNT$dir" || true
    done < <(sed 's/#.*//' "$RESCUE_MNT/etc/fstab")
    ok "$(tf 'your system is mounted at %s' "$RESCUE_MNT")"
}

rescue_fix_kernel() {
    local -a kernels=()
    mapfile -t kernels < <(in_target pacman -Qq 2>/dev/null | grep -E '^linux(-lts|-zen|-hardened|-rt|-rt-lts)?$')
    (( ${#kernels[@]} )) || kernels=(linux)
    step "Reinstall the kernel(s): ${kernels[*]}" in_target pacman -S --noconfirm "${kernels[@]}" || return 1
    step "Rebuild all initramfs images" in_target mkinitcpio -P
}

rescue_fix_bootloader() {
    local root esp
    root=$(target_root)
    if [[ -d $root/boot/grub ]] || [[ -f $root/etc/default/grub ]]; then
        if [[ -d /sys/firmware/efi ]]; then
            for esp in /boot/efi /efi /boot; do
                mountpoint -q "$root$esp" 2>/dev/null && break
            done
            step "Reinstall GRUB (UEFI, EFI partition at $esp)" \
                in_target grub-install --target=x86_64-efi --efi-directory="$esp" --bootloader-id=GRUB || return 1
        else
            local disk
            disk=$(lsblk -dpno NAME,SIZE,MODEL 2>/dev/null | pick "Which disk boots (GRUB goes to its start)") || return 1
            step "Reinstall GRUB (BIOS) on ${disk%% *}" in_target grub-install --target=i386-pc "${disk%% *}" || return 1
        fi
        step "Regenerate the GRUB menu" in_target grub-mkconfig -o /boot/grub/grub.cfg
    elif [[ -d $root/boot/loader ]] || [[ -d $root/efi/loader ]]; then
        step "Reinstall systemd-boot" in_target bootctl install
    else
        warn "no GRUB or systemd-boot found. Check wiki.archlinux.org/title/Arch_boot_process"
        return 1
    fi
}

rescue_password() {
    local user
    user=$(awk -F: '$3 >= 1000 && $3 < 60000 { print $1 }' "$(target_root)/etc/passwd" | pick "Whose password") || return 0
    step "Set a new password for $user" in_target passwd "$user"
}

cmd_rescue() {
    section "cmaal rescue"
    if is_live_iso; then
        msg "Running from the Arch USB stick. First we mount your installed system."
        rescue_mount || die "could not mount your system"
    else
        msg "Running on your installed system. For a system that won't boot, start the Arch USB stick and run cmaal rescue there."
    fi

    local choice
    local -a menu=(
        "Remove a stuck pacman lock"
        "Update everything (fixes broken partial upgrades)"
        "Reinstall the kernel and rebuild initramfs (black screen, kernel panic, no modules)"
        "Reinstall the bootloader (GRUB or systemd-boot)"
        "Reset a user password"
        "Show errors from the last boot"
        "Open a shell inside the system"
        "Done"
    )
    while true; do
        choice=$(for m in "${menu[@]}"; do t "$m"; echo; done | pick "What's wrong") || break
        case $choice in
            "$(t "${menu[0]}")")
                local lock=$PACMAN_LOCK
                is_live_iso && lock="$RESCUE_MNT/var/lib/pacman/db.lck"
                step "Remove the pacman lock" as_root rm -f -- "$lock"
                ;;
            "$(t "${menu[1]}")") step "Full system upgrade" in_target pacman -Syu ;;
            "$(t "${menu[2]}")") rescue_fix_kernel ;;
            "$(t "${menu[3]}")") rescue_fix_bootloader ;;
            "$(t "${menu[4]}")") rescue_password ;;
            "$(t "${menu[5]}")")
                if is_live_iso; then
                    as_root journalctl -D "$RESCUE_MNT/var/log/journal" -b -1 -p 3 --no-pager | tail -n 40
                else
                    journalctl -b -1 -p 3 --no-pager | tail -n 40
                fi
                ;;
            "$(t "${menu[6]}")")
                msg "Type exit to come back"
                if is_live_iso; then as_root arch-chroot "$RESCUE_MNT"; else "${SHELL:-bash}"; fi
                ;;
            *) break ;;
        esac
        [[ -n $CMAAL_YES ]] && break
    done
    if is_live_iso && mountpoint -q "$RESCUE_MNT" 2>/dev/null; then
        ask "Unmount your system now (do this before rebooting)?" y && as_root umount -R "$RESCUE_MNT" && ok "unmounted, you can reboot"
    fi
}
