# Hardening installazione e runtime

- Commit sorgente: [`c2a4145`](../../commit/c2a4145)
- Data: 2026-10-24
- File principali: `lib/modules/fan.sh`, `bin/ps5-fan-daemon`, `tests/run-tests.sh`

## Problema

La prima versione non propagava ogni errore dell'installazione, validava in modo incompleto i profili e non proteggeva sufficientemente l'avvio in presenza di target hardware assente o di configurazioni corrotte.

## Causa individuata

L'installer eseguiva copie e symlink senza controllarne il risultato; il demone caricava configurazioni non sufficientemente vincolate e il percorso di runtime non aveva una serializzazione esplicita. Queste cause sono state riprodotte con rootfs non scrivibile, configurazione malformata e assenza del target.

## Correzione applicata

L'installer ora controlla ogni creazione/copia/symlink e restituisce errore. Il demone usa un parser a chiavi consentite, valida 15 zone e range, protegge la doppia istanza con `flock`, verifica il readback e mantiene il target più conservativo in `DEGRADED`.

## File coinvolti

| File | Responsabilità |
|---|---|
| `lib/modules/fan.sh` | installazione con propagazione degli errori |
| `bin/ps5-fan-daemon` | parsing, validazione, lock, readback e stati |
| `bin/ps5-fan` | selezione persistente del profilo con error handling |
| `tests/run-tests.sh` | regressioni su configurazione e installazione |

Fonte primaria: [commit c2a4145](../../commit/c2a4145) e il diff del commit nel repository locale.
## Verifica e limiti

`bash -n`, `git diff --check` e `tests/run-tests.sh` sono stati eseguiti con esito positivo: 16 test superati, 0 falliti. Non sono state eseguite prove su hardware PS5 reale; driver, temperature, RPM, rumore e throttling restano da validare sulla console.
