#!/usr/bin/bash
set -euo pipefail

if [[ $EUID -eq 0 ]]; then
    echo "Run this script as your normal user; it invokes sudo only where needed." >&2
    exit 1
fi

RAKU_IMAGE="${RAKU_IMAGE:-}"
if [[ -z "$RAKU_IMAGE" ]]; then
    echo "Set RAKU_IMAGE to the registry image to install." >&2
    echo "Example: RAKU_IMAGE=registry.example/raku-kris:tag ./installer/build-installer.sh" >&2
    exit 1
fi

if [[ "$RAKU_IMAGE" =~ [[:space:]] ]] || [[ "$RAKU_IMAGE" == registry:* ]]; then
    echo "RAKU_IMAGE must be a plain OCI registry reference without spaces or a registry: prefix." >&2
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
installer_image="localhost/raku-kris-installer:f45"

mkdir -p "$output_dir"

printf 'Building Fedora 45 installer runtime for payload: %s\n' "$RAKU_IMAGE"
sudo podman build \
    --pull=always \
    --build-arg "RAKU_IMAGE=$RAKU_IMAGE" \
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
