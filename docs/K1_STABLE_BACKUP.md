# K1.0 stable backup references

The K1 runtime fixes and krisCC 0.5.1-10 are now promoted to `main`.
The fixed backup baseline therefore advances to the exact signed immutable
`main` payload below; the mutable `m1` tag is not used as the backup lock.

- KrisOS commit: `35c76d6a85033203f885e3e4bd6d7dcc6f1784c5`
- KrisOS immutable ref: `ghcr.io/krism-eu/krisos:35c76d6a85033203f885e3e4bd6d7dcc6f1784c5`
- KrisOS digest: `sha256:8c87cb770273f10e7b4eeabb48b709e54c95b6080473cd3c63ef732aa4145c41`
- krisCC stable component: `v0.5.1-10`
- krisCC stable RPM SHA256: `80bd3dc6a488688ed80ca7bb0462837a8fcafe8a1c2dc4849aa0e6bf62de941f`

This reference is the direct-bootc `main` baseline used for recovery/comparison
while the installer ISO receives its final physical-machine validation.
