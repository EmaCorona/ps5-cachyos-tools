# Gamescope: diagnostica opt-in della pipeline DRM ultrawide

Implementazione sul branch `feature/kde-gamescope-black-screen` (28 ottobre 2026), commit [`9dc7cb9ef92369c737961cfcfbfe9550103e96da`](https://github.com/EmaCorona/ps5-cachyos-tools/commit/9dc7cb9ef92369c737961cfcfbfe9550103e96da).

## Problema

Sul target, Gamescope seleziona 3440×1440@100 Hz tramite il candidato CVT-RB e avvia il compositor, ma l'utente continua a vedere nero. La modalità 16:9 resta visibile. La selezione CVT e il superamento dell'atomic `TEST_ONLY` non hanno risolto il sintomo.

## Causa individuata

La causa specifica non è ancora dimostrata. I log correnti non registrano in modo sufficiente il risultato del commit atomico effettivo, il completamento del page flip e il framebuffer realmente associato al primary plane durante il nero. Il link DP/HPD va campionato separatamente mentre il difetto è presente. Un commit e un flip completati non dimostrerebbero da soli che il pannello mostri l'immagine.

## Correzione applicata

La patch downstream Gamescope aggiunge telemetria esplicita solo quando il wrapper riceve `PS5_DRM_DIAGNOSTICS=1` nella configurazione del modulo. Per limitare impatto e volume, registra al massimo 32 tentativi di commit e 32 page flip nella finestra iniziale e altri 32+32 alla prima ripresa effettiva del seat. Ogni evento indica la finestra; il callback conserva quella del commit anche se arriva dopo la ripresa. La telemetria include timestamp monotono, connettore/CRTC, timing e flag richiesti, esito e errno del commit; ogni callback porta anche l'ID del commit associato. Dopo il page flip legge lo stato CRTC, primary plane e framebuffer con dimensioni, FourCC e modifier. Registra esplicitamente se il primary plane manca. Nei commit riusciti `errno=0`; in caso di errore registra il valore osservato. Non cambia timing, formato, colore, modalità o link e non emette messaggi per ogni frame oltre il limite.

Il valore predefinito è disattivato. La selezione dinamica esistente, il fallback KMS e la modifica CVT-RB precedente restano intatti. La CVT-RB non è dichiarata una soluzione del nero: è stata applicata e selezionata sul target senza ottenere un'immagine visibile. Nessun workaround VT automatico viene aggiunto. L'assenza del callback va valutata su una finestra temporale controllata; la telemetria non applica un timeout o un retry.

## File coinvolti

| Percorso | Responsabilità |
|---|---|
| `packaging/gamescope/0001-drm-use-preferred-edid-dtd.patch` | Log opt-in, limitati e read-only di commit, page flip, CRTC, primary plane e framebuffer |
| `packaging/gamescope/PKGBUILD` | Nuovo `pkgrel` e fingerprint della patch aggiornata |
| `modules/gamescope/files/gamescope-session-ps5` | Validazione della config e propagazione del flag solo quando `1` |
| `modules/gamescope/install.sh` | Esempio commentato dell'opzione diagnostica |
| `tests/gamescope-upstream-patch-tests.sh` | Verifica applicazione al commit Gamescope fissato e presenza dei campi/limiti diagnostici |
| `tests/graphics-modules-tests.sh` | Verifica che il flag resti spento per default, sia propagato quando richiesto e rifiuti valori non booleani |
| `docs/modules/gamescope.md`, `packaging/gamescope/README.md` | Istruzioni di abilitazione, interpretazione e limite della prova |

## Verifica e limiti

- Test di applicazione della patch contro il commit upstream fissato: **PASS**.
- Test wrapper, suite Gamescope e suite completa repository: **PASS** (suite completa exit code 0; le prove ventole usano fixture temporanee).
- Parsing del PKGBUILD con `makepkg --printsrcinfo` e coerenza del checksum BLAKE2: **PASS**.
- Build Gamescope 3.17.0-3 dal PKGBUILD: **PASS**; compilati e linkati i 785 target Meson/Ninja, incluso `src/gamescope` con la patch diagnostica. `makepkg --noarchive` non ha creato né installato un pacchetto. I warning di compilazione osservati appartengono a sorgenti upstream non toccati.
- Dipendenze build: installate temporaneamente quelle mancanti e rimosse a fine build; il confronto Pacman prima/dopo è identico e nessun pacchetto preesistente è stato aggiornato.
- Acquisizione hardware con telemetria durante il nero, confronto col 16:9 e prova visiva: **NOT RUN**. L'implementazione migliora l'osservabilità, non dimostra né corregge da sola la causa fisica del nero.
- Modulo ventole: file e servizi non modificati; la suite completa ha eseguito i propri test isolati in fixture temporanee.

Il task seguente resta la raccolta T-001 sul display: acquisire il log `PS5_DRM_DIAG`, journal e stato DRM/link/HPD mentre lo schermo è nero, poi confrontarli con KDE visibile. Solo dopo si può scegliere e implementare il ramo T-002 appropriato.

## Evidenza hardware successiva — pacchetto 3.17.0-4

La build 3.17.0-3 sopra riportata è la verifica storica eseguita durante l'implementazione originaria. Nel test Gamescope a risoluzione ridotta del 2026-10-29 era installato `ps5-cachyos-gamescope 3.17.0-4`. Pacman possiede il binario `/usr/lib/ps5-cachyos-tools/gamescope/bin/gamescope` (percorso predefinito del wrapper) e `/usr/share/ps5-cachyos-tools/gamescope/build-info`; `pacman -Qkk ps5-cachyos-gamescope` ha riportato 47 file e 0 alterati.

Il `build-info` dell'artefatto installato dichiara upstream commit `e6674a98118ca7b098b98a3874b8f195ae1bf750`, patch SHA256 `aef0714d0301b396d1c0903939b5f236218ecf7e2e12c4a961330f93d78a42cd` e helper SHA256 `511ed608e3825e9a4573d2bcfda500f7dd71c0ee27b55a35a178eb60ad87b564`; i digest corrispondono ai file correnti del branch. La sessione Gamescope e il gioco del run ridotto sono quindi stati verificati sull'artefatto pkgrel 4 corrispondente. Questa verifica attesta l'identità del pacchetto installato e il suo uso nel run; non è una nuova compilazione locale lanciata durante l'audit.
