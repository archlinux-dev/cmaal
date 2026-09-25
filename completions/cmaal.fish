# fish completion for cmaal

function __cmaal_hosts
    test -f ~/.ssh/config; and awk 'tolower($1) == "host" { for (i = 2; i <= NF; i++) if ($i !~ /[*?!]/) print $i }' ~/.ssh/config
end

set -l cmds -S -Ss -Si -Syu -Syyu -Rns install search remove upgrade ssh clean mirrors news history owns big sys doctor helper config self-update uninstall help undo downgrade snapshot fix pkglist services logs ports ip theme weather fetch

complete -c cmaal -f
complete -c cmaal -n "not __fish_seen_subcommand_from $cmds" -a "-S" -d "install from repos, AUR or flatpak"
complete -c cmaal -n "not __fish_seen_subcommand_from $cmds" -a "-Ss" -d "search repos, AUR and flatpak"
complete -c cmaal -n "not __fish_seen_subcommand_from $cmds" -a "-Si" -d "package info"
complete -c cmaal -n "not __fish_seen_subcommand_from $cmds" -a "-Syu" -d "upgrade everything"
complete -c cmaal -n "not __fish_seen_subcommand_from $cmds" -a "-Syyu" -d "upgrade, force db refresh"
complete -c cmaal -n "not __fish_seen_subcommand_from $cmds" -a "-Rns" -d "remove package"
complete -c cmaal -n "not __fish_seen_subcommand_from $cmds" -a "install search remove upgrade" -d "package command"
complete -c cmaal -n "not __fish_seen_subcommand_from $cmds" -a "ssh" -d "ssh hosts and keys"
complete -c cmaal -n "not __fish_seen_subcommand_from $cmds" -a "clean" -d "remove orphans, trim caches"
complete -c cmaal -n "not __fish_seen_subcommand_from $cmds" -a "mirrors" -d "rank mirrors"
complete -c cmaal -n "not __fish_seen_subcommand_from $cmds" -a "news" -d "Arch news"
complete -c cmaal -n "not __fish_seen_subcommand_from $cmds" -a "history" -d "recent package changes"
complete -c cmaal -n "not __fish_seen_subcommand_from $cmds" -a "owns" -d "which package owns a command"
complete -c cmaal -n "not __fish_seen_subcommand_from $cmds" -a "big" -d "largest packages"
complete -c cmaal -n "not __fish_seen_subcommand_from $cmds" -a "sys" -d "system overview"
complete -c cmaal -n "not __fish_seen_subcommand_from $cmds" -a "doctor" -d "health check"
complete -c cmaal -n "not __fish_seen_subcommand_from $cmds" -a "helper" -d "AUR helper"
complete -c cmaal -n "not __fish_seen_subcommand_from $cmds" -a "config" -d "edit config"
complete -c cmaal -n "not __fish_seen_subcommand_from $cmds" -a "self-update" -d "update cmaal"
complete -c cmaal -n "not __fish_seen_subcommand_from $cmds" -a "uninstall" -d "remove cmaal"

complete -c cmaal -n "not __fish_seen_subcommand_from $cmds" -a "undo" -d "revert the last pacman transaction"
complete -c cmaal -n "not __fish_seen_subcommand_from $cmds" -a "downgrade" -d "go back to an older version"
complete -c cmaal -n "not __fish_seen_subcommand_from $cmds" -a "snapshot" -d "snapper/timeshift snapshots"
complete -c cmaal -n "not __fish_seen_subcommand_from $cmds" -a "fix" -d "fix common pacman problems"
complete -c cmaal -n "not __fish_seen_subcommand_from $cmds" -a "pkglist" -d "export/import all packages"
complete -c cmaal -n "not __fish_seen_subcommand_from $cmds" -a "services" -d "manage systemd services"
complete -c cmaal -n "not __fish_seen_subcommand_from $cmds" -a "logs" -d "errors from the journal"
complete -c cmaal -n "not __fish_seen_subcommand_from $cmds" -a "ports" -d "listening ports"
complete -c cmaal -n "not __fish_seen_subcommand_from $cmds" -a "ip" -d "local and public IP"
complete -c cmaal -n "not __fish_seen_subcommand_from $cmds" -a "theme" -d "change kitty theme"
complete -c cmaal -n "not __fish_seen_subcommand_from $cmds" -a "weather" -d "weather forecast"
complete -c cmaal -n "not __fish_seen_subcommand_from $cmds" -a "fetch" -d "system info with Arch logo"

complete -c cmaal -n "__fish_seen_subcommand_from -S -Si install" -a "(pacman -Slq 2>/dev/null)"
complete -c cmaal -n "__fish_seen_subcommand_from -Rns remove downgrade" -a "(pacman -Qq 2>/dev/null)"
complete -c cmaal -n "__fish_seen_subcommand_from ssh" -a "-t ls add rm edit keygen keys copy test server (__cmaal_hosts)"
complete -c cmaal -n "__fish_seen_subcommand_from owns" -a "(__fish_complete_command)"
complete -c cmaal -n "__fish_seen_subcommand_from helper" -a "status install yay paru"
complete -c cmaal -n "__fish_seen_subcommand_from config" -a "edit show path reset"
complete -c cmaal -n "__fish_seen_subcommand_from snapshot" -a "list create restore"
complete -c cmaal -n "__fish_seen_subcommand_from pkglist" -a "export import" -F
complete -c cmaal -n "__fish_seen_subcommand_from services" -a "--user status start stop restart enable disable logs"
complete -c cmaal -n "__fish_seen_subcommand_from logs" -a "prev -f"
