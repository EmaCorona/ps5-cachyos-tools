# Parsing decimale del timeout di readiness

## Problema

Il calcolo del timeout dell'installer leggeva `POLL_INTERVAL` dal profilo e lo usava direttamente nelle espressioni aritmetiche Bash. Valori validi con zeri iniziali, come `08` o `060`, potevano quindi essere interpretati in base ottale e fallire. Inoltre, il parser dell'installer ricadeva silenziosamente su `balanced` o su un polling predefinito quando lo stato persistente o il profilo erano invalidi, creando una readiness non coerente con il demone.

## Causa individuata

`module_fan_health_timeout()` non condivideva la normalizzazione decimale già applicata dal demone e validava il profilo selezionato con un fallback permissivo. Il percorso dell'override `PS5_FAN_POLL_SEC` non era incluso nel calcolo del timeout health.

## Correzione applicata

Il modulo ora normalizza gli interi senza segno dopo aver rimosso le virgolette, limita la lunghezza prima dell'aritmetica e verifica i range prima di usare i valori. Il profilo viene selezionato dallo stato persistente; uno stato o un profilo invalido produce errore, senza fallback silenzioso. `PS5_FAN_POLL_SEC`, quando presente, prevale sul polling del profilo dopo la stessa validazione. `PS5_FAN_HEALTH_TIMEOUT` segue la medesima normalizzazione e deve rimanere nell'intervallo 1–300.

## File coinvolti

| Percorso | Responsabilità |
| --- | --- |
| `lib/modules/fan.sh` | Normalizzazione e validazione del timeout health e del polling runtime. |
| `tests/run-tests.sh` | Regressioni per zeri iniziali, valori quotati, overflow, stato invalido e override. |
| `README.md` | Conteggio e ambito aggiornati della suite. |
| `docs/modules/fan.md` | Contratto documentato del calcolo readiness. |

## Verifica e limiti

`bash -n lib/modules/fan.sh tests/run-tests.sh`, `git diff --check` e `tests/run-tests.sh` sono passati; la suite ha riportato 71 test superati e 0 falliti. I casi diretti coprono `8`, `08`, `0008`, `"08"`, `060`, `000`, overflow, testo non numerico, override runtime e stato persistente invalido. La verifica systemd live, il driver, la temperatura fisica, gli RPM e il comportamento su console PS5 reale restano da eseguire sull'hardware target.

Commit sorgente: [`b899122836c1ba159376dbd0385996387a9465cd`](https://github.com/EmaCorona/ps5-cachyos-tools/commit/b899122836c1ba159376dbd0385996387a9465cd).
