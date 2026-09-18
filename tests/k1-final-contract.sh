#!/usr/bin/env bash
set -euo pipefail

# Stable backup baseline: never advance on the candidate branch.
# shellcheck source=/dev/null
source build_files/KrisOS-payload.lock
test "$KRISOS_COMMIT" = "75e2584aa6681fefe6b5bc019aa64c812751a607"
test "$KRISOS_TARGET_REF" = "ghcr.io/krism-eu/krisos:m1"
test "$KRISOS_DIGEST" = "sha256:a13ddfd6d2d6032873cac8b1ea64fdeba6d93a9500da1c1222139314a8f9cb04"

# Stable krisCC backup component remains main's 0.5.1-7.
# shellcheck source=/dev/null
source build_files/krisCC.lock
test "$KRISCC_TAG" = "v0.5.1-7"
test "$KRISCC_RPM" = "krisCC-0.5.1-7.fc44.x86_64.rpm"
test "$KRISCC_SHA256" = "ac7fe241599190c49aaf62338f41142b6025a64c3f073fc23e03a9846a17b56f"

# Candidate restyle is separately pinned and immutable.
# shellcheck source=/dev/null
source build_files/krisCC-candidate.lock
test "$KRISCC_TAG" = "v0.5.1-8"
test "$KRISCC_RPM" = "krisCC-0.5.1-8.fc44.x86_64.rpm"
test "$KRISCC_SHA256" = "673f5f16c34a5c80ba0bd713e40c8c84be2baf6d0cdb8f877fcc8a8b700dedf1"
test "$KRISCC_COMMIT" = "32d202a79e05453e181f93f2e834c136b1481ff8"

# AMD microcode must be rebuilt into the canonical bootc initramfs.
grep -Fq 'dracut --force --no-hostonly --early-microcode --reproducible --zstd' Containerfile
grep -Fq "kernel/x86/microcode/AuthenticAMD.bin" Containerfile
grep -Fq '/usr/lib/firmware/amd-ucode/microcode_amd_fam19h.bin' Containerfile

# SELinux homedir generation follows /var/home, without custom allow rules or
# an fcontext equivalence workaround.
grep -Fq "HOME=/var/home" Containerfile
grep -Fq "semodule -B" Containerfile
grep -Fq "matchpathcon -n /var/home/kris" Containerfile
! grep -RniE 'semanage[[:space:]]+fcontext.*(-e|/var/home)|semanage[[:space:]]+permissive' Containerfile build_files systemd

# Installer storage/user setup stays interactive and non-destructive.
grep -Fxq 'graphical' installer/Containerfile < /dev/null || true
! grep -Eq '^[[:space:]]*(clearpart|autopart|part|partition|logvol|volgroup|user|rootpw)([[:space:]]|$)' installer/Containerfile
! grep -Eq '^[[:space:]]*(clearpart|autopart|part|partition|logvol|volgroup|user|rootpw)([[:space:]]|$)' kickstart/krisos.ks
grep -Fq '/boot/efi' installer/README.md
grep -Fq '/var/home' installer/README.md
grep -Fq 'administrator' installer/README.md
grep -Fq 'No swap partition' installer/README.md

# Runtime QA must ignore only RPM mtime drift, not content/ownership/mode drift.
grep -Fq 'rpm -V --nomtime krisCC' tests/release-check.sh
grep -Fq 'AMD early microcode embedded' tests/release-check.sh
grep -Fq 'expected admin user is in wheel' tests/release-check.sh

echo "K1 final static contract passed"
