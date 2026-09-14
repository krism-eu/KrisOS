# M1 notes — problemi da chiudere prima di `rk`

Questo file registra i punti che M0 non deve risolvere prematuramente ma che
vanno chiusi con test prima di implementare il package wrapper.

## 1. Stato persistente fuori da `/usr`

L'overlay copre solo `/usr`, ma un RPM può dichiarare file sotto `/etc` o
`/var` e gli scriptlet possono modificare stato persistente anche quando il
payload dell'RPM vive quasi interamente in `/usr`.

Dopo un cambio deployment `upper/` viene ricreato. Qualunque effetto persistente
fuori da `/usr` non viene quindi automaticamente ricostruito o rimosso insieme
all'overlay.

M1 deve scegliere e testare una policy esplicita. Le due opzioni ammissibili sono:

- supportare inizialmente solo un sottoinsieme di RPM compatibili con il modello
  raku-Kris, rifiutando quelli con effetti persistenti non gestibili;
- oppure definire una semantica di lifecycle/cleanup per `/etc` e `/var` senza
  introdurre una seconda rpmdb o un database proprietario complesso.

Non è accettabile promettere cleanup completo senza poterlo dimostrare dopo
update e rollback.

## 2. Enforcement reale di additive-only

`/usr/share/raku-kris/base-packages.txt` elenca i pacchetti appartenenti
all'immagine immutabile. M1 deve rendere impossibile a una transazione overlay
di aggiornare, fare downgrade, rimuovere o sostituire semanticamente quei
pacchetti.

DNF5 documenta `excludepkgs` come filtro che rende i pacchetti disponibili
invisibili alle transazioni. Questo va comunque validato sulla nostra immagine
con casi avversi, almeno:

- dipendenza hard che richiede una versione più nuova di un pacchetto base;
- `Obsoletes:` / `Conflicts:` verso un pacchetto base;
- pacchetto con nome diverso che fornisce la stessa capability;
- file conflict con un file già posseduto dalla base;
- RPM locale passato direttamente come file;
- downgrade o installazione di una NEVRA esplicita di un pacchetto base.

`protected_packages` e/o versionlock sono candidati di hardening da valutare
insieme agli excludes; non sono ancora parte del contratto M1.

## Compatibility gate: DNF5 su bootc con `/usr` già writable

DNF5 ha una propria semantica di `persistence` sui sistemi bootc. Il default
`auto` tratta in modo speciale un sistema bootc il cui `/usr` è già writable,
e la modalità `transient` può gestire un overlay bootc proprio.

Prima di implementare `rk`, sulla versione DNF5 realmente presente nella base
pinned va verificato che una transazione possa operare direttamente sul nostro
`/usr` già overlaid senza creare, sostituire o interpretare un secondo overlay.
Il wrapper dovrà impostare esplicitamente la modalità compatibile risultante dal
test; non deve dipendere dal default `auto`.

Questo è un gate di integrazione, non un terzo modello di stato: raku-Kris
continua ad avere un solo upper persistente e non delega a DNF5 il lifecycle
dell'overlay.

## Note implementative già decise

- Il first boot deve armare `needs-sync` anche se il factory `packages.list` è
  vuoto: così una futura immagine derivata con richieste pre-registrate non ha
  un caso speciale.
- I file di stato creati nell'initrd possono richiedere relabeling dopo
  switch-root. Il servizio M1 userà un `restorecon` mirato sui file/directories
  di stato sotto `/var/lib/raku-kris`, mai un relabel ricorsivo di `upper/`.
- `packages.list` descrive solo le richieste esplicite dell'utente; le
  dipendenze vengono risolte nuovamente contro la base corrente a ogni rebuild.
- `rk rm` non implementerà un dependency graph o autoremove proprietario: la
  rimozione deve essere una vera transazione RPM/DNF5 e la lista viene aggiornata
  solo dopo successo.
