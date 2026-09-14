#!/bin/bash
# raku-kris-overlay — initrd hook.
#
# Single responsibility: mount a persistent overlay on /sysroot/usr whose
# cache belongs to the currently booted OSTree deployment identity.
# Any failure falls back to the immutable base and returns success.

set -u

log() {
    echo "raku-kris-overlay: $*"
}

# Read ostree= from the kernel command line without relying on dracut helpers.
cmdline=""
IFS= read -r cmdline < /proc/cmdline || true

deploy_path=""
for tok in $cmdline; do
    case "$tok" in
        ostree=*) deploy_path="${tok#ostree=}" ;;
    esac
done

if [ -z "$deploy_path" ]; then
    log "no ostree= parameter in cmdline — skipping"
    exit 0
fi

# Expected OSTree bootlink:
# /ostree/boot.BOOTVERSION/OSNAME/BOOTCSUM/TREESERIAL
case "$deploy_path" in
    /ostree/boot.[01]/*/*/*) ;;
    *)
        log "unsupported ostree= path '$deploy_path' — skipping"
        exit 0
        ;;
esac

rest="${deploy_path#/ostree/}"
boot_generation="${rest%%/*}"
rest="${rest#*/}"
stateroot="${rest%%/*}"
rest="${rest#*/}"
bootcsum="${rest%%/*}"
treeserial="${rest#*/}"

# Reject malformed components before using the stateroot in a filesystem path.
case "$boot_generation" in
    boot.0|boot.1) ;;
    *) log "invalid boot generation — skipping"; exit 0 ;;
esac
case "$stateroot" in
    ""|*[!A-Za-z0-9._-]*) log "invalid stateroot — skipping"; exit 0 ;;
esac
case "$bootcsum" in
    ""|*[!0-9a-f]*) log "invalid boot checksum — skipping"; exit 0 ;;
esac
case "$treeserial" in
    ""|*[!0-9]*) log "invalid tree serial — skipping"; exit 0 ;;
esac
case "$treeserial" in
    */*) log "invalid tree serial — skipping"; exit 0 ;;
esac

# Deliberately exclude boot.0/boot.1: that generation may flip while the same
# deployment remains selected.
deployment_id="$stateroot/$bootcsum/$treeserial"

sysroot=/sysroot

# A manual/retriggered invocation must be a no-op once /sysroot/usr is already
# overlaid. Check this before touching upper/work so a live mount can never be
# invalidated by the deployment-change cleanup path.
already_mounted=0
while read -r _source target fstype _rest; do
    if [ "$target" = "$sysroot/usr" ] && [ "$fstype" = "overlay" ]; then
        already_mounted=1
        break
    fi
done < /proc/mounts

if [ "$already_mounted" -eq 1 ]; then
    log "already mounted"
    exit 0
fi

var="$sysroot/ostree/deploy/$stateroot/var"
if [ ! -d "$var" ]; then
    log "persistent var not found for stateroot '$stateroot' — skipping"
    exit 0
fi

state="$var/lib/raku-kris"
upper="$state/upper"
work="$state/work"
saved="$state/deployment"
needs_sync="$state/needs-sync"

if ! mkdir -p "$state"; then
    log "WARNING: cannot create state directory — continuing on base /usr"
    exit 0
fi

wipe_cache() {
    reason="$1"
    log "$reason — wiping overlay cache"

    if ! rm -rf -- "$upper" "$work"; then
        log "WARNING: cache wipe failed — continuing on base /usr"
        return 1
    fi
    if ! mkdir -p "$upper" "$work"; then
        log "WARNING: cache recreation failed — continuing on base /usr"
        return 1
    fi
    return 0
}

saved_id=""
if [ -f "$saved" ]; then
    IFS= read -r saved_id < "$saved" || saved_id=""
fi

changed=0
if [ -z "$saved_id" ]; then
    # Unknown provenance must never be mounted. On a true first boot this only
    # removes empty directories. Arm needs-sync too: M1 may seed packages.list
    # in a derived image and must not need a special first-boot path.
    changed=1
    if ! wipe_cache "deployment identity not initialized"; then
        exit 0
    fi
elif [ "$saved_id" != "$deployment_id" ]; then
    changed=1
    if ! wipe_cache "deployment changed"; then
        exit 0
    fi
else
    if ! mkdir -p "$upper" "$work"; then
        log "WARNING: cannot prepare overlay cache — continuing on base /usr"
        exit 0
    fi
fi

if [ "$changed" -eq 1 ]; then
    if ! : > "$needs_sync"; then
        log "WARNING: cannot create needs-sync marker — continuing on base /usr"
        exit 0
    fi
fi

log "mounting persistent overlay on /sysroot/usr"
if ! mount -t overlay overlay \
        -o "lowerdir=$sysroot/usr,upperdir=$upper,workdir=$work" \
        "$sysroot/usr"; then
    log "WARNING: overlay mount failed — continuing on base /usr (degraded)"
    exit 0
fi

# Record validity only after a successful mount. If this write fails the next
# boot safely treats the cache as uninitialized and rebuilds it.
if ! printf '%s\n' "$deployment_id" > "$saved"; then
    log "WARNING: mounted, but deployment identity could not be persisted"
fi

log "mounted for $deployment_id"
exit 0
