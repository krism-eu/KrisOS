# raku-Kris — Architettura e invarianti

`raku-Kris` è un desktop Fedora bootc minimale con SELinux enforcing e un
OverlayFS persistente su `/usr`.

La base Fedora è immutabile e fissata per digest OCI. L'`upper` è cache
ricostruibile, non una seconda base del sistema. Il progetto non dipende da
codice, RPM, repository o formati di stato RakuOS.

## Ambito M0

M0 valida una sola cosa: il lifecycle del nostro overlay `/usr`.

- Fedora 44 bootc Minimal con contratto di deployment OSTree (`ostree=`).
- Fedora può presentare la root immutabile tramite composefs/OverlayFS; quel
  mount resta proprietà di bootc/OSTree.
- raku-Kris monta un OverlayFS persistente dedicato soltanto su `/usr`.
- Il mount avviene in early real-root userspace: dopo `ostree-remount.service`
  e prima di `local-fs.target`.
- Stesso deployment: `upper/` viene conservato.
- Deployment diverso: `upper/` e `work/` vengono ricreati vuoti.
- Se setup o mount falliscono, il servizio termina con successo e il boot
  continua sulla `/usr` immutabile.
- Nessun package wrapper e nessun sync RPM in M0.
- Nessun codice custom nell'initramfs.

Questa collocazione è intenzionale. In initrd il deployment composefs esponeva
una root preparata con semantiche diverse dalla normale real root; dopo
switch-root `/var` è persistente e scrivibile, SELinux è pienamente operativo e
possiamo montare `/usr` prima dei normali servizi senza duplicare il lavoro di
bootc.

## Stato persistente

Lo stato specifico del progetto vive in `/var/lib/raku-kris/`:

```text
/var/lib/raku-kris/
├── packages.list   # M1: richieste RPM esplicite dell'utente
├── deployment      # identità OSTree per cui upper/ è valido
├── needs-sync      # M1: marker per ricostruire i pacchetti richiesti
├── upper/          # cache OverlayFS ricostruibile
└── work/
```

`packages.list` sarà la fonte di verità per ricostruire il payload RPM
nell'overlay `/usr`, non l'intero stato della macchina. `/etc` e `/var` restano
stato host secondo le normali semantiche bootc.

## Identità del deployment

OSTree passa normalmente una riga kernel del tipo:

```text
ostree=/ostree/boot.BOOTVERSION/OSNAME/BOOTCSUM/TREESERIAL
```

`boot.0` / `boot.1` è una generazione volatile e non fa parte dell'identità
persistita. M0 salva invece:

```text
OSNAME/BOOTCSUM/TREESERIAL
```

Lo stateroot viene ricavato dalla cmdline e validato; non è hard-coded.

## Cambio deployment e first boot

Un'identità assente o diversa produce sempre la stessa reazione:

1. elimina completamente `upper/` e `work/`;
2. se il wipe fallisce, non monta l'overlay e continua sulla base;
3. ricrea `upper/` e `work/` e crea `needs-sync`;
4. copia sulla radice di `upper/` il contesto SELinux della `/usr` immutabile;
5. monta l'overlay persistente su `/usr`;
6. registra la nuova identità solo dopo un mount riuscito.

`needs-sync` viene armato anche al first boot. In M0 il factory `packages.list`
è vuoto e il marker è innocuo; in M1 segnalerà che le richieste esplicite vanno
ricostruite sulla nuova base.

## Invarianti

1. **Boot, rete e login appartengono alla base immutabile.** Nessun pacchetto
   overlay è requisito per raggiungere il desktop.
2. **Fail open verso la base.** Un errore del nostro servizio non deve impedire
   il boot.
3. **Mai riutilizzare cache di provenienza incerta.** Identità assente o diversa
   implica upper vuoto prima del mount.
4. **Upper e work sono disposable.** La recovery consiste nel ricrearli e, da
   M1, reinstallare le richieste esplicite.
5. **Additive-only è una policy tecnica.** Un pacchetto overlay non deve
   sostituire, aggiornare, fare downgrade o rimuovere pacchetti dell'immagine.
6. **SELinux resta enforcing.** Non viene eseguito alcun `restorecon -R`
   sull'upper. Prima del mount `chcon --reference=/usr` etichetta soltanto la
   directory radice `upper/`; i payload vengono creati tramite i pathname
   logici di `/usr`.
7. **Single-arch.** raku-Kris usa soltanto `x86_64` e `noarch`; i686/multilib
   sono esclusi dalla policy DNF e non devono comparire nell'immagine.
8. **Niente refresh DNF periodico.** I timer makecache sono mascherati; il
   refresh metadata è esplicito e legato alle operazioni package che lo
   richiedono.
9. **Niente RakuOS a runtime o build-time.** Il motivo è ridurre compatibilità,
   superficie di cambiamento e manutenzione, non aggirare una licenza.

## M1

M1 aggiunge il comando `rk` sopra DNF5 senza introdurre una seconda rpmdb o un
dependency graph proprietario. `/usr/share/raku-kris/owned-packages.txt`
protegge l'intera immagine immutabile (base Fedora + delta raku); `packages.list`
contiene soltanto richieste esplicite dell'utente.

La policy già congelata per M1 è:

- solo `x86_64`/`noarch`, niente i686 o multilib;
- nessun refresh metadata periodico in background;
- niente update/downgrade/remove/replace di pacchetti owned;
- dopo cambio deployment, reinstallazione delle sole richieste esplicite;
- `rk rm` usa una vera transazione DNF/RPM, senza pseudo-autoremove.

Restano da implementare nel wrapper la protezione transazionale additive-only e
la gestione esplicita degli effetti RPM fuori da `/usr`; sono dettagli M1, non
ragioni per complicare M0.

## Milestone

- **M0**: overlay early-userspace; reboot; invalidazione al cambio deployment;
  fallback degradato.
- **M1**: wrapper `rk`, policy additive-only, sync post-deployment.
- **M2**: cleanup/polish e test automatici solo dove danno valore reale.

## Alternative registrate e non scelte

- **Overlay custom in initrd**: abbandonato; interagiva male con il deployment
  composefs preparato prima dello switch-root senza offrire vantaggi rispetto
  al mount early-userspace.
- **systemd-sysext**: ottimo per estensioni strettamente additive, ma troppo
  restrittivo per RPM generici con scriptlet/configurazione.
- **split rpmdb custom**: esclusa; ricreerebbe la parte più complessa di un
  package manager.
- **Rust per il mount M0**: escluso; lo shell hook usa primitive filesystem
  semplici e mantiene piccola la superficie di manutenzione.
