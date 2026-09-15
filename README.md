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
ostree=/ostree/boot.BOOTVERSION/OSNAME/BOOTCSUM/TREEBOOTSERIAL
```

`BOOTCSUM` identifica gli artefatti di boot e viene usato per localizzare il
bootlink, ma non è l'identità della cache raku-Kris. Il servizio risolve il
target del bootlink e persiste `OSNAME/COMMIT/DEPLOYSERIAL`, dove `COMMIT` copre
l'intero tree OSTree. Un'immagine con `/usr` diverso invalida quindi sempre
l'upper anche quando kernel e initramfs non cambiano.

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
questi controlli in un unico smoke test e verifica che `deployment` corrisponda
al commit OSTree realmente bootato.

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

Package-layer implementation candidate: see [rk commands and limits](docs/RK.md).

`/usr/share/raku-kris/owned-packages.txt` contiene tutti i pacchetti
dell'immagine finale (base Fedora + delta raku-Kris). `rk` usa questa lista
per la policy additive-only e `owned-nevra.txt` per verificarne le versioni.

## Avvio di emergenza

Aggiungere temporaneamente `raku-kris.overlay=off` alla riga del kernel
nell'editor del menu di avvio. Il servizio salta il mount prima di toccare
lo stato persistente; anche il sync automatico viene saltato. Rimuovere il
parametro al successivo avvio per riattivare l'overlay. Non cancella la cache
né le richieste salvate. SELinux enforcing resta il contratto supportato;
`selinux=0` non è il meccanismo di recupero dell'overlay.

`tests/boot-check.sh` distingue tre esiti: 0 = controlli del boot normale
superati; 1 = errore; 2 = controlli del boot di recupero superati, overlay
volutamente disabilitato. Il codice 2 non certifica il funzionamento dell'overlay.
