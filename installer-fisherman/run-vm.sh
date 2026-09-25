#!/usr/bin/env bash
set -euo pipefail

# Fixed destructive profile for the disposable 20 GiB KrisOS test VM.
export KRISOS_ROOT_PART=/dev/vda1
export KRISOS_BOOT_PART=/dev/vda3
export KRISOS_ESP_PART=/dev/vda4
export KRISOS_HOME_PART=/dev/vda2
export KRISOS_ESP_ACTION="FORMAT EFI"
export KRISOS_USERNAME=kris
export KRISOS_FULLNAME=kris
export KRISOS_GENERIC_IMAGE=1

echo "KrisOS VM profile:"
echo "  /       -> /dev/vda1 (FORMAT ext4)"
echo "  /boot   -> /dev/vda3 (FORMAT ext4)"
echo "  EFI     -> /dev/vda4 (FORMAT FAT32)"
echo "  /home   -> /dev/vda2 (FORMAT ext4)"
echo "  user    -> kris"
echo "  boot    -> generic-image mode"
echo
echo "The installer will still require INSTALL KRISOS and ask for the password."
echo

exec bash <(curl -fsSL https://raw.githubusercontent.com/krism-eu/KrisOS/fix/iso-finalization-20260925/installer-fisherman/run.sh)
