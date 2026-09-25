# KrisOS quick bootc-installer path

This is the low-effort alternative to the Anaconda ISO while the existing K1
ISO remains available as a fallback.

It uses the actively maintained `tuna-os/bootc-installer` Flatpak and its
Fisherman backend. The pinned bundle contains Fisherman commit
`60f672ff376f079dd88b66d3058aed32bedfdc3d`.

## Existing-partition install

`run.sh` is deliberately wired to Fisherman's `customMounts` path. It does
not hand a whole disk to Fisherman and therefore does not run Fisherman's
automatic repartitioning code.

From a Fedora live session:

```bash
bash installer-fisherman/run.sh
```

The script shows `lsblk` and asks for exactly four existing partitions:

- KrisOS root: formatted ext4;
- KrisOS `/boot`: formatted ext4;
- an existing FAT EFI System Partition: reused without formatting;
- KrisOS `/home`: formatted ext4.

All four selections must be distinct and unmounted. The script prints an
explicit destructive summary and requires `INSTALL KRISOS` before Fisherman
is started.

It then asks for the desktop username/full name/password, creates a private
autoinstall recipe and launches:

```text
bootc-installer --autoinstall <recipe>
```

The recipe contains non-empty `customMounts`, so Fisherman skips its
whole-disk partitioner and formats/mounts only the listed partitions.

The profile keeps KrisOS on the current Fedora/OSTree GRUB path:

- source image: validated KrisOS payload #118 by default;
- target image: same reference unless `KRISOS_TARGET_REF` is supplied;
- ext4 root, `/boot`, and separate `/home`;
- existing ESP preserved;
- GRUB2;
- SELinux enabled;
- composefs-native/Dakota backend disabled;
- experimental unified storage disabled;
- user added to `wheel`.

To point it at another published KrisOS image:

```bash
KRISOS_IMAGE=ghcr.io/krism-eu/krisos:<commit> \
KRISOS_TARGET_REF=ghcr.io/krism-eu/krisos:<update-tag> \
bash installer-fisherman/run.sh
```

Do not add the old KrisOS Anaconda home-label workaround here. Current
Fisherman already has bootc-aware first-boot handling for user home ownership
and SELinux labels.
