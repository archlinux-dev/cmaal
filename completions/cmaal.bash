# bash completion for cmaal

_cmaal() {
    local cur=${COMP_WORDS[COMP_CWORD]}
    local first=${COMP_WORDS[1]:-}
    local cmds="-S -Ss -Si -Sy -Syu -Syyu -R -Rns -Q -Qi -Ql -Qs
        install search remove upgrade ssh clean mirrors news history owns big sys
        doctor helper config self-update uninstall help version --help --version"

    if (( COMP_CWORD == 1 )); then
        mapfile -t COMPREPLY < <(compgen -W "$cmds" -- "$cur")
        return
    fi

    case $first in
        -S|-Si|-Sy|install)
            mapfile -t COMPREPLY < <(compgen -W "$(pacman -Slq 2>/dev/null)" -- "$cur") ;;
        -R*|-Q*|remove)
            mapfile -t COMPREPLY < <(compgen -W "$(pacman -Qq 2>/dev/null)" -- "$cur") ;;
        ssh)
            local hosts=""
            [[ -f ~/.ssh/config ]] && hosts=$(awk 'tolower($1) == "host" { for (i = 2; i <= NF; i++) if ($i !~ /[*?!]/) print $i }' ~/.ssh/config)
            if (( COMP_CWORD == 2 )); then
                mapfile -t COMPREPLY < <(compgen -W "ls add rm edit keygen keys copy test server help $hosts" -- "$cur")
            else
                case ${COMP_WORDS[2]} in
                    server) mapfile -t COMPREPLY < <(compgen -W "on off status" -- "$cur") ;;
                    rm|copy|test) mapfile -t COMPREPLY < <(compgen -W "$hosts" -- "$cur") ;;
                esac
            fi
            ;;
        owns) mapfile -t COMPREPLY < <(compgen -c -- "$cur") ;;
        helper) mapfile -t COMPREPLY < <(compgen -W "status install yay paru" -- "$cur") ;;
        config) mapfile -t COMPREPLY < <(compgen -W "edit show path reset" -- "$cur") ;;
        self-update) mapfile -t COMPREPLY < <(compgen -W "--force" -- "$cur") ;;
    esac
}
complete -F _cmaal cmaal
