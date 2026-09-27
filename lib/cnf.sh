# shellcheck shell=bash
# cmaal: "command not found" helper for bash, zsh and fish
# Part of cmaal, sourced by /usr/bin/cmaal. https://github.com/archlinux-dev/cmaal
#
# Type a program you don't have and the shell tells you which package has it:
#   $ htop
#   htop: command not found
#     It's in the package extra/htop. Install it with: cmaal -S htop

CNF_BEGIN="# >>> cmaal command-not-found >>>"
CNF_END="# <<< cmaal command-not-found <<<"
CNF_FISH="${XDG_CONFIG_HOME:-$HOME/.config}/fish/conf.d/cmaal-cnf.fish"

# the lookup the shells call; must be quick and never ask anything
cmd_cnf_lookup() {
    local name=${1:-} out pkgs
    [[ -n $name ]] || return 127
    printf '%s: %s\n' "$name" "$(t 'command not found')" >&2
    if ! compgen -G "$PACMAN_SYNC/*.files" >/dev/null; then
        printf '  %s\n' "$(tf 'Find the package once with: cmaal provides %s' "$name")" >&2
        return 127
    fi
    out=$(pacman -F -- "usr/bin/$name" 2>/dev/null)
    [[ -n $out ]] || return 127
    # lines like "extra/htop 3.3.0-1" (plus the file lines, indented)
    pkgs=$(awk '/^[^ ]/ { print $1 }' <<<"$out" | head -n 3)
    if [[ $(grep -c . <<<"$pkgs") == 1 ]]; then
        printf '  %s\n' "$(tf "It's in the package %s. Install it with: cmaal -S %s" "$pkgs" "${pkgs#*/}")" >&2
    else
        printf '  %s\n' "$(t 'These packages have it:')" >&2
        local p
        while read -r p; do printf '    cmaal -S %s\n' "${p#*/}" >&2; done <<<"$pkgs"
    fi
    return 127
}

cnf_rc_files() {
    [[ -f $HOME/.bashrc || ${SHELL##*/} == bash ]] && printf '%s\n' "$HOME/.bashrc"
    [[ -f $HOME/.zshrc || ${SHELL##*/} == zsh ]] && printf '%s\n' "$HOME/.zshrc"
    return 0
}

cnf_strip() {
    local f=$1
    [[ -f $f ]] || return 0
    awk -v b="$CNF_BEGIN" -v e="$CNF_END" '$0 == b { skip = 1; next } $0 == e { skip = 0; next } !skip' "$f" >"$f.cmaal-tmp" \
        && cat "$f.cmaal-tmp" >"$f" && rm -f "$f.cmaal-tmp"
}

# The hooks below are written into your shell's rc file, so "$1" and
# $argv must stay literal there.
# shellcheck disable=SC2016
cmd_cnf() {
    local f bin=$CMAAL_BIN
    case ${1:-status} in
        install|on)
            while IFS= read -r f; do
                cnf_strip "$f"
                case $f in
                    *bashrc) {
                        printf '%s\n' "$CNF_BEGIN"
                        printf 'command_not_found_handle() {\n    [ -x %q ] && %q __cnf "$1"\n    return 127\n}\n' "$bin" "$bin"
                        printf '%s\n' "$CNF_END"
                    } >>"$f" ;;
                    *zshrc) {
                        printf '%s\n' "$CNF_BEGIN"
                        printf 'command_not_found_handler() {\n    [ -x %q ] && %q __cnf "$1"\n    return 127\n}\n' "$bin" "$bin"
                        printf '%s\n' "$CNF_END"
                    } >>"$f" ;;
                esac
                ok "$(tf 'added to %s' "$f")"
            done < <(cnf_rc_files)
            if have fish || [[ -d $(dirname "$CNF_FISH") || ${SHELL##*/} == fish ]]; then
                mkdir -p "$(dirname "$CNF_FISH")"
                printf 'function fish_command_not_found\n    test -x %q; and %q __cnf $argv[1]\nend\n' "$bin" "$bin" >"$CNF_FISH"
                ok "$(tf 'added to %s' "$CNF_FISH")"
            fi
            # the lookup needs pacman's file database
            if have pacman && ! compgen -G "$PACMAN_SYNC/*.files" >/dev/null; then
                ensure_files_db || true
            fi
            msg "Open a new terminal to use it."
            ;;
        remove|off|uninstall)
            while IFS= read -r f; do cnf_strip "$f"; done < <(cnf_rc_files)
            rm -f -- "$CNF_FISH"
            ok "command-not-found helper removed"
            ;;
        status|"")
            local any=""
            while IFS= read -r f; do
                if grep -qF "$CNF_BEGIN" "$f" 2>/dev/null; then ok "$(tf 'active in %s' "$f")"; any=1; fi
            done < <(cnf_rc_files)
            [[ -f $CNF_FISH ]] && { ok "$(tf 'active in %s' "$CNF_FISH")"; any=1; }
            [[ -n $any ]] || msg "Off. Turn it on with: cmaal cnf install"
            ;;
        *) die "usage: cmaal cnf [install|remove|status]" ;;
    esac
}
