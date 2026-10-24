# Readiness per istanza del demone

## Problema

L'health check confrontava `cycles` del processo riavviato con quelli dell'istanza precedente. Un demone nuovo riparte da zero e poteva quindi essere dichiarato non pronto dopo un aggiornamento valido.

## Causa individuata

Il contatore è locale al processo e non è globale. Il confronto tra istanze diverse non è valido; inoltre uno stato runtime vecchio poteva essere accettato se il processo risultava attivo.

## Correzione applicata

Il demone pubblica `instance_id`, creato una sola volta all'avvio. `module_fan_wait_ready` richiede un'identità diversa e almeno un ciclo per un restart; per la stessa istanza richiede invece identità uguale e avanzamento del contatore. `DEGRADED` restituisce un esito distinto dalla readiness hardware.

## File coinvolti

| File | Responsabilità |
|---|---|
| `bin/ps5-fan-daemon` | Identificatore di istanza e stato runtime |
| `lib/modules/fan.sh` | Contratto readiness e classificazione DEGRADED |
| `tests/run-tests.sh` | Restart, stato obsoleto, progresso e DEGRADED |

## Verifica e limiti

`bash -n`, `git diff --check` e `tests/run-tests.sh` passano con 61 test e 0 fallimenti. Il test è simulato; PID/systemd live e hardware PS5 restano da verificare.

Commit: [`fb5e82d422f6345f7a5063b28ad7db6432e6d481`](https://github.com/EmaCorona/ps5-cachyos-tools/commit/fb5e82d422f6345f7a5063b28ad7db6432e6d481).
