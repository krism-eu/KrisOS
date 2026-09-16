# KrisOS Fedora 45 installer

This directory contains the minimal installer path for KrisOS.

## Goals

- Fedora 45 Anaconda runtime, independent from the installed KrisOS payload.
- `bootc-generic-iso`, not the legacy `anaconda-iso` path.
- Remote bootc payload selected at install time through Kickstart.
- No destructive automatic partitioning.
- Manual ext4 layout with separate `/var/home` supported by Fedora 45 Anaconda.
- Reduce avoidable disk-discovery delay without disabling generic storage discovery.

## Build

The installer build requires `podman` and the current `image-builder` CLI on the host.
Build the generic installer ISO with:

```text
bash installer/build-installer.sh
```

The script builds a Fedora 45 installer runtime and writes the ISO artifacts below `installer/output/`.
No KrisOS image URL is embedded in the ISO.

## Installation layout

Do not use automatic partition clearing while validating the installer. In Anaconda storage configuration, use the existing/free disk space and assign:

- EFI System Partition -> `/boot/efi` (vfat)
- dedicated ext4 partition -> `/boot`
- dedicated ext4 partition -> `/`
- dedicated ext4 partition -> `/var/home`

`/var/home` is intentional: KrisOS exposes `/home` as a symlink to `/var/home`, matching bootc/OSTree conventions.

No swap partition is required; KrisOS uses zram.

## Disk discovery policy

The ISO boot entry currently adds:

- `inst.wait_for_disks=0`
- `inst.noibft`

This removes Anaconda's extra wait and avoids iBFT probing. We intentionally do **not** disable multipath, mdraid, LVM, USB, device-mapper, or generic block probing yet. Fedora 45 must first be measured on the physical validation machine; only a confirmed slow subsystem should be disabled.

## Remote Kickstart / payload URL

To select the image without rebuilding the ISO, boot the ISO, edit the kernel command line, and add a remote Kickstart such as:

```text
inst.ks=https://host.example/krisos.ks
```

The remote Kickstart can contain:

```text
bootc --source-imgref=registry:REGISTRY/IMAGE:TAG
```

This is the V1 mechanism for selecting the bootc URL; no custom Anaconda UI is added.

## Security note

The live installer entry currently uses `selinux=0`, matching the upstream minimal `bootc-generic-iso` Anaconda example. This affects only the disposable installer runtime, not the installed KrisOS system, whose SELinux policy remains enforcing. We can remove this boot argument later if Fedora 45 testing proves the generic installer path works correctly with SELinux enabled.
