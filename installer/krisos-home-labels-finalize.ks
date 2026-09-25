# KrisOS installer-only SELinux finalization for a fresh bootc target.
# Anaconda creates the local user after bootc's physical-root relabel.  With
# /home -> /var/home and a separately mounted /var/home, Anaconda's
# restorecon -r /home/USER does not leave the real persistent tree correctly
# labeled.  Reconcile the freshly created mutable state with the TARGET policy
# before first boot.  This runs only during installation, never on updates.
%post --nochroot --erroronfail
set -eu

sysroot=/mnt/sysroot
restorecon=/usr/sbin/restorecon

[ -d "$sysroot" ] || {
    echo "KrisOS target system root is missing: $sysroot" >&2
    exit 1
}
[ -x "$sysroot$restorecon" ] || {
    echo "KrisOS target restorecon is missing" >&2
    exit 1
}
grep -Fxq 'HOME=/var/home' "$sysroot/etc/default/useradd"
grep -Eq '^SELINUX=enforcing$' "$sysroot/etc/selinux/config"

# /etc is mutable per-deployment state.  Anaconda creates/updates passwd,
# shadow, hostname, localtime and related files after bootc's earlier relabel.
# -F is intentional here: this is a fresh install and both SELinux user/role
# and type must match the target policy.
chroot "$sysroot" "$restorecon" -RFv /etc

# Relabel the real persistent homes, not the /home compatibility symlink.
for home in "$sysroot"/var/home/*; do
    [ -d "$home" ] || continue
    [ ! -L "$home" ] || continue
    user=${home##*/}

    chroot "$sysroot" getent passwd "$user" >/dev/null 2>&1 || continue
    chroot "$sysroot" "$restorecon" -RFv -- "/var/home/$user"
done

# Installation must fail rather than ship a target that would be blocked by
# SELinux on first boot.  Dry-run output means a mismatch is still present.
etc_preview="$(chroot "$sysroot" "$restorecon" -nRFv /etc)"
if [ -n "$etc_preview" ]; then
    echo "KrisOS target /etc still has SELinux label mismatches:" >&2
    printf '%s\n' "$etc_preview" >&2
    exit 1
fi

for home in "$sysroot"/var/home/*; do
    [ -d "$home" ] || continue
    [ ! -L "$home" ] || continue
    user=${home##*/}
    chroot "$sysroot" getent passwd "$user" >/dev/null 2>&1 || continue

    home_preview="$(chroot "$sysroot" "$restorecon" -nRFv -- "/var/home/$user")"
    if [ -n "$home_preview" ]; then
        echo "KrisOS target home still has SELinux label mismatches: /var/home/$user" >&2
        printf '%s\n' "$home_preview" >&2
        exit 1
    fi
done
%end
