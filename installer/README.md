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

The local installer build requires only `podman`. Image Builder itself runs from the official container image so local and GitHub Actions builds use the same path.

Build the generic installer ISO with:

```text
bash installer/build-installer.sh
```

The script:

1. builds the Fedora 45 installer runtime;
2. runs the containerized Image Builder;
3. creates a `bootc-generic-iso` below `installer/output/`;
4. writes `installer/output/SHA256SUMS` for every generated artifact.

By default the builder image is `ghcr.io/osbuild/image-builder-cli:latest`. It can be overridden explicitly for compatibility testing or pinning:

```text
IMAGE_BUILDER_IMAGE=ghcr.io/osbuild/image-builder-cli:TAG bash installer/build-installer.sh
```

No KrisOS payload image URL is embedded in the ISO.

## GitHub generation

Installer-related pull requests run the `Build Installer ISO` workflow automatically for pre-merge validation. On `main`, the same workflow can be launched manually with `workflow_dispatch`. In both cases it invokes the same `installer/build-installer.sh` used locally; successful runs verify and upload the generated ISO plus `SHA256SUMS` as a GitHub Actions artifact.

This workflow generates installer media only. It does not publish or replace the KrisOS bootc payload image.

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

The remote Kickstart should set both the installation source and the update target:

```text
bootc --source-imgref=registry:REGISTRY/IMAGE:TAG --target-imgref=REGISTRY/IMAGE:TAG
```

`--source-imgref` requires the transport prefix (`registry:`). `--target-imgref` deliberately does not use that prefix and becomes the reference used by the installed system for subsequent bootc updates.

This is the V1 mechanism for selecting the bootc URL; no custom Anaconda UI is added.

## Security note

The live installer keeps SELinux enabled and permissive with `selinux=1 enforcing=0`. Interactive defaults require `selinux --enforcing` for the installed system. The main installer is the historical remote-Kickstart path, not the validated K1 offline ISO; use the installer branch for that ISO.

`SHA256SUMS` detects corruption or accidental changes to a downloaded installer artifact. It is not a replacement for a future signed-release policy such as Cosign.
