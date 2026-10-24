# Stato profilo obbligatorio per il controller

## Problema

Dopo l'installazione, il daemon poteva continuare a usare il profilo dichiarato in `fan.conf` se `/etc/ps5-fan/state` veniva rimosso o non era leggibile. L'installer invece non poteva derivare il timeout di readiness dallo stesso stato, creando comportamenti divergenti.

## Correzione applicata

Il daemon richiede ora lo stato profilo leggibile prima dell'avvio e pubblica `profile-state-missing` come errore persistente quando manca. Durante il runtime, la scomparsa dello stato non seleziona più implicitamente il profilo configurato: viene trattata come profilo non valido. Il test di regressione verifica il rifiuto esplicito all'avvio; la suite mantiene anche il controllo parallelo dell'installer.

## Verifica e limiti

`bash -n bin/ps5-fan-daemon lib/modules/fan.sh tests/run-tests.sh`, `git diff --check` e `tests/run-tests.sh` sono passati con 75 test superati e 0 falliti. Restano non verificati ShellCheck locale, systemd live, driver e hardware PS5 reale. La verifica systemd su staging CI passa e i workflow/status GitHub non risultano ancora osservabili.

Commit sorgente: [`3392ca142be6f0c9b88dec19cb6b5b2383dd8eee`](https://github.com/EmaCorona/ps5-cachyos-tools/commit/3392ca142be6f0c9b88dec19cb6b5b2383dd8eee).
