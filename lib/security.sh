# shellcheck shell=bash
# cmaal: security check, known vulnerabilities, firewall
# Part of cmaal, sourced by /usr/bin/cmaal. https://github.com/femboyss/cmaal

sec_ok()   { printf '   %s+%s %s\n' "$C_GREEN" "$C_RESET" "$(t "$*")"; _SEC_OK=$((_SEC_OK + 1)); }
sec_warn() { printf '   %s!%s %s\n' "$C_YELLOW" "$C_RESET" "$(t "$*")"; _SEC_WARN=$((_SEC_WARN + 1)); }
sec_hint() { printf '     %s%s%s\n' "$C_DIM" "$(t "$*")" "$C_RESET"; }

firewall_state() {
    # service states need no root, so the check never asks for a password
    if have systemctl && systemctl is-active --quiet ufw 2>/dev/null; then echo ufw
    elif have firewall-cmd && firewall-cmd --state >/dev/null 2>&1; then echo firewalld
    elif have systemctl && systemctl is-active --quiet nftables 2>/dev/null; then echo nftables
    elif have systemctl && systemctl is-active --quiet iptables 2>/dev/null; then echo iptables
    fi
}

security_overview() {
    _SEC_OK=0 _SEC_WARN=0
    local n fixable fw open
    section "Security check"

    # 1. updates: most security fixes simply come with them
    if have pacman; then
        if have checkupdates; then n=$(checkupdates 2>/dev/null | grep -c .); else n=$(pacman -Qu 2>/dev/null | grep -c .); fi
        if (( n )); then
            sec_warn "$(tf '%s update(s) waiting (security fixes come with them)' "$n")"
            sec_hint "cmaal -Syu"
        else
            sec_ok "system is up to date"
        fi
    fi

    # 2. known vulnerabilities (Arch security tracker)
    if have arch-audit; then
        n=$(arch-audit -q 2>/dev/null | grep -c .)
        fixable=$(arch-audit -uq 2>/dev/null | grep -c .)
        if (( n )); then
            sec_warn "$(tf '%s installed packages have known vulnerabilities, %s fixed by updating' "$n" "$fixable")"
            sec_hint "details: cmaal security audit"
        else
            sec_ok "no known vulnerabilities in installed packages"
        fi
    else
        sec_warn "can't check for known vulnerabilities (arch-audit is not installed)"
        sec_hint "cmaal -S arch-audit"
    fi

    # 3. firewall
    fw=$(firewall_state)
    if [[ -n $fw ]]; then
        sec_ok "$(tf 'firewall active (%s)' "$fw")"
    else
        sec_warn "no firewall is running"
        sec_hint "cmaal security firewall on"
    fi

    # 4. ports reachable from other computers
    if have ss; then
        open=$(ss -tlnH 2>/dev/null | awk '{ print $4 }' | grep -Ev '^(127\.|\[?::1\]?:|\[?::ffff:127\.)' \
            | sed 's/.*://' | sort -un | tr '\n' ' ')
        if [[ -n ${open// /} ]]; then
            sec_warn "$(tf 'ports open to the network: %s' "$open")"
            sec_hint "which program: cmaal ports"
        else
            sec_ok "no ports open to the network"
        fi
    fi

    # 5. ssh server settings
    if have systemctl && systemctl is-active --quiet sshd 2>/dev/null; then
        local conf root pass
        conf=$(cat /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null)
        root=$(awk 'tolower($1) == "permitrootlogin" { print tolower($2); exit }' <<<"$conf")
        pass=$(awk 'tolower($1) == "passwordauthentication" { print tolower($2); exit }' <<<"$conf")
        if [[ $root == yes ]]; then sec_warn "SSH allows logging in as root"; sec_hint "set PermitRootLogin no in /etc/ssh/sshd_config"; else sec_ok "SSH root login is off"; fi
        if [[ ${pass:-yes} == yes ]]; then sec_warn "SSH accepts passwords (keys are safer)"; sec_hint "cmaal ssh keygen, then PasswordAuthentication no"; else sec_ok "SSH only accepts keys"; fi

        # 6. failed logins in the last day
        n=$(journalctl _COMM=sshd --since -24h --no-pager 2>/dev/null | grep -Ec 'Failed password|Invalid user')
        if (( n > 0 )); then sec_warn "$(tf '%s failed SSH logins in the last 24 hours' "$n")"; else sec_ok "no failed SSH logins in the last 24 hours"; fi
    else
        sec_ok "SSH server is off"
    fi

    printf '\n'
    if (( _SEC_WARN )); then
        msg "$(tf '%s checks fine, %s to look at' "$_SEC_OK" "$_SEC_WARN")"
    else
        ok "$(tf 'all %s checks fine' "$_SEC_OK")"
    fi
}

security_audit() {
    need_arch
    if ! have arch-audit; then
        ask "arch-audit is not installed. Install it?" y || return 1
        pac -S --needed arch-audit || return 1
    fi
    section "Known vulnerabilities (security.archlinux.org)"
    local out
    out=$(arch-audit 2>/dev/null)
    if [[ -z $out ]]; then
        ok "no known vulnerabilities in installed packages"
        return 0
    fi
    printf '%s\n' "$out" | sed 's/^/   /'
    if [[ -n $(arch-audit -uq 2>/dev/null) ]]; then
        printf '\n'
        msg "Some of these are fixed by updating: cmaal -Syu"
    fi
}

security_firewall() {
    case ${1:-status} in
        on|enable)
            if have systemctl && systemctl is-active --quiet firewalld 2>/dev/null; then
                ok "firewalld is already running, manage it with firewall-cmd"
                return 0
            fi
            if ! have ufw; then
                ask "The firewall uses ufw, which isn't installed. Install it?" y || return 1
                pac -S --needed ufw || return 1
            fi
            msg "Blocking incoming connections, allowing outgoing"
            as_root ufw default deny incoming >/dev/null
            as_root ufw default allow outgoing >/dev/null
            if have systemctl && systemctl is-active --quiet sshd 2>/dev/null; then
                as_root ufw allow ssh >/dev/null && msg "SSH is running, so SSH stays allowed"
            fi
            as_root systemctl enable --now ufw >/dev/null 2>&1
            as_root ufw --force enable >/dev/null && ok "firewall on (and at every boot)"
            msg "Allow something later with: cmaal security firewall allow <port>"
            ;;
        off|disable)
            have ufw || die "ufw is not installed"
            as_root ufw disable >/dev/null && ok "firewall off"
            ;;
        allow)
            [[ -n ${2:-} ]] || die "usage: cmaal security firewall allow <port or service>"
            as_root ufw allow "$2" && ok "$(tf 'allowed %s' "$2")"
            ;;
        status)
            if have ufw; then as_root ufw status verbose; else msg "ufw is not installed: cmaal security firewall on"; fi
            ;;
        *) die "usage: cmaal security firewall [on|off|status|allow <port>]" ;;
    esac
}

cmd_security() {
    case ${1:-} in
        ""|check) security_overview ;;
        audit|cve) security_audit ;;
        firewall|fw) shift; security_firewall "$@" ;;
        *) die "usage: cmaal security [check|audit|firewall on|off|status|allow <port>]" ;;
    esac
}
