# KrisOS release validation

KrisOS uses a deliberately small end-to-end release check instead of reproducing a full openQA installation.

The normal release path is the bootc image from `main`. The ISO is a secondary installation/recovery path and must converge on the same payload and runtime invariants.

## Runtime check

`tests/release-check.sh` runs on a booted KrisOS system. It reuses `tests/boot-check.sh` and additionally verifies:

- bootc status is readable as JSON;
- the exact expected reference is in `status.booted.image.image.image` when `KRISOS_EXPECT_IMAGE` is set; staged and rollback references cannot satisfy this check;
- krisCC is installed, verifies cleanly and matches the immutable owned-package snapshots;
- the expected krisCC EVRA is present when `KRISOS_EXPECT_KRISCC` is set;
- `krisos-sync.timer` is enabled and active;
- `rk status --json` reports a ready overlay with neither pending recovery nor needs-sync;
- krisCC passes the same offscreen runtime smoke used by CI;
- the image-level useradd default is `HOME=/var/home` and SELinux resolves user/config/data paths below `/var/home`;
- the canonical initramfs contains AMD early microcode (`AuthenticAMD.bin`);
- optional admin-user checks run only when `KRISOS_EXPECT_ADMIN_USER` is explicitly set.

The `prepare-reboot` and `verify-reboot` modes write a temporary sentinel through the live `/usr` overlay, reboot, verify that the same-deployment overlay persisted, and remove the sentinel.

## VM harness

`tests/run-release-vm.sh` drives an already-installed disposable KrisOS VM over SSH. It can optionally switch that VM to an immutable bootc candidate before running the common checks.

Example:

```bash
export KRISOS_E2E_TARGET=qa@192.0.2.10
export KRISOS_E2E_SWITCH_IMAGE=ghcr.io/krism-eu/krisos:<immutable-commit>
export KRISOS_EXPECT_IMAGE="$KRISOS_E2E_SWITCH_IMAGE"
export KRISOS_EXPECT_KRISCC=<version-release.fc44.x86_64>
tests/run-release-vm.sh
```

The VM must be disposable and the SSH user must have non-interactive sudo. The harness intentionally does not automate Anaconda or partitioning.

## ISO coherence

The installer ISO should embed the exact immutable payload already validated from `main`, rather than rebuilding a second payload from installer-branch sources. After an ISO installation, run the same `release-check.sh`; this keeps the update and installation paths comparable without maintaining two separate QA systems.


## Direct bootc main path

`main` remains the primary KrisOS delivery path and publishes the signed bootc image directly to GHCR. It does not create users, repartition disks, or run Anaconda. Existing accounts and storage layout are preserved across bootc updates.

The `/var/home` useradd default and SELinux homedir policy are image defaults for future user creation and installer consistency; they do not rewrite an existing account's passwd entry during an update.

Installer-specific Anaconda, partitioning and ISO build logic stays on the installer branch. Once a main payload is validated and published, installer validation should embed that exact immutable main payload rather than rebuilding a second OS payload.

## krisCC component adoption

krisCC is not polled on a schedule. Updating the component in KrisOS is an explicit operation:

1. run the **Adopt krisCC component** workflow;
2. provide the exact validated release tag, for example `v0.7.0-4`;
3. the workflow verifies the RPM identity and checksum, builds KrisOS with that exact component and runs the integration checks;
4. only after validation does it update `build_files/krisCC.lock` and dispatch the normal KrisOS build.

There is no automatic "latest release" lookup. This keeps the KrisOS image reproducible and prevents a newly published krisCC candidate from entering the OS without an explicit decision.

If component adoption is automated in the future, the trigger should be limited to the single official stable krisCC release stream; the validation and immutable lock remain unchanged.

## Corrective source revision

The SSH harness forwards `KRISOS_EXPECT_ADMIN_USER` and includes release-state.py.
All three files boot-check.sh, release-check.sh and release-state.py must remain
together when running the release checks manually.
Component promotion dispatches Build M1 with publish=true; compatibility builds
with base_image overrides remain non-publishing. Runtime fixes require a new
main build, signature, and validated payload lock before they enter an offline ISO.
