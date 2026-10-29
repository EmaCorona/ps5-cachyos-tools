# Selezione ripetuta dei moduli durante la migrazione 7.2.3

Fonte primaria: [commit `ea9738987eb2`](https://github.com/EmaCorona/ps5-cachyos-tools/commit/ea9738987eb20594c59f5f258cc5b0dd5d86f48e), 29 ottobre 2026.

## Problema

La CLI accettava più opzioni `--module` nella stessa invocazione, ma conservava soltanto l'ultima. Un dry run che elencava cinque moduli poteva quindi mostrare un piano per il solo ultimo modulo, creando un falso senso di completezza nella migrazione selettiva che esclude `fan`.

## Causa individuata

Il parser assegnava ogni valore alla stessa variabile scalare `module` senza rifiutare la seconda occorrenza. Il resolver delle dipendenze riceve un solo identificatore e non implementa una selezione multipla.

## Correzione applicata

Il parser rifiuta una seconda opzione `--module` con un errore esplicito prima di accedere al target. La migrazione documentata usa una transazione selettiva per comando; `session` risolve comunque le dipendenze `kde` e `gamescope`.

## File coinvolti

| File | Responsabilità |
| --- | --- |
| `bin/ps5-cachyos-tools` | Rifiuto della selezione ripetuta. |
| `tests/graphics-modules-tests.sh` | Regressione del parser e controllo che il target resti intatto. |
| `README.md` | Procedura selettiva per il kernel 7.2.3. |

## Verifica e limiti

Il test di regressione invoca la CLI su una root fixture con due opzioni `--module` e verifica l'errore e l'assenza di artefatti installati. La prova della migrazione hardware e del segnale video è documentata separatamente nel report E2E corrente; il test della CLI non la sostituisce.
