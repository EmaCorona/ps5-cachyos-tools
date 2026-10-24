# Hardening MOD-READY del framework modulare

## Problema

La revisione finale richiedeva di completare la compatibilità della root live `/`, l'installazione selettiva delle dipendenze, lo stato `once`/`always`, il lifecycle dei service, il rollback transazionale, il coordinamento concorrente, la rimozione conservativa delle configurazioni e la copertura end-to-end.

## Causa individuata

Il resolver selettivo filtrava l'ordine in una pipeline Bash e perdeva l'array associativo delle selezioni nella subshell. Inoltre il lock non copriva reset e reapply offline, il percorso `check --live` non validava la root live e l'installer rieseguiva dipendenze già valide. Il rollback dei service non aveva uno snapshot associato alla transazione per tutte le unit selezionate.

## Correzione applicata

- normalizzazione centralizzata dei percorsi per `root=/`, con confini offline e controllo dei symlink preservati;
- selezione transitiva applicata allo stesso ordine usato dal preflight, con riuso delle dipendenze già valide;
- riconoscimento del completamento persistente delle dipendenze `once` e controllo del boot corrente per `always`;
- reapply offline dei service rifiutato esplicitamente e lifecycle live con stato e rollback;
- snapshot per-unità dei service live e ripristino di enabled/active durante il rollback;
- mutex condiviso su install, remove, reset, reapply e runner;
- rispetto di `ENABLED=false`, conservazione configurazioni fan predefinita e `--purge-config` esplicito;
- piano dry-run più informativo e supporto `check --live`;
- test di riuso dipendenze e di concorrenza con fixture deterministiche.

## File coinvolti

| Percorso | Responsabilità |
|---|---|
| `lib/core/target.sh` | validazione target live/offline |
| `lib/core/dependencies.sh` | ordine selettivo senza subshell |
| `lib/core/installer.sh` | dipendenze valide e transazione |
| `lib/core/service.sh` | snapshot/restore per unità |
| `lib/core/boot-runner.sh` | stato e dipendenze runtime |
| `bin/ps5-cachyos-tools` | CLI, lock e lifecycle |
| `modules/fan/remove.sh` | politica keep/purge |
| `tests/core/run-tests.sh` | regressioni P0/P1 e failure injection |
| `README.md`, `docs/architecture.md`, `docs/module-api.md`, `docs/modules/fan.md` | contratto e operatività |

## Verifica e limiti

Eseguiti direttamente: `bash -n` sui file modificati, `./tests/core/run-tests.sh` con 42 test superati e 0 falliti, `git diff --check`. La suite include root live simulata, isolamento offline, dipendenze transitivamente selezionate e riusate, once dopo disable/enable, service disabilitati, lifecycle service mockato, rollback di unità presenti e nuove, lock concorrenti su install/remove/reset/reapply e riconciliazione dopo fallimento del consumo request. La CI remota, ShellCheck, la suite legacy completa e l'hardware PS5 devono essere verificati sul commit pushato; la prova hardware non è eseguibile in questo ambiente.

## Fonte

La correzione appartiene al branch `feature/modular-tools-framework` del repository `EmaCorona/ps5-cachyos-tools`; il riferimento SHA definitivo viene associato dopo il commit del codice e verificato nel successivo aggiornamento dello storico.
