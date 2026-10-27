# Gamescope lascia al DRM le modalità native e gli eventi hotplug

- Commit sorgente: [`7b93e2d86e2b142e9549731e7654e9f0c1f21eb3`](https://github.com/EmaCorona/ps5-cachyos-tools/commit/7b93e2d86e2b142e9549731e7654e9f0c1f21eb3)
- Data: 2026-10-27
- File principali: `modules/gamescope/files/gamescope-session-ps5`, `modules/gamescope/files/ps5-gamescope-display-mode`

## Problema

Gamescope mostrava il display in 16:9 anche se l'EDID collegato dichiarava modalità 3440×1440. Il wrapper calcolava una risoluzione, un refresh e un connettore all'avvio e passava sempre `-W/-H/-w/-h/-r` e `--prefer-output`; queste preferenze restavano legate al display presente all'avvio e potevano prevalere sull'auto-selezione del backend DRM dopo un cambio di connettore o modalità.

## Causa individuata

Le prove live mostrano che l'EDID di `ZQE-CAA` dichiara 3440×1440 a circa 99,98 e 59,97 Hz, ma `/sys/class/drm/card0-DP-1/modes` e `modetest -M amdgpu -c` espongono soltanto 2560×1440@59,95 e 1920×1080@60/59,94. Il vecchio detector, correttamente limitato alle modalità KMS, sceglieva quindi 2560×1440, formato 16:9.

KScreen mostrava una modalità custom 3440×1440@99,94 segnata `!`, mentre KWin registrava `Modeset failed: Invalid argument`. Il kernel rifiutava inoltre il parametro di boot attualmente attivo `video=DP-1:1920x1080@60` con `User-defined mode not supported`. Tale parametro spiega i tentativi falliti a 1080p; non è dimostrato che causi anche il filtraggio delle modalità 3440. Il file di boot persistente risultava già pulito, ma il parametro resta nella command line del boot corrente.

## Correzione applicata

- Il detector legge il flag `preferred` restituito da KMS e preferisce quella modalità; se non esiste, sceglie tra le sole modalità condivise da sysfs e `modetest` usando risoluzione e refresh, senza priorità codificate per nomi di connettore o rapporti d'aspetto.
- In configurazione automatica il wrapper non passa più risoluzione, refresh o connettore come preferenze fisse. Gamescope DRM può selezionare il modo preferred esposto dal driver e gestire i propri eventi di hotplug.
- La modalità rilevata resta nei log come candidato diagnostico; il wrapper non forza timing letti soltanto dall'EDID e assenti dall'elenco KMS.
- Gli override espliciti rimangono disponibili per compatibilità; risoluzioni output e annidata devono essere indicate in coppia e tutti i valori sono validati.

## File coinvolti

| Percorso | Responsabilità |
|---|---|
| `modules/gamescope/files/gamescope-session-ps5` | Preferenze dinamiche per impostazione predefinita, override espliciti e log diagnostici |
| `modules/gamescope/files/ps5-gamescope-display-mode` | Priorità modalità native e selezione dinamica tra modalità KMS valide |
| `tests/gamescope-display-mode-tests.py` | Mode preferred, selezione 32:9, connettore disconnesso e modalità non concordi |
| `tests/graphics-modules-tests.sh` | Assenza di blocchi automatici e validazione degli override |
| `docs/modules/gamescope.md` | Comportamento e limiti KMS documentati |

## Verifica e limiti

- `python3 tests/gamescope-display-mode-tests.py`: superato, 8/8.
- `bash tests/graphics-modules-tests.sh`: superato, 36/36.
- `tests/run-tests.sh`: superato, exit code 0; include le suite framework, VRAM, grafica, KDE, Gamescope, manifesti e fixture isolate del controller ventole.
- `bash -n` sugli script modificati, `python3 -m py_compile` e `git diff --check`: superati.
- La build installata è Gamescope 3.17.0; il sorgente ufficiale del backend DRM gestisce il refresh dei connettori dopo gli eventi e sceglie tra modalità KMS.
- Verifica hardware del nuovo wrapper, switch live e hotplug: non ancora eseguiti al momento della redazione.
- Avvio con command line pulita e modeset reale 3440×1440: non verificati. La sessione corrente mantiene `video=DP-1:1920x1080@60`; rimuoverlo dall'avvio già configurato richiede un nuovo boot, che non è stato eseguito per rispettare il vincolo operativo sulle ventole.
- Finché il driver non espone e convalida 3440×1440 tramite KMS, il wrapper non può garantire quella risoluzione. La verifica dopo boot pulito dovrà ricontrollare `modetest` e il risultato effettivo del modeset.

## Fonti

- [Backend DRM Gamescope 3.17.0](https://github.com/ValveSoftware/gamescope/blob/3.17.0/src/Backends/DRMBackend.cpp)
- [Documentazione kernel sui parametri di boot](https://docs.kernel.org/admin-guide/kernel-parameters.html)
- [Documentazione kernel DRM/KMS](https://docs.kernel.org/gpu/drm-kms-helpers.html)
- [Commit sorgente della correzione](https://github.com/EmaCorona/ps5-cachyos-tools/commit/7b93e2d86e2b142e9549731e7654e9f0c1f21eb3)
