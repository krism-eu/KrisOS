# rk: persistent RPM policy layer

`rk` is the restricted package-management interface used by KrisOS for additive
RPMs on the persistent `/usr` overlay.

Commands in the Fedora guest:

```bash
rk status
rk plan tree
sudo rk add tree
sudo rk rm tree
sudo rk sync
```

`rk plan <name>` is read-only and is intended for krisCC transaction previews.
It uses the same libdnf5 solver configuration, enabled repositories, immutable
base exclusions, architecture policy and exact-name checks as `rk add`, but it
does not download packages, modify the RPM database or change `packages.list`.
Payload/scriptlet validation still occurs during the real install after download.

The Fedora libdnf5 API resolves and applies transactions under its
system-repository lock. No second rpmdb, no bootc marker hiding, no transient
overlay creation, and no external package-management components. RPM and
libdnf5 system state live under the existing persistent `/usr` overlay.

This implementation accepts exact package names from repositories that are
enabled in the system DNF configuration, x86_64/noarch only. Repository
enable/disable state is an administrator-controlled input; rk does not silently
re-enable Fedora repositories that the administrator disabled. It rejects all changes to image-owned packages,
incoming replacements, indirect removals, local RPMs and command-line DNF
options. Incoming RPMs must have payloads under `/usr`, cannot overwrite existing
non-directory paths, and cannot contain package scriptlets or triggers. Installed
Fedora triggers are still executed by RPM. This supports a concrete, restricted
class of packages; it does not claim arbitrary desktop RPM support. Repository configuration and already-installed signing keys remain trusted
administrator-controlled inputs. krisCC may add repository files only from
HTTPS URLs and enable/disable repositories through authenticated DNF5
config-manager calls; rk still forces per-repository package signature checking
and rejects a transaction when signatures cannot be verified. Direct root use of RPM/DNF is outside rk's
contract.

The immutable image records exact owned RPM identities, checked before and after
transactions. RPM signatures and transaction tests are mandatory. Package names
are committed atomically only after success. A pending marker blocks further
operations after interruption; at reboot the overlay service resets the cache,
and sync restores the last committed requests. The overlay hook is the sole
owner of deployment identity and cache invalidation; `rk` validates the live
writable overlay, recovery markers, SELinux state and immutable package NEVRAs,
but does not reconstruct deployment identity from the kernel boot checksum.
Shared existing directory metadata and installed Fedora trigger side effects
still require VM validation. This is not a full rollback of `/etc` or `/var`.

After deployment changes, the sync oneshot runs only when the overlay hook has
published its volatile readiness marker. Failure leaves `needs-sync` for a later
healthy boot or an explicit `sudo rk sync` retry; there is no refresh timer. The
desktop does not require successful sync to boot.

Validation gates:

1. Source policy tests: base actions, multilib, indirect removal, option injection, degraded status and read-only plan dispatch.
2. Disposable Fedora container: real solver plan plus signed `tree` install/remove through libdnf5.
3. Fresh qcow2: `rk plan tree`, `rk add tree`, reboot, tree and rpmdb still present, base unchanged.
4. Deployment change and interrupted transaction recovery in a disposable VM.

Only gates actually executed may be reported as passing. Container tests cannot
prove boot correctness, persistence or recovery.

## Recovering an unavailable request

If deployment recovery cannot install a saved request, inspect the rk sync error.
Use `sudo rk forget NAME` only for a request that is absent from the installed
overlay (or now owned by the base image), then run `sudo rk sync`. The command
requires `needs-sync`, a healthy overlay, no interrupted transaction and the
exclusive rk lock. It atomically updates intent without changing RPMs, and keeps
`needs-sync` until sync succeeds. Installed overlay packages cannot be forgotten.
Missing factory state is reported with the explicit tmpfiles provisioning command.
