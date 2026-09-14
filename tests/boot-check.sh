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

check "/usr is overlay"        "findmnt -no FSTYPE /usr | grep -qx overlay"
check "deployment recorded"    "test -s /var/lib/raku-kris/deployment"
check "overlay upper present"  "test -d /var/lib/raku-kris/upper"
check "overlay work present"   "test -d /var/lib/raku-kris/work"
check "hook ran (journal)"     "journalctl -b | grep -q raku-kris-overlay"
check "SELinux enforcing"      "getenforce | grep -qx Enforcing"
check "login manager active"   "systemctl is-active plasmalogin.service | grep -qx active"

echo
if [ "$fail" -eq 0 ]; then
    echo "ALL CHECKS PASSED"
else
    echo "SOME CHECKS FAILED"
fi
exit "$fail"
