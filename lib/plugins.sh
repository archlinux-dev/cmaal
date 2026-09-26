# shellcheck shell=bash
# cmaal: plugins, your own commands in ~/.config/cmaal/plugins
# Part of cmaal, sourced by /usr/bin/cmaal. https://github.com/archlinux-dev/cmaal
#
# A plugin is a bash file <name>.sh that defines plugin_<name>. It becomes
# `cmaal <name>`. Dashes in the name turn into underscores in the function:
# hello-world.sh -> plugin_hello_world -> `cmaal hello-world`.
#
# Optional in the file:
#   PLUGIN_DESC="one line for `cmaal plugins` and the help"
#   cmaal_on pre_upgrade  my_function     run before cmaal -Syu
#   cmaal_on post_upgrade my_function     run after cmaal -Syu
#   cmaal_on post_install my_function     run after cmaal -S (gets the names)
#
# Plugins can use every cmaal helper: msg, ok, warn, ask, as_root, have, ...

PLUGIN_DIRS=("$CONFIG_DIR/plugins" "$CMAAL_SHARE/plugins")
declare -gA _PLUGIN_FILE=() _PLUGIN_DESC=()
_HOOKS=()

cmaal_on() {
    local event=$1 fn=$2
    case $event in
        pre_upgrade|post_upgrade|post_install) _HOOKS+=("$event:$fn") ;;
        *) warn "plugin hook '$event' does not exist (pre_upgrade, post_upgrade, post_install)" ;;
    esac
}

run_hooks() {
    local event=$1 h
    shift
    for h in "${_HOOKS[@]}"; do
        [[ ${h%%:*} == "$event" ]] || continue
        "${h#*:}" "$@" || warn "plugin hook ${h#*:} ($event) failed"
    done
    return 0
}

load_plugins() {
    local dir f name fn
    for dir in "${PLUGIN_DIRS[@]}"; do
        [[ -d $dir ]] || continue
        for f in "$dir"/*.sh; do
            [[ -f $f ]] || continue
            name=$(basename "$f" .sh)
            [[ -n ${_PLUGIN_FILE[$name]+x} ]] && continue   # the user's copy wins
            # a plugin with a syntax error must not take cmaal down with it
            if ! bash -n "$f" 2>/dev/null; then
                warn "skipping plugin $f (syntax error, check it with: bash -n $f)"
                continue
            fi
            PLUGIN_DESC=""
            # shellcheck source=/dev/null
            source "$f" || { warn "plugin $f failed to load"; continue; }
            fn="plugin_${name//-/_}"
            if ! declare -F "$fn" >/dev/null; then
                warn "plugin $f does not define $fn(), skipping it"
                continue
            fi
            _PLUGIN_FILE[$name]=$f
            _PLUGIN_DESC[$name]=$PLUGIN_DESC
        done
    done
    unset PLUGIN_DESC
}

# run_plugin name args... ; returns 127 when there is no such plugin
run_plugin() {
    local name=$1
    shift
    [[ -n ${_PLUGIN_FILE[$name]+x} ]] || return 127
    "plugin_${name//-/_}" "$@"
}

plugin_help_lines() {
    local name
    for name in $(printf '%s\n' "${!_PLUGIN_FILE[@]}" | sort); do
        printf '  cmaal %-20s %s\n' "$name" "${_PLUGIN_DESC[$name]:-$(t "(plugin)")}"
    done
}

cmd_plugins() {
    local sub=${1:-list} name=${2:-} file
    case $sub in
        list|ls)
            if (( ! ${#_PLUGIN_FILE[@]} )); then
                msg "No plugins yet. Make one with: cmaal plugins new <name>"
                return 0
            fi
            section "Plugins"
            for name in $(printf '%s\n' "${!_PLUGIN_FILE[@]}" | sort); do
                printf '   %s%-20s%s %s\n      %s%s%s\n' "$C_CYAN$C_BOLD" "$name" "$C_RESET" \
                    "${_PLUGIN_DESC[$name]}" "$C_DIM" "${_PLUGIN_FILE[$name]}" "$C_RESET"
            done
            ;;
        new|create)
            [[ $name =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "usage: cmaal plugins new <name>  (lowercase letters, digits and -)"
            if is_builtin_command "$name"; then
                die "'$name' is already a cmaal command, pick another name"
            fi
            file="$CONFIG_DIR/plugins/$name.sh"
            [[ -e $file ]] && die "$file already exists (cmaal plugins edit $name)"
            mkdir -p "$CONFIG_DIR/plugins"
            cat >"$file" <<EOF
# cmaal plugin: $name
# Run it with: cmaal $name [arguments]
# All cmaal helpers work here: msg, ok, warn, die, ask, as_root, have, section

PLUGIN_DESC="what $name does, in one line"

plugin_${name//-/_}() {
    section "Hello from $name"
    msg "You passed: \$*"
    # Example: open a program, run a script, anything bash can do
}

# Optional: run something after every cmaal -Syu
# ${name//-/_}_after_upgrade() { ok "system upgraded, $name says hi"; }
# cmaal_on post_upgrade ${name//-/_}_after_upgrade
EOF
            ok "created $file"
            msg "Edit it with: cmaal plugins edit $name   then run: cmaal $name"
            ;;
        edit)
            [[ -n $name ]] || die "usage: cmaal plugins edit <name>"
            file=${_PLUGIN_FILE[$name]:-$CONFIG_DIR/plugins/$name.sh}
            [[ -e $file ]] || die "no plugin named $name"
            "${EDITOR:-nano}" "$file"
            ;;
        rm|remove)
            [[ -n $name ]] || die "usage: cmaal plugins rm <name>"
            file="$CONFIG_DIR/plugins/$name.sh"
            [[ -e $file ]] || die "no plugin named $name in $CONFIG_DIR/plugins"
            ask "Delete $file?" n || return 1
            rm -f -- "$file" && ok "removed $name"
            ;;
        dir|path) printf '%s\n' "$CONFIG_DIR/plugins" ;;
        *) die "usage: cmaal plugins [list|new|edit|rm|dir] [name]" ;;
    esac
}
