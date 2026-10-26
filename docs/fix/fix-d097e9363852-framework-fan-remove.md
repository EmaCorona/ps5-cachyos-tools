# Rimozione fan coordinata con il lifecycle del framework

## Problema

La rimozione live del modulo `fan` falliva dopo l'arresto e la disabilitazione della unit da parte del framework. L'hook `modules/fan/remove.sh` delegava sempre alla rimozione standalone, che richiede il wants-link systemd come artefatto ancora valido; il core lo aveva già rimosso con `systemctl disable`.

## Causa individuata

Il percorso `remove --live` esegue `core_service_stop` prima dell'hook del modulo. In questa sequenza `/etc/systemd/system/multi-user.target.wants/ps5-fan-daemon.service` non esiste più, quindi la validazione del manifest dell'adapter standalone restituisce `symlink non valido` e la transazione si interrompe prima di eliminare o preservare le configurazioni secondo l'opzione richiesta.

## Correzione applicata

Con `CORE_FRAMEWORK_MANAGED=1`, l'hook ora valida il write set, applica soltanto la politica `--keep-config`/`--purge-config` alle configurazioni fan e lascia al core la gestione degli artefatti systemd e del registry. Il dispatcher `core_cli_run_remove_hook()` esporta esplicitamente questa variabile, così il comando CLI live percorre davvero il ramo coordinato. Il percorso standalone resta invariato e continua a gestire autonomamente lifecycle e manifest.

## File coinvolti

| File | Responsabilità |
| --- | --- |
| `modules/fan/remove.sh` | separazione tra rimozione coordinata dal framework e rimozione standalone |
| `tests/core/r4-tests.sh` | regressione con wants-link già disabilitato prima dell'hook |
| `docs/modules/fan.md` | comportamento aggiornato del lifecycle di rimozione |

## Verifica e limiti

- `bash -n modules/fan/remove.sh tests/core/r4-tests.sh`: PASS.
- `bash tests/core/r4-tests.sh`: 21 test superati, 0 falliti; il test di regressione attraversa il dispatcher reale dopo la rimozione del wants-link.
- `bash tests/boot-cleanup-tests.sh`: 18 test superati, 0 falliti.
- `bash tests/run-tests.sh`: 81 test superati, 0 falliti.
- `git diff --check`: PASS.
- La rimozione live era stata riprodotta sul sistema PS5 prima della correzione; la riesecuzione live della rimozione e la nuova installazione pulita sono ancora da eseguire dopo la revisione del fix.

Fonti primarie: commit [`d097e9363852455e51f01d7a916e2390b0329d54`](https://github.com/EmaCorona/ps5-cachyos-tools/commit/d097e9363852455e51f01d7a916e2390b0329d54) e [`39a26dc256499babd75a38c94d88d14649503968`](https://github.com/EmaCorona/ps5-cachyos-tools/commit/39a26dc256499babd75a38c94d88d14649503968).
