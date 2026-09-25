#!/usr/bin/env bash
set -euo pipefail

# This branch owns only the installer. The installed OS is the exact signed main payload.
source build_files/KrisOS-payload.lock
test "$KRISOS_COMMIT" = "1b54db16a8208e226e65ec54653cd4880da38dd1"
test "$KRISOS_TARGET_REF" = "ghcr.io/krism-eu/krisos:1b54db16a8208e226e65ec54653cd4880da38dd1"
test "$KRISOS_DIGEST" = "sha256:5ed8b3a2f7a925abc9ac365b76e9f944957908517c3f429bc5091c56b1a64301"
test "$KRISOS_KRISCC" = "0.7.9-1.fc44.x86_64"

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
grep -Fq 'ARG ANACONDA_NEVR=45.25-1.fc45' installer/Containerfile
grep -Fq 'anaconda-${ANACONDA_NEVR}' installer/Containerfile
grep -Fq 'anaconda-install-img-deps-${ANACONDA_NEVR}' installer/Containerfile
grep -Fq 'anaconda-dracut-${ANACONDA_NEVR}' installer/Containerfile
grep -Fq "grep -Fxq 'Alias=autovt@.service'" installer/Containerfile
grep -Fq "grep -Fxq 'ReserveVT=2'" installer/Containerfile
grep -Fq "grep -Fxq 'StandardInput=null'" installer/Containerfile
grep -Fq 'systemctl enable anaconda-shell@.service' installer/Containerfile
grep -Fq 'KrisOS workaround: Anaconda 45.25 invokes shadow-utils chage with -R' installer/Containerfile
test ! -e installer/anaconda-shell.conf
! grep -Fq 'ln -s /usr/lib/systemd/system/anaconda-shell@.service' installer/Containerfile
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

# SELinux installer behavior is intentionally frozen after host acceptance.
grep -Fq 'selinux=1 enforcing=0' installer/iso.yaml
if grep -Eq '(^|[[:space:]])(selinux=0|enforcing=1)([[:space:]]|$)' installer/iso.yaml; then
  echo "ERROR: live installer SELinux contract changed" >&2
  exit 1
fi
grep -Fq "'selinux --enforcing'" installer/Containerfile

# fstab finalization is installer-only and removes the redundant physical-root
# entry that makes systemd-remount-fs fail against a composefs /.
test -s installer/krisos-fstab-finalize.ks
grep -Fq 'COPY krisos-fstab-finalize.ks /usr/share/anaconda/krisos-fstab-finalize.ks' installer/Containerfile
grep -Fq '/usr/share/anaconda/krisos-fstab-finalize.ks \' installer/Containerfile
grep -Fq '>> /usr/share/anaconda/interactive-defaults.ks' installer/Containerfile
grep -Fq '%post --nochroot --erroronfail' installer/krisos-fstab-finalize.ks
grep -Fq 'sysroot=/mnt/sysroot' installer/krisos-fstab-finalize.ks
grep -Fq 'fstab="$sysroot/etc/fstab"' installer/krisos-fstab-finalize.ks
! grep -Fq '/mnt/sysimage' installer/krisos-fstab-finalize.ks
grep -Fq "anaconda_stamp='Created by anaconda'" installer/krisos-fstab-finalize.ks
grep -Fq "bootc_stamp='Updated by bootc-fstab-edit.service'" installer/krisos-fstab-finalize.ks
grep -Fq 'root_count_before=' installer/krisos-fstab-finalize.ks
grep -Fq '$2 == "/" { next }' installer/krisos-fstab-finalize.ks
grep -Fq 'root_count_after=' installer/krisos-fstab-finalize.ks
! grep -Fq 'bootc internals fixup-etc-fstab' installer/krisos-fstab-finalize.ks
! grep -Fq 'root_is_ro' installer/krisos-fstab-finalize.ks
if grep -Eq '(^|[[:space:]])(systemctl|daemon-reload)([[:space:]]|$)' installer/krisos-fstab-finalize.ks; then
  echo "ERROR: fstab finalizer must not add a runtime systemd workaround" >&2
  exit 1
fi

# Network finalization is installer-only. Keep IPv6 available in the kernel,
# but rewrite only Anaconda-created target NetworkManager keyfiles to IPv4-only.
# The previous recursive home relabel must stay absent while validating the
# native separate /home path.
test -s installer/krisos-network-finalize.ks
test ! -e installer/krisos-home-labels-finalize.ks
grep -Fq 'COPY krisos-network-finalize.ks /usr/share/anaconda/krisos-network-finalize.ks' installer/Containerfile
grep -Fq '/usr/share/anaconda/krisos-network-finalize.ks \' installer/Containerfile
grep -Fq "grep -c -x '%post --nochroot --erroronfail'" installer/Containerfile
grep -Fq "grep -c -x '%end'" installer/Containerfile
grep -Fq '%post --nochroot --erroronfail' installer/krisos-network-finalize.ks
grep -Fq 'sysroot=/mnt/sysroot' installer/krisos-network-finalize.ks
! grep -Fq '/mnt/sysimage' installer/krisos-network-finalize.ks
grep -Fq 'profiles="$sysroot/etc/NetworkManager/system-connections"' installer/krisos-network-finalize.ks
grep -Fq 'chroot "$sysroot" /usr/bin/nmcli --offline connection modify ipv6.method disabled \' installer/krisos-network-finalize.ks
grep -Fq 'install -m 0600 -o root -g root "$tmp" "$profile"' installer/krisos-network-finalize.ks
grep -Fq 'chroot "$sysroot" /usr/sbin/restorecon -F -- "/etc/NetworkManager/system-connections/$name"' installer/krisos-network-finalize.ks
grep -Fq "grep -Fq 'method=disabled'" installer/krisos-network-finalize.ks
! grep -Fq 'ipv6.disable=1' installer/krisos-network-finalize.ks
! grep -Eq '(^|[[:space:]])(chcon|semanage|semodule)([[:space:]]|$)' installer/krisos-network-finalize.ks
# Pin the integration contract to the exact main source behind the payload:
# main owns /var/home policy/defaults; the installer deliberately does not relabel home.
git fetch --no-tags origin "$KRISOS_COMMIT"
main_container="$(mktemp)"
trap 'rm -f "$main_container"' EXIT
git show "$KRISOS_COMMIT:Containerfile" > "$main_container"
grep -Fq "sed -ri 's|^HOME=.*$|HOME=/var/home|' /etc/default/useradd" "$main_container"
grep -Fq 'semodule -B' "$main_container"
grep -Fq 'matchpathcon -n /var/home/kris' "$main_container"
grep -Fq 'matchpathcon -n /var/home/kris/.config' "$main_container"
grep -Fq 'matchpathcon -n /var/home/kris/.local/share' "$main_container"
grep -Fq "grep -Eq '^SELINUX=enforcing$' /etc/selinux/config" "$main_container"

# Preserve the approved interactive partitioning contract documented for K1.
grep -Fq '/boot/efi' installer/README.md
grep -Fq 'dedicated ext4 partition -> `/home`' installer/README.md
grep -Fq 'administrator' installer/README.md
grep -Fq 'No swap partition' installer/README.md

echo "K1 installer-only contract passed"
