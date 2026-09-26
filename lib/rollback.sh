# shellcheck shell=bash
# cmaal: undo, downgrade, snapshots, package lists
# Part of cmaal, sourced by /usr/bin/cmaal. https://github.com/archlinux-dev/cmaal

# ---------------------------------------------------------------------------
# undo / downgrade
# ---------------------------------------------------------------------------
pkg_cache_dirs() {
    local d
    # pacman-conf prints the dirs with a trailing slash, drop it
    if have pacman-conf; then pacman-conf CacheDir 2>/dev/null; else printf '/var/cache/pacman/pkg/\n'; fi | sed 's|/*$||'
    for d in "$HOME/.cache/yay" "$HOME/.cache/paru/clone" "$HOME/.cache/pikaur/pkg"; do
        [[ -d $d ]] && printf '%s\n' "$d"
    done
}

# foo-bar-1.2-3-x86_64.pkg.tar.zst -> foo-bar
pkg_file_name() {
    local b=${1##*/}
    b=${b%.pkg.tar.*}; b=${b%-*}; b=${b%-*}; b=${b%-*}
    printf '%s' "$b"
}

# foo-bar-1.2-3-x86_64.pkg.tar.zst -> 1.2-3
pkg_file_version() {
    local b=${1##*/} rel
    b=${b%.pkg.tar.*}; b=${b%-*}
    rel=${b##*-}; b=${b%-*}
    b="${b##*-}-$rel"
    printf '%s' "${b//%3A/:}"
}

# Arch Linux Archive keeps every version of every official package
ala_find() {
    local name=$1 ver=$2 arch ext url
    have curl || return 1
    for arch in x86_64 any; do
        for ext in zst xz; do
            url="https://archive.archlinux.org/packages/${name:0:1}/${name}/${name}-${ver}-${arch}.pkg.tar.${ext}"
            if curl -fsIL --max-time 10 -o /dev/null "$url" 2>/dev/null; then
                printf '%s\n' "$url"
                return 0
            fi
        done
    done
    return 1
}

# find_pkg name version -> path in a local cache, or an archive URL
find_pkg() {
    local name=$1 ver=$2 d f
    while IFS= read -r d; do
        for f in "$d"/"$name-$ver"-*.pkg.tar.* "$d"/*/"$name-$ver"-*.pkg.tar.*; do
            [[ -f $f && $f != *.sig ]] || continue
            [[ $(pkg_file_name "$f") == "$name" ]] || continue
            printf '%s\n' "$f"
            return 0
        done
    done < <(pkg_cache_dirs)
    ala_find "$name" "$ver"
}

cmd_undo() {
    need_arch
    local log=$PACMAN_LOG start when
    [[ -r $log ]] || die "cannot read $log"
    start=$(grep -n '\[ALPM\] transaction started' "$log" | tail -n1 | cut -d: -f1)
    [[ -n $start ]] || die "no transactions found in $log"
    when=$(sed -n "${start}p" "$log" | cut -d']' -f1 | tr -d '[')

    local -a changes=() install=() remove=() missing=()
    mapfile -t changes < <(tail -n +"$start" "$log" | grep -E '\[ALPM\] (installed|upgraded|downgraded|removed) ')
    (( ${#changes[@]} )) || die "the last transaction did not change any packages"

    section "Last transaction ($when)"
    local l action name ver old file
    for l in "${changes[@]}"; do
        action=$(awk '{ print $3 }' <<<"$l")
        name=$(awk '{ print $4 }' <<<"$l")
        ver=$(sed -E 's/.*\((.*)\)$/\1/' <<<"$l")
        case $action in
            installed)
                printf '   %sinstalled%s   %s %s  -> will be removed\n' "$C_GREEN" "$C_RESET" "$name" "$ver"
                remove+=("$name")
                ;;
            upgraded|downgraded|removed)
                old=${ver%% -> *}
                if [[ $action == removed ]]; then
                    printf '   %s%-11s%s %s %s  -> will be reinstalled\n' "$C_RED" "$action" "$C_RESET" "$name" "$ver"
                else
                    printf '   %s%-11s%s %s %s  -> back to %s\n' "$C_BLUE" "$action" "$C_RESET" "$name" "$ver" "$old"
                fi
                if file=$(find_pkg "$name" "$old"); then install+=("$file"); else missing+=("$name $old"); fi
                ;;
        esac
    done

    if (( ${#missing[@]} )); then
        warn "no package file found for these (not in cache or the Arch archive):"
        printf '      %s\n' "${missing[@]}" >&2
    fi
    (( ${#install[@]} + ${#remove[@]} )) || die "nothing can be undone"
    (( ${#changes[@]} > 30 )) && warn "this was a big transaction (${#changes[@]} packages), a snapshot restore may be safer"

    if (( ${#missing[@]} )); then
        ask "Undo the rest anyway?" n || return 1
    else
        ask "Undo it?" n || return 1
    fi
    local rc=0
    if (( ${#install[@]} )); then
        section "Restoring previous versions"
        as_root pacman -U -- "${install[@]}" || rc=1
    fi
    if (( ${#remove[@]} )); then
        section "Removing newly installed packages"
        as_root pacman -R -- "${remove[@]}" || rc=1
    fi
    (( rc == 0 )) && ok "undone. Run 'cmaal undo' again to redo."
    return "$rc"
}

cmd_downgrade() {
    need_arch
    local name=${1:-} current d f v pick i
    [[ -n $name ]] || die "usage: cmaal downgrade <package>"
    current=$(pacman -Q -- "$name" 2>/dev/null | awk '{ print $2 }')
    [[ -n $current ]] || warn "$name is not installed"

    local -a options=()  # version<TAB>source<TAB>path-or-url
    while IFS= read -r d; do
        for f in "$d"/"$name"-*.pkg.tar.* "$d"/*/"$name"-*.pkg.tar.*; do
            [[ -f $f && $f != *.sig ]] || continue
            [[ $(pkg_file_name "$f") == "$name" ]] || continue
            options+=("$(pkg_file_version "$f")"$'\t'"cache"$'\t'"$f")
        done
    done < <(pkg_cache_dirs)

    if have curl; then
        msg "Checking the Arch Linux Archive..."
        local base="https://archive.archlinux.org/packages/${name:0:1}/${name}/"
        while IFS= read -r f; do
            [[ -n $f && $(pkg_file_name "$f") == "$name" ]] || continue
            options+=("$(pkg_file_version "$f")"$'\t'"archive"$'\t'"$base$f")
        done < <(curl -fsSL --max-time 15 "$base" 2>/dev/null \
            | grep -o 'href="[^"]*\.pkg\.tar\.[a-z0-9]*"' | cut -d'"' -f2)
    fi
    (( ${#options[@]} )) || die "no versions of $name found in the package cache or the Arch archive (AUR packages are only in your local cache)"

    # newest first, one line per version, prefer the local cache
    mapfile -t options < <(printf '%s\n' "${options[@]}" | sort -t $'\t' -k1,1Vr -k2,2r | awk -F'\t' '!seen[$1]++' | head -n 40)

    if have fzf; then
        v=$(printf '%s\n' "${options[@]}" \
            | awk -F'\t' -v c="$current" '{ printf "%-20s %-8s%s\n", $1, $2, ($1 == c ? "  <- installed" : "") }' \
            | fzf --no-sort --prompt "$name> " --header 'ENTER install this version') || return 1
        v=${v%% *}
        pick=$(printf '%s\n' "${options[@]}" | awk -F'\t' -v v="$v" '$1 == v { print $3; exit }')
        [[ -n $pick ]] || return 1
    else
        for i in "${!options[@]}"; do
            IFS=$'\t' read -r v d _ <<<"${options[i]}"
            printf '   %s%2d)%s %-20s %s%s\n' "$C_CYAN" "$((i + 1))" "$C_RESET" "$v" "$d" "$([[ $v == "$current" ]] && printf '  <- installed')"
        done
        i=$(prompt "Version number")
        [[ $i =~ ^[0-9]+$ ]] && (( i >= 1 && i <= ${#options[@]} )) || return 1
        pick=$(cut -f3 <<<"${options[i - 1]}")
    fi

    as_root pacman -U -- "$pick" || return 1
    msg "Tip: keep $name at this version with: cmaal hold $name"
}

# ---------------------------------------------------------------------------
# Snapshots (snapper or timeshift)
# ---------------------------------------------------------------------------
snapshot_tool() {
    if have snapper && [[ -f /etc/snapper/configs/root ]]; then
        printf 'snapper\n'
    elif have timeshift; then
        printf 'timeshift\n'
    else
        return 1
    fi
}

snapshot_create() {
    local desc=$1
    case $(snapshot_tool) in
        snapper) as_root snapper -c root create --description "$desc" --cleanup-algorithm number ;;
        timeshift) as_root timeshift --create --comments "$desc" --scripted ;;
        *) warn "no snapshot tool found. Install snapper (btrfs) or timeshift."; return 1 ;;
    esac
}

pre_upgrade_snapshot() {
    [[ $SNAPSHOT_BEFORE_UPGRADE == no ]] && return 0
    local tool
    tool=$(snapshot_tool) || { [[ $SNAPSHOT_BEFORE_UPGRADE == yes ]] && warn "SNAPSHOT_BEFORE_UPGRADE=yes but no snapper or timeshift found"; return 0; }
    # these packages already snapshot on every pacman run, don't double up
    if [[ $SNAPSHOT_BEFORE_UPGRADE == auto ]]; then
        [[ $tool == snapper ]] && pacman -Q snap-pac >/dev/null 2>&1 && return 0
        [[ $tool == timeshift ]] && pacman -Q timeshift-autosnap >/dev/null 2>&1 && return 0
    fi
    section "Snapshot before upgrade ($tool)"
    if ! snapshot_create "cmaal: before upgrade"; then
        ask "Snapshot failed. Upgrade anyway?" n || return 1
    fi
}

cmd_snapshot() {
    local tool
    case ${1:-list} in
        list|ls)
            tool=$(snapshot_tool) || die "no snapshot tool found. Install snapper (btrfs) or timeshift."
            if [[ $tool == snapper ]]; then as_root snapper -c root list; else as_root timeshift --list; fi
            ;;
        create|new)
            shift
            snapshot_create "${*:-cmaal: manual snapshot}" && ok "snapshot created"
            ;;
        restore|rollback)
            tool=$(snapshot_tool) || die "no snapshot tool found"
            if [[ $tool == timeshift ]]; then
                as_root timeshift --restore
            else
                msg "snapper rollback depends on your subvolume layout, so cmaal won't run it for you."
                msg "Pick a snapshot number from 'cmaal snapshot list', then run:"
                printf '      sudo snapper rollback <number>   (then reboot)\n'
                msg "If you use grub-btrfs you can also boot straight into a snapshot from the grub menu."
            fi
            ;;
        *) die "usage: cmaal snapshot [list|create [description]|restore]" ;;
    esac
}

# ---------------------------------------------------------------------------
# pkglist: export / import everything you installed
# ---------------------------------------------------------------------------
cmd_pkglist() {
    local sub=${1:-} file=${2:-$HOME/cmaal-packages.txt}
    case $sub in
        export) pkglist_export "$file" ;;
        import) pkglist_import "$file" ;;
        *) die "usage: cmaal pkglist export|import [file]   (default: ~/cmaal-packages.txt)" ;;
    esac
}

pkglist_export() {
    need_arch
    local file=$1
    {
        printf '# cmaal package list\n'
        printf '# exported %s from %s\n' "$(date '+%Y-%m-%d %H:%M')" "${HOSTNAME:-$(uname -n)}"
        printf '# restore with: cmaal pkglist import %s\n\n' "${file##*/}"
        printf '[pacman]\n'
        pacman -Qqen
        printf '\n[aur]\n'
        pacman -Qqem
        if use_flatpak; then
            printf '\n[flatpak]\n'
            flatpak list --app --columns=origin,application 2>/dev/null | tr '\t' ' '
        fi
    } >"$file" || die "could not write $file"
    ok "saved to $file"
    printf '      %s repo, %s AUR%s packages\n' "$(pacman -Qqen | wc -l)" "$(pacman -Qqem | wc -l)" \
        "$(use_flatpak && printf ', %s flatpak' "$(flatpak list --app 2>/dev/null | wc -l)")"
}

pkglist_import() {
    need_arch
    local file=$1 line part=""
    [[ -r $file ]] || die "cannot read $file"
    local -a repo=() aur=() flat=() gone=() flags=(--needed) fp_yes=()
    while IFS= read -r line || [[ -n $line ]]; do
        line=${line%%#*}
        line=${line#"${line%%[![:space:]]*}"}
        line=${line%"${line##*[![:space:]]}"}
        [[ -z $line ]] && continue
        case $line in
            "[pacman]") part=repo; continue ;;
            "[aur]") part=aur; continue ;;
            "[flatpak]") part=flatpak; continue ;;
            "["*) part=""; continue ;;
        esac
        case $part in
            repo) repo+=("$line") ;;
            aur) aur+=("$line") ;;
            flatpak) [[ $line == *" "* ]] && flat+=("${line%% *}"$'\t'"${line#* }") ;;
        esac
    done <"$file"

    # packages that left the official repos can't be installed from there
    if (( ${#repo[@]} )); then
        local all
        all=$(pacman -Slq | sort -u)
        mapfile -t gone < <(comm -23 <(printf '%s\n' "${repo[@]}" | sort -u) <(printf '%s\n' "$all"))
        mapfile -t repo < <(comm -12 <(printf '%s\n' "${repo[@]}" | sort -u) <(printf '%s\n' "$all"))
    fi
    use_flatpak || flat=()

    msg "From $file:"
    printf '      %s repo, %s AUR, %s flatpak packages\n' "${#repo[@]}" "${#aur[@]}" "${#flat[@]}"
    (( ${#gone[@]} )) && warn "no longer in the repos, skipping: ${gone[*]}"
    (( ${#repo[@]} + ${#aur[@]} + ${#flat[@]} )) || die "nothing to install"
    ask "Install everything that's missing?" y || return 1
    [[ -n $CMAAL_YES ]] && { flags+=(--noconfirm); fp_yes=(-y); }
    install_resolved
}
