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

# Immutable raku-Kris package delta. Fedora owns every RPM already present in
# the pinned bootc base: exclude those names from the layering transaction and
# verify their exact installed EVRAs are unchanged afterwards. If the desktop
# requires a newer Fedora-owned RPM, the build must fail and the base digest
# must move forward instead.
COPY build_files/base-packages.txt /tmp/base-packages.txt
RUN set -eux; \
    rpm -qa --qf '%{NAME}\n' | sort -u > /tmp/fedora-base-names.txt; \
    : > /tmp/fedora-base-nevra.before; \
    while IFS= read -r pkg; do \
      rpm -q --qf '%{NAME}\t%{EPOCHNUM}:%{VERSION}-%{RELEASE}.%{ARCH}\n' "$pkg" \
        >> /tmp/fedora-base-nevra.before; \
    done < /tmp/fedora-base-names.txt; \
    sort -u -o /tmp/fedora-base-nevra.before /tmp/fedora-base-nevra.before; \
    base_excludes="$(paste -sd, /tmp/fedora-base-names.txt)"; \
    grep -vE '^[[:space:]]*(#|$)' /tmp/base-packages.txt \
      | xargs dnf5 -y \
          --setopt=install_weak_deps=False \
          --setopt="excludepkgs=${base_excludes}" \
          install; \
    rpm -q glibc-langpack-en glibc-langpack-it langpacks-core-en langpacks-core-it; \
    if rpm -q glibc-all-langpacks >/dev/null 2>&1; then \
      ! grep -Fxq glibc-all-langpacks /tmp/fedora-base-names.txt; \
      rpm -e glibc-all-langpacks; \
    fi; \
    for pkg in \
      glibc-all-langpacks \
      pipewire-jack-audio-connection-kit \
      pipewire-jack-audio-connection-kit-libs \
      phonon-qt6 \
      phonon-common \
      sane-backends \
      sane-backends-libs \
      sane-airscan \
      libsane-airscan; \
    do \
      ! rpm -q "$pkg" >/dev/null 2>&1; \
    done; \
    rpm -q \
      NetworkManager-wifi \
      wpa_supplicant \
      bluedevil \
      bluez \
      bluez-obexd \
      mt7xxx-firmware \
      amd-gpu-firmware \
      amd-ucode-firmware \
      mesa-dri-drivers \
      mesa-vulkan-drivers \
      udisks2 \
      plasma-print-manager \
      cups \
      cups-filters \
      plasma-firewall \
      plasma-firewall-firewalld \
      firewalld \
      iproute \
      tar \
      zram-generator \
      zram-generator-defaults; \
    rpm -q --whatprovides mesa-va-drivers; \
    test -e /usr/lib64/dri/radeonsi_drv_video.so; \
    ! rpm -q linux-firmware >/dev/null 2>&1; \
    dnf5 check --dependencies; \
    : > /tmp/fedora-base-nevra.after; \
    while IFS= read -r pkg; do \
      rpm -q --qf '%{NAME}\t%{EPOCHNUM}:%{VERSION}-%{RELEASE}.%{ARCH}\n' "$pkg" \
        >> /tmp/fedora-base-nevra.after; \
    done < /tmp/fedora-base-names.txt; \
    sort -u -o /tmp/fedora-base-nevra.after /tmp/fedora-base-nevra.after; \
    diff -u /tmp/fedora-base-nevra.before /tmp/fedora-base-nevra.after; \
    dnf5 clean all; \
    rm -f \
      /tmp/base-packages.txt \
      /tmp/fedora-base-names.txt \
      /tmp/fedora-base-nevra.before \
      /tmp/fedora-base-nevra.after

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
# dracut runs, then restore it linearly. If dracut fails the build fails too,
# so no trap/helper is needed for an intermediate layer that will be discarded.
RUN set -eux; \
    root_was_symlink=0; root_target=''; \
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
      lsinitrd "$moddir/initramfs.img" > /tmp/raku-kris-lsinitrd.txt; \
      grep -Fq 'usr/bin/raku-kris-overlay' /tmp/raku-kris-lsinitrd.txt; \
      grep -Fq 'raku-kris-overlay.service' /tmp/raku-kris-lsinitrd.txt; \
      rm -f /tmp/raku-kris-lsinitrd.txt; \
    done; \
    [ "$found_kernel" -eq 1 ]; \
    if [ "$root_was_symlink" -eq 1 ]; then \
      rm -rf /root; ln -s "$root_target" /root; \
    fi; \
    rm -f /boot/initramfs-*.img; \
    test -z "$(find /boot -mindepth 1 -maxdepth 1 -type f -print -quit 2>/dev/null)"

RUN set -eux; \
    systemctl enable --force plasmalogin.service; \
    systemctl enable firewalld.service; \
    systemctl disable ufw.service || true; \
    systemctl set-default graphical.target

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
    test -e /usr/lib64/qt6/plugins/plasma/kcms/systemsettings/kcm_firewall.so; \
    test -e /usr/lib64/qt6/plugins/kf6/plasma_firewall/firewalldbackend.so; \
    systemctl is-enabled firewalld.service | grep -qx enabled; \
    ! systemctl is-enabled ufw.service >/dev/null 2>&1; \
    test -z "$(ldd /usr/lib64/qt6/plugins/platforms/libqxcb.so | awk '/not found/{print}')"; \
    test -z "$(ldd /usr/libexec/plasma-login-greeter | awk '/not found/{print}')"; \
    ! rpm -q glibc-all-langpacks >/dev/null 2>&1; \
    ! rpm -q linux-firmware >/dev/null 2>&1; \
    bootc container lint
