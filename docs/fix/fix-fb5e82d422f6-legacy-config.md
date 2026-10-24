# Compatibilità con SENSOR_FAILURE_LIMIT legacy

## Problema

Gli aggiornamenti preservano `fan.conf`, ma il parser rifiutava `SENSOR_FAILURE_LIMIT`, presente nelle installazioni precedenti, lasciando il nuovo demone non avviabile.

## Correzione applicata

La chiave legacy viene accettata solo se numerica, marcata come deprecata e ignorata dalla politica termica. La transizione a `DEGRADED` resta immediata. Le chiavi sconosciute continuano a essere rifiutate e un valore legacy non numerico genera un errore persistente.

## Verifica e limiti

La suite verifica configurazione legacy valida, valore invalido, chiavi sconosciute e stato diagnostico. Non viene modificato automaticamente il file personalizzato dell'utente.

Commit: [`fb5e82d422f6345f7a5063b28ad7db6432e6d481`](https://github.com/EmaCorona/ps5-cachyos-tools/commit/fb5e82d422f6345f7a5063b28ad7db6432e6d481).
