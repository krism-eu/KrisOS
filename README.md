# raku-Kris

Fedora 44 bootc Minimal con SELinux enforcing e overlay persistente su `/usr`.
Il progetto è indipendente da RakuOS: nessun suo codice, RPM, repository o
formato di stato viene usato.

**M0** valida esclusivamente il lifecycle dell'overlay: first boot, reboot,
cambio deployment e fallback alla base in caso di errore. Il mount avviene in
early userspace sul sistema reale, dopo `ostree-remount.service` e prima di
`local-fs.target`: `/var` è già persistente e scrivibile, ma i normali servizi
non sono ancora partiti.

Il package wrapper arriva in M1. La policy è già stretta: raku-Kris è
`x86_64`/`noarch`, non usa multilib/i686 e non esegue refresh periodici dei
metadata DNF in background.

## Build

```bash
sudo podman build -t localhost/raku-kris:m0 .
```

La base Fedora è fissata per digest nel `Containerfile`; un aggiornamento della
base deve quindi essere un commit esplicito e testato.

Il boot continua a usare il contratto OSTree della kernel cmdline:

```text
ostree=/ostree/boot.BOOTVERSION/OSNAME/BOOTCSUM/TREESERIAL
```

Fedora 44 può presentare la root immutabile tramite composefs/OverlayFS; raku-Kris
non modifica quel mount. Sovrappone un proprio OverlayFS persistente soltanto a
`/usr`, con `upper/` e `work/` in `/var/lib/raku-kris/`.

## M0 rapido

Dopo il boot:

```bash
findmnt -T /usr -o TARGET,SOURCE,FSTYPE,OPTIONS
systemctl is-active raku-kris-overlay.service
cat /var/lib/raku-kris/deployment
ls -la /var/lib/raku-kris/
getenforce
```

`/usr` deve essere un mount `overlay` dedicato, il servizio deve essere `active`
e `upper/`, `work/` e `deployment` devono esistere. `tests/boot-check.sh` raccoglie
questi controlli in un unico smoke test.

La prova di persistenza M0 è semplice: creare un file sotto `/usr`, riavviare e
verificare che esista ancora. Quando cambia il deployment, la cache `upper/` è
invece ricreata vuota e viene armato `needs-sync` per M1.

## Layout repository

```text
.
├── ARCHITECTURE.md
├── Containerfile
├── README.md
├── build_files/
│   ├── base-packages.txt
│   ├── dnf-raku-kris.conf
│   └── tmpfiles-raku-kris.conf
├── docs/
│   └── M1-NOTES.md
├── systemd/
│   ├── raku-kris-overlay.sh
│   └── raku-kris-overlay.service
└── tests/
    └── boot-check.sh
```

`RakuKrisOS` resta un archivio/laboratorio separato. `raku-Kris` è una nuova
implementazione con storia e contratto propri.
