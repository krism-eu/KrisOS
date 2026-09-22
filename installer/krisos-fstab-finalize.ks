# KrisOS installer-only finalization for bootc-managed Anaconda installs.
# Keep this narrowly scoped: do not rewrite mounts or fstab options.
%post --nochroot --erroronfail
set -eu

fstab=/mnt/sysimage/etc/fstab
anaconda_stamp='Created by anaconda'
bootc_stamp='Updated by bootc-fstab-edit.service'

[ -f "$fstab" ] || exit 0
grep -Fq "$anaconda_stamp" "$fstab" || exit 0
grep -Fq "$bootc_stamp" "$fstab" && exit 0

# If Anaconda already emitted the root mount read-only, bootc has nothing to
# change. Record bootc's own marker so its generator does not schedule the
# no-op fstab editor on every boot. If root is not already ro, leave fstab
# untouched and let bootc perform its normal one-time fix.
if awk '
  /^[[:space:]]*#/ || NF < 4 { next }
  $2 == "/" {
    n = split($4, opts, ",")
    for (i = 1; i <= n; i++) {
      if (opts[i] == "ro") found = 1
    }
  }
  END { exit found ? 0 : 1 }
' "$fstab"; then
    printf '\n# %s\n' "$bootc_stamp" >> "$fstab"
fi
%end
