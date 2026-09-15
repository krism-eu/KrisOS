# M1 notes — contratto del package layer

M1 aggiunge il comando `rk` sopra DNF5. Il principio resta semplice:
`packages.list` contiene solo le richieste esplicite dell'utente e l'overlay
`/usr` è cache ricostruibile.

## Ownership immutabile

`/usr/share/raku-kris/owned-packages.txt` elenca per nome tutti i pacchetti
appartenenti all'immagine finale: base Fedora pinned più delta raku-Kris.
Le pseudo-entry `gpg-pubkey` sono escluse; repository e chiavi sono una policy
separata.

M1 deve impedire alle transazioni utente di aggiornare, fare downgrade,
rimuovere, obsoletare o sostituire semanticamente pacchetti owned. Il wrapper
usa DNF/RPM reali; non introduce una seconda rpmdb.

## Architettura pacchetti — congelata

raku-Kris è single-arch:

- ammessi `x86_64` e `noarch`;
- `i686` non è supportato;
- niente multilib;
- la configurazione DNF globale esclude `*.i686` e usa
  `multilib_policy=best`;
- `rk` deve rifiutare richieste `.i686`, architetture forzate incompatibili e
  tentativi di disabilitare gli excludes della policy.

Anche l'immagine viene verificata in build: un RPM `i686` rende la build non
valida.

## Metadata DNF — niente refresh continuo

I timer `dnf-makecache.timer` e `dnf5-makecache.timer` sono mascherati.
raku-Kris non mantiene i metadata DNF aggiornati in background.

Il refresh è esplicito e on-demand: una futura operazione `rk` può richiederlo
quando serve, oppure l'utente può richiederlo direttamente. Non esiste un timer
periodico nascosto.

## Transazioni M1

`rk add` e `rk rm` devono usare vere transazioni DNF/RPM. La modalità DNF5 per
un `/usr` già writable deve essere scelta esplicitamente dal wrapper; non si
affida al default `auto` e non deve creare un secondo overlay concorrente.

`rk rm` aggiorna `packages.list` solo dopo una transazione riuscita. Non viene
implementato un dependency graph o un autoremove proprietario: le dipendenze
restano responsabilità di DNF.

Dopo un cambio deployment M0 ricrea `upper/` e arma `needs-sync`; M1 reinstalla
le richieste esplicite di `packages.list` contro la nuova base e risolve di
nuovo le dipendenze.

## Stato fuori da `/usr`

Un RPM può dichiarare file sotto `/etc` o `/var` e gli scriptlet possono
modificare stato persistente. L'overlay copre solo `/usr`, quindi M1 deve essere
conservativo: inizialmente può rifiutare pacchetti con effetti persistenti non
gestibili, invece di promettere cleanup che non può garantire.

I file di stato propri di raku-Kris sotto `/var/lib/raku-kris` possono essere
sottoposti a relabel mirato. Non si esegue mai un relabel ricorsivo di
`upper/`.

## Contratto minimo di `rk`

- `rk add`: valida policy/architettura, esegue la transazione, poi registra la
  richiesta esplicita.
- `rk rm`: esegue la rimozione reale, poi rimuove la richiesta dalla lista.
- niente i686/multilib;
- niente refresh metadata periodico;
- niente modifica dei pacchetti owned;
- niente database proprietari aggiuntivi.
