# KrisOS installer-only network finalization.
# Keep kernel IPv6 support available, but make every NetworkManager keyfile
# created by Anaconda IPv4-only for the installed target. This does not touch
# the live installer network and does not add a kernel command-line disable.
%post --nochroot --erroronfail
set -eu

sysroot=/mnt/sysroot
profiles="$sysroot/etc/NetworkManager/system-connections"

[ -d "$sysroot" ] || {
    echo "KrisOS target system root is missing: $sysroot" >&2
    exit 1
}
[ -x "$sysroot/usr/bin/nmcli" ] || {
    echo "KrisOS target nmcli is missing" >&2
    exit 1
}

if [ -d "$profiles" ]; then
    for profile in "$profiles"/*.nmconnection; do
        [ -f "$profile" ] || continue
        tmp="$(mktemp)"
        trap 'rm -f "$tmp"' EXIT
        chroot "$sysroot" /usr/bin/nmcli --offline connection modify ipv6.method disabled \
            < "$profile" > "$tmp"
        install -m 0600 -o root -g root "$tmp" "$profile"
        name="${profile##*/}"
        chroot "$sysroot" /usr/sbin/restorecon -F -- "/etc/NetworkManager/system-connections/$name"
        grep -Fq 'method=disabled' "$profile" || {
            echo "KrisOS failed to disable IPv6 in NetworkManager profile: $name" >&2
            exit 1
        }
        rm -f "$tmp"
        trap - EXIT
    done
fi
%end
