# raku-Kris M1 — persistent /usr overlay plus restricted rk package layer.
# M1 includes additive rk transactions, deployment sync and recovery.

# Release builds use this exact Fedora 44 bootc Minimal digest. CI and manual
# compatibility tests may override BASE_IMAGE explicitly without weakening the
# reproducible default.
ARG BASE_IMAGE=quay.io/bootc-devel/fedora-bootc-44-minimal@sha256:03d9e53e46040b1d91441f7776a987dfc136ceb39500daa605237eb0cd211207
FROM ${BASE_IMAGE}

ARG RELEASE=0.1.0-m1
LABEL org.opencontainers.image.title="raku-kris"
LABEL org.opencontainers.image.version="${RELEASE}"
LABEL org.opencontainers.image.description="Fedora 44 bootc Minimal + persistent additive /usr overlay and rk package layer (M1)"
LABEL containers.bootc="1"
LABEL ostree.bootable="1"

# Global DNF5 policy: raku-Kris is x86_64/noarch only. User-facing package
# operations in M1 inherit this and the wrapper will reject attempts to bypass
# the architecture/exclude policy.
RUN install -d -m 0755 /etc/dnf/libdnf5.conf.d
COPY build_files/dnf-raku-kris.conf /etc/dnf/libdnf5.conf.d/90-raku-kris.conf

# Immutable raku-Kris package delta. Fedora owns every RPM already present in
# the pinned bootc base: exclude those names from the layering transaction and
# verify their exact installed EVRAs are unchanged afterwards. If the desktop
# requires a newer Fedora-owned RPM, the build must fail and the base digest
# must move forward instead.
COPY build_files/base-packages.txt /tmp/base-packages.txt
RUN set -eux; \
    rpm -qa --qf '%{NAME}\n' > /tmp/fedora-base-names.raw; \
    sed -e '/^gpg-pubkey$/d' \
      /tmp/fedora-base-names.raw > /tmp/fedora-base-names.filtered; \
    LC_ALL=C sort -u \
      /tmp/fedora-base-names.filtered > /tmp/fedora-base-names.txt; \
    test -s /tmp/fedora-base-names.txt; \
    for pkg in bootc bootupd dracut ostree systemd rpm dnf5 kernel-core; do \
      if ! grep -Fxq "$pkg" /tmp/fedora-base-names.txt; then \
        echo "Pinned Fedora base sanity check failed: missing $pkg" >&2; \
        exit 1; \
      fi; \
    done; \
    sed \
      -e 's/\r$//' \
      -e 's/[[:space:]]*#.*$//' \
      -e 's/^[[:space:]]*//' \
      -e 's/[[:space:]]*$//' \
      -e '/^$/d' \
      /tmp/base-packages.txt > /tmp/raku-delta-names.raw; \
    LC_ALL=C sort -u \
      /tmp/raku-delta-names.raw > /tmp/raku-delta-names.txt; \
    LC_ALL=C comm -12 \
      /tmp/fedora-base-names.txt \
      /tmp/raku-delta-names.txt \
      > /tmp/raku-base-collisions.txt; \
    if [ -s /tmp/raku-base-collisions.txt ]; then \
      echo 'raku-Kris package delta collides with Fedora-owned base packages:' >&2; \
      cat /tmp/raku-base-collisions.txt >&2; \
      echo 'Remove these names from build_files/base-packages.txt.' >&2; \
      exit 1; \
    fi; \
    : > /tmp/fedora-base-nevra.before; \
    while IFS= read -r pkg; do \
      rpm -q --qf '%{NAME}\t%{EPOCHNUM}:%{VERSION}-%{RELEASE}.%{ARCH}\n' "$pkg" \
        >> /tmp/fedora-base-nevra.before; \
    done < /tmp/fedora-base-names.txt; \
    LC_ALL=C sort -u -o \
      /tmp/fedora-base-nevra.before /tmp/fedora-base-nevra.before; \
    base_excludes="$(paste -sd, /tmp/fedora-base-names.txt)"; \
    xargs -r dnf5 -y \
      --setopt=install_weak_deps=False \
      --setopt="excludepkgs=${base_excludes}" \
      install < /tmp/raku-delta-names.txt; \
    rpm -q glibc-langpack-en glibc-langpack-it langpacks-core-en langpacks-core-it; \
    if rpm -q glibc-all-langpacks >/dev/null 2>&1; then \
      if grep -Fxq glibc-all-langpacks /tmp/fedora-base-names.txt; then \
        echo 'glibc-all-langpacks is Fedora-base-owned; refusing image-side removal' >&2; \
        exit 1; \
      fi; \
      rpm -e glibc-all-langpacks; \
    fi; \
    assert_absent() { \
      if rpm -q "$1" >/dev/null 2>&1; then \
        echo "forbidden package installed: $1" >&2; \
        exit 1; \
      fi; \
    }; \
    for pkg in \
      glibc-all-langpacks \
      pipewire-jack-audio-connection-kit \
      pipewire-jack-audio-connection-kit-libs \
      sane-backends \
      sane-backends-libs \
      sane-airscan \
      libsane-airscan; \
    do \
      assert_absent "$pkg"; \
    done; \
    rpm -q \
      NetworkManager-wifi \
      wpa_supplicant \
      bluedevil \
      bluez \
      bluez-obexd \
      mt7xxx-firmware \
      realtek-firmware \
      amd-gpu-firmware \
      amd-ucode-firmware \
      mesa-dri-drivers \
      mesa-vulkan-drivers \
      udisks2 \
      dolphin \
      konsole \
      kate \
      spectacle \
      ark \
      gwenview \
      okular \
      kcalc \
      kio-admin \
      kinfocenter \
      power-profiles-daemon \
      plasma-print-manager \
      cups \
      cups-filters \
      plasma-firewall \
      plasma-firewall-firewalld \
      firewalld \
      iproute \
      iputils \
      pciutils \
      tar \
      bash-completion \
      ntfs-3g \
      ntfsprogs \
      os-prober \
      zram-generator \
      zram-generator-defaults; \
    rpm -q --whatprovides mesa-va-drivers; \
    test -e /usr/lib64/dri/radeonsi_drv_video.so; \
    find /usr/lib/firmware/rtl_nic -maxdepth 1 -name 'rtl8168h-2.fw*' -print -quit | grep -q .; \
    assert_absent linux-firmware; \
    if rpm -qa --qf '%{ARCH}\n' | grep -qx i686; then \
      echo 'i686 packages are not allowed in raku-Kris' >&2; \
      exit 1; \
    fi; \
    dnf5 check --dependencies; \
    : > /tmp/fedora-base-nevra.after; \
    while IFS= read -r pkg; do \
      rpm -q --qf '%{NAME}\t%{EPOCHNUM}:%{VERSION}-%{RELEASE}.%{ARCH}\n' "$pkg" \
        >> /tmp/fedora-base-nevra.after; \
    done < /tmp/fedora-base-names.txt; \
    LC_ALL=C sort -u -o \
      /tmp/fedora-base-nevra.after /tmp/fedora-base-nevra.after; \
    diff -u /tmp/fedora-base-nevra.before /tmp/fedora-base-nevra.after; \
    dnf5 clean all; \
    rm -f \
      /tmp/base-packages.txt \
      /tmp/fedora-base-names.raw \
      /tmp/fedora-base-names.filtered \
      /tmp/fedora-base-names.txt \
      /tmp/raku-delta-names.raw \
      /tmp/raku-delta-names.txt \
      /tmp/raku-base-collisions.txt \
      /tmp/fedora-base-nevra.before \
      /tmp/fedora-base-nevra.after

# Add Fedora bindings without replacing any image package.
RUN set -eux; \
    excludes="$(rpm -qa --qf '%{NAME}\n' | sort -u | paste -sd,)"; \
    rpm -qa --qf '%{NAME}\t%{EPOCHNUM}:%{VERSION}-%{RELEASE}.%{ARCH}\n' | sort > /tmp/rk-before; \
    dnf5 -y --setopt=install_weak_deps=False --setopt="excludepkgs=$excludes" install python3-libdnf5; \
    rpm -qa --qf '%{NAME}\t%{EPOCHNUM}:%{VERSION}-%{RELEASE}.%{ARCH}\n' | sort > /tmp/rk-after; \
    test -z "$(comm -23 /tmp/rk-before /tmp/rk-after)"; \
    python3 -c 'import libdnf5; assert hasattr(libdnf5.base.Base, "lock_system_repo")'; \
    dnf5 clean all; rm -f /tmp/rk-before /tmp/rk-after
COPY bin/rk /usr/bin/rk
RUN chmod 0755 /usr/bin/rk
COPY systemd/raku-kris-sync.service /usr/lib/systemd/system/raku-kris-sync.service
RUN systemctl enable raku-kris-sync.service

# Persistent /usr overlay. Mount it in early real-root userspace rather than in
# initrd: OSTree has already exposed writable /var, while local-fs.target still
# holds normal services behind the overlay setup.
COPY systemd/raku-kris-overlay.sh /usr/libexec/raku-kris-overlay
COPY systemd/raku-kris-overlay.service /usr/lib/systemd/system/raku-kris-overlay.service
RUN chmod 0755 /usr/libexec/raku-kris-overlay

# Conservative hardening: only deltas from Fedora defaults that passed real
# Plasma/Wayland, networking, audio, rootless Podman and S3 suspend testing.
COPY build_files/55-raku-hardening.conf /usr/lib/sysctl.d/55-raku-hardening.conf

# Snapshot every immutable package name owned by the final image: pinned Fedora
# base plus the raku-Kris delta. RPM key pseudo-packages are deliberately not
# package-ownership policy; M1 handles repository/key trust separately.
RUN set -eux; \
    install -d -m 0755 /usr/share/raku-kris; \
    rpm -qa --qf '%{NAME}\n' \
      | sed -e '/^gpg-pubkey$/d' \
      | LC_ALL=C sort -u \
      > /usr/share/raku-kris/owned-packages.txt; \
    test -s /usr/share/raku-kris/owned-packages.txt; \
    rpm -qa --qf '%{NAME}\t%{EPOCHNUM}:%{VERSION}-%{RELEASE}.%{ARCH}\n' | sed '/^gpg-pubkey\t/d' | LC_ALL=C sort -u > /usr/share/raku-kris/owned-nevra.txt; \
    if grep -Fxq gpg-pubkey /usr/share/raku-kris/owned-packages.txt; then \
      echo 'gpg-pubkey must not appear in immutable ownership snapshot' >&2; \
      exit 1; \
    fi

# Factory state plus an explicit tmpfiles contract. Seed package intent and the
# initial NetworkManager radio policy only when missing; persistent user state
# must survive reboot and bootc image updates.
COPY build_files/tmpfiles-raku-kris.conf /usr/lib/tmpfiles.d/raku-kris.conf
RUN set -eux; \
    install -d -m 0755 /usr/share/factory/var/lib/raku-kris; \
    install -d -m 0755 /usr/share/factory/var/lib/NetworkManager; \
    : > /usr/share/factory/var/lib/raku-kris/packages.list
COPY build_files/NetworkManager.state /usr/share/factory/var/lib/NetworkManager/NetworkManager.state

RUN set -eux; \
    printf '%s\n' 'LANG=it_IT.UTF-8' > /etc/locale.conf; \
    test -f /etc/bluetooth/main.conf; \
    sed -i 's/^#AutoEnable=true$/AutoEnable=false/' /etc/bluetooth/main.conf; \
    grep -Fxq 'AutoEnable=false' /etc/bluetooth/main.conf; \
    test -f /etc/xdg/autostart/geoclue-demo-agent.desktop; \
    grep -Fxq 'Hidden=true' /etc/xdg/autostart/geoclue-demo-agent.desktop || printf '\nHidden=true\n' >> /etc/xdg/autostart/geoclue-demo-agent.desktop; \
    firewall-offline-cmd --zone=public --remove-service=ssh; \
    firewall-offline-cmd --zone=public --remove-service=mdns; \
    systemctl enable raku-kris-overlay.service; \
    systemctl enable raku-kris-sync.service; \
    systemctl enable --force plasmalogin.service; \
    systemctl enable firewalld.service; \
    systemctl enable systemd-timesyncd.service; \
    systemctl disable systemd-homed.service; \
    systemctl disable avahi-daemon.service avahi-daemon.socket; \
    systemctl disable mdmonitor.service raid-check.timer; \
    systemctl disable flatpak-add-fedora-repos.service; \
    systemctl mask dnf-makecache.timer dnf5-makecache.timer || true; \
    systemctl disable ufw.service || true; \
    systemctl set-default graphical.target

# Static image invariants. Runtime overlay persistence is intentionally left to
# the M1 VM smoke test; a green container build cannot prove it.
RUN set -eux; \
    assert_absent() { \
      if rpm -q "$1" >/dev/null 2>&1; then \
        echo "forbidden package installed: $1" >&2; \
        exit 1; \
      fi; \
    }; \
    assert_not_in_file() { \
      if grep -Fxq "$1" "$2"; then \
        echo "forbidden entry in $2: $1" >&2; \
        exit 1; \
      fi; \
    }; \
    assert_disabled() { \
      if systemctl is-enabled "$1" >/dev/null 2>&1; then \
        echo "unit must not be enabled: $1" >&2; \
        exit 1; \
      fi; \
    }; \
    test -x /usr/bin/bootc; \
    test -x /usr/bin/ostree; \
    test -x /usr/bin/dnf5; \
    test -x /usr/bin/dolphin; \
    test -x /usr/bin/konsole; \
    test -x /usr/bin/kate; \
    test -x /usr/bin/spectacle; \
    test -x /usr/bin/ark; \
    test -x /usr/bin/gwenview; \
    test -x /usr/bin/okular; \
    test -x /usr/bin/kcalc; \
    test -x /usr/bin/kinfocenter; \
    test -x /usr/bin/powerprofilesctl; \
    test -x /usr/bin/os-prober; \
    test -x /usr/bin/ntfsresize; \
    test -x /usr/bin/ping; \
    test -x /usr/bin/lspci; \
    test -x /usr/libexec/raku-kris-overlay; \
    test -f /usr/lib/systemd/system/raku-kris-overlay.service; \
    test -e /usr/lib/systemd/system/plasmalogin.service; \
    test -s /usr/share/raku-kris/owned-packages.txt; \
    assert_not_in_file gpg-pubkey /usr/share/raku-kris/owned-packages.txt; \
    test -e /usr/share/factory/var/lib/raku-kris/packages.list; \
    test ! -s /usr/share/factory/var/lib/raku-kris/packages.list; \
    test -f /usr/share/factory/var/lib/NetworkManager/NetworkManager.state; \
    grep -Fxq 'WirelessEnabled=false' /usr/share/factory/var/lib/NetworkManager/NetworkManager.state; \
    test -f /usr/lib/tmpfiles.d/raku-kris.conf; \
    grep -Fxq 'd /var/lib/raku-kris 0755 root root -' \
      /usr/lib/tmpfiles.d/raku-kris.conf; \
    grep -Fxq 'C /var/lib/raku-kris/packages.list 0644 root root - /usr/share/factory/var/lib/raku-kris/packages.list' \
      /usr/lib/tmpfiles.d/raku-kris.conf; \
    grep -Fxq 'C /var/lib/NetworkManager/NetworkManager.state 0600 root root - /usr/share/factory/var/lib/NetworkManager/NetworkManager.state' \
      /usr/lib/tmpfiles.d/raku-kris.conf; \
    test -f /usr/lib/sysctl.d/55-raku-hardening.conf; \
    grep -Fxq 'kernel.kptr_restrict = 2' /usr/lib/sysctl.d/55-raku-hardening.conf; \
    grep -Fxq 'fs.protected_regular = 2' /usr/lib/sysctl.d/55-raku-hardening.conf; \
    grep -Fxq 'fs.protected_fifos = 2' /usr/lib/sysctl.d/55-raku-hardening.conf; \
    grep -Fxq 'fs.suid_dumpable = 0' /usr/lib/sysctl.d/55-raku-hardening.conf; \
    grep -Fxq 'AutoEnable=false' /etc/bluetooth/main.conf; \
    grep -Fxq 'Hidden=true' /etc/xdg/autostart/geoclue-demo-agent.desktop; \
    ! firewall-offline-cmd --zone=public --list-services | tr ' ' '\n' | grep -Eq '^(ssh|mdns)$'; \
    grep -Eq '^SELINUX=enforcing$' /etc/selinux/config; \
    grep -Fxq 'LANG=it_IT.UTF-8' /etc/locale.conf; \
    grep -Fxq 'excludepkgs=*.i686' /etc/dnf/libdnf5.conf.d/90-raku-kris.conf; \
    grep -Fxq 'multilib_policy=best' /etc/dnf/libdnf5.conf.d/90-raku-kris.conf; \
    rpm -q glibc-langpack-en glibc-langpack-it langpacks-core-en langpacks-core-it; \
    rpm -q xcb-util-cursor realtek-firmware iputils pciutils; \
    find /usr/lib/firmware/rtl_nic -maxdepth 1 -name 'rtl8168h-2.fw*' -print -quit | grep -q .; \
    test -e /usr/lib64/qt6/plugins/platforms/libqxcb.so; \
    test -e /usr/lib64/qt6/plugins/plasma/kcms/systemsettings/kcm_firewall.so; \
    test -e /usr/lib64/qt6/plugins/kf6/plasma_firewall/firewalldbackend.so; \
    systemctl is-enabled raku-kris-overlay.service | grep -qx enabled; \
    systemctl is-enabled raku-kris-sync.service | grep -qx enabled; \
    systemctl is-enabled plasmalogin.service | grep -qx enabled; \
    systemctl is-enabled firewalld.service | grep -qx enabled; \
    systemctl is-enabled systemd-timesyncd.service | grep -qx enabled; \
    assert_disabled systemd-homed.service; \
    assert_disabled avahi-daemon.service; \
    assert_disabled avahi-daemon.socket; \
    assert_disabled mdmonitor.service; \
    assert_disabled raid-check.timer; \
    assert_disabled flatpak-add-fedora-repos.service; \
    assert_disabled dnf-makecache.timer; \
    assert_disabled dnf5-makecache.timer; \
    assert_disabled ufw.service; \
    test -z "$(ldd /usr/lib64/qt6/plugins/platforms/libqxcb.so | awk '/not found/{print}')"; \
    test -z "$(ldd /usr/libexec/plasma-login-greeter | awk '/not found/{print}')"; \
    assert_absent glibc-all-langpacks; \
    assert_absent linux-firmware; \
    bootc container lint
