# Gamescope prova in sequenza i timing EDID supportati dal driver

- Commit sorgente: [`b3844c7402802a1662bd62b8ecb49353f81f9c7d`](https://github.com/EmaCorona/ps5-cachyos-tools/commit/b3844c7402802a1662bd62b8ecb49353f81f9c7d)
- Data: 2026-10-27
- Sorgente Gamescope verificato: commit upstream [`e6674a98118ca7b098b98a3874b8f195ae1bf750`](https://github.com/ValveSoftware/gamescope/commit/e6674a98118ca7b098b98a3874b8f195ae1bf750)
- File principali: `packaging/gamescope/0001-drm-use-preferred-edid-dtd.patch`, `packaging/gamescope/PKGBUILD`, `tests/gamescope-upstream-patch-tests.sh`

## Problema

L’EDID del monitor dichiara un timing nativo 3440×1440, ma DRM/KMS sul sistema analizzato enumera 2560×1440 e 1920×1080 senza 3440×1440. Il backend Gamescope seleziona una modalità KMS e non prova il timing dettagliato EDID escluso dal kernel; l’output risultava quindi 16:9 anche quando il display dichiarava un formato ultrawide.

## Causa individuata

Le rilevazioni di sistema riportate nell’analisi precedente mostravano il timing 3440×1440 nell’EDID e nelle impostazioni di KWin, ma non in `modetest`/KMS. Nel sorgente Gamescope 3.17.0 fissato, la selezione automatica usa le modalità enumerate dal connettore. La prima patch downstream considerava solo il primo DTD EDID: se quel timing veniva rifiutato dal test DRM, non verificava eventuali timing EDID successivi.

## Correzione applicata

La patch ora:

- esamina in ordine tutti i DTD digitali progressivi esposti da libdisplay-info, mantenendo il preferred per primo;
- rifiuta valori non positivi, porches incoerenti, refresh non rappresentabili e timing che eccedono i campi di modalità DRM; non impone risoluzione, rapporto d’aspetto o frequenza massimi specifici per il monitor;
- evita di duplicare timing EDID identici;
- riusa una modalità KMS già enumerata quando coincide con il candidato;
- prova con atomic `TEST_ONLY | ALLOW_MODESET` ciascun timing EDID non enumerato e passa al successivo quando il driver lo rifiuta;
- mantiene la modalità KMS originariamente selezionata se nessun candidato viene accettato;
- ricostruisce i candidati quando Gamescope aggiorna lo stato del connettore dopo hotplug o cambio di EDID.

Il `PKGBUILD` ricostruisce il pacchetto Arch standard `gamescope` 3.17.0 con la patch prima della compilazione. L’installer del modulo `ps5-cachyos-tools` non possiede né sostituisce `/usr/bin/gamescope`; reinstallare quel solo modulo non applica la fix al binario.

## File coinvolti

| File | Responsabilità |
|---|---|
| `packaging/gamescope/0001-drm-use-preferred-edid-dtd.patch` | Candidati dinamici EDID, controllo DRM, fallback KMS e aggiornamento dopo hotplug. |
| `packaging/gamescope/EDIDModeSelection.h` | Helper puro per selezionare in ordine il primo candidato accettato, condiviso con i test comportamentali. |
| `packaging/gamescope/PKGBUILD` | Costruzione pacman di Gamescope 3.17.0 con applicazione della patch e installazione dell’helper nel sorgente upstream. |
| `packaging/gamescope/README.md` | Procedura di build/installazione e vincolo di versione upstream. |
| `tests/gamescope-upstream-patch-tests.sh` | Applicabilità alla revisione fissata, iterazione DTD, hotplug e fallback. |
| `tests/gamescope-edid-mode-selection-tests.cpp` e `.sh` | Test compilato dell’ordine dei candidati, del fallback quando tutti sono rifiutati e dei diversi formati. |
| `docs/modules/gamescope.md` | Comportamento automatico e confine tra modulo wrapper e pacchetto Gamescope. |
| `.github/workflows/validate.yml` | Esclude dal solo controllo whitespace il diff unified incorporato, che conserva spazi di contesto necessari alla patch; l’applicabilità resta verificata dal test dedicato. |

## Verifica e limiti

- `./tests/run-tests.sh`: suite completa terminata senza errori, incluso il test C++ dell’helper di selezione; gli 87 test ventole eseguiti usano directory temporanee e non hanno modificato servizi o configurazioni live.
- `bash tests/gamescope-upstream-patch-tests.sh /tmp/gamescope-audit`: patch applicata al commit upstream fissato e controlli di iterazione/fallback superati.
- `makepkg --printsrcinfo` sul PKGBUILD: superato.
- Verifica isolata della sorgente locale makepkg (`--verifysource` con checksum BLAKE2): superata.
- Compilazione del pacchetto Gamescope e modeset sul display reale: non eseguiti. In questa sessione non sono presenti Meson, Ninja o pkg-config e non è stato installato/sostituito il binario di sistema. La stabilità del modeset e l’uso effettivo della modalità ultrawide vanno confermati con il pacchetto ricostruito e una prova hardware.
- Il PKGBUILD è fissato a 3.17.0; per versioni upstream successive occorre aggiornare pin e patch e ripetere le verifiche. Un aggiornamento ufficiale del pacchetto può sostituire la build patchata.
- Il modulo ventole e il suo stato live non sono stati modificati.

## Riferimenti

- [Gamescope 3.17.0 DRMBackend.cpp](https://github.com/ValveSoftware/gamescope/blob/e6674a98118ca7b098b98a3874b8f195ae1bf750/src/Backends/DRMBackend.cpp)
- [`packaging/gamescope/README.md`](../../packaging/gamescope/README.md)
