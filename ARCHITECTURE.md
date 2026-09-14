# raku-Kris — Architettura e invarianti

`raku-Kris` è un desktop Fedora bootc minimale con SELinux enforcing e un
OverlayFS persistente su `/usr`.

La base Fedora è immutabile e fissata per digest OCI. L'overlay è deliberatamente
semplice: il suo `upper` è cache ricostruibile, non una seconda base del sistema.
Il progetto non dipende da codice, RPM, repository o formati di stato RakuOS.

## Ambito M0

M0 valida una sola cosa: il percorso di boot dell'overlay.

- Fedora 44 bootc Minimal, backend OSTree.
- OverlayFS persistente montato su `/usr` dentro l'initrd.
- Stesso deployment: l'upper viene conservato.
- Deployment diverso (update, rollback, switch): l'upper viene ricreato vuoto.
- Se mount o cleanup falliscono, il boot continua sulla `/usr` immutabile.
- Nessun package wrapper e nessun sync RPM in M0.

Il backend bootc composefs non fa parte di M0. La presenza delle librerie
composefs nell'immagine non abilita da sola quel backend; ciò che conta è il
layout del sistema effettivamente installato. Il codice M0 richiede il parametro
kernel `ostree=` nel formato documentato sotto e il relativo persistent `/var`.
Se il primo boot non soddisfa questo contratto, il test deve fallire chiaramente
invece di adattare implicitamente l'hook a un secondo backend.

## Stato persistente

Lo stato specifico del progetto vive in `/var/lib/raku-kris/`:

```text
/var/lib/raku-kris/
├── packages.list   # M1: richieste RPM esplicite dell'utente
├── deployment      # identità boot OSTree per cui upper/ è valido
├── needs-sync      # M1: marker per ricostruire i pacchetti richiesti
├── upper/          # cache OverlayFS ricostruibile
└── work/
```

`packages.list` sarà la fonte di verità per ricostruire **il payload RPM
nell'overlay `/usr`**, non l'intero stato della macchina. `/etc` e `/var`
restano stato host secondo le normali semantiche bootc; gli effetti di RPM e
scriptlet fuori da `/usr` sono una decisione esplicita di M1, non qualcosa che
M0 nasconde.

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

Questo evita wipe inutili quando cambia solo la generazione dei bootlink, ma
invalida l'upper quando cambia il booted deployment.

## Cambio deployment e first boot

Un'identità assente o diversa produce sempre la stessa reazione:

1. l'initrd tenta di eliminare completamente `upper/` e `work/`;
2. se il wipe fallisce, **non monta l'overlay** e continua sulla base;
3. se il wipe riesce, ricrea `upper/` e `work/` e crea `needs-sync`;
4. monta un overlay vuoto sulla nuova `/usr`;
5. registra la nuova identità solo dopo un mount riuscito.

`needs-sync` viene armato anche al primo boot. In M0 il factory `packages.list`
è vuoto e il marker è innocuo; in M1 evita un caso speciale se un'immagine
derivata contiene richieste pre-registrate.

In M1 il servizio userspace userà `packages.list` per ripopolare l'overlay.
Non esiste merge della rpmdb e non esiste una split-rpmdb proprietaria.

## Invarianti

1. **Boot, rete e login appartengono alla base immutabile.** Nessun pacchetto
   overlay può essere requisito per raggiungere il desktop.
2. **Fail open verso la base.** Un errore del nostro hook non deve impedire il
   boot: il servizio termina con successo dopo aver loggato il degraded mode.
3. **Mai riutilizzare cache di provenienza incerta.** Se l'identità salvata è
   assente o diversa, l'upper deve essere vuoto prima del mount. Se non può
   essere svuotato, non viene montato.
4. **Upper e work sono disposable.** Nessuna migrazione di formato: la forma di
   recovery è ricrearli e, da M1, reinstallare le richieste esplicite.
5. **Additive-only è una policy tecnica.** Un pacchetto overlay non deve
   sostituire, aggiornare, fare downgrade o rimuovere pacchetti della base.
   Il meccanismo DNF5 concreto viene validato in M1 prima di essere congelato.
6. **SELinux resta enforcing.** Nessun `restorecon -R` sul backing path
   `upper/`: i payload vengono creati attraverso il pathname logico `/usr`.
   Prima del mount, a ogni boot, `chcon --reference=/sysroot/usr` copia il
   contesto della base sulla sola directory radice `upper/`, senza ricorsione.
   Se questa operazione fallisce, l'hook continua sulla base senza overlay.
   M1 può eseguire un relabel mirato dei soli file di stato sotto
   `/var/lib/raku-kris` creati nell'initrd.
7. **Niente RakuOS a runtime o build-time.** Il motivo è ridurre compatibilità,
   superficie di cambiamento e manutenzione, non aggirare una licenza.
8. **L'initrd fa solo filesystem.** Niente RPM, rete, JSON/TOML, sync o policy
   desktop nel percorso initrd.

## Cosa non fa M0

- non installa o rimuove pacchetti dall'overlay;
- non ricostruisce package state dopo un update;
- non tenta di diagnosticare/riparare whiteout creati manualmente nello stesso
  deployment;
- non supporta il backend bootc composefs;
- non promette che `packages.list` descriva modifiche a `/etc` o `/var`.

Queste omissioni sono intenzionali: M0 deve dimostrare prima il mount lifecycle.

## M1 — decisioni da chiudere con test

I due problemi architetturali che devono essere risolti prima di congelare `rk`
sono documentati in [`docs/M1-NOTES.md`](docs/M1-NOTES.md):

1. **stato persistente fuori da `/usr`** prodotto dal payload o dagli scriptlet
   RPM e relativa semantica di cleanup/rebuild;
2. **enforcement reale di additive-only**, inclusi hard dependency, Obsoletes,
   Conflicts, file conflict, RPM locali e NEVRA esplicite.

Le scelte implementative subordinate restano volutamente semplici:

- `rk rm` usa una vera transazione RPM/DNF5 e aggiorna `packages.list` solo dopo
  successo; niente pseudo-autoremove proprietario;
- dopo cambio deployment il sync reinstalla solo le richieste esplicite e le
  dipendenze vengono risolte nuovamente contro la nuova base;
- i file di stato creati nell'initrd possono essere sottoposti a `restorecon`
  mirato dopo switch-root, mai al backing tree `upper/`.

## Milestone

- **M0**: boot overlay vuoto; reboot; update; rollback; degraded fallback.
- **M1**: wrapper `rk`, policy additive-only, sync post-deployment.
- **M2**: test QEMU automatizzati, cleanup/polish, eventuale supporto composefs.

## Alternative registrate e non scelte

- **systemd-sysext**: ottimo per estensioni strettamente additive, ma troppo
  restrittivo per RPM generici con scriptlet/configurazione.
- **split rpmdb custom**: esclusa; ricreerebbe la parte più complessa di un
  package manager per un requisito che non abbiamo.
- **Rust nell'initrd**: escluso in M0; lo shell hook usa solo primitive dracut e
  riduce toolchain e superficie di manutenzione.
