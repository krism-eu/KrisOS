#!/usr/bin/env bash
set -euo pipefail

# KrisOS install on pre-existing partitions through the current TunaOS
# bootc-installer/Fisherman backend.  This path never repartitions a whole disk:
# customMounts makes Fisherman skip its automatic partitioning code.

default_image="ghcr.io/krism-eu/krisos@sha256:a7e79ac9a3b524571e8b6788f6ac401c9b34a0b8bd364a0011093fc1720a67be"
default_target="ghcr.io/krism-eu/krisos:4be27021c77f3942d896e5a59baeb3af1e78e3ed"
image="${KRISOS_IMAGE:-$default_image}"
target="${KRISOS_TARGET_REF:-$default_target}"

# Immutable GitHub release asset published 2026-09-25.
# It contains tuna-os/fisherman commit 60f672ff376f079dd88b66d3058aed32bedfdc3d.
bundle_url="https://api.github.com/repos/tuna-os/bootc-installer/releases/assets/588538088"
bundle_sha256="82e044c2a49c58456bfdb4d4e333a965abdf4b012dbb91784ff37a49708dd4b2"
app_id="org.bootcinstaller.Installer.Devel"

for cmd in curl flatpak python3 sha256sum sudo lsblk blkid findmnt sfdisk mkfs.fat mkfs.ext4 skopeo podman; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "Missing required command: $cmd" >&2
        exit 1
    }
done

case "$image" in
    ghcr.io/krism-eu/krisos:*|ghcr.io/krism-eu/krisos@sha256:*) ;;
    *)
        echo "KRISOS_IMAGE must be a KrisOS GHCR tag or sha256 digest reference" >&2
        exit 1
        ;;
esac

echo
echo "Existing block devices:"
lsblk -o NAME,PATH,SIZE,FSTYPE,LABEL,PARTLABEL,MOUNTPOINTS
echo
echo "Select ONLY the partitions reserved for KrisOS."
echo "Root, /boot and /home will be FORMATTED as ext4."
echo "The EFI System Partition will be REUSED WITHOUT FORMATTING."
echo "No other partition and no partition table will be modified by Fisherman's customMounts path."
echo

read -r -p "KrisOS root partition (example /dev/nvme0n1p6): " root_part
read -r -p "KrisOS /boot partition: " boot_part
read -r -p "EFI System Partition to reuse: " esp_part
read -r -p "KrisOS /home partition: " home_part

parts=("$root_part" "$boot_part" "$esp_part" "$home_part")
for part in "${parts[@]}"; do
    [[ -b "$part" ]] || {
        echo "Not a block device: $part" >&2
        exit 1
    }
    [[ "$(lsblk -dn -o TYPE "$part")" == "part" ]] || {
        echo "Not a partition: $part" >&2
        exit 1
    }
    if findmnt -rn -S "$part" >/dev/null 2>&1; then
        echo "Partition is mounted; unmount it before installing: $part" >&2
        findmnt -rn -S "$part" >&2 || true
        exit 1
    fi
done

# All four roles must be distinct.
for ((i=0; i<${#parts[@]}; i++)); do
    for ((j=i+1; j<${#parts[@]}; j++)); do
        if [[ "${parts[i]}" == "${parts[j]}" ]]; then
            echo "A partition was selected for more than one role: ${parts[i]}" >&2
            exit 1
        fi
    done
done

esp_type="$(sudo blkid -s TYPE -o value "$esp_part" 2>/dev/null || true)"
[[ "$esp_type" == "vfat" ]] || {
    echo "EFI partition must already contain a FAT/VFAT filesystem; got: ${esp_type:-unknown}" >&2
    exit 1
}

echo
echo "DESTRUCTIVE TARGET SUMMARY"
echo "  FORMAT ext4  root : $root_part"
echo "  FORMAT ext4  /boot: $boot_part"
echo "  KEEP   vfat  ESP  : $esp_part"
echo "  FORMAT ext4  /home: $home_part"
echo "  IMAGE              : $image"
echo
read -r -p "Type INSTALL KRISOS to continue: " confirm
[[ "$confirm" == "INSTALL KRISOS" ]] || {
    echo "Cancelled."
    exit 1
}

read -r -p "Username: " username
[[ "$username" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || {
    echo "Invalid username." >&2
    exit 1
}
read -r -p "Full name: " fullname
while true; do
    read -r -s -p "Password: " password
    echo
    read -r -s -p "Repeat password: " password2
    echo
    [[ -n "$password" ]] || {
        echo "Password must not be empty." >&2
        continue
    }
    [[ "$password" == "$password2" ]] && break
    echo "Passwords do not match." >&2
done

tmpdir="$(mktemp -d)"
cfgdir="$HOME/.cache/krisos-installer"
mkdir -p "$cfgdir"
chmod 0700 "$cfgdir"
recipe_path="$cfgdir/autoinstall.json"
trap 'rm -rf "$tmpdir"; rm -f "$recipe_path"' EXIT

echo "Fetching pinned TunaOS bootc-installer..."
curl -fL --retry 3 --retry-delay 2 \
    -H "Accept: application/octet-stream" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    -o "$tmpdir/installer.flatpak" "$bundle_url"
printf '%s  %s\n' "$bundle_sha256" "$tmpdir/installer.flatpak" | sha256sum -c -

ROOT_PART="$root_part" BOOT_PART="$boot_part" ESP_PART="$esp_part" HOME_PART="$home_part" \
IMAGE="$image" TARGET="$target" USERNAME="$username" FULLNAME="$fullname" PASSWORD="$password" \
python3 - "$recipe_path" <<'PY'
import json
import os
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
recipe = {
    "filesystem": "ext4",
    "btrfsSubvolumes": False,
    "encryption": {"type": "none"},
    "image": os.environ["IMAGE"],
    "targetImgref": os.environ["TARGET"],
    "selinuxDisabled": False,
    "unifiedStorage": False,
    "composeFsBackend": False,
    "bootloader": "grub2",
    "imageType": "bootc",
    "hostname": "krisos",
    "flatpaks": [],
    "distroID": "krisos",
    "customMounts": [
        {"partition": os.environ["ROOT_PART"], "target": "/", "fstype": "ext4"},
        {"partition": os.environ["BOOT_PART"], "target": "/boot", "fstype": "ext4"},
        {"partition": os.environ["ESP_PART"], "target": "/boot/efi", "fstype": "unformatted"},
        {"partition": os.environ["HOME_PART"], "target": "/home", "fstype": "ext4"},
    ],
    "user": {
        "username": os.environ["USERNAME"],
        "fullname": os.environ["FULLNAME"],
        "password": os.environ["PASSWORD"],
        "groups": ["wheel"],
    },
}
path.write_text(json.dumps(recipe, indent=2) + "\n")
path.chmod(0o600)
PY
unset password password2 PASSWORD

sudo flatpak install --bundle -y "$tmpdir/installer.flatpak"

echo
echo "Starting Fisherman with the pre-existing-partition recipe."
echo "Automatic whole-disk partitioning is disabled by customMounts."
echo
flatpak run "$app_id" --autoinstall "$recipe_path"
