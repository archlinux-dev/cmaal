# shellcheck shell=bash
# cmaal: install, search, info, upgrade, pickers
# Part of cmaal, sourced by /usr/bin/cmaal. https://github.com/archlinux-dev/cmaal

# ---------------------------------------------------------------------------
# AUR RPC (works even without a helper installed)
# ---------------------------------------------------------------------------
# aur_names pkg... -> prints the names that exist in the AUR
aur_names() {
    local url="https://aur.archlinux.org/rpc/v5/info?" p out
    for p in "$@"; do
        url+="arg%5B%5D=${p//+/%2B}&"
    done
    if have curl && out=$(curl -fsSL --max-time 15 "$url" 2>/dev/null) && [[ $out != *'"type":"error"'* ]]; then
        grep -o '"Name":"[^"]*"' <<<"$out" | cut -d'"' -f4
        return 0
    fi
    # RPC unreachable, ask the helper one by one
    [[ -n $HELPER ]] || return 1
    for p in "$@"; do
        "$HELPER" -Si --aur -- "$p" >/dev/null 2>&1 && printf '%s\n' "$p"
    done
}

# ---------------------------------------------------------------------------
# Flatpak lookup
# ---------------------------------------------------------------------------
# flatpak_find name -> prints "remote<TAB>app-id" of the chosen match
flatpak_find() {
    local q=$1 line id remote i choice
    local -a hits=()
    mapfile -t hits < <(flatpak search --columns=application,remotes -- "$q" 2>/dev/null \
        | awk -F'\t' 'NF >= 2 && $1 ~ /\./ { split($2, r, ","); print $1 "\t" r[1] }' | head -n 9)
    (( ${#hits[@]} )) || return 1

    # exact match on a part of the app id: "firefox" -> org.mozilla.firefox,
    # "spotify" -> com.spotify.Client. Last part wins over middle parts.
    local pattern
    for pattern in "*.${q,,}" "*.${q,,}.*"; do
        for line in "${hits[@]}"; do
            id=${line%%$'\t'*}
            # shellcheck disable=SC2053
            if [[ ${id,,} == $pattern ]]; then
                remote=${line#*$'\t'}
                printf '%s\t%s\n' "$remote" "$id"
                return 0
            fi
        done
    done

    [[ -z $CMAAL_YES ]] && has_tty || return 1
    printf '%s::%s No exact flatpak for "%s", closest matches:\n' "$C_BLUE$C_BOLD" "$C_RESET" "$q" >/dev/tty
    for i in "${!hits[@]}"; do
        printf '   %s%d)%s %s\n' "$C_CYAN" "$((i + 1))" "$C_RESET" "${hits[i]%%$'\t'*}" >/dev/tty
    done
    choice=$(prompt "Pick one (enter to skip)")
    [[ $choice =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#hits[@]} )) || return 1
    line=${hits[choice - 1]}
    printf '%s\t%s\n' "${line#*$'\t'}" "${line%%$'\t'*}"
}

# ---------------------------------------------------------------------------
# -S  install from wherever the package lives
# ---------------------------------------------------------------------------
cmd_install() {
    need_arch
    local -a flags=() pkgs=() repo=() aur=() flat=() missing=() rest=() found=()
    local a p hit fp_yes=()
    for a in "$@"; do
        if [[ $a == -* ]]; then
            flags+=("$a")
            [[ $a == --noconfirm ]] && { CMAAL_YES=1; fp_yes=(-y); }
        else
            pkgs+=("$a")
        fi
    done
    (( ${#pkgs[@]} )) || { cmd_pick_install "${flags[@]}"; return; }

    msg "$(tf 'Looking up %s package(s)...' "${#pkgs[@]}")"

    # 1. official repos (also resolves groups and provides)
    for p in "${pkgs[@]}"; do
        if pacman -Sp --noconfirm -- "$p" >/dev/null 2>&1; then
            repo+=("$p")
        else
            rest+=("$p")
        fi
    done

    # 2. AUR
    if (( ${#rest[@]} )); then
        mapfile -t found < <(aur_names "${rest[@]}")
        local -a still=()
        for p in "${rest[@]}"; do
            hit=""
            for a in "${found[@]}"; do [[ $a == "$p" ]] && hit=1 && break; done
            if [[ -n $hit ]]; then aur+=("$p"); else still+=("$p"); fi
        done
        rest=("${still[@]}")
    fi

    # 3. flatpak
    for p in "${rest[@]}"; do
        if use_flatpak && hit=$(flatpak_find "$p"); then
            flat+=("$hit")
        else
            missing+=("$p")
        fi
    done

    (( ${#repo[@]} )) && printf '   %spacman%s   %s\n' "$C_GREEN$C_BOLD" "$C_RESET" "${repo[*]}"
    (( ${#aur[@]} ))  && printf '   %saur%s      %s\n' "$C_YELLOW$C_BOLD" "$C_RESET" "${aur[*]}"
    if (( ${#flat[@]} )); then
        printf '   %sflatpak%s  ' "$C_CYAN$C_BOLD" "$C_RESET"
        for hit in "${flat[@]}"; do printf '%s ' "${hit#*$'\t'}"; done
        printf '\n'
    fi
    (( ${#missing[@]} )) && printf '   %s%s%s %s\n' "$C_RED$C_BOLD" "$(t "not found")" "$C_RESET" "${missing[*]}"

    if (( ${#repo[@]} + ${#aur[@]} + ${#flat[@]} == 0 )); then
        die "$(tf 'nothing to install. Try: cmaal -Ss %s' "${missing[0]}")"
    fi

    local rc=0
    install_resolved || rc=1
    (( rc == 0 )) && run_hooks post_install "${repo[@]}" "${aur[@]}"
    (( ${#missing[@]} )) && rc=1
    return "$rc"
}

# Installs the caller's repo/aur/flat arrays, using its flags and fp_yes.
# (bash functions see the locals of the function that called them)
install_resolved() {
    local rc=0 hit
    if (( ${#repo[@]} )); then
        section "pacman -S ${repo[*]}"
        as_root pacman -S "${flags[@]}" -- "${repo[@]}" || rc=1
    fi

    if (( ${#aur[@]} )); then
        if [[ -z $HELPER ]]; then
            warn "${aur[*]} are AUR packages but no AUR helper is installed"
            if ask "Install yay now?" y; then
                cmd_helper install yay || rc=1
            fi
        fi
        if [[ -n $HELPER ]] && ! aur_precheck "${aur[@]}"; then
            warn "skipped the AUR packages: ${aur[*]}"
            rc=1
        elif [[ -n $HELPER ]]; then
            section "$HELPER -S ${aur[*]}"
            if "$HELPER" -S "${flags[@]}" -- "${aur[@]}"; then
                aur_remember "${aur[@]}"
            else
                rc=1
            fi
        else
            rc=1
        fi
    fi

    for hit in "${flat[@]}"; do
        section "flatpak install ${hit#*$'\t'}"
        flatpak install --or-update "${fp_yes[@]}" "${hit%%$'\t'*}" "${hit#*$'\t'}" || rc=1
    done

    return "$rc"
}

# ---------------------------------------------------------------------------
# -Ss  search everywhere
# ---------------------------------------------------------------------------
cmd_search() {
    need_arch
    (( $# )) || die "usage: cmaal -Ss <query>..."
    local out

    section "Official repos (pacman)"
    out=$(pacman -Ss --color=always -- "$@" 2>/dev/null)
    [[ -n $out ]] && printf '%s\n' "$out" || printf '   %snothing found%s\n' "$C_DIM" "$C_RESET"

    section "AUR${HELPER:+ ($HELPER)}"
    if [[ -n $HELPER ]]; then
        out=$("$HELPER" -Ss --aur --color=always -- "$@" 2>/dev/null)
    elif have curl && have jq; then
        out=$(curl -fsSL --max-time 15 "https://aur.archlinux.org/rpc/v5/search/$1?by=name-desc" 2>/dev/null \
            | jq -r '.results | sort_by(-.Popularity) | .[:25][] | "aur/\(.Name) \(.Version)\n    \(.Description // "")"')
    else
        out="   (install yay/paru or jq to search the AUR)"
    fi
    [[ -n $out ]] && printf '%s\n' "$out" || printf '   %snothing found%s\n' "$C_DIM" "$C_RESET"

    if use_flatpak; then
        section "Flatpak"
        out=$(flatpak search --columns=application,version,description -- "$@" 2>/dev/null | grep -v '^No matches')
        [[ -n $out ]] && printf '%s\n' "$out" | head -n 20 || printf '   %snothing found%s\n' "$C_DIM" "$C_RESET"
    fi
}

# ---------------------------------------------------------------------------
# -Si  info from wherever the package lives
# ---------------------------------------------------------------------------
cmd_pkginfo() {
    need_arch
    (( $# )) || die "usage: cmaal -Si <package>"
    local p
    for p in "$@"; do
        if pacman -Si -- "$p" 2>/dev/null; then continue; fi
        if [[ -n $HELPER ]] && "$HELPER" -Si --aur -- "$p" 2>/dev/null; then continue; fi
        if use_flatpak && flatpak remote-info flathub "$p" 2>/dev/null; then continue; fi
        warn "$p: not found in repos${HELPER:+, AUR}$(use_flatpak && printf ', flatpak')"
    done
}

# ---------------------------------------------------------------------------
# -Syu / -Syyu  upgrade everything
# ---------------------------------------------------------------------------
cmd_upgrade() {
    need_arch
    local op=${1:--Syu}; shift || true
    local -a extra=("$@") fp_yes=()
    local a
    for a in "${extra[@]}"; do
        [[ $a == --noconfirm ]] && { CMAAL_YES=1; fp_yes=(-y); }
    done

    check_news_before_upgrade || die "upgrade aborted"
    aur_upgrade_check || die "upgrade aborted"
    pre_upgrade_snapshot || die "upgrade aborted"
    run_hooks pre_upgrade
    local -a aur_before=()
    [[ -n $HELPER && $AUR_CHECK == yes ]] && mapfile -t aur_before < <("$HELPER" -Qua 2>/dev/null | awk '{ print $1 }')
    local started=$SECONDS

    local rc=0
    if [[ -n $HELPER ]]; then
        section "$HELPER $op (repos + AUR)"
        "$HELPER" "$op" "${extra[@]}" || rc=1
    else
        section "pacman $op"
        as_root pacman "$op" "${extra[@]}" || rc=1
    fi

    if use_flatpak; then
        section "flatpak update"
        flatpak update "${fp_yes[@]}" || rc=1
    fi

    post_upgrade_checks
    (( rc == 0 && ${#aur_before[@]} )) && aur_remember "${aur_before[@]}"
    run_hooks post_upgrade

    local took=$(( SECONDS - started ))
    if (( NOTIFY_AFTER_SECONDS > 0 && took >= NOTIFY_AFTER_SECONDS )); then
        if (( rc == 0 )); then
            notify "Upgrade finished in $(( took / 60 ))m $(( took % 60 ))s"
        else
            notify "Upgrade finished with errors, check the terminal"
        fi
    fi
    return "$rc"
}

post_upgrade_checks() {
    local -a pacnew=()
    mapfile -t pacnew < <(find /etc -name '*.pacnew' 2>/dev/null)
    if (( ${#pacnew[@]} )); then
        warn "${#pacnew[@]} .pacnew file(s) need merging (tip: sudo pacdiff):"
        printf '      %s\n' "${pacnew[@]}" >&2
    fi
    if [[ ! -d /usr/lib/modules/$(uname -r) ]]; then
        warn "the running kernel was updated, reboot to load the new one"
    fi
}

# ---------------------------------------------------------------------------
# Anything else that looks like a pacman flag goes to the helper or pacman
# ---------------------------------------------------------------------------
passthrough() {
    need_arch
    if [[ -n $HELPER ]]; then
        "$HELPER" "$@"
        return
    fi
    case $1 in
        -Q*|-T*|-Si*|-Ss*|-Sg*|-Sl*|-F|-Fl*|-Fx*|-Fo*|-Fs*|-V|--version|-h|--help)
            pacman "$@" ;;
        *)
            as_root pacman "$@" ;;
    esac
}

# ---------------------------------------------------------------------------
# fzf pickers:  cmaal -S  /  cmaal -R  with no package names
# ---------------------------------------------------------------------------
# Every AUR package name, cached for a day (about 1 MB download)
aur_package_list() {
    local f="$CACHE_DIR/aur-packages" age=999999
    mkdir -p "$CACHE_DIR"
    [[ -f $f ]] && age=$(( $(date +%s) - $(stat -c %Y "$f") ))
    if (( age > 86400 )) && have curl; then
        if curl -fsSL --max-time 60 https://aur.archlinux.org/packages.gz 2>/dev/null | gzip -dc >"$f.tmp" 2>/dev/null && [[ -s $f.tmp ]]; then
            mv "$f.tmp" "$f"
        fi
        rm -f "$f.tmp"
    fi
    [[ -f $f ]] && grep -v '^#' "$f"
}

preview_cmd() {
    printf '%q __preview %s' "$CMAAL_BIN" "$*"
}

cmd_pick_install() {
    need_arch
    need_fzf || die "the package picker needs fzf (or use: cmaal -S <package>)"
    local -a flags=("$@") repo=() aur=() flat=() fp_yes=() picked=()
    local a line src name extra
    for a in "${flags[@]}"; do [[ $a == --noconfirm ]] && fp_yes=(-y); done

    msg "Loading package lists (repos, AUR$(use_flatpak && printf ', flatpak'))..."
    mapfile -t picked < <(
        {
            pacman -Sl 2>/dev/null | awk '{ printf "repo\t%s\t%s%s\n", $2, $3, ($4 != "" ? "  [installed]" : "") }'
            aur_package_list | awk '{ printf "aur\t%s\t\n", $1 }'
            if use_flatpak; then
                for r in $(flatpak remotes --columns=name 2>/dev/null); do
                    flatpak remote-ls --app --columns=application "$r" 2>/dev/null \
                        | awk -v r="$r" '{ printf "flatpak\t%s\t%s\n", $1, r }'
                done
            fi
        } | fzf --multi --delimiter '\t' --tabstop 9 \
                --prompt 'install> ' --header 'TAB select   ENTER install   ESC cancel' \
                --preview "$(preview_cmd '{1} {2} {3}')" --preview-window 'right,55%,wrap'
    )
    (( ${#picked[@]} )) || { msg "nothing selected"; return 0; }

    for line in "${picked[@]}"; do
        IFS=$'\t' read -r src name extra <<<"$line"
        case $src in
            repo) repo+=("$name") ;;
            aur) aur+=("$name") ;;
            flatpak) flat+=("$extra"$'\t'"$name") ;;
        esac
    done
    install_resolved
}

cmd_pick_remove() {
    need_arch
    need_fzf || die "the package picker needs fzf (or use: cmaal -Rns <package>)"
    local op=${1:--Rns}; shift || true
    local -a flags=("$@") pk=() fp=() picked=()
    local line src name rc=0

    mapfile -t picked < <(
        {
            pacman -Qe 2>/dev/null | awk '{ printf "pacman\t%s\t%s\n", $1, $2 }'
            if use_flatpak; then
                flatpak list --app --columns=application,name 2>/dev/null \
                    | awk -F'\t' '{ printf "flatpak\t%s\t%s\n", $1, $2 }'
            fi
        } | fzf --multi --delimiter '\t' --tabstop 9 \
                --prompt 'remove> ' --header 'TAB select   ENTER remove   ESC cancel   (explicitly installed packages)' \
                --preview "$(preview_cmd 'rm-{1} {2}')" --preview-window 'right,55%,wrap'
    )
    (( ${#picked[@]} )) || { msg "nothing selected"; return 0; }

    for line in "${picked[@]}"; do
        IFS=$'\t' read -r src name _ <<<"$line"
        if [[ $src == flatpak ]]; then fp+=("$name"); else pk+=("$name"); fi
    done
    if (( ${#pk[@]} )); then
        passthrough "$op" "${flags[@]}" -- "${pk[@]}" || rc=1
    fi
    if (( ${#fp[@]} )); then
        section "flatpak uninstall ${fp[*]}"
        flatpak uninstall "${fp[@]}" || rc=1
    fi
    return "$rc"
}

# Used by the fzf preview windows: cmaal __preview <kind> <name> [extra]
cmd_preview() {
    local kind=${1:-} name=${2:-} extra=${3:-}
    case $kind in
        repo) pacman -Si -- "$name" 2>/dev/null ;;
        aur)
            if [[ -n $HELPER ]]; then
                "$HELPER" -Si --aur -- "$name" 2>/dev/null
            elif have jq; then
                curl -fsSL --max-time 10 "https://aur.archlinux.org/rpc/v5/info?arg%5B%5D=${name//+/%2B}" 2>/dev/null | jq -r '.results[0] |
                    "Name        : \(.Name)\nVersion     : \(.Version)\nDescription : \(.Description)\nURL         : \(.URL)\nVotes       : \(.NumVotes)\nPopularity  : \(.Popularity)\nMaintainer  : \(.Maintainer)"'
            else
                printf 'AUR package %s\n' "$name"
            fi
            ;;
        flatpak) flatpak remote-info "$extra" "$name" 2>/dev/null ;;
        rm-pacman) pacman -Qi -- "$name" 2>/dev/null ;;
        rm-flatpak) flatpak info "$name" 2>/dev/null ;;
        service)
            # shellcheck disable=SC2086
            SYSTEMD_COLORS=1 systemctl $extra status --no-pager -n 15 -- "$name" 2>/dev/null ;;
    esac
    return 0
}
