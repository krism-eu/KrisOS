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
installer_image="localhost/krisos-installer:f45"
image_builder_image="${IMAGE_BUILDER_IMAGE:-ghcr.io/osbuild/image-builder-cli:latest}"

rm -rf "$output_dir"
mkdir -p "$output_dir"

printf 'Building generic Fedora 45 KrisOS installer runtime...\n'
sudo podman build \
    --pull=always \
    -f "$repo_root/installer/Containerfile" \
    -t "$installer_image" \
    "$repo_root/installer"

printf 'Pulling containerized Image Builder...\n'
sudo podman pull "$image_builder_image"

printf 'Image Builder image digest: '
sudo podman image inspect "$image_builder_image" --format '{{.Digest}}'

printf 'Building bootc-generic-iso...\n'
sudo podman run \
    --rm \
    --privileged \
    --security-opt label=disable \
    -v /var/lib/containers/storage:/var/lib/containers/storage \
    -v "$output_dir:/output" \
    "$image_builder_image" \
    build \
    --output-dir /output \
    --bootc-ref "$installer_image" \
    --bootc-default-fs ext4 \
    bootc-generic-iso

sudo chown -R "$(id -u):$(id -g)" "$output_dir"

if ! find "$output_dir" -type f -name '*.iso' -print -quit | grep -q .; then
    echo "Image Builder completed without producing an ISO." >&2
    exit 1
fi

(
    cd "$output_dir"
    find . -type f ! -name SHA256SUMS -print0 \
        | LC_ALL=C sort -z \
        | xargs -0 sha256sum > SHA256SUMS
)

printf '\nInstaller artifacts:\n'
find "$output_dir" -maxdepth 3 -type f -printf '%p\n' | sort
