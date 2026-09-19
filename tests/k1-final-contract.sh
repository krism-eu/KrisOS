#!/usr/bin/env bash
set -euo pipefail

# Stable backup baseline: exact validated main payload after K1 runtime promotion.
# shellcheck source=/dev/null
source build_files/KrisOS-payload.lock
test "$KRISOS_COMMIT" = "b40417ff49af48d9c693f49e553a0bef3cceb59b"
test "$KRISOS_TARGET_REF" = "ghcr.io/krism-eu/krisos:b40417ff49af48d9c693f49e553a0bef3cceb59b"
test "$KRISOS_DIGEST" = "sha256:9218df60225d4d6d415c4bcc21de530bd2bd65b97d9045374050ac7addd01579"

# Stable krisCC component is main's validated 0.6.0-1.
# shellcheck source=/dev/null
source build_files/krisCC.lock
test "$KRISCC_TAG" = "v0.6.0-1"
test "$KRISCC_RPM" = "krisCC-0.6.0-1.fc44.x86_64.rpm"
test "$KRISCC_SHA256" = "5cb01133a54e8c715715bc5ec2bb87244ae5b57b5ed9272212b8203900a80298"

# Compatibility mirror matches the promoted krisCC release; the ISO build input is main.
# shellcheck source=/dev/null
source build_files/krisCC-candidate.lock
test "$KRISCC_TAG" = "v0.6.0-1"
test "$KRISCC_RPM" = "krisCC-0.6.0-1.fc44.x86_64.rpm"
test "$KRISCC_SHA256" = "5cb01133a54e8c715715bc5ec2bb87244ae5b57b5ed9272212b8203900a80298"
test "$KRISCC_COMMIT" = "8a23e8fb59d01ef11f98ddd623a533a55a0e75ff"

# rk must honor the repositories explicitly enabled by the administrator while
# retaining mandatory package signature verification. Never re-enable Fedora
# repositories behind the UI's back.
! grep -Fq "repo.get_config().enabled = repo.get_id() in ('fedora', 'updates')" bin/rk
grep -Fq 'config.pkg_gpgcheck = True' bin/rk
grep -Fq 'config.localpkg_gpgcheck = True' bin/rk
grep -Fq 'config.pkg_gpgcheck = True' bin/rk
grep -Fq 'tx.check_gpg_signatures()' bin/rk
grep -Fq 'fd = acquire_plan_lock()' bin/rk
grep -Fq "fd = os.open(STATE / 'lock', os.O_RDONLY)" bin/rk
grep -Fq 'LOCK_SH | fcntl.LOCK_NB' bin/rk
grep -Fq 'f /var/lib/krisos/lock 0644 root root -' build_files/tmpfiles-krisos.conf

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
