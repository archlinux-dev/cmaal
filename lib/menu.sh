# shellcheck shell=bash
# cmaal: the main menu (just type `cmaal`)
# Part of cmaal, sourced by /usr/bin/cmaal. https://github.com/femboyss/cmaal
#
# Every entry runs a normal cmaal command in its own process, so a command
# that stops with an error just brings you back to the menu.

# category | label | command ({word} = ask the user for it first)
MENU_ITEMS=(
    "Packages|Install packages (browse everything)|-S"
    "Packages|Search for a package|-Ss {search}"
    "Packages|Update everything|-Syu"
    "Packages|Show available updates|updates"
    "Packages|Remove packages|-Rns"
    "Packages|Why is a package installed?|why {package}"
    "Packages|Which package has a command?|provides {command}"
    "Packages|Check my AUR packages|review"
    "Packages|Undo the last change|undo"
    "Packages|Go back to an older version|downgrade {package}"
    "Packages|Keep a package at its version|hold {package}"
    "Packages|Clean up (orphans, caches, journal)|clean"
    "System|Health check|doctor"
    "System|Security check|security"
    "System|Battery and power|power"
    "System|My Arch stats|stats"
    "System|Fix pacman problems|fix"
    "System|Find the fastest mirrors|mirrors"
    "System|Services|services"
    "System|Errors since boot|logs"
    "System|Disk space|disk"
    "System|Kernel and reboot check|kernel"
    "System|Arch news|news"
    "System|Back up my config files|backup"
    "System|Rescue a broken system|rescue"
    "Desktop|Wi-Fi|wifi"
    "Desktop|Bluetooth|bluetooth"
    "Desktop|Drivers|drivers"
    "Desktop|Gaming setup|gaming"
    "Desktop|kitty theme|theme"
    "Desktop|SSH: connect to a server|ssh"
    "Fun|System info with the Arch logo|fetch"
    "Fun|Weather|weather"
    "cmaal|Settings (run the setup again)|setup"
    "cmaal|Update alerts on / off|alerts {on/off}"
    "cmaal|Command-not-found helper|cnf status"
    "cmaal|Plugins|plugins"
    "cmaal|Update cmaal|self-update"
    "cmaal|What's new|whatsnew"
    "cmaal|All commands (help)|help"
)

menu_lines() {
    local item cat label cmd name
    for item in "${MENU_ITEMS[@]}"; do
        IFS='|' read -r cat label cmd <<<"$item"
        printf '%-10s %s\t%s\n' "$(t "$cat")" "$(t "$label")" "$cmd"
    done
    for name in $(printf '%s\n' "${!_PLUGIN_FILE[@]}" | sort); do
        printf '%-10s %s\t%s\n' "Plugins" "${_PLUGIN_DESC[$name]:-$name}" "$name"
    done
    printf '%-10s %s\t%s\n' "" "$(t "Quit")" "__quit"
}

menu_pick() {
    local -a lines=()
    local i choice
    mapfile -t lines < <(menu_lines)
    if have fzf; then
        printf '%s\n' "${lines[@]}" | fzf --delimiter '\t' --with-nth 1 --no-sort --reverse \
            --prompt "cmaal> " --header "cmaal v$CMAAL_VERSION   $(t 'type to search, ENTER to run, ESC to quit')" \
            --preview "printf '%s\n' {2}" --preview-window 'bottom,1,border-top' || return 1
        return
    fi
    for i in "${!lines[@]}"; do
        printf '   %s%2d)%s %s\n' "$C_CYAN" "$((i + 1))" "$C_RESET" "${lines[i]%%$'\t'*}" >/dev/tty
    done
    choice=$(prompt "Number (enter to quit)")
    [[ $choice =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#lines[@]} )) || return 1
    printf '%s\n' "${lines[choice - 1]}"
}

cmd_menu() {
    # first time in 2.0: set things up
    [[ -f $CONFIG_DIR/.setup-done ]] || cmd_setup

    local line cmd word answer
    local -a args=()
    while true; do
        line=$(menu_pick) || break
        cmd=${line#*$'\t'}
        [[ $cmd == __quit || -z $cmd ]] && break

        # fill in {placeholders} by asking
        args=()
        for word in $cmd; do
            if [[ $word == \{*\} ]]; then
                word=${word#\{}; word=${word%\}}
                answer=$(prompt "$(t "${word^}")")
                [[ -n $answer ]] || { args=(); break; }
                args+=("$answer")
            else
                args+=("$word")
            fi
        done
        # nothing typed: back to the menu (or stop, if nobody can type)
        if (( ! ${#args[@]} )); then
            has_tty || break
            continue
        fi

        printf '\n%s$ cmaal %s%s\n' "$C_DIM" "${args[*]}" "$C_RESET"
        "$CMAAL_BIN" "${args[@]}"

        # nobody at the keyboard (tests, pipes): one round is enough
        has_tty || break
        printf '\n%s' "$(t 'Press Enter for the menu (q to quit) ')" >/dev/tty
        read -r answer </dev/tty || break
        [[ $answer == [qQ] ]] && break
    done
}
