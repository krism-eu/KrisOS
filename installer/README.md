# KrisOS Fedora 45 installer

This directory contains the minimal installer path for KrisOS.

## Goals

- Fedora 45 Anaconda runtime, independent from the installed KrisOS payload.
- `bootc-generic-iso`, not the legacy `anaconda-iso` path.
- Exact validated KrisOS bootc payload embedded in the ISO, while Anaconda storage and user setup remain interactive.
- No destructive automatic partitioning.
- Manual ext4 layout with separate `/var/home` supported by Fedora 45 Anaconda.
- Manual user creation: the intended desktop user must be marked as administrator (wheel); no account credentials or autologin are baked into the image.
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

The build pins the exact validated KrisOS payload reference into Anaconda's interactive defaults and embeds that same container in the ISO. This avoids a network dependency during installation while keeping partitioning and user creation manual.

## GitHub generation

Installer-related pull requests run the `Build Installer ISO` workflow automatically for pre-merge validation. On `main`, the same workflow can be launched manually with `workflow_dispatch`. In both cases it invokes the same `installer/build-installer.sh` used locally; successful runs verify and upload the generated ISO plus `SHA256SUMS` as a GitHub Actions artifact.

This workflow generates installer media only. It does not publish or replace the KrisOS bootc payload image.

## Installation layout

Do not use automatic partition clearing while validating the installer. In Anaconda storage configuration, use the existing/free disk space and assign:

- EFI System Partition -> `/boot/efi` (vfat)
- dedicated ext4 partition -> `/boot`
- dedicated ext4 partition -> `/`
- dedicated ext4 partition -> `/var/home`

Do not select automatic storage, automatic partition clearing, LVM autopartitioning, or a swap partition for the K1.0 validation install.

`/var/home` is intentional: KrisOS exposes `/home` as a symlink to `/var/home`, matching bootc/OSTree conventions.

No swap partition is required; KrisOS uses zram.

## User creation

Keep user creation interactive in Anaconda. For the K1.0 physical validation:

- create the intended desktop account manually;
- enable the Anaconda **administrator** option so the account is a member of `wheel`;
- do not enable automatic login;
- do not bake a password, password hash, or user-specific secret into the installer image.

KrisOS sets the image-level `useradd` default home root to `/var/home` and rebuilds the SELinux homedir policy before Anaconda creates users. The installed-system validation checks both `wheel` membership and the real `/var/home/<user>` SELinux label.

## Disk discovery policy

The ISO boot entry currently adds:

- `inst.wait_for_disks=0`
- `inst.noibft`

This removes Anaconda's extra wait and avoids iBFT probing. We intentionally do **not** disable multipath, mdraid, LVM, USB, device-mapper, or generic block probing yet. Fedora 45 must first be measured on the physical validation machine; only a confirmed slow subsystem should be disabled.

## Installer interaction contract

The ISO starts the normal graphical Anaconda flow. It does **not** provide
`clearpart`, `autopart`, `part`, `user`, `rootpw`, `reboot` or
`shutdown` directives, and the boot entry does not use `inst.ks=`,
`inst.cmdline` or `inst.noninteractive`.

Only the bootc payload source/target is preselected. Storage, formatting and
desktop-user creation remain explicit installer choices. The payload container
is embedded by Image Builder through `--bootc-installer-payload-ref`; this
option is used with the recommended `bootc-generic-iso` image type and does
not select the historical `bootc-installer` image type.

## Security note

The ISO boot entry does not pass `selinux=` or `enforcing=`. Anaconda's installation environment keeps SELinux enabled and runs it permissive by default, so the live graphical installer is not forced into enforcing mode.

The interactive Anaconda defaults explicitly contain `selinux --enforcing` for the installed system. The embedded KrisOS payload also carries `SELINUX=enforcing` in `/etc/selinux/config`. Post-install validation must confirm `getenforce == Enforcing` and that the installed kernel command line contains neither `selinux=0` nor `enforcing=0`.

`SHA256SUMS` detects corruption or accidental changes to a downloaded installer artifact. It is not a replacement for a future signed-release policy such as Cosign.
