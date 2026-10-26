# Modulo boot-cleanup

`boot-cleanup` è un task `early/always` senza dipendenze da altri moduli. La dipendenza presente nel sorgente è stata rimossa perché `session-bootstrap` non è presente in questo branch e gli hook di cleanup non usano alcuno stato prodotto da quel modulo. Non importa il cleanup legacy e non esegue scansioni globali: una migrazione once produce record solo per il file regolare `/home/<utente>/.steam/steam.pid`; `steam.pipe` (FIFO, socket o altro tipo non verificato) non viene mai letto. Il runtime legge inoltre `/run/ps5-cachyos-tools/boot-cleanup/steam-stale.list`, con righe `pid starttime uid artifact command reason owner`.

Ogni record è accettato solo con PID/starttime/UID validi, artefatto nel pattern allowlistato `steam-(runtime|webhelper|client)-<id>` sotto `/run/user/<uid>`, command Steam allowlistato, ownership coerente e `/proc/<pid>` verificato quando ancora esistente. I processi attivi non vengono terminati; per un record stale viene rimosso solo il file regolare posseduto dall'UID dichiarato. Input malformati, PID riutilizzati, symlink e ownership errata vengono conteggiati come rifiutati. Lo stato è scritto atomicamente in `cleanup.state`.

Non vengono terminati PID arbitrari, non vengono usati glob indiscriminati e non sono inclusi fan controller, ps5fan o M.2. `PS5_CLEANUP_DRY_RUN=1` pubblica `action=DRY_RUN` senza rimuovere; a runtime senza candidati lo stato espone `action=NO_ACTION`.

Prima del primo boot `check --root` può fallire perché `cleanup.state` non esiste ancora. `remove --keep-config` conserva la configurazione; `remove --purge-config` elimina `boot-cleanup.conf` e gli artefatti interni posseduti dal modulo.

## Ripristino manuale della cartella dump di Steam

Il modulo installa anche `recover.sh`, un helper manuale per `/tmp/dumps`. Non viene invocato dall'hook `early/always`: è separato dal cleanup automatico e non cambia lo stato a ogni boot. Dopo aver chiuso Steam, l'utente `steam` può eseguirlo così:

```bash
/usr/lib/ps5-cachyos-tools/modules/boot-cleanup/recover.sh
```

L'helper verifica `steam` e `steamwebhelper` con `pgrep`; se uno dei due è attivo non modifica nulla. Se non riesce a verificare i processi, si ferma senza modifiche. A Steam fermo, crea `/tmp/dumps` con modalità `700` se manca oppure, solo se la directory è posseduta da Steam e ha una modalità diversa da `700`/`1700`, la normalizza a `700`. Rifiuta symlink, percorsi non-directory e proprietari inattesi. Non cancella né sposta i dump o i log; la presenza di `.crash` non è usata come prova sufficiente di un guasto.
