# Validazione coerente dello stato profilo e del polling runtime

## Problema

La readiness dell'installer poteva calcolare un timeout usando `balanced` quando lo stato profilo mancava, mentre il controllo del polling runtime considerava vuoto `PS5_FAN_POLL_SEC` come non impostato. Inoltre non esisteva una regressione esplicita per un aggiornamento parzialmente fallito con artefatti già presenti.

## Correzione applicata

`module_fan_health_timeout()` ora richiede uno stato profilo leggibile e rifiuta l'assenza prima di selezionare il profilo. Il daemon e l'installer trattano allo stesso modo un override `PS5_FAN_POLL_SEC` presente ma vuoto: viene validato e rifiutato. La suite simula anche un errore durante l'installazione di un aggiornamento con artefatti preesistenti e verifica che file e stato persistente siano ripristinati.

## Verifica e limiti

`bash -n bin/ps5-fan-daemon lib/modules/fan.sh tests/run-tests.sh`, `git diff --check` e `tests/run-tests.sh` sono passati con 74 test superati e 0 falliti. Restano non verificati ShellCheck locale, systemd live, driver e hardware PS5 reale. La verifica systemd su staging CI passa; i workflow/status GitHub del commit non risultano ancora osservabili.

Commit sorgente: [`a16699c48105c31e452f49ceb27181e02336dd60`](https://github.com/EmaCorona/ps5-cachyos-tools/commit/a16699c48105c31e452f49ceb27181e02336dd60).
