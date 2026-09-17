# KrisOS M1 — persistent /usr overlay plus restricted rk package layer.
# M1 includes additive rk transactions, deployment sync and recovery.

ARG BASE_IMAGE=quay.io/bootc-devel/fedora-bootc-44-minimal@sha256:03d9e53e46040b1d91441f7776a987dfc136ceb39500daa605237eb0cd211207

FROM ${BASE_IMAGE} AS rtl8168-firmware-source
RUN set -eux; \
    dnf5 -y --setopt=install_weak_deps=False install linux-firmware; \
    test -f /usr/lib/firmware/rtl_nic/rtl8168h-2.fw.xz; \
    rpm -qf /usr/lib/firmware/rtl_nic/rtl8168h-2.fw.xz | grep -q '^linux-firmware-'; \
    test -d /usr/share/licenses/linux-firmware; \
    install -d -m 0755 /out/firmware/rtl_nic /out/licenses; \
    cp -a /usr/lib/firmware/rtl_nic/rtl8168h-2.fw.xz /out/firmware/rtl_nic/; \
    cp -a /usr/share/licenses/linux-firmware/. /out/licenses/

FROM ${BASE_IMAGE}

ARG RELEASE=0.1.0-m1
LABEL org.opencontainers.image.title="krisos"
LABEL org.opencontainers.image.version="${RELEASE}"
LABEL org.opencontainers.image.description="Fedora 44 bootc Minimal + persistent additive /usr overlay and rk package layer (M1)"
LABEL containers.bootc="1"
LABEL ostree.bootable="1"

COPY --from=rtl8168-firmware-source /out/firmware/rtl_nic/rtl8168h-2.fw.xz /usr/lib/firmware/rtl_nic/rtl8168h-2.fw.xz
COPY --from=rtl8168-firmware-source /out/licenses/ /usr/share/licenses/krisos-rtl8168-firmware/

RUN install -d -m 0755 /etc/dnf/libdnf5.conf.d /etc/dnf/repos.override.d /etc/xdg/KDE
COPY build_files/dnf-krisos.conf /etc/dnf/libdnf5.conf.d/90-krisos.conf
COPY build_files/90-krisos-privacy.repo /etc/dnf/repos.override.d/90-krisos-privacy.repo
COPY build_files/KDE-UserFeedback.conf /etc/xdg/KDE/UserFeedback.conf

COPY build_files/base-packages.txt /tmp/base-packages.txt
RUN set -eux; \
    rpm -qa --qf '%{NAME}\n' > /tmp/fedora-base-names.raw; \
    sed -e '/^gpg-pubkey$/d' /tmp/fedora-base-names.raw > /tmp/fedora-base-names.filtered; \
    LC_ALL=C sort -u /tmp/fedora-base-names.filtered > /tmp/fedora-base-names.txt; \
    test -s /tmp/fedora-base-names.txt; \
    for pkg in bootc bootupd dracut ostree systemd rpm dnf5 kernel-core; do \
      grep -Fxq "$pkg" /tmp/fedora-base-names.txt || { echo "Pinned Fedora base sanity check failed: missing $pkg" >&2; exit 1; }; \
    done; \
    sed -e 's/\r$//' -e 's/[[:space:]]*#.*$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e '/^$/d' /tmp/base-packages.txt > /tmp/krisos-delta-names.raw; \
    LC_ALL=C sort -u /tmp/krisos-delta-names.raw > /tmp/krisos-delta-names.txt; \
    LC_ALL=C comm -12 /tmp/fedora-base-names.txt /tmp/krisos-delta-names.txt > /tmp/krisos-base-collisions.txt; \
    if [ -s /tmp/krisos-base-collisions.txt ]; then cat /tmp/krisos-base-collisions.txt >&2; exit 1; fi; \
    : > /tmp/fedora-base-nevra.before; \
    while IFS= read -r pkg; do rpm -q --qf '%{NAME}\t%{EPOCHNUM}:%{VERSION}-%{RELEASE}.%{ARCH}\n' "$pkg" >> /tmp/fedora-base-nevra.before; done < /tmp/fedora-base-names.txt; \
    LC_ALL=C sort -u -o /tmp/fedora-base-nevra.before /tmp/fedora-base-nevra.before; \
    base_excludes="$(paste -sd, /tmp/fedora-base-names.txt)"; \
    xargs -r dnf5 -y --setopt=install_weak_deps=False --setopt="excludepkgs=${base_excludes}" install < /tmp/krisos-delta-names.txt; \
    rpm -q glibc-langpack-en glibc-langpack-it langpacks-core-en langpacks-core-it; \
    if rpm -q glibc-all-langpacks >/dev/null 2>&1; then \
      grep -Fxq glibc-all-langpacks /tmp/fedora-base-names.txt && exit 1; \
      rpm -e glibc-all-langpacks; \
    fi; \
    assert_absent() { if rpm -q "$1" >/dev/null 2>&1; then echo "forbidden package installed: $1" >&2; exit 1; fi; }; \
    for pkg in glibc-all-langpacks pipewire-jack-audio-connection-kit pipewire-jack-audio-connection-kit-libs sane-backends sane-backends-libs sane-airscan libsane-airscan; do assert_absent "$pkg"; done; \
    rpm -q NetworkManager-wifi wpa_supplicant bluedevil bluez bluez-obexd mt7xxx-firmware amd-gpu-firmware amd-ucode-firmware mesa-dri-drivers mesa-vulkan-drivers udisks2 dolphin konsole kate spectacle ark gwenview okular kcalc kio-admin kinfocenter power-profiles-daemon plasma-print-manager cups cups-filters plasma-firewall plasma-firewall-firewalld firewalld iproute tar bash-completion ntfs-3g ntfsprogs os-prober zram-generator zram-generator-defaults; \
    rpm -q --whatprovides mesa-va-drivers; \
    test -e /usr/lib64/dri/radeonsi_drv_video.so; \
    test -f /usr/lib/firmware/rtl_nic/rtl8168h-2.fw.xz; \
    assert_absent linux-firmware; \
    ! rpm -qa --qf '%{ARCH}\n' | grep -qx i686; \
    dnf5 check --dependencies; \
    : > /tmp/fedora-base-nevra.after; \
    while IFS= read -r pkg; do rpm -q --qf '%{NAME}\t%{EPOCHNUM}:%{VERSION}-%{RELEASE}.%{ARCH}\n' "$pkg" >> /tmp/fedora-base-nevra.after; done < /tmp/fedora-base-names.txt; \
    LC_ALL=C sort -u -o /tmp/fedora-base-nevra.after /tmp/fedora-base-nevra.after; \
    diff -u /tmp/fedora-base-nevra.before /tmp/fedora-base-nevra.after; \
    dnf5 clean all; \
    rm -f /tmp/base-packages.txt /tmp/fedora-base-names.raw /tmp/fedora-base-names.filtered /tmp/fedora-base-names.txt /tmp/krisos-delta-names.raw /tmp/krisos-delta-names.txt /tmp/krisos-base-collisions.txt /tmp/fedora-base-nevra.before /tmp/fedora-base-nevra.after

COPY build_files/krisCC/krisCC.rpm /tmp/krisCC.rpm
RUN set -eux; \
    rpm -Uvh /tmp/krisCC.rpm; \
    rpm -q krisCC; \
    rpm -V krisCC; \
    rm -f /tmp/krisCC.rpm
COPY build_files/krisCC-autostart.desktop /etc/xdg/autostart/krisCC-background.desktop

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
COPY systemd/krisos-sync.service /usr/lib/systemd/system/krisos-sync.service
RUN systemctl enable krisos-sync.service

COPY systemd/krisos-overlay.sh /usr/libexec/krisos-overlay
COPY systemd/krisos-overlay.service /usr/lib/systemd/system/krisos-overlay.service
RUN chmod 0755 /usr/libexec/krisos-overlay

COPY build_files/55-krisos-hardening.conf /usr/lib/sysctl.d/55-krisos-hardening.conf

RUN set -eux; \
    install -d -m 0755 /usr/share/krisos; \
    rpm -qa --qf '%{NAME}\n' | sed -e '/^gpg-pubkey$/d' | LC_ALL=C sort -u > /usr/share/krisos/owned-packages.txt; \
    test -s /usr/share/krisos/owned-packages.txt; \
    rpm -qa --qf '%{NAME}\t%{EPOCHNUM}:%{VERSION}-%{RELEASE}.%{ARCH}\n' | sed '/^gpg-pubkey\t/d' | LC_ALL=C sort -u > /usr/share/krisos/owned-nevra.txt; \
    grep -Fxq krisCC /usr/share/krisos/owned-packages.txt; \
    ! grep -Fxq gpg-pubkey /usr/share/krisos/owned-packages.txt

COPY build_files/tmpfiles-krisos.conf /usr/lib/tmpfiles.d/krisos.conf
RUN set -eux; \
    install -d -m 0755 /usr/share/factory/var/lib/krisos; \
    install -d -m 0755 /usr/share/factory/var/lib/NetworkManager; \
    : > /usr/share/factory/var/lib/krisos/packages.list
COPY build_files/NetworkManager.state /usr/share/factory/var/lib/NetworkManager/NetworkManager.state

RUN set -eux; \
    printf '%s\n' 'LANG=it_IT.UTF-8' > /etc/locale.conf; \
    test -f /etc/bluetooth/main.conf; \
    sed -i 's/^#AutoEnable=true$/AutoEnable=false/' /etc/bluetooth/main.conf; \
    grep -Fxq 'AutoEnable=false' /etc/bluetooth/main.conf; \
    test -f /etc/xdg/autostart/geoclue-demo-agent.desktop; \
    grep -Fxq 'Hidden=true' /etc/xdg/autostart/geoclue-demo-agent.desktop || printf '\nHidden=true\n' >> /etc/xdg/autostart/geoclue-demo-agent.desktop; \
    firewall-offline-cmd --zone=public --remove-service-from-zone=ssh; \
    firewall-offline-cmd --zone=public --remove-service-from-zone=mdns; \
    systemctl enable krisos-overlay.service; \
    systemctl enable krisos-sync.service; \
    systemctl enable --force plasmalogin.service; \
    systemctl enable firewalld.service; \
    systemctl enable systemd-timesyncd.service; \
    systemctl disable systemd-homed.service; \
    systemctl disable avahi-daemon.service avahi-daemon.socket; \
    systemctl disable mdmonitor.service raid-check.timer; \
    systemctl disable flatpak-add-fedora-repos.service; \
    systemctl mask dnf-makecache.timer dnf5-makecache.timer || true

CMD ["/sbin/init"]
