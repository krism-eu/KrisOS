# KrisOS quick bootc-installer path

This is the low-effort alternative to the Anaconda ISO while the existing K1
ISO path remains available as a fallback.

It uses the actively maintained `tuna-os/bootc-installer` Flatpak and its
Fisherman backend. The bundle pinned here was published on 2026-09-25 and
contains Fisherman commit
`60f672ff376f079dd88b66d3058aed32bedfdc3d`.

The profile keeps KrisOS on the normal Fedora/OSTree GRUB path:

- source image: the current validated KrisOS payload by default;
- target image: the same reference unless `KRISOS_TARGET_REF` is supplied;
- ext4 root;
- GRUB2;
- SELinux enabled;
- Fisherman composefs-native mode disabled;
- user creation enabled.

From a Fedora live session:

```bash
bash installer-fisherman/run.sh
```

To point it at another published KrisOS build:

```bash
KRISOS_IMAGE=ghcr.io/krism-eu/krisos:<commit> \
KRISOS_TARGET_REF=ghcr.io/krism-eu/krisos:<update-tag> \
bash installer-fisherman/run.sh
```

The script verifies the exact installer Flatpak SHA256 before installing it and
writes only KrisOS-specific configuration under `/etc/bootc-installer/`.

## Storage caveat

The stock Fisherman graphical whole-disk path currently owns its standard GRUB
layout (EFI + /boot + root). Fisherman's backend already supports
`customMounts`, including a separate ext4 `/home`, but the stock GUI does
not expose that layout as a simple switch. Therefore this quick path gets a
working KrisOS installer with minimal integration effort; the existing Anaconda
ISO remains the fallback when a physically separate `/home` is mandatory.

Do not add KrisOS SELinux workarounds to Fisherman. Current Fisherman already
creates bootc user homes with a first-boot tmpfiles rule and restores their
SELinux labels under the live target policy.
