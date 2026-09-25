# KrisOS installer-only fstab finalization for bootc/composefs installs.
# The physical root is selected by bootc kernel arguments.  Listing that same
# backing filesystem as / in fstab makes systemd-remount-fs try to remount the
# composefs root and fail with mount(8) exit 32.  Preserve normal /boot and
# persistent-data entries, but remove the redundant / entry.
%post --nochroot --erroronfail
set -eu

sysroot=/mnt/sysroot
fstab="$sysroot/etc/fstab"
anaconda_stamp='Created by anaconda'
bootc_stamp='Updated by bootc-fstab-edit.service'

[ -d "$sysroot" ] || {
    echo "KrisOS target system root is missing: $sysroot" >&2
    exit 1
}
[ -f "$fstab" ] || {
    echo "KrisOS target fstab is missing" >&2
    exit 1
}
grep -Fq "$anaconda_stamp" "$fstab" || {
    echo "KrisOS target fstab was not created by Anaconda" >&2
    exit 1
}

root_count_before="$(awk '
  /^[[:space:]]*#/ || NF < 4 { next }
  $2 == "/" { count++ }
  END { print count + 0 }
' "$fstab")"
[ "$root_count_before" -eq 1 ] || {
    echo "KrisOS expected exactly one Anaconda root entry before finalization, found $root_count_before" >&2
    exit 1
}

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
awk '
  /^[[:space:]]*#/ || NF < 4 { print; next }
  $2 == "/" { next }
  { print }
' "$fstab" > "$tmp"
cat "$tmp" > "$fstab"

if ! grep -Fq "$bootc_stamp" "$fstab"; then
    printf '\n# %s\n' "$bootc_stamp" >> "$fstab"
fi
printf '%s\n' '# KrisOS: bootc kernel arguments own the physical root; composefs / is not an fstab remount target.' >> "$fstab"

root_count_after="$(awk '
  /^[[:space:]]*#/ || NF < 4 { next }
  $2 == "/" { count++ }
  END { print count + 0 }
' "$fstab")"
[ "$root_count_after" -eq 0 ] || {
    echo "KrisOS root entry survived fstab finalization" >&2
    exit 1
}
%end
