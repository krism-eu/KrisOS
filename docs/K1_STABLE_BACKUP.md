# K1.0 stable backup references

These values deliberately remain the exact validated `main` baseline while the
K1.0 final candidate is tested. They are not the payload embedded in the
candidate ISO.

- KrisOS commit: `75e2584aa6681fefe6b5bc019aa64c812751a607`
- KrisOS channel: `ghcr.io/krism-eu/krisos:m1`
- KrisOS digest: `sha256:a13ddfd6d2d6032873cac8b1ea64fdeba6d93a9500da1c1222139314a8f9cb04`
- krisCC stable component: `v0.5.1-7`
- krisCC stable RPM SHA256: `ac7fe241599190c49aaf62338f41142b6025a64c3f073fc23e03a9846a17b56f`

Do not advance these backup references on the candidate branch. After physical
K1.0 validation succeeds and the same fixes/restyle are promoted to `main`,
the backup baseline can be advanced in a separate reviewed change.
