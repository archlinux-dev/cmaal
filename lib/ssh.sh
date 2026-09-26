# shellcheck shell=bash
# cmaal: SSH hosts, keys and kitty integration
# Part of cmaal, sourced by /usr/bin/cmaal. https://github.com/archlinux-dev/cmaal

# ---------------------------------------------------------------------------
# SSH
# ---------------------------------------------------------------------------
SSH_DIR="$HOME/.ssh"
SSH_CONFIG="$SSH_DIR/config"

ssh_hosts() {
    [[ -f $SSH_CONFIG ]] || return 0
    awk 'tolower($1) == "host" { for (i = 2; i <= NF; i++) if ($i !~ /[*?!]/) print $i }' "$SSH_CONFIG"
}

in_kitty() { [[ $TERM == xterm-kitty || -n ${KITTY_WINDOW_ID:-} ]]; }

# kitten ssh copies kitty's terminfo to the server, so no "unknown terminal" errors
ssh_connect() {
    local -a run=(ssh "$@")
    if [[ $SSH_USE_KITTEN == yes ]] || { [[ $SSH_USE_KITTEN == auto ]] && in_kitty; }; then
        have kitten && run=(kitten ssh "$@")
    fi
    if [[ -n ${SSH_TAB:-} ]] && in_kitty && have kitten; then
        if kitten @ launch --type=tab --tab-title "$1" "${run[@]}" >/dev/null 2>&1; then
            ok "opened $1 in a new kitty tab"
            return 0
        fi
        warn "could not open a new tab. Add 'allow_remote_control yes' to ~/.config/kitty/kitty.conf and restart kitty. Connecting here instead."
    fi
    "${run[@]}"
}

ssh_list() {
    local h
    local -a hosts=()
    mapfile -t hosts < <(ssh_hosts)
    if (( ! ${#hosts[@]} )); then
        msg "No hosts in $SSH_CONFIG yet. Add one: cmaal ssh add"
        return 0
    fi
    for h in "${hosts[@]}"; do
        local target
        target=$(ssh -G "$h" 2>/dev/null | awk '$1 == "user" { u = $2 } $1 == "hostname" { hn = $2 } $1 == "port" { p = $2 } END { print u "@" hn ":" p }')
        printf '   %s%-20s%s %s\n' "$C_CYAN$C_BOLD" "$h" "$C_RESET" "$target"
    done
}

ssh_pick() {
    local -a hosts=()
    local choice
    mapfile -t hosts < <(ssh_hosts)
    (( ${#hosts[@]} )) || { msg "No saved hosts. Add one: cmaal ssh add"; return 1; }
    if have fzf; then
        choice=$(printf '%s\n' "${hosts[@]}" | fzf --height 40% --reverse --prompt 'ssh> ' \
            --preview 'ssh -G {} | grep -E "^(hostname|user|port|identityfile) "') || return 1
    else
        ssh_list
        choice=$(prompt "Host")
    fi
    [[ -n $choice ]] || return 1
    ssh_connect "$choice"
}

ssh_add() {
    local alias=${1:-} target=${2:-} key=${3:-} user host port
    [[ -n $alias ]] || alias=$(prompt "Alias (short name)")
    [[ -n $alias ]] || die "alias required"
    [[ $alias =~ ^[A-Za-z0-9._-]+$ ]] || die "alias may only contain letters, numbers, . _ -"
    ssh_hosts | grep -qx -- "$alias" && die "host '$alias' already exists (cmaal ssh rm $alias)"

    [[ -n $target ]] || target=$(prompt "Address (user@host[:port])")
    [[ -n $target ]] || die "address required"
    if [[ $target == *@* ]]; then user=${target%%@*}; host=${target#*@}; else user=""; host=$target; fi
    if [[ $host == *:* ]]; then port=${host##*:}; host=${host%:*}; else port=""; fi
    [[ -n $user ]] || user=$(prompt "User" "$USER")
    [[ -n $port ]] || port=$(prompt "Port" "22")
    if [[ -z $key && -z $CMAAL_YES ]] && has_tty; then
        key=$(prompt "Identity file (enter for default)")
    fi

    mkdir -p "$SSH_DIR" && chmod 700 "$SSH_DIR"
    touch "$SSH_CONFIG" && chmod 600 "$SSH_CONFIG"
    {
        [[ -s $SSH_CONFIG ]] && printf '\n'
        printf 'Host %s\n    HostName %s\n    User %s\n' "$alias" "$host" "$user"
        [[ $port != 22 ]] && printf '    Port %s\n' "$port"
        [[ -n $key ]] && printf '    IdentityFile %s\n' "$key"
    } >>"$SSH_CONFIG"
    ok "added '$alias'. Connect with: cmaal ssh $alias"
}

ssh_rm() {
    local alias=${1:-}
    [[ -n $alias ]] || die "usage: cmaal ssh rm <alias>"
    ssh_hosts | grep -qx -- "$alias" || die "no host named '$alias'"
    cp "$SSH_CONFIG" "$SSH_CONFIG.bak"
    awk -v a="$alias" '
        tolower($1) == "host" || tolower($1) == "match" { skip = (tolower($1) == "host" && NF == 2 && $2 == a) }
        !skip' "$SSH_CONFIG.bak" >"$SSH_CONFIG"
    ok "removed '$alias' (backup: $SSH_CONFIG.bak)"
}

ssh_keygen() {
    local name=${1:-id_ed25519} file
    file="$SSH_DIR/$name"
    mkdir -p "$SSH_DIR" && chmod 700 "$SSH_DIR"
    if [[ -e $file ]]; then
        ask "$file exists. Overwrite?" n || return 1
    fi
    ssh-keygen -t ed25519 -a 100 -C "${USER}@${HOSTNAME:-$(uname -n)}" -f "$file"
}

ssh_keys() {
    local f any=""
    for f in "$SSH_DIR"/*.pub; do
        [[ -e $f ]] || continue
        any=1
        printf '   %s%s%s\n      %s\n' "$C_CYAN$C_BOLD" "${f##*/}" "$C_RESET" "$(ssh-keygen -lf "$f")"
    done
    [[ -n $any ]] || msg "no keys yet. Create one: cmaal ssh keygen"
}

ssh_server() {
    case ${1:-status} in
        on|enable|start)
            have sshd || { ask "openssh is not installed. Install it?" y && as_root pacman -S --needed openssh; } || return 1
            as_root systemctl enable --now sshd && ok "sshd running"
            ;;
        off|disable|stop)
            as_root systemctl disable --now sshd && ok "sshd stopped"
            ;;
        status)
            systemctl status sshd --no-pager
            ;;
        *) die "usage: cmaal ssh server [on|off|status]" ;;
    esac
}

cmd_ssh() {
    have ssh || die "ssh not found. Install it with: cmaal -S openssh"
    SSH_TAB=""
    [[ $SSH_NEW_TAB == yes ]] && SSH_TAB=1
    if [[ ${1:-} == -t || ${1:-} == --tab ]]; then SSH_TAB=1; shift; fi
    local sub=${1:-}
    case $sub in
        "") ssh_pick ;;
        ls|list) ssh_list ;;
        add|new) shift; ssh_add "$@" ;;
        rm|remove|del) shift; ssh_rm "$@" ;;
        edit) mkdir -p "$SSH_DIR"; "${EDITOR:-nano}" "$SSH_CONFIG" ;;
        keygen) shift; ssh_keygen "$@" ;;
        keys) ssh_keys ;;
        copy|copy-id)
            shift
            [[ -n ${1:-} ]] || die "usage: cmaal ssh copy <host> [key.pub]"
            if [[ -n ${2:-} ]]; then ssh-copy-id -i "$2" "$1"; else ssh-copy-id "$1"; fi
            ;;
        test)
            shift
            [[ -n ${1:-} ]] || die "usage: cmaal ssh test <host>"
            if ssh -o BatchMode=yes -o ConnectTimeout=5 "$1" true 2>/dev/null; then
                ok "$1 reachable, key login works"
            else
                warn "$1: key login failed or host unreachable"
                return 1
            fi
            ;;
        server) shift; ssh_server "$@" ;;
        help|-h|--help) usage_ssh ;;
        *) ssh_connect "$@" ;;
    esac
}
