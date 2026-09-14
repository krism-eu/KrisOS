# raku-Kris

Fedora 44 bootc Minimal con SELinux enforcing e overlay persistente su `/usr`.
Il progetto è indipendente da RakuOS: nessun suo codice, RPM, repository o
formato di stato viene usato.

**M0** valida esclusivamente il lifecycle dell'overlay con backend OSTree:
first boot, reboot, update, rollback e fallback alla base in caso di errore.
Il package wrapper arriva solo in M1, dopo i test descritti in
[`ARCHITECTURE.md`](ARCHITECTURE.md). I problemi di package layering da
risolvere prima di `rk` sono registrati in [`docs/M1-NOTES.md`](docs/M1-NOTES.md).

## Build

```bash
buildah bud -t raku-kris:m0 .
```

La base Fedora è fissata per digest nel `Containerfile`; un aggiornamento della
base deve quindi essere un commit esplicito e testato.

La presenza dei pacchetti `composefs` nella base non abilita da sola il backend
bootc composefs. M0 richiede però esplicitamente il contratto OSTree corrente:
una kernel cmdline con `ostree=/ostree/boot.BOOTVERSION/OSNAME/BOOTCSUM/TREESERIAL`
e il relativo `/sysroot/ostree/deploy/<stateroot>/var`. Se il primo boot non
soddisfa questo contratto, la milestone si ferma: non si adatta il codice alla
cieca a un backend diverso.

## Matrice di test M0

| # | Azione | Risultato atteso |
|---|---|---|
| 1 | Boot pulito | contratto OSTree accettato; `findmnt /usr` mostra `overlay`; login manager raggiungibile |
| 2 | Scrittura overlay | creare `/usr/local/bin/rk-test`, reboot → file ancora presente |
| 3 | Reboot sullo stesso deployment | upper conservato; identità invariata |
| 4 | `bootc upgrade` + reboot | upper ricreato; `needs-sync` presente; desktop raggiungibile |
| 5 | `bootc rollback` + reboot | stesso comportamento del punto 4 |
| 6 | Mount overlay deliberatamente rotto | boot riuscito sulla base `/usr`, con log degraded |

Verifica rapida post-boot:

```bash
grep -o 'ostree=[^ ]*' /proc/cmdline
findmnt -no SOURCE,FSTYPE /usr
cat /var/lib/raku-kris/deployment
ls -la /var/lib/raku-kris/
journalctl -b | grep raku-kris-overlay
getenforce
```

È disponibile anche `tests/boot-check.sh` come smoke test da eseguire sulla VM.

## Layout repository

```text
.
├── ARCHITECTURE.md
├── Containerfile
├── README.md
├── build_files/
│   └── base-packages.txt
├── docs/
│   └── M1-NOTES.md
├── dracut/modules.d/90raku-kris/
│   ├── module-setup.sh
│   ├── raku-kris-overlay.service
│   └── raku-kris-overlay.sh
└── tests/
    └── boot-check.sh
```

`RakuKrisOS` resta un archivio/laboratorio separato. `raku-Kris` è una nuova
implementazione con storia e contratto propri.
