# KrisOS release validation

KrisOS uses a deliberately small end-to-end release check instead of reproducing a full openQA installation.

The normal release path is the bootc image from `main`. The ISO is a secondary installation/recovery path and must converge on the same payload and runtime invariants.

## Runtime check

`tests/release-check.sh` runs on a booted KrisOS system. It reuses `tests/boot-check.sh` and additionally verifies:

- bootc status is readable as JSON;
- the expected image reference is present when `KRISOS_EXPECT_IMAGE` is set;
- krisCC is installed, verifies cleanly and matches the immutable owned-package snapshots;
- the expected krisCC EVRA is present when `KRISOS_EXPECT_KRISCC` is set;
- `krisos-sync.timer` is enabled and active;
- `rk status` succeeds;
- krisCC passes the same offscreen runtime smoke used by CI.

The `prepare-reboot` and `verify-reboot` modes write a temporary sentinel through the live `/usr` overlay, reboot, verify that the same-deployment overlay persisted, and remove the sentinel.

## VM harness

`tests/run-release-vm.sh` drives an already-installed disposable KrisOS VM over SSH. It can optionally switch that VM to an immutable bootc candidate before running the common checks.

Example:

```bash
export KRISOS_E2E_TARGET=qa@192.0.2.10
export KRISOS_E2E_SWITCH_IMAGE=ghcr.io/krism-eu/krisos:<immutable-commit>
export KRISOS_EXPECT_IMAGE="$KRISOS_E2E_SWITCH_IMAGE"
export KRISOS_EXPECT_KRISCC=0.5.1-7.fc44.x86_64
tests/run-release-vm.sh
```

The VM must be disposable and the SSH user must have non-interactive sudo. The harness intentionally does not automate Anaconda or partitioning.

## ISO coherence

The installer ISO should embed the exact immutable payload already validated from `main`, rather than rebuilding a second payload from installer-branch sources. After an ISO installation, run the same `release-check.sh`; this keeps the update and installation paths comparable without maintaining two separate QA systems.
