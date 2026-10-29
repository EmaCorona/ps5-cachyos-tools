# Workaround KWin per il fallimento AMDGPU RA24 al rientro a KDE

- **Branch:** `fix/kde-amdgpu-ra24`
- **Commit sorgente:** [`46dcb0011a7e`](https://github.com/EmaCorona/ps5-cachyos-tools/commit/46dcb0011a7ec6e6913e19f8dbcb69a46b690eca) — `46dcb0011a7ec6e6913e19f8dbcb69a46b690eca`.
- **Data:** 2026-10-29
- **Moduli:** `kde`, `session`

## Problema

Dopo il ritorno da Gamescope a KDE, il kernel AMDGPU registra ripetutamente `Unsupported screen format RA24 little-endian`, mentre KWin segnala `Modeset failed: Invalid argument` e `Applying output configuration failed`. La sessione può restare senza output visibile.

## Causa individuata

Nei log esaminati il fallimento della configurazione DRM di KWin coincide con il riavvio del compositor dopo Gamescope. I log non identificano quale plane o proprietà della richiesta atomica introduca RA24. L'uso del cursor plane hardware è un meccanismo plausibile ma non dimostrato; `KWIN_FORCE_SW_CURSOR=1` è un workaround reversibile segnalato per la stessa firma di errore, non una causa verificata su questo hardware.

## Correzione applicata

- Il profilo KDE conserva il default `KWIN_FORCE_SW_CURSOR=0` e rende disponibile `KWIN_FORCE_SW_CURSOR=1` come override diagnostico reversibile. Il default non cambia finché l'A/B 16:9 richiesto dall'analisi non conferma il workaround.
- Il supervisore mantiene i parametri KWin per il successivo avvio KDE, li importa negli ambienti systemd/D-Bus di KDE e li rimuove da tali ambienti prima dello switch.
- Il processo Gamescope filtra i parametri KWin, così il workaround resta confinato al compositor KDE.
- Le revisioni dei moduli KDE e Session sono incrementate affinché un aggiornamento del repository rinnovi i file installati.

Questa modifica prepara il percorso controllato per provare il workaround, ma non corregge ancora automaticamente il fallimento RA24: il valore `1` non è attivo per default. Un test A/B su monitor 16:9 resta necessario per confermare che `1` elimini RA24 e ripristini l'output; il software cursor può aumentare il lavoro di compositing in KDE.

## File coinvolti

| File | Responsabilità |
|---|---|
| `modules/kde/files/ps5-kde-environment.sh` | Default software cursor e override `0`. |
| `modules/kde/check.sh`, `modules/kde/module.conf` | Verifica del profilo e rinnovo degli artefatti installati. |
| `modules/session/files/session-supervisor`, `modules/session/check.sh`, `modules/session/module.conf` | Propagazione KWin solo a KDE, isolamento da Gamescope e verifica degli artefatti installati. |
| `tests/graphics-modules-tests.sh` | Default/override, aggiornamento revisioni e passaggio KDE→Gamescope→KDE con controllo dell'ambiente. |
| `docs/modules/kde.md`, `docs/modules/session.md` | Documentazione del comportamento e dei limiti. |

## Verifica e limiti

- `bash tests/graphics-modules-tests.sh`: 44 test superati, 0 falliti.
- `bash tests/run-tests.sh`: 88 test superati, 0 falliti.
- `bash tests/core/run-tests.sh`: 65 test superati, 0 falliti.
- `bash -n` sugli script modificati e `git diff --check`: superati.
- ShellCheck non è installato nell'ambiente.
- Non è stato eseguito uno switch grafico né un test A/B su un monitor 16:9; quindi non si dichiara ancora verificata la correzione su hardware PS5. I test ventole della suite usano esclusivamente file e root temporanee; il modulo ventole installato e il profilo reale non sono stati toccati.
