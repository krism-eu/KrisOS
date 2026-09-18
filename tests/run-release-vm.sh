#!/usr/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target="${KRISOS_E2E_TARGET:?Set KRISOS_E2E_TARGET, for example qa@192.0.2.10}"
expected_kriscc="${KRISOS_EXPECT_KRISCC:-}"
expected_image="${KRISOS_EXPECT_IMAGE:-}"
switch_image="${KRISOS_E2E_SWITCH_IMAGE:-}"
token="${KRISOS_E2E_TOKEN:-krisos-e2e-$(date +%s)-$$}"
remote_dir="/tmp/krisos-release-e2e"
ssh_opts=(-o BatchMode=yes -o ConnectTimeout=8)

validate_simple() {
    local name="$1"
    local value="$2"
    local pattern="$3"
    if [[ -n "$value" && ! "$value" =~ $pattern ]]; then
        echo "Unsafe $name value: $value" >&2
        exit 2
    fi
}

validate_simple "KRISOS_EXPECT_KRISCC" "$expected_kriscc" '^[A-Za-z0-9._+:-]+$'
validate_simple "KRISOS_EXPECT_IMAGE" "$expected_image" '^[A-Za-z0-9._/@:+-]+$'
validate_simple "KRISOS_E2E_SWITCH_IMAGE" "$switch_image" '^[A-Za-z0-9._/@:+-]+$'
validate_simple "KRISOS_E2E_TOKEN" "$token" '^[A-Za-z0-9._-]+$'

upload_checks() {
    tar -C "$repo_root/tests" -cf - boot-check.sh release-check.sh |
        ssh "${ssh_opts[@]}" "$target"             "rm -rf '$remote_dir' && mkdir -p '$remote_dir' && tar -C '$remote_dir' -xf - && chmod 0755 '$remote_dir/'*.sh"
}

run_release_check() {
    local mode="$1"
    ssh "${ssh_opts[@]}" "$target"         "sudo env KRISOS_EXPECT_KRISCC='$expected_kriscc' KRISOS_EXPECT_IMAGE='$expected_image' KRISOS_E2E_TOKEN='$token' '$remote_dir/release-check.sh' '$mode'"
}

wait_for_new_boot() {
    local old_boot_id="$1"
    local new_boot_id=""
    for _ in $(seq 1 60); do
        sleep 5
        new_boot_id="$(ssh "${ssh_opts[@]}" "$target" 'cat /proc/sys/kernel/random/boot_id' 2>/dev/null || true)"
        if [[ -n "$new_boot_id" && "$new_boot_id" != "$old_boot_id" ]]; then
            printf 'Observed new boot id: %s\n' "$new_boot_id"
            return 0
        fi
    done
    echo "VM did not return with a new boot id within 300 seconds." >&2
    return 1
}

reboot_and_wait() {
    local old_boot_id
    old_boot_id="$(ssh "${ssh_opts[@]}" "$target" 'cat /proc/sys/kernel/random/boot_id')"
    ssh "${ssh_opts[@]}" "$target" 'sudo systemctl reboot' || true
    wait_for_new_boot "$old_boot_id"
    upload_checks
}

upload_checks

if [[ -n "$switch_image" ]]; then
    echo "Switching VM to immutable candidate: $switch_image"
    ssh "${ssh_opts[@]}" "$target" "sudo bootc switch '$switch_image'"
    reboot_and_wait
fi

run_release_check check
run_release_check prepare-reboot
reboot_and_wait
run_release_check verify-reboot

echo "KrisOS VM release validation passed for $target"
