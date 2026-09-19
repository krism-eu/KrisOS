# K1.0 stable backup references

The corrected K1 runtime and krisCC 0.6.0-1 are now promoted to `main`.
The installer must consume this exact signed immutable main payload; the mutable
`m1` tag is not used as the installer lock.

- KrisOS commit: `ccb73fe74faf92d7102fcb24c3526b791ff83590`
- KrisOS immutable ref: `ghcr.io/krism-eu/krisos:ccb73fe74faf92d7102fcb24c3526b791ff83590`
- KrisOS digest: `sha256:3419f8d0834cb7f3b99d09444f7e3666a670477d94ae1aebdcad1b59963d2275`
- krisCC stable component: `v0.6.0-1`
- krisCC stable RPM SHA256: `5cb01133a54e8c715715bc5ec2bb87244ae5b57b5ed9272212b8203900a80298`

This is the direct-bootc main baseline and the only payload accepted by the
final K1 installer ISO workflow. Any future runtime change requires a new main
build, immutable digest and explicit lock update before a new ISO is produced.

Payload build and Cosign verification: https://github.com/krism-eu/KrisOS/actions/runs/35475017759
This payload includes guarded rk recovery and corrected release QA. Hardware and installation checks remain separate from container CI.
