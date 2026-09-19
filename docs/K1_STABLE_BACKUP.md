# K1.0 stable backup references

The corrected K1 runtime and krisCC 0.6.0-1 are now promoted to `main`.
The installer must consume this exact signed immutable main payload; the mutable
`m1` tag is not used as the installer lock.

- KrisOS commit: `b40417ff49af48d9c693f49e553a0bef3cceb59b`
- KrisOS immutable ref: `ghcr.io/krism-eu/krisos:b40417ff49af48d9c693f49e553a0bef3cceb59b`
- KrisOS digest: `sha256:9218df60225d4d6d415c4bcc21de530bd2bd65b97d9045374050ac7addd01579`
- krisCC stable component: `v0.6.0-1`
- krisCC stable RPM SHA256: `5cb01133a54e8c715715bc5ec2bb87244ae5b57b5ed9272212b8203900a80298`

This is the direct-bootc main baseline and the only payload accepted by the
final K1 installer ISO workflow. Any future runtime change requires a new main
build, immutable digest and explicit lock update before a new ISO is produced.
