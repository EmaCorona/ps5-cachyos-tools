# Ripristinato il cambio live tra KDE e Gamescope

- **Commit sorgente:** [`08f967d83253`](https://github.com/EmaCorona/ps5-cachyos-tools/commit/08f967d8325377a121ec5f20159f49fd1c8aa8f9) — `08f967d8325377a121ec5f20159f49fd1c8aa8f9`.
- **Data:** 2026-10-26
- **Modulo:** `session`

## Problema

La policy del repository avviava KDE come sessione predefinita, ma il comando installato `steamos-session-select` era diventato uno stub informativo. La richiesta di passaggio a Gamescope non raggiungeva un controller attivo e la sessione grafica già avviata restava KDE.

## Causa individuata

Il supervisore precedente eseguiva una sola sessione in foreground e terminava con essa; non esisteva un canale di controllo live che consentisse al selettore di chiedere una transizione. Rendere il selettore persistente avrebbe inoltre violato il requisito che il branch controlli la sessione iniziale al boot.

## Correzione applicata

- Il supervisore ora resta attivo e lancia KDE e Gamescope in process group separati, arrestando il gruppo corrente prima del cambio.
- `steamos-session-select` invia richieste atomiche e volatili tramite file richiesta atomico in una directory privata sotto `$XDG_RUNTIME_DIR` e polling del supervisore ogni 200 ms in sessione e al successivo intervallo DRM durante l’attesa.
- `--default` e `--once` attivano una transizione live senza modificare la scelta del prossimo boot.
- Un lock singleton impedisce supervisori concorrenti; le richieste durante l'attesa DRM vengono rilevate al successivo polling per tornare a KDE.
- La policy versionata rimane l'unica autorità per scegliere la sessione al boot e i fallback Gamescope continuano ad avviare KDE senza cambiare la policy.

## File coinvolti

| File | Responsabilità |
|---|---|
| `modules/session/files/session-common.sh` | Canale IPC privato, richieste atomiche, verifica PID e lock singleton. |
| `modules/session/files/session-supervisor` | Gestione persistente delle sessioni, transizioni, arresto e fallback. |
| `modules/session/files/steamos-session-select` | Invio delle richieste live senza scrivere la policy di boot. |
| `modules/session/module.conf` | Revisione del modulo Session. |
| `tests/graphics-modules-tests.sh` | Verifica cambi live, DRM wait, assenza supervisore e policy invariata. |
| `docs/modules/session.md`, `docs/architecture.md` | Documentazione aggiornata. |

## Verifica e limiti

- `bash -n` sui tre script Session e sul test runner: superato.
- `./tests/graphics-modules-tests.sh`: 29 superati, 0 falliti.
- `git diff --check`: superato.
- I test usano processi mock e non attestano la transizione su PS5 reale, la resa HDMI o il comportamento al reboot hardware. L'installazione live sul sistema non è stata eseguita.
