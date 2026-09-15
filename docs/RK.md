# rk: first executable package layer

Implementation candidate, not a validated VM release. Based on main d1da618.

Commands in the Fedora guest:

```bash
sudo rk sync
sudo rk add tree
rk status
sudo rk rm tree
```

The Fedora libdnf5 API resolves and applies the same transaction under its
system-repository lock. No second rpmdb, no bootc marker hiding, no transient
overlay creation, no external RakuOS components. RPM and libdnf5 system state
live under the existing persistent /usr overlay.

This first implementation accepts exact package names from enabled Fedora and
updates repositories, x86_64/noarch only. It rejects all changes to image-owned
packages, incoming replacements, indirect removals, local RPMs and command-line
DNF options. Incoming RPMs must have payloads under /usr, cannot overwrite
existing non-directory paths, and cannot contain package scriptlets or triggers.
Installed Fedora triggers are still executed by RPM. This supports a concrete,
restricted class of packages; it does not claim arbitrary desktop RPM support.
Repository configuration and already-installed signing keys remain trusted
administrator-controlled inputs. Direct root use of RPM/DNF is outside rk's contract.

The immutable image records exact owned RPM identities, checked before and after
transactions. RPM signatures and transaction tests are mandatory. Package names
are committed atomically only after success. A pending marker blocks further
operations after interruption; at reboot the overlay service resets the cache,
and sync restores the last committed requests. Shared existing directory metadata
and installed Fedora trigger side effects still require VM validation. This is
not a full rollback of /etc or /var.

After deployment changes, the sync oneshot runs after multi-user.target. Failure
leaves needs-sync for an explicit `sudo rk sync` retry; there is no refresh timer.
The desktop does not require successful sync to boot.

Validation gates:

1. Source policy tests (base actions, multilib, indirect removal, option injection).
2. Disposable Fedora container: real signed tree install/remove through libdnf5.
3. Fresh qcow2: rk add tree, reboot, tree and rpmdb still present, base unchanged.
4. Deployment change and interrupted transaction recovery in a disposable VM.

Only gates actually executed may be reported as passing. Container tests cannot
prove boot correctness, persistence or recovery.
