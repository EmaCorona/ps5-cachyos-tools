# Documentazione del purge di boot-cleanup

- Commit: [`8b93ac65cb9bbe2fe5d84f0374bb945fd30006b3`](https://github.com/EmaCorona/ps5-cachyos-tools/commit/8b93ac65cb9bbe2fe5d84f0374bb945fd30006b3)
- Data: 2026-10-26

## Problema

Il README affermava che `--purge-config` conservasse `boot-cleanup.conf` e che l'hook `remove.sh` non lo eliminasse. Il comportamento documentato era contrario all'implementazione.

## Causa individuata

`modules/boot-cleanup/remove.sh` elimina `/etc/ps5-cachyos-tools/boot-cleanup.conf` quando riceve `keep=0`, cioè con `--purge-config`. Inoltre `modules/boot-cleanup/module.conf` dichiara `cleanup.state`, `steam-stale.list` e `migration.state` in `OWNED_PATHS`; il core rimuove questi file dichiarati durante la rimozione in entrambe le modalità. I file sono rimossi, mentre le directory vuote non sono eliminate esplicitamente.

## Correzione applicata

Il README ora distingue il comportamento di `--keep-config` e `--purge-config` e descrive separatamente la rimozione degli artefatti posseduti e delle directory residue. Non è cambiato il comportamento del modulo.

## File coinvolti

| File | Responsabilità |
|---|---|
| `README.md` | Corregge le istruzioni e la descrizione del purge di `boot-cleanup`. |

## Verifica e limiti

- `tests/boot-cleanup-tests.sh`: PASS, 18 test superati e 0 falliti; verifica keep-config, purge-config e ciclo del runner su root temporanee.
- `tests/run-tests.sh`: PASS, 78 test fan superati e 0 falliti; la suite boot-cleanup inclusa ha superato 18 test. La trap finale ha riportato un errore di permessi rimuovendo un artefatto temporaneo, senza cambiare il codice d'uscita 0.
- `tests/core/run-tests.sh`: PASS, 56 test core superati e 0 falliti, inclusi 20 test di regressione R4.
- `bash -n` sui file shell della CI e `git diff --check`: PASS.
- Verifica della console: DMI identifica una PS5 Sony CFI-2016 B01Y con CachyOS, ma i test live che richiedono root/systemd non sono stati eseguiti. `sudo -n` è bloccato da `no new privileges` e il bus systemd di sistema non è accessibile in questa sessione.

Fonti primarie: [commit della correzione](https://github.com/EmaCorona/ps5-cachyos-tools/commit/8b93ac65cb9bbe2fe5d84f0374bb945fd30006b3), [`remove.sh`](https://github.com/EmaCorona/ps5-cachyos-tools/blob/8b93ac65cb9bbe2fe5d84f0374bb945fd30006b3/modules/boot-cleanup/remove.sh), [`module.conf`](https://github.com/EmaCorona/ps5-cachyos-tools/blob/8b93ac65cb9bbe2fe5d84f0374bb945fd30006b3/modules/boot-cleanup/module.conf), [`installer.sh`](https://github.com/EmaCorona/ps5-cachyos-tools/blob/8b93ac65cb9bbe2fe5d84f0374bb945fd30006b3/lib/core/installer.sh) e [test boot-cleanup](https://github.com/EmaCorona/ps5-cachyos-tools/blob/8b93ac65cb9bbe2fe5d84f0374bb945fd30006b3/tests/boot-cleanup-tests.sh).
