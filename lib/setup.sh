# shellcheck shell=bash
# cmaal: first-run setup (`cmaal setup`, starts by itself the first time
# you open the menu)
# Part of cmaal, sourced by /usr/bin/cmaal. https://github.com/archlinux-dev/cmaal

# set_config KEY VALUE: change one setting in ~/.config/cmaal/config
set_config() {
    local key=$1 value=$2
    [[ -f $CONFIG_FILE ]] || write_default_config
    if grep -q "^$key=" "$CONFIG_FILE"; then
        # value is always a plain word from cmaal itself, no sed special chars
        sed -i "s|^$key=.*|$key=\"$value\"|" "$CONFIG_FILE"
    else
        printf '%s="%s"\n' "$key" "$value" >>"$CONFIG_FILE"
    fi
    printf -v "$key" '%s' "$value"
}

# setup_choice "question" "value|label" ... -> the chosen value (first = default)
setup_choice() {
    local question=$1 line
    shift
    # to stderr: stdout is the answer
    msg "$question" >&2
    line=$(for o in "$@"; do printf '%s\t%s\n' "$(t "${o#*|}")" "${o%%|*}"; done | pick "$question") || {
        printf '%s\n' "${1%%|*}"
        return
    }
    printf '%s\n' "${line##*$'\t'}"
}

cmd_setup() {
    local v
    section "cmaal setup"
    msg "A few questions to make cmaal yours. Change anything later with: cmaal setup"

    v=$(setup_choice "Language" "auto|Automatic (like my system)" "en|English" "de|Deutsch")
    set_config LANGUAGE_UI "$v"
    i18n_init

    v=$(setup_choice "Answer questions for me?" \
        "yes|Yes, use the default answer (recommended: almost always yes)" \
        "all|Yes to absolutely everything" \
        "no|No, always ask me")
    set_config AUTO_CONFIRM "$v"

    if [[ -z $HELPER ]] && have pacman && (( EUID != 0 )); then
        ask "No AUR helper yet. Install yay (for AUR packages)?" y && cmd_helper install yay
    fi

    if have flatpak; then
        if ask "Also search, install and update flatpaks?" y; then set_config USE_FLATPAK yes; else set_config USE_FLATPAK no; fi
    fi

    if have systemctl && ask "Tell me when updates or Arch news arrive (desktop notification)?" y; then
        cmd_alerts on || warn "could not turn on alerts"
    fi

    if ask "When I type a program I don't have, suggest the package (command-not-found helper)?" y; then
        cmd_cnf install || warn "could not install the command-not-found helper"
    fi

    mkdir -p "$CONFIG_DIR"
    : >"$CONFIG_DIR/.setup-done"
    ok "setup done. Open the menu any time by typing: cmaal"
}
