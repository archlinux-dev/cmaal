# shellcheck shell=bash
# cmaal: back up your config files (dotfiles) into a git repository
# Part of cmaal, sourced by /usr/bin/cmaal. https://github.com/archlinux-dev/cmaal
#
# Files are copied into BACKUP_REPO keeping their path below $HOME
# (~/.config/kitty/kitty.conf -> home/.config/kitty/kitty.conf), plus a
# package list. Secrets are never copied: private SSH keys, GPG keys, *.key,
# *.pem, password stores and browser profiles are always skipped.

BACKUP_REPO="${XDG_DATA_HOME:-$HOME/.local/share}/cmaal/backup"
BACKUP_LIST="$BACKUP_REPO/.cmaal-paths"

BACKUP_DEFAULTS=(
    .bashrc .bash_profile .zshrc .zprofile .profile .gitconfig .inputrc .vimrc
    .config/kitty .config/fish .config/nvim .config/hypr .config/waybar .config/sway
    .config/i3 .config/alacritty .config/starship.toml .config/cmaal .config/fastfetch
    .ssh/config
)

# never, ever back these up
backup_is_secret() {
    case $1 in
        */.ssh/id_*.pub|*/.ssh/config|*/.ssh/known_hosts) return 1 ;;
        */.ssh/*|*/.gnupg/*|*.key|*.pem|*.p12|*.pfx|*/.password-store/*|*/.mozilla/*|\
        */.config/google-chrome/*|*/.config/chromium/*|*/.local/share/keyrings/*|*/.netrc|*/.aws/credentials|\
        */.docker/config.json|*token*|*secret*) return 0 ;;
    esac
    return 1
}

backup_paths() {
    local p
    for p in "${BACKUP_DEFAULTS[@]}" $BACKUP_PATHS; do printf '%s\n' "${p#"$HOME"/}"; done
    [[ -f $BACKUP_LIST ]] && grep -v '^#' "$BACKUP_LIST"
    return 0
}

need_backup_repo() {
    have git || die "git is required: cmaal -S git"
    [[ -d $BACKUP_REPO/.git ]] || die "no backup yet. Start one with: cmaal backup init [git-url]"
}

backup_copy() {
    local rel src f n=0 skipped=0
    rm -rf -- "${BACKUP_REPO:?}/home"
    mkdir -p "$BACKUP_REPO/home"
    while IFS= read -r rel; do
        [[ -n $rel ]] || continue
        src="$HOME/$rel"
        [[ -e $src ]] || continue
        while IFS= read -r -d '' f; do
            if backup_is_secret "$f"; then
                skipped=$((skipped + 1))
                continue
            fi
            mkdir -p "$BACKUP_REPO/home/$(dirname "${f#"$HOME"/}")"
            cp -a -- "$f" "$BACKUP_REPO/home/${f#"$HOME"/}" && n=$((n + 1))
        done < <(find "$src" \( -name .git -o -name node_modules -o -iname cache -o -name '*.log' \) -prune -o -type f -size -5M -print0 2>/dev/null)
    done < <(backup_paths | sort -u)
    have pacman && pkglist_export "$BACKUP_REPO/packages.txt" >/dev/null 2>&1
    printf '%s %s\n' "$n" "$skipped"
}

cmd_backup() {
    local sub=${1:-run} arg=${2:-}
    case $sub in
        init)
            have git || die "git is required: cmaal -S git"
            mkdir -p "$BACKUP_REPO"
            if [[ ! -d $BACKUP_REPO/.git ]]; then
                git -C "$BACKUP_REPO" init -q -b main
                printf '# extra paths for cmaal backup, relative to your home, one per line\n' >"$BACKUP_LIST"
                ok "backup repository created: $BACKUP_REPO"
            fi
            if [[ -n $arg ]]; then
                git -C "$BACKUP_REPO" remote remove origin 2>/dev/null
                git -C "$BACKUP_REPO" remote add origin "$arg" && ok "$(tf 'will push to %s' "$arg")"
                warn "use a PRIVATE repository: config files can still say a lot about you"
            fi
            msg "Back up now with: cmaal backup"
            ;;
        run|now|"")
            need_backup_repo
            section "Backing up"
            local counts n skipped
            counts=$(backup_copy)
            read -r n skipped <<<"$counts"
            msg "$(tf '%s files copied, %s secret files skipped' "$n" "$skipped")"
            git -C "$BACKUP_REPO" add -A
            if git -C "$BACKUP_REPO" diff --cached --quiet; then
                ok "nothing changed since the last backup"
            else
                git -C "$BACKUP_REPO" -c user.name="${USER:-cmaal}" -c user.email="${USER:-cmaal}@localhost" \
                    commit -q -m "backup $(date '+%Y-%m-%d %H:%M') from ${HOSTNAME:-$(uname -n)}" && ok "backup saved"
            fi
            if git -C "$BACKUP_REPO" remote get-url origin >/dev/null 2>&1; then
                git -C "$BACKUP_REPO" push -q -u origin main && ok "pushed"
            else
                msg "Only on this PC. To keep it safe elsewhere: cmaal backup init <git-url>"
            fi
            ;;
        add)
            need_backup_repo
            [[ -n $arg ]] || die "usage: cmaal backup add <path>"
            arg=$(realpath -m -- "$arg")
            [[ $arg == "$HOME"/* ]] || die "only files inside your home folder can be backed up"
            backup_is_secret "$arg/" && die "that looks like a secret, cmaal won't back it up"
            printf '%s\n' "${arg#"$HOME"/}" >>"$BACKUP_LIST"
            ok "$(tf 'added %s' "${arg#"$HOME"/}")"
            ;;
        rm|remove)
            need_backup_repo
            [[ -n $arg ]] || die "usage: cmaal backup rm <path>"
            arg=$(realpath -m -- "$arg")
            grep -vxF -- "${arg#"$HOME"/}" "$BACKUP_LIST" >"$BACKUP_LIST.tmp"; mv -- "$BACKUP_LIST.tmp" "$BACKUP_LIST"
            ok "$(tf 'removed %s from the list' "${arg#"$HOME"/}")"
            ;;
        list|ls)
            section "What cmaal backs up (if it exists)"
            backup_paths | sort -u | while read -r rel; do
                if [[ -e $HOME/$rel ]]; then printf '   %s+%s ~/%s\n' "$C_GREEN" "$C_RESET" "$rel"
                else printf '   %s- ~/%s%s\n' "$C_DIM" "$rel" "$C_RESET"; fi
            done
            ;;
        log|history)
            need_backup_repo
            git -C "$BACKUP_REPO" log --oneline -n 20
            ;;
        restore)
            need_backup_repo
            local -a files=()
            mapfile -t files < <(cd "$BACKUP_REPO/home" && find . -type f | sed 's|^\./||' | grep -- "${arg:-.}")
            (( ${#files[@]} )) || die "nothing in the backup matches '${arg:-}'"
            section "Restore"
            printf '   ~/%s\n' "${files[@]}" | head -n 30
            (( ${#files[@]} > 30 )) && printf '   ... %s\n' "$(tf 'and %s more' $(( ${#files[@]} - 30 )))"
            msg "Files that exist now are kept as <name>.cmaal-old"
            ask "$(tf 'Restore %s files into your home?' "${#files[@]}")" n || return 1
            local f
            for f in "${files[@]}"; do
                mkdir -p "$HOME/$(dirname "$f")"
                [[ -e $HOME/$f ]] && ! cmp -s "$HOME/$f" "$BACKUP_REPO/home/$f" && cp -a -- "$HOME/$f" "$HOME/$f.cmaal-old"
                cp -a -- "$BACKUP_REPO/home/$f" "$HOME/$f"
            done
            ok "restored"
            [[ -f $BACKUP_REPO/packages.txt ]] && msg "Reinstall your packages too with: cmaal pkglist import $BACKUP_REPO/packages.txt"
            ;;
        where|path) printf '%s\n' "$BACKUP_REPO" ;;
        *) die "usage: cmaal backup [init [git-url]|add <path>|rm <path>|list|log|restore [match]]" ;;
    esac
}
