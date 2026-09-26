# Publishing cmaal on the AUR

`cmaal-git/` holds the AUR package. Once it's published, anyone can install cmaal with:

```bash
yay -S cmaal-git
```

and it updates together with the rest of the system on `cmaal -Syu`.

## First time (about 5 minutes)

1. Create an account on https://aur.archlinux.org (Register, top right).
2. If you don't have an SSH key yet: `cmaal ssh keygen`
3. Copy your public key: `cat ~/.ssh/id_ed25519.pub`
4. Paste it into the AUR: My Account → SSH Public Key → Update.
5. Test it: `ssh aur@aur.archlinux.org help` should print a help text.
6. From the cmaal repository run:

   ```bash
   ./packaging/aur/publish.sh
   ```

## Later

A `-git` package always builds the newest commit, so normal releases need no AUR update at all. Run `publish.sh` again only when the PKGBUILD itself changes (new dependencies, for example). It checks `.SRCINFO` and only pushes when something changed.

## Two packages, one program

- `cmaal` is what `install.sh` builds (from `packaging/PKGBUILD`).
- `cmaal-git` is the AUR package (from `packaging/aur/cmaal-git/PKGBUILD`).

They install the same files, so they conflict with each other. Pick one. `cmaal self-update` knows which one you have.
