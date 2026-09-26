#!/usr/bin/env bash
# Publish or update cmaal-git on the AUR. Run it on your own Arch PC:
#
#   ./packaging/aur/publish.sh
#
# Needs: an AUR account with your SSH public key added
# (https://aur.archlinux.org -> My Account -> SSH Public Key), plus git and
# makepkg. The first run creates the package on the AUR; later runs only
# push when something changed.

set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
pkg="$here/cmaal-git"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

command -v makepkg >/dev/null || { echo "makepkg not found, run this on Arch"; exit 1; }

echo ":: Checking the PKGBUILD builds"
(cd "$pkg" && makepkg --printsrcinfo >"$work/SRCINFO")
cmp -s "$work/SRCINFO" "$pkg/.SRCINFO" || {
    echo ":: .SRCINFO was out of date, updating it"
    cp "$work/SRCINFO" "$pkg/.SRCINFO"
}

echo ":: Cloning the AUR repository (ssh://aur@aur.archlinux.org/cmaal-git.git)"
if ! git clone -q ssh://aur@aur.archlinux.org/cmaal-git.git "$work/aur"; then
    echo "!! Could not reach the AUR over SSH. Is your SSH key added to your AUR account?"
    echo "   Test it with: ssh aur@aur.archlinux.org help"
    exit 1
fi

cp "$pkg/PKGBUILD" "$pkg/.SRCINFO" "$work/aur/"
cd "$work/aur"
git add PKGBUILD .SRCINFO
if git diff --cached --quiet; then
    echo " ok the AUR already has this version, nothing to push"
    exit 0
fi
git commit -q -m "cmaal-git: update $(grep -m1 'pkgver = ' .SRCINFO | cut -d= -f2 | tr -d ' ')"
git push -q origin HEAD:master
echo " ok published: https://aur.archlinux.org/packages/cmaal-git"
echo "    install it anywhere with: yay -S cmaal-git"
