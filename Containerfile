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
      tar \
      bash-completion \
      ntfs-3g \
      ntfsprogs \
      os-prober \
      zram-generator \
      zram-generator-defaults; \
    rpm -q --whatprovides mesa-va-drivers; \
    test -e /usr/lib64/dri/radeonsi_drv_video.so; \
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

# Persistent /usr overlay. Mount it in early real-root userspace rather than in
# initrd: OSTree has already exposed writable /var, while local-fs.target still
# holds normal services behind the overlay setup.
COPY systemd/raku-kris-overlay.sh /usr/libexec/raku-kris-overlay
COPY systemd/raku-kris-overlay.service /usr/lib/systemd/system/raku-kris-overlay.service
RUN chmod 0755 /usr/libexec/raku-kris-overlay

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
    if grep -Fxq gpg-pubkey /usr/share/raku-kris/owned-packages.txt; then \
      echo 'gpg-pubkey must not appear in immutable ownership snapshot' >&2; \
      exit 1; \
    fi

# Factory state plus an explicit tmpfiles contract. The C rule seeds the empty
# M1 package-intent file only when it is missing; existing persistent state is
# never overwritten by a reboot or image update.
COPY build_files/tmpfiles-raku-kris.conf /usr/lib/tmpfiles.d/raku-kris.conf
RUN set -eux; \
    install -d -m 0755 /usr/share/factory/var/lib/raku-kris; \
    : > /usr/share/factory/var/lib/raku-kris/packages.list

RUN set -eux; \
    printf '%s\n' 'LANG=it_IT.UTF-8' > /etc/locale.conf; \
    systemctl enable raku-kris-overlay.service; \
    systemctl enable --force plasmalogin.service; \
    systemctl enable firewalld.service; \
    systemctl enable systemd-timesyncd.service; \
    systemctl mask dnf-makecache.timer dnf5-makecache.timer || true; \
    systemctl disable ufw.service || true; \
    systemctl set-default graphical.target

# Static image invariants. Runtime overlay persistence is intentionally left to
# the M0 VM smoke test; a green container build cannot prove it.
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
    test -x /usr/libexec/raku-kris-overlay; \
    test -f /usr/lib/systemd/system/raku-kris-overlay.service; \
    test -e /usr/lib/systemd/system/plasmalogin.service; \
    test -s /usr/share/raku-kris/owned-packages.txt; \
    assert_not_in_file gpg-pubkey /usr/share/raku-kris/owned-packages.txt; \
    test -e /usr/share/factory/var/lib/raku-kris/packages.list; \
    test ! -s /usr/share/factory/var/lib/raku-kris/packages.list; \
    test -f /usr/lib/tmpfiles.d/raku-kris.conf; \
    grep -Fxq 'd /var/lib/raku-kris 0755 root root -' \
      /usr/lib/tmpfiles.d/raku-kris.conf; \
    grep -Fxq 'C /var/lib/raku-kris/packages.list 0644 root root - /usr/share/factory/var/lib/raku-kris/packages.list' \
      /usr/lib/tmpfiles.d/raku-kris.conf; \
    grep -Eq '^SELINUX=enforcing$' /etc/selinux/config; \
    grep -Fxq 'LANG=it_IT.UTF-8' /etc/locale.conf; \
    grep -Fxq 'excludepkgs=*.i686' /etc/dnf/libdnf5.conf.d/90-raku-kris.conf; \
    grep -Fxq 'multilib_policy=best' /etc/dnf/libdnf5.conf.d/90-raku-kris.conf; \
    rpm -q glibc-langpack-en glibc-langpack-it langpacks-core-en langpacks-core-it; \
    rpm -q xcb-util-cursor; \
    test -e /usr/lib64/qt6/plugins/platforms/libqxcb.so; \
    test -e /usr/lib64/qt6/plugins/plasma/kcms/systemsettings/kcm_firewall.so; \
    test -e /usr/lib64/qt6/plugins/kf6/plasma_firewall/firewalldbackend.so; \
    systemctl is-enabled raku-kris-overlay.service | grep -qx enabled; \
    systemctl is-enabled firewalld.service | grep -qx enabled; \
    systemctl is-enabled systemd-timesyncd.service | grep -qx enabled; \
    if systemctl is-enabled dnf-makecache.timer >/dev/null 2>&1; then \
      echo 'dnf-makecache.timer must not be enabled' >&2; \
      exit 1; \
    fi; \
    if systemctl is-enabled dnf5-makecache.timer >/dev/null 2>&1; then \
      echo 'dnf5-makecache.timer must not be enabled' >&2; \
      exit 1; \
    fi; \
    if systemctl is-enabled ufw.service >/dev/null 2>&1; then \
      echo 'ufw.service must not be enabled' >&2; \
      exit 1; \
    fi; \
    test -z "$(ldd /usr/lib64/qt6/plugins/platforms/libqxcb.so | awk '/not found/{print}')"; \
    test -z "$(ldd /usr/libexec/plasma-login-greeter | awk '/not found/{print}')"; \
    assert_absent glibc-all-langpacks; \
    assert_absent linux-firmware; \
    bootc container lint
