# KrisOS release validation

KrisOS uses a deliberately small end-to-end release check instead of reproducing a full openQA installation.

The normal release path is the bootc image from `main`. krisCC 0.6.0-1 and the validated K1 runtime fixes are now promoted to `main`. The final installer branch consumes the exact signed immutable main commit `ccb73fe74faf92d7102fcb24c3526b791ff83590` at digest `sha256:3419f8d0834cb7f3b99d09444f7e3666a670477d94ae1aebdcad1b59963d2275`; it never rebuilds a separate payload and never relies on the mutable `m1` tag.

## Runtime check

`tests/release-check.sh` runs on a booted KrisOS system. It reuses `tests/boot-check.sh` and additionally verifies:

- bootc status is readable as JSON;
- the exact expected reference is in `status.booted.image.image.image` when `KRISOS_EXPECT_IMAGE` is set; staged and rollback references cannot satisfy this check;
- krisCC is installed, verifies cleanly and matches the immutable owned-package snapshots;
- the expected krisCC EVRA is present when `KRISOS_EXPECT_KRISCC` is set;
- `krisos-sync.timer` is enabled and active;
- `rk status` reports a ready overlay with neither pending recovery nor needs-sync;
- krisCC passes the same offscreen runtime smoke used by CI;
- the image-level useradd default is `HOME=/var/home` and SELinux resolves user/config/data paths below `/var/home` correctly;
- the canonical initramfs contains AMD early microcode (`AuthenticAMD.bin`);
- when `KRISOS_EXPECT_ADMIN_USER` is set, that Anaconda-created account exists, belongs to `wheel`, resolves below `/var/home`, and has the expected SELinux home label.

The `prepare-reboot` and `verify-reboot` modes write a temporary sentinel through the live `/usr` overlay, reboot, verify that the same-deployment overlay persisted, and remove the sentinel.

## VM harness

`tests/run-release-vm.sh` drives an already-installed disposable KrisOS VM over SSH. It can optionally switch that VM to an immutable bootc candidate before running the common checks.

Example:

```bash
export KRISOS_E2E_TARGET=qa@192.0.2.10
export KRISOS_E2E_SWITCH_IMAGE=ghcr.io/krism-eu/krisos:<immutable-commit>
export KRISOS_EXPECT_IMAGE="$KRISOS_E2E_SWITCH_IMAGE"
export KRISOS_EXPECT_KRISCC=0.6.0-1.fc44.x86_64
tests/run-release-vm.sh
```

The VM must be disposable and the SSH user must have non-interactive sudo. The harness intentionally does not automate Anaconda or partitioning.

## Final K1.0 ISO candidate

The final QA ISO embeds the exact immutable payload already built, published and signed by the `main` Build M1 workflow. The ISO workflow verifies the locked registry manifest digest and Cosign identity before pulling it, then builds Anaconda from that exact local image. The artifact bundle contains the exact main payload and krisCC locks.

Install manually in Fedora 45 Anaconda. Do not use automatic partition clearing or autopartitioning. The validation layout is:

- EFI System Partition: vfat mounted at `/boot/efi`;
- dedicated ext4 `/boot`;
- dedicated ext4 `/`;
- dedicated ext4 `/var/home`;
- no disk swap partition; KrisOS uses zram.

Create the desktop account interactively, enable Anaconda's administrator option so it belongs to `wheel`, do not enable automatic login, and do not bake a password/hash into the image.

After installation, run the bundled `release-check.sh` with the locked main image reference, krisCC EVRA and admin user exported. Then run the reboot sentinel test. Physical QA additionally confirms Plasma login, KWallet behavior, networking, audio/GPU, suspend/resume, rk add/remove/sync/recovery, the krisCC GUI pages, and a recovery boot with `krisos.overlay=off`.

The runtime changes are already promoted to `main`. Physical ISO validation now decides only whether the installer branch is ready to be closed/promoted; it does not gate the direct bootc runtime already published from `main`.

## Corrective source revision

The SSH harness forwards `KRISOS_EXPECT_ADMIN_USER` and includes release-state.py.
All three files boot-check.sh, release-check.sh and release-state.py must remain
together when running the release checks manually.
Component promotion dispatches Build M1 with publish=true; compatibility builds
with base_image overrides remain non-publishing. Runtime fixes require a new
main build, signature, and validated payload lock before they enter an offline ISO.
