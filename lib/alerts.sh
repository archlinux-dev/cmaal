# shellcheck shell=bash
# cmaal: background update alerts (systemd user timer + desktop notification)
# Part of cmaal, sourced by /usr/bin/cmaal. https://github.com/archlinux-dev/cmaal
#
# `cmaal alerts on` installs a user timer (no root needed). Every
# ALERTS_EVERY it runs `cmaal __alert-check`, which counts updates and unread
# Arch news without changing anything, and sends one notification when there
# is something new to tell you.

ALERT_UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"

alerts_summary() {
    local repo=0 aur=0 fp=0 news=0 out
    if have checkupdates; then
        repo=$(checkupdates 2>/dev/null | grep -c .)
    elif have pacman; then
        repo=$(pacman -Qu 2>/dev/null | grep -c .)
    fi
    [[ -n $HELPER ]] && aur=$("$HELPER" -Qua 2>/dev/null | grep -c .)
    use_flatpak && fp=$(flatpak remote-ls --updates --app 2>/dev/null | grep -c .)
    have curl && news=$(unread_news | grep -c .)

    local total=$(( repo + aur + fp ))
    out=""
    (( total )) && out=$(tf '%s updates' "$total")
    (( aur )) && out+=" $(tf '(%s AUR)' "$aur")"
    if (( news )); then
        [[ -n $out ]] && out+=", "
        out+=$(tf '%s unread Arch news, read before upgrading' "$news")
    fi
    printf '%s\n' "$out"
}

# the timer runs this; also handy by hand: cmaal alerts now
alerts_check() {
    local summary last="" last_time=0 now
    mkdir -p "$CACHE_DIR"
    summary=$(alerts_summary)
    printf '%s\n' "${summary:-$(t 'everything up to date')}" >"$CACHE_DIR/alerts_last"
    [[ -n $summary ]] || return 0

    # don't repeat the same message more than once a day
    now=$(date +%s)
    if [[ -f $CACHE_DIR/alerts_notified ]]; then
        { read -r last_time; read -r last; } <"$CACHE_DIR/alerts_notified"
    fi
    if [[ $summary == "$last" && $(( now - ${last_time:-0} )) -lt 86400 ]]; then
        return 0
    fi
    printf '%s\n%s\n' "$now" "$summary" >"$CACHE_DIR/alerts_notified"
    if have notify-send; then
        notify-send --app-name=cmaal --icon=system-software-update "cmaal" "$summary. $(t 'Run: cmaal -Syu')" 2>/dev/null || true
    fi
    printf '%s\n' "$summary"
}

cmd_alerts() {
    local sub=${1:-status}
    case $sub in
        on|enable)
            have systemctl || die "systemd is needed for alerts"
            have notify-send || warn "notify-send is missing, install libnotify to see the notifications"
            mkdir -p "$ALERT_UNIT_DIR"
            cat >"$ALERT_UNIT_DIR/cmaal-alerts.service" <<EOF
[Unit]
Description=cmaal: check for updates and Arch news

[Service]
Type=oneshot
ExecStart=$CMAAL_BIN __alert-check
EOF
            cat >"$ALERT_UNIT_DIR/cmaal-alerts.timer" <<EOF
[Unit]
Description=cmaal: check for updates every $ALERTS_EVERY

[Timer]
OnBootSec=5min
OnUnitActiveSec=$ALERTS_EVERY
Persistent=true

[Install]
WantedBy=timers.target
EOF
            if ! systemctl --user daemon-reload || ! systemctl --user enable --now cmaal-alerts.timer; then
                die "could not start the timer"
            fi
            ok "$(tf 'alerts on: cmaal checks every %s and notifies you' "$ALERTS_EVERY")"
            msg "Change how often with ALERTS_EVERY in cmaal config (e.g. 2h, 1d)"
            ;;
        off|disable)
            have systemctl && systemctl --user disable --now cmaal-alerts.timer 2>/dev/null
            rm -f -- "$ALERT_UNIT_DIR/cmaal-alerts.timer" "$ALERT_UNIT_DIR/cmaal-alerts.service"
            have systemctl && systemctl --user daemon-reload 2>/dev/null
            ok "alerts off"
            ;;
        now|check)
            section "Checking"
            local s
            s=$(alerts_check)
            if [[ -n $s ]]; then msg "$s"; else ok "everything up to date"; fi
            ;;
        status|"")
            if [[ -f $ALERT_UNIT_DIR/cmaal-alerts.timer ]]; then
                ok "$(tf 'alerts are on (every %s)' "$ALERTS_EVERY")"
                have systemctl && systemctl --user list-timers cmaal-alerts.timer --no-pager 2>/dev/null | sed -n '1,2p' | sed 's/^/   /'
            else
                msg "Alerts are off. Turn them on with: cmaal alerts on"
            fi
            [[ -f $CACHE_DIR/alerts_last ]] && msg "$(tf 'Last check: %s' "$(<"$CACHE_DIR/alerts_last")")"
            ;;
        *) die "usage: cmaal alerts [on|off|now|status]" ;;
    esac
}
