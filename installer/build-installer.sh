#!/usr/bin/bash
set -euo pipefail

if [[ $EUID -eq 0 ]]; then
    echo "Run this script as your normal user; it invokes sudo only where needed." >&2
    exit 1
fi

if ! command -v podman >/dev/null 2>&1; then
    echo "Missing required command: podman" >&2
    exit 1
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_dir="$repo_root/installer/output"
installer_image="${KRISOS_INSTALLER_IMAGE:-localhost/krisos-installer-complete:f45}"
payload_ref="${KRISOS_PAYLOAD_REF:-localhost/krisos-iso-payload:20260918}"
image_builder_image="${IMAGE_BUILDER_IMAGE:-ghcr.io/osbuild/image-builder-cli:latest}"

sudo rm -rf -- "$output_dir"
mkdir -p "$output_dir"

if [[ "$payload_ref" == localhost/* ]]; then
    printf 'Using locally built KrisOS payload: %s\n' "$payload_ref"
    if ! sudo podman image exists "$payload_ref"; then
        echo "Local payload image not found: $payload_ref" >&2
        exit 1
    fi
else
    printf 'Pulling KrisOS payload: %s\n' "$payload_ref"
    sudo podman pull "$payload_ref"
fi

printf 'Payload image ID: '
sudo podman image inspect "$payload_ref" --format '{{.Id}}'

printf 'Building Fedora 45 Anaconda bootc installer runtime...\n'
sudo podman build \
    --pull=always \
    -f "$repo_root/installer/Containerfile" \
    -t "$installer_image" \
    "$repo_root/installer"

printf 'Pulling Image Builder...\n'
sudo podman pull "$image_builder_image"
printf 'Image Builder digest: '
sudo podman image inspect "$image_builder_image" --format '{{.Digest}}'

printf 'Building bootc-installer ISO with embedded payload %s...\n' "$payload_ref"
sudo podman run \
    --rm \
    --privileged \
    --security-opt label=type:unconfined_t \
    -v /var/lib/containers/storage:/var/lib/containers/storage \
    -v "$output_dir:/output" \
    "$image_builder_image" \
    build \
    --output-dir /output \
    --bootc-ref "$installer_image" \
    --bootc-installer-payload-ref "$payload_ref" \
    --bootc-default-fs ext4 \
    bootc-installer

sudo chown -R "$(id -u):$(id -g)" "$output_dir"

iso="$(find "$output_dir" -type f -name '*.iso' -print -quit)"
if [[ -z "$iso" ]]; then
    echo "Image Builder completed without producing an ISO." >&2
    exit 1
fi

(
    cd "$output_dir"
    find . -type f ! -name SHA256SUMS -print0 \
        | LC_ALL=C sort -z \
        | xargs -0 sha256sum > SHA256SUMS
)

printf '\nInstaller ISO:\n%s\n' "$iso"
printf '\nInstaller artifacts:\n'
find "$output_dir" -maxdepth 3 -type f -printf '%s %p\n' | sort -n
