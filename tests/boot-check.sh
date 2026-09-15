#!/bin/bash
# Post-boot smoke test for raku-Kris M0. Run on the booted system.
set -u

fail=0

check() {
    if eval "$2"; then
        echo "PASS: $1"
    else
        echo "FAIL: $1"
        fail=1
    fi
}

check "OSTree backend contract"  "grep -Eq '(^|[[:space:]])ostree=/ostree/boot\.[01]/[^/[:space:]]+/[0-9a-f]+/[0-9]+([[:space:]]|$)' /proc/cmdline"
check "/usr dedicated overlay"    "test \"$(findmnt -T /usr -n -o TARGET)\" = /usr && test \"$(findmnt -T /usr -n -o FSTYPE)\" = overlay"
check "overlay service active"    "systemctl is-active raku-kris-overlay.service | grep -qx active"
check "deployment recorded"       "test -s /var/lib/raku-kris/deployment"
check "overlay upper present"     "test -d /var/lib/raku-kris/upper"
check "overlay work present"      "test -d /var/lib/raku-kris/work"
check "package intent seed"       "test -e /var/lib/raku-kris/packages.list"
check "SELinux enforcing"         "getenforce | grep -qx Enforcing"
check "login manager active"      "systemctl is-active plasmalogin.service | grep -qx active"

echo
if [ "$fail" -eq 0 ]; then
    echo "ALL CHECKS PASSED"
else
    echo "SOME CHECKS FAILED"
fi
exit "$fail"
