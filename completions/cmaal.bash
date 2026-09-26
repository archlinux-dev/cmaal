# bash completion for cmaal

_cmaal() {
    local cur=${COMP_WORDS[COMP_CWORD]}
    local first=${COMP_WORDS[1]:-}
    local cmds="-S -Ss -Si -Sy -Syu -Syyu -R -Rns -Q -Qi -Ql -Qs
        install search remove upgrade ssh clean mirrors news history owns big sys
        undo downgrade snapshot fix pkglist services logs ports ip theme weather fetch
        updates why files provides pkgbuild hold unhold holds orphans kernel disk whatsnew
        doctor helper config self-update uninstall help version --help --version"

    if (( COMP_CWORD == 1 )); then
        mapfile -t COMPREPLY < <(compgen -W "$cmds" -- "$cur")
        return
    fi

    case $first in
        -S|-Si|-Sy|install)
            mapfile -t COMPREPLY < <(compgen -W "$(pacman -Slq 2>/dev/null)" -- "$cur") ;;
        -R*|-Q*|remove|downgrade|why|files|hold)
            mapfile -t COMPREPLY < <(compgen -W "$(pacman -Qq 2>/dev/null)" -- "$cur") ;;
        ssh)
            local hosts=""
            [[ -f ~/.ssh/config ]] && hosts=$(awk 'tolower($1) == "host" { for (i = 2; i <= NF; i++) if ($i !~ /[*?!]/) print $i }' ~/.ssh/config)
            if (( COMP_CWORD == 2 )); then
                mapfile -t COMPREPLY < <(compgen -W "-t ls add rm edit keygen keys copy test server help $hosts" -- "$cur")
            else
                case ${COMP_WORDS[2]} in
                    server) mapfile -t COMPREPLY < <(compgen -W "on off status" -- "$cur") ;;
                    rm|copy|test) mapfile -t COMPREPLY < <(compgen -W "$hosts" -- "$cur") ;;
                esac
            fi
            ;;
        owns) mapfile -t COMPREPLY < <(compgen -c -- "$cur") ;;
        pkgbuild) mapfile -t COMPREPLY < <(compgen -W "$(pacman -Slq 2>/dev/null)" -- "$cur") ;;
        unhold) mapfile -t COMPREPLY < <(compgen -W "$(pacman-conf IgnorePkg 2>/dev/null)" -- "$cur") ;;
        orphans) mapfile -t COMPREPLY < <(compgen -W "rm" -- "$cur") ;;
        whatsnew) mapfile -t COMPREPLY < <(compgen -W "all" -- "$cur") ;;
        help) mapfile -t COMPREPLY < <(compgen -W "packages rollback system ssh fun" -- "$cur") ;;
        snapshot) mapfile -t COMPREPLY < <(compgen -W "list create restore" -- "$cur") ;;
        pkglist)
            if (( COMP_CWORD == 2 )); then
                mapfile -t COMPREPLY < <(compgen -W "export import" -- "$cur")
            else
                mapfile -t COMPREPLY < <(compgen -f -- "$cur")
            fi
            ;;
        services|logs)
            if (( COMP_CWORD == 2 )); then
                local extra="--user"
                [[ $first == logs ]] && extra="prev -f"
                mapfile -t COMPREPLY < <(compgen -W "$extra $(systemctl list-unit-files --type=service --no-legend 2>/dev/null | awk '{ sub(/\.service$/, "", $1); print $1 }')" -- "$cur")
            elif [[ $first == services ]]; then
                mapfile -t COMPREPLY < <(compgen -W "status start stop restart enable disable logs" -- "$cur")
            fi
            ;;
        helper) mapfile -t COMPREPLY < <(compgen -W "status install yay paru" -- "$cur") ;;
        config) mapfile -t COMPREPLY < <(compgen -W "edit show path reset" -- "$cur") ;;
        self-update) mapfile -t COMPREPLY < <(compgen -W "--force" -- "$cur") ;;
    esac
}
complete -F _cmaal cmaal
