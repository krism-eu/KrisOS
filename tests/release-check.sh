#!/usr/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mode="${1:-check}"
expected_kriscc="${KRISOS_EXPECT_KRISCC:-}"
expected_image="${KRISOS_EXPECT_IMAGE:-}"
token="${KRISOS_E2E_TOKEN:-}"
sentinel="/usr/local/share/.krisos-release-e2e"

fail=0

pass() {
    printf 'PASS: %s\n' "$1"
}

fail_check() {
    printf 'FAIL: %s\n' "$1" >&2
    fail=1
}

run_check() {
    local label="$1"
    shift
    if "$@"; then
        pass "$label"
    else
        fail_check "$label"
    fi
}

if [[ "$mode" != "check" && "$mode" != "prepare-reboot" && "$mode" != "verify-reboot" ]]; then
    echo "Usage: $0 [check|prepare-reboot|verify-reboot]" >&2
    exit 2
fi

if bash "$script_dir/boot-check.sh"; then
    pass "base boot checks"
else
    fail_check "base boot checks"
fi

status_file="$(mktemp)"
rk_file="$(mktemp)"
trap 'rm -f "$status_file" "$rk_file"' EXIT

if bootc status --format json >"$status_file"; then
    pass "bootc status JSON"
else
    fail_check "bootc status JSON"
fi

if [[ -n "$expected_image" ]]; then
    if python3 "$script_dir/release-state.py" image "$status_file" "$expected_image"; then
        pass "expected image is the booted deployment"
    else
        fail_check "expected image is the booted deployment"
    fi
fi

run_check "SELinux enforcing" bash -c 'getenforce | grep -qx Enforcing'
run_check "kernel cmdline keeps SELinux enabled" bash -c '! grep -Eq "(^|[[:space:]])(selinux=0|enforcing=0)([[:space:]]|$)" /proc/cmdline'

run_check "krisCC installed" rpm -q krisCC
run_check "krisCC files verify" rpm -V --nomtime krisCC
run_check "krisCC executable" test -x /usr/bin/krisCC
run_check "krisCC owned by immutable image" grep -Fxq krisCC /usr/share/krisos/owned-packages.txt
run_check "ISO Image Writer installed" rpm -q isoimagewriter
run_check "ISO Image Writer executable" test -x /usr/bin/isoimagewriter
run_check "Gwenview removed from immutable image" bash -c '! rpm -q gwenview >/dev/null 2>&1'
run_check "Plasma Discover installed" rpm -q plasma-discover
run_check "Plasma Discover Flatpak backend installed" rpm -q plasma-discover-flatpak
run_check "Discover notifier omitted" bash -c '! rpm -q plasma-discover-notifier >/dev/null 2>&1'
run_check "Discover PackageKit backend omitted" bash -c '! rpm -q plasma-discover-packagekit >/dev/null 2>&1'
run_check "PackageKit omitted" bash -c '! rpm -q PackageKit >/dev/null 2>&1'
run_check "Cockpit installed" rpm -q cockpit
run_check "Cockpit socket disabled by default" bash -c 'systemctl is-enabled cockpit.socket 2>&1 | grep -qx disabled'
run_check "DNF weak dependencies disabled" grep -Fxq 'install_weak_deps=False' /etc/dnf/libdnf5.conf.d/90-krisos.conf

run_check "useradd default points to /var/home" grep -Fxq 'HOME=/var/home' /etc/default/useradd
run_check "SELinux /var/home user context" bash -c "matchpathcon -n /var/home/kris | grep -q ':user_home_dir_t:'"
run_check "SELinux config context below /var/home" bash -c "matchpathcon -n /var/home/kris/.config | grep -q ':config_home_t:'"
run_check "SELinux data context below /var/home" bash -c "matchpathcon -n /var/home/kris/.local/share | grep -q ':data_home_t:'"

kernel_image="/usr/lib/modules/$(uname -r)/initramfs.img"
run_check "canonical initramfs present" test -s "$kernel_image"
run_check "AMD early microcode embedded" bash -c "lsinitrd '$kernel_image' | grep -F 'kernel/x86/microcode/AuthenticAMD.bin' >/dev/null"

expected_admin_user="${KRISOS_EXPECT_ADMIN_USER:-}"
if [[ -n "$expected_admin_user" ]]; then
    run_check "expected admin user exists" getent passwd "$expected_admin_user"
    run_check "expected admin user is in wheel" bash -c "id -nG '$expected_admin_user' | tr ' ' '\n' | grep -qx wheel"
    admin_home="$(getent passwd "$expected_admin_user" | cut -d: -f6)"
    if [[ -n "$admin_home" ]]; then
        run_check "admin home resolves below /var/home" bash -c 'test "$(readlink -f -- "$1")" = "$2"' _ "$admin_home" "/var/home/$expected_admin_user"
        run_check "admin home SELinux label" bash -c "ls -Zd '/var/home/$expected_admin_user' | grep -q ':user_home_dir_t:'"
    fi
fi

actual_kriscc="$(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}' krisCC 2>/dev/null || true)"
if [[ -n "$expected_kriscc" ]]; then
    if [[ "$actual_kriscc" == "$expected_kriscc" ]]; then
        pass "expected krisCC NEVRA"
    else
        printf 'Expected krisCC %s, found %s\n' "$expected_kriscc" "${actual_kriscc:-missing}" >&2
        fail_check "expected krisCC NEVRA"
    fi
fi

owned_nevra_line="$(rpm -q --qf '%{NAME}\t%{EPOCHNUM}:%{VERSION}-%{RELEASE}.%{ARCH}' krisCC 2>/dev/null || true)"
if [[ -n "$owned_nevra_line" ]] && grep -Fxq "$owned_nevra_line" /usr/share/krisos/owned-nevra.txt; then
    pass "krisCC NEVRA matches immutable ownership snapshot"
else
    fail_check "krisCC NEVRA matches immutable ownership snapshot"
fi

run_check "krisos-sync timer enabled" bash -c 'systemctl is-enabled krisos-sync.timer | grep -qx enabled'
run_check "krisos-sync timer active" bash -c 'systemctl is-active krisos-sync.timer | grep -qx active'

if /usr/bin/rk status --json >"$rk_file" 2>&1 && python3 "$script_dir/release-state.py" rk "$rk_file"; then
    pass "rk overlay ready and recovery complete"
else
    cat "$rk_file" >&2 || true
    fail_check "rk overlay ready and recovery complete"
fi

run_check "krisCC offscreen smoke" timeout 20s env     QT_QPA_PLATFORM=offscreen     QT_QUICK_BACKEND=software     QT_QUICK_CONTROLS_STYLE=Basic     KRISCC_SMOKE_TEST=1     /usr/bin/krisCC --background

case "$mode" in
    prepare-reboot)
        if [[ $EUID -ne 0 ]]; then
            echo "prepare-reboot must run as root" >&2
            exit 2
        fi
        if [[ -z "$token" ]]; then
            echo "KRISOS_E2E_TOKEN is required for prepare-reboot" >&2
            exit 2
        fi
        install -d -m 0755 "$(dirname "$sentinel")"
        printf '%s\n' "$token" > "$sentinel"
        chmod 0644 "$sentinel"
        sync "$sentinel"
        pass "overlay persistence sentinel prepared"
        ;;
    verify-reboot)
        if [[ $EUID -ne 0 ]]; then
            echo "verify-reboot must run as root" >&2
            exit 2
        fi
        if [[ -z "$token" ]]; then
            echo "KRISOS_E2E_TOKEN is required for verify-reboot" >&2
            exit 2
        fi
        if [[ -f "$sentinel" ]] && grep -Fxq "$token" "$sentinel"; then
            pass "overlay persistence across reboot"
            rm -f "$sentinel"
        else
            fail_check "overlay persistence across reboot"
        fi
        ;;
esac

echo
if [[ "$fail" -eq 0 ]]; then
    echo "KRISOS RELEASE CHECKS PASSED"
else
    echo "KRISOS RELEASE CHECKS FAILED"
fi
exit "$fail"
