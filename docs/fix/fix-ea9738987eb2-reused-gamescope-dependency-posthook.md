# Rebuild Gamescope non necessaria durante l'installazione di Session

Fonte primaria: [commit `ea9738987eb2`](https://github.com/EmaCorona/ps5-cachyos-tools/commit/ea9738987eb20594c59f5f258cc5b0dd5d86f48e), 29 ottobre 2026.

## Problema

Su PS5 con kernel 7.2.3, l'installazione selettiva di `session` riconosceva `gamescope` già valido e ne saltava la copia, ma eseguiva comunque il post-hook del pacchetto. Questo scaricava e ricompilava Gamescope 3.17.0, pur non richiedendo alcun aggiornamento, e installava temporaneamente le dipendenze di build.

## Causa individuata

`core_install_body` applicava il riuso alle dipendenze valide; `core_install_preflight` e `core_install_post_hooks` iteravano invece sull'intero ordine selezionato senza escluderle. Il preflight del pacchetto poteva richiedere strumenti di build anche quando non era necessaria alcuna build.

## Correzione applicata

Il preflight conserva la validazione degli hook ma evita quello esterno del pacchetto per una dipendenza già valida. La transazione registra gli ID delle dipendenze riusate e salta per esse i post-hook `install`, `commit`, `finalize` e `rollback`. Una richiesta esplicita di reinstallazione del modulo conserva il normale percorso di aggiornamento. La selezione e la discovery tramite manifest restano invariate.

## File coinvolti

| File | Responsabilità |
| --- | --- |
| `lib/core/installer.sh` | Tracciamento delle dipendenze valide e filtro dei post-hook. |
| `tests/graphics-modules-tests.sh` | Prima installazione e reinstallazione selettiva di `session` con conteggio delle operazioni del pacchetto. |
| `docs/modules/gamescope.md` | Lifecycle documentato. |

## Verifica e limiti

La suite grafica verifica che la prima installazione esegua `install`, che la successiva installazione selettiva di `session` non esegua più operazioni pacchetto sulla dipendenza valida e che riesca anche quando il preflight esterno è forzato a fallire. Il test usa un helper fittizio; l'installazione live e il pacchetto reale sono verificati separatamente nel report E2E.
