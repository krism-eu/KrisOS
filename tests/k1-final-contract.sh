#!/usr/bin/env bash
set -euo pipefail

# This branch owns only the installer. The installed OS is the exact signed main payload.
source build_files/KrisOS-payload.lock
test "$KRISOS_COMMIT" = "6212322d22ccf170562976bef3c288d531f98bb2"
test "$KRISOS_TARGET_REF" = "ghcr.io/krism-eu/krisos:6212322d22ccf170562976bef3c288d531f98bb2"
test "$KRISOS_DIGEST" = "sha256:7f1e12e8fbf3b94acb389045dc920d30d998458ca170453a8493810ffdebecff"
test "$KRISOS_KRISCC" = "0.7.0-4.fc44.x86_64"

# Runtime sources and runtime workflows belong to main and must not drift here.
test ! -e Containerfile
test ! -e bin
test ! -e systemd
test ! -e scripts
test ! -e build_files/krisCC.lock
test ! -e build_files/krisCC-candidate.lock
test ! -e .github/workflows/build-m1.yml
test ! -e .github/workflows/sync-kriscc.yml
test ! -e .github/workflows/build-installer.yml

# Installer must remain graphical, interactive and non-destructive.
grep -Fq 'bootc-generic-iso' installer/build-installer.sh
grep -Fq -- '--bootc-installer-payload-ref "$payload_ref"' installer/build-installer.sh
grep -Fq -- '--build-arg KRISOS_PAYLOAD_REF="$payload_ref"' installer/build-installer.sh
grep -Fq 'ARG KRISOS_PAYLOAD_REF' installer/Containerfile
grep -Fq "'graphical'" installer/Containerfile
grep -Fq 'bootc --source-imgref=registry:$KRISOS_PAYLOAD_REF --target-imgref=$KRISOS_PAYLOAD_REF' installer/Containerfile
if grep -Eq '^[[:space:]]*(clearpart|autopart|part|partition|logvol|volgroup|user|rootpw|reboot|shutdown)([[:space:]]|$)' installer/Containerfile; then
  echo "ERROR: installer container bakes unattended/destructive directives" >&2
  exit 1
fi
if grep -Eq 'inst\.(ks|cmdline|noninteractive)' installer/iso.yaml; then
  echo "ERROR: ISO boot arguments enable unattended installation" >&2
  exit 1
fi
grep -Fq 'selinux=1 enforcing=0' installer/iso.yaml
if grep -Eq '(^|[[:space:]])(selinux=0|enforcing=1)([[:space:]]|$)' installer/iso.yaml; then
  echo "ERROR: live installer SELinux contract changed" >&2
  exit 1
fi
grep -Fq "'selinux --enforcing'" installer/Containerfile
grep -Fq '/boot/efi' installer/README.md
grep -Fq '/var/home' installer/README.md
grep -Fq 'administrator' installer/README.md
grep -Fq 'No swap partition' installer/README.md

echo "K1 installer-only contract passed"
