#!/usr/bin/env bash
set -euo pipefail

# KrisOS quick path through the actively maintained TunaOS bootc-installer.
# Run this from a Fedora live session with network access.

default_image="ghcr.io/krism-eu/krisos:1b54db16a8208e226e65ec54653cd4880da38dd1"
image="${KRISOS_IMAGE:-$default_image}"
target="${KRISOS_TARGET_REF:-$image}"

bundle_url="https://github.com/tuna-os/bootc-installer/releases/download/latest-dev/org.bootcinstaller.Installer.Devel.flatpak"
bundle_sha256="82e044c2a49c58456bfdb4d4e333a965abdf4b012dbb91784ff37a49708dd4b2"
app_id="org.bootcinstaller.Installer.Devel"

for cmd in curl flatpak python3 sha256sum sudo; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "Missing required command: $cmd" >&2
        exit 1
    }
done

case "$image" in
    ghcr.io/krism-eu/krisos:*) ;;
    *)
        echo "KRISOS_IMAGE must be a ghcr.io/krism-eu/krisos:<tag> reference" >&2
        exit 1
        ;;
esac

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

echo "KrisOS source image: $image"
echo "KrisOS update target: $target"
echo "Fetching pinned TunaOS bootc-installer bundle..."
curl -fL --retry 3 --retry-delay 2 -o "$tmpdir/installer.flatpak" "$bundle_url"
printf '%s  %s\n' "$bundle_sha256" "$tmpdir/installer.flatpak" | sha256sum -c -

python3 - "$image" "$target" "$tmpdir" <<'PY'
import json
import pathlib
import sys

image, target, out = sys.argv[1:4]
out = pathlib.Path(out)

images = {
    "default_image": image,
    "fallback_flatpaks": [],
    "images": [
        {
            "name": "KrisOS",
            "icon": "computer-symbolic",
            "needs_user_creation": True,
            "children": [
                {
                    "name": "K1",
                    "imgref": image,
                    "desc": "KrisOS K1 Fedora bootc image",
                    "composefs": False,
                    "bootloader": "grub2",
                    "filesystem": "ext4",
                    "needs_user_creation": True,
                }
            ],
        }
    ],
}

recipe = {
    "hostname": "krisos",
    "filesystem": "ext4",
    "selinuxDisabled": False,
    "unifiedStorage": False,
    "composeFsBackend": False,
    "bootloader": "grub2",
    "targetImgref": target,
    "flatpaks": [],
    "distroID": "krisos",
}

(out / "images.json").write_text(json.dumps(images, indent=2) + "\n")
(out / "recipe.json").write_text(json.dumps(recipe, indent=2) + "\n")
PY

sudo install -d -m 0755 /etc/bootc-installer
sudo install -m 0644 "$tmpdir/images.json" /etc/bootc-installer/images.json
sudo install -m 0644 "$tmpdir/recipe.json" /etc/bootc-installer/recipe.json

# The bundle published on 2026-09-25 carries tuna-os/fisherman
# 60f672ff376f079dd88b66d3058aed32bedfdc3d.
sudo flatpak install --bundle -y "$tmpdir/installer.flatpak"

echo
echo "Launching KrisOS installer..."
echo "The selected source is $image"
echo "The installed system will track $target"
exec flatpak run "$app_id"
