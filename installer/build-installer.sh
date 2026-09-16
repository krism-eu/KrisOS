#!/usr/bin/bash
set -euo pipefail

if [[ $EUID -eq 0 ]]; then
    echo "Run this script as your normal user; it invokes sudo only where needed." >&2
    exit 1
fi

for cmd in podman image-builder; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Missing required command: $cmd" >&2
        exit 1
    fi
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_dir="$repo_root/installer/output"
installer_image="localhost/krisos-installer:f45"

mkdir -p "$output_dir"

printf 'Building generic Fedora 45 KrisOS installer runtime...\n'
sudo podman build \
    --pull=always \
    -f "$repo_root/installer/Containerfile" \
    -t "$installer_image" \
    "$repo_root/installer"

printf 'Building bootc-generic-iso...\n'
sudo image-builder build \
    --bootc-ref "$installer_image" \
    --bootc-default-fs ext4 \
    --output-dir "$output_dir" \
    bootc-generic-iso

printf '\nInstaller artifacts:\n'
find "$output_dir" -maxdepth 3 -type f -printf '%p\n' | sort
