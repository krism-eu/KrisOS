#!/bin/bash
# Dracut module for the raku-Kris persistent /usr overlay.

check() {
    return 0
}

depends() {
    echo "ostree systemd"
    return 0
}

installkernel() {
    instmods overlay
}

install() {
    inst_multiple mount mkdir rm chcon
    inst_script "$moddir/raku-kris-overlay.sh" /usr/bin/raku-kris-overlay
    inst_simple "$moddir/raku-kris-overlay.service" \
        "$systemdsystemunitdir/raku-kris-overlay.service"

    mkdir -p "$initdir$systemdsystemunitdir/initrd-root-fs.target.wants"
    ln_r "$systemdsystemunitdir/raku-kris-overlay.service" \
        "$systemdsystemunitdir/initrd-root-fs.target.wants/raku-kris-overlay.service"
}
