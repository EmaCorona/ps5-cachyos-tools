# Gamescope prova il timing DTD preferito dell’EDID con fallback KMS

- Commit del repository: `84ffe90eb659b0c8f5d7f12ed69836473721ce37` (`fix(gamescope): try preferred EDID timing with atomic test`)
- Data: 2026-10-27
- Sorgente Gamescope supportata dalla patch: commit upstream [`e6674a98118ca7b098b98a3874b8f195ae1bf750`](https://github.com/ValveSoftware/gamescope/commit/e6674a98118ca7b098b98a3874b8f195ae1bf750)
- File principali: `packaging/gamescope/patches/0001-drm-use-preferred-edid-dtd.patch`, `tests/gamescope-upstream-patch-tests.sh`

## Problema

Il display dichiara un timing nativo tramite EDID, ma il driver non sempre lo include nella lista DRM `GETCONNECTOR`. Il backend Gamescope sceglie una modalità tra quelle enumerate; in questo caso poteva quindi ripiegare su 2560×1440 16:9 anche se il DTD EDID descriveva 3440×1440 ultrawide.

Le prove raccolte sul sistema mostravano 3440×1440 attivo in KWin, mentre `modetest` e sysfs elencavano soltanto 2560×1440 e 1920×1080. Questo dimostra che KWin aveva impostato il timing, ma non provava da solo che Gamescope potesse riutilizzarlo in ogni stato KMS.

## Causa individuata

Nel sorgente upstream fissato, la selezione iniziale in `DRMBackend.cpp` cerca la modalità richiesta o sceglie tra le modalità del connettore restituite dal kernel. Il DTD dell’EDID viene analizzato per altri metadati, ma non diventa un candidato nella selezione iniziale se il driver lo ha filtrato.

## Correzione applicata

La patch downstream:

- costruisce un candidato da un DTD progressivo con sync digitali separati, usando pixel clock, porches e polarità presenti nell’EDID;
- rifiuta timing fuori dai limiti dimensionali/frequenza o con porches non coerenti;
- durante la selezione automatica conserva una modalità KMS già coincidente con dimensioni e refresh del DTD;
- se la modalità nativa manca, invia un atomic `TEST_ONLY | ALLOW_MODESET` per verificare il timing prima di selezionarlo;
- in caso di EDID non idoneo, proprietà DRM mancanti o test atomico rifiutato, continua con la modalità KMS già selezionata;
- rilegge il DTD quando il backend aggiorna lo stato del connettore.

La patch è in `packaging/gamescope` perché questo repository installa wrapper e helper, ma non costruisce né gestisce il pacchetto Gamescope di sistema. Deve essere applicata dal processo che costruisce Gamescope 3.17.0; l’installazione del solo modulo non modifica il binario già installato.

## File coinvolti

| File | Responsabilità |
|---|---|
| `packaging/gamescope/patches/0001-drm-use-preferred-edid-dtd.patch` | Estrae e prova il timing DTD preferito nel backend DRM, con fallback KMS. |
| `packaging/gamescope/README.md` | Fissa versione/commit upstream e spiega il confine d’integrazione del pacchetto. |
| `tests/gamescope-upstream-patch-tests.sh` | Verifica che la patch si applichi alla revisione Gamescope supportata e contenga il percorso di fallback. |
| `docs/modules/gamescope.md` | Documenta comportamento e limite dell’installer del modulo. |

## Verifica e limiti

- `tests/gamescope-upstream-patch-tests.sh /tmp/ps5-gamescope-3.17.0`: superato contro il commit upstream fissato.
- `python3 tests/gamescope-display-mode-tests.py`: 8 test superati.
- `bash -n tests/gamescope-upstream-patch-tests.sh` e `git diff --check` sui file del repository: superati; il file `.patch` è escluso dal controllo whitespace perché contiene contesto diff upstream con indentazione tab già presente.
- Revisione indipendente della patch: approvata.
- Compilazione di Gamescope: non eseguita; nell’ambiente non sono disponibili Meson, Ninja, pkg-config né gli header Vulkan.
- Atomic test-only e modeset reale su display: non eseguiti. Il risultato su Gamescope richiede un pacchetto ricostruito con la patch e una prova hardware; il binario di sistema non è stato sostituito.
- Nessuna ventola, sessione grafica, configurazione KMS live o stato di boot è stata modificata.

## Riferimenti

- [Sorgente Gamescope 3.17.0: backend DRM](https://github.com/ValveSoftware/gamescope/blob/e6674a98118ca7b098b98a3874b8f195ae1bf750/src/Backends/DRMBackend.cpp)
- [API DRM atomic e modalità](https://docs.kernel.org/gpu/drm-kms.html)
