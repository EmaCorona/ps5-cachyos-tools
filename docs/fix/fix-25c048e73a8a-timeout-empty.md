# Rifiuto dell'override health vuoto

## Problema

Un override esplicito `PS5_FAN_HEALTH_TIMEOUT=` veniva interpretato come variabile assente e sostituito dal timeout derivato dal polling.

## Correzione applicata

La validazione distingue variabile assente e variabile presente ma vuota. Il secondo caso, così come valori non numerici, nulli, negativi o oltre 300 secondi, viene rifiutato prima dell'aritmetica.

## Verifica e limiti

La suite verifica il rifiuto dell'override vuoto e continua a superare i test di readiness. Il timeout su systemd live resta da verificare sulla PS5.

Commit: [`25c048e73a8ae19e6cd5a8d61a5b77f14cedc2e9`](https://github.com/EmaCorona/ps5-cachyos-tools/commit/25c048e73a8ae19e6cd5a8d61a5b77f14cedc2e9).
