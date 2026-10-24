# Timeout health coerente con il polling

## Problema

Il timeout readiness fisso di 30 secondi non era proporzionato al polling configurabile, che può arrivare a 60 secondi.

## Correzione applicata

L'installer legge il `POLL_INTERVAL` del profilo persistente e deriva un timeout pari ad almeno due intervalli più margine, con limite massimo di 300 secondi. Un override `PS5_FAN_HEALTH_TIMEOUT` viene validato tra 1 e 300 secondi; valori nulli, negativi o non numerici vengono rifiutati.

## Verifica e limiti

La validazione numerica e i percorsi di readiness sono coperti dalla suite simulata. La misura su systemd live resta da eseguire sulla PS5.

Commit: [`fb5e82d422f6345f7a5063b28ad7db6432e6d481`](https://github.com/EmaCorona/ps5-cachyos-tools/commit/fb5e82d422f6345f7a5063b28ad7db6432e6d481).
