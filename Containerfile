# raku-Kris M0 — persistent /usr overlay lifecycle only.
# No package wrapper or RPM sync yet.

# Release builds use this exact Fedora 44 bootc Minimal digest. CI and manual
# compatibility tests may override BASE_IMAGE explicitly without weakening the
# reproducible default.
ARG BASE_IMAGE=quay.io/bootc-devel/fedora-bootc-44-minimal@sha256:03d9e53e46040b1d91441f7776a987dfc136ceb39500daa605237eb0cd211207
FROM ${BASE_IMAGE}

ARG RELEASE=0.1.0-m0
LABEL org.opencontainers.image.title="raku-kris"
LABEL org.opencontainers.image.version="${RELEASE}"
LABEL org.opencontainers.image.description="Fedora 44 bootc Minimal + persistent additive /usr overlay (M0)"
LABEL containers.bootc="1"
LABEL ostree.bootable="1"

# Immutable base package set. Keep weak dependencies disabled and defer further
# trimming until the M0 boot/login path has been verified in a VM.
COPY build_files/base-packages.txt /tmp/base-packages.txt
RUN set -eux; \
    grep -vE '^[[:space:]]*(#|$)' /tmp/base-packages.txt \
      | xargs dnf5 -y --setopt=install_weak_deps=False install; \
    if rpm -q glibc-all-langpacks >/dev/null 2>&1; then \
      dnf5 -y remove glibc-all-langpacks; \
    fi; \
    dnf5 clean all; \
    rm -f /tmp/base-packages.txt; \
    ! rpm -q glibc-all-langpacks >/dev/null 2>&1

# Overlay infrastructure.
COPY dracut/modules.d/90raku-kris /usr/lib/dracut/modules.d/90raku-kris/
RUN chmod 0755 \
    /usr/lib/dracut/modules.d/90raku-kris/module-setup.sh \
    /usr/lib/dracut/modules.d/90raku-kris/raku-kris-overlay.sh

# Snapshot the immutable package names. M1 will use this as input to the
# additive-only policy after its DNF5 semantics are verified by tests.
RUN set -eux; \
    install -d -m 0755 /usr/share/raku-kris; \
    rpm -qa --qf '%{NAME}\n' | sort -u > /usr/share/raku-kris/base-packages.txt; \
    test -s /usr/share/raku-kris/base-packages.txt

# Factory state. bootc's root.transient handling copies /usr/share/factory/var
# into persistent /var via systemd-tmpfiles semantics.
RUN set -eux; \
    install -d -m 0755 /usr/share/factory/var/lib/raku-kris; \
    : > /usr/share/factory/var/lib/raku-kris/packages.list

# bootc images carry initramfs next to each kernel under /usr/lib/modules.
# /root is normally a symlink to /var/roothome; materialize it only while
# dracut runs, then restore the original link.
RUN set -eux; \
    root_was_symlink=0; root_target=''; \
    cleanup_root() { \
      if [ "$root_was_symlink" -eq 1 ] && [ ! -L /root ]; then \
        rm -rf /root; ln -s "$root_target" /root; \
      fi; \
    }; \
    trap cleanup_root EXIT; \
    if [ -L /root ]; then \
      root_was_symlink=1; root_target="$(readlink /root)"; \
      rm -f /root; install -d -m 0700 /root; \
    fi; \
    found_kernel=0; \
    for moddir in /usr/lib/modules/*; do \
      [ -d "$moddir" ] || continue; \
      kver="${moddir##*/}"; \
      [ -e "$moddir/vmlinuz" ] || continue; \
      found_kernel=1; \
      dracut --force --no-hostonly "$moddir/initramfs.img" "$kver"; \
      lsinitrd "$moddir/initramfs.img" | grep -q 'raku-kris-overlay'; \
      lsinitrd "$moddir/initramfs.img" | grep -q '90raku-kris'; \
    done; \
    [ "$found_kernel" -eq 1 ]; \
    cleanup_root; trap - EXIT; \
    rm -f /boot/initramfs-*.img; \
    test -z "$(find /boot -mindepth 1 -maxdepth 1 -type f -print -quit 2>/dev/null)"

RUN systemctl enable --force plasmalogin.service \
    && systemctl set-default graphical.target

# Static image invariants. Runtime overlay persistence is intentionally left to
# the M0 VM matrix; a green container build cannot prove it.
RUN set -eux; \
    test -x /usr/bin/bootc; \
    test -x /usr/bin/ostree; \
    test -x /usr/bin/dnf5; \
    test -x /usr/lib/dracut/modules.d/90raku-kris/module-setup.sh; \
    test -x /usr/lib/dracut/modules.d/90raku-kris/raku-kris-overlay.sh; \
    test -e /usr/lib/dracut/modules.d/90raku-kris/raku-kris-overlay.service; \
    test -e /usr/lib/systemd/system/plasmalogin.service; \
    test -s /usr/share/raku-kris/base-packages.txt; \
    test -e /usr/share/factory/var/lib/raku-kris/packages.list; \
    test ! -s /usr/share/factory/var/lib/raku-kris/packages.list; \
    test -L /root; \
    grep -Eq '^SELINUX=enforcing$' /etc/selinux/config; \
    rpm -q glibc-langpack-en glibc-langpack-it langpacks-core-en langpacks-core-it; \
    rpm -q xcb-util-cursor; \
    test -e /usr/lib64/qt6/plugins/platforms/libqxcb.so; \
    test -z "$(ldd /usr/lib64/qt6/plugins/platforms/libqxcb.so | awk '/not found/{print}')"; \
    test -z "$(ldd /usr/libexec/plasma-login-greeter | awk '/not found/{print}')"; \
    ! rpm -q glibc-all-langpacks >/dev/null 2>&1; \
    bootc container lint
