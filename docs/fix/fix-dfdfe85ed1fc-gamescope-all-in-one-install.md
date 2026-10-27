# Gamescope dinamico installato insieme al modulo

Commit sorgente: [`dfdfe85ed1fc`](https://github.com/EmaCorona/ps5-cachyos-tools/commit/dfdfe85ed1fcf81895fc91630eb7ec7f92323907) · 2026-10-27.

## Causa

Il modulo `gamescope` installava wrapper e strumenti di diagnosi, mentre la patch EDID viveva in un PKGBUILD da invocare separatamente. Un'installazione normale del repository poteva quindi lasciare attivo il Gamescope stock, che non applicava la selezione dei DTD EDID.

## Correzione

Il manifest del modulo dichiara un `POST_INSTALL_HOOK` che valida e costruisce Gamescope downstream durante la normale installazione. Il pacchetto `ps5-cachyos-gamescope` conserva i file in percorsi privati, lascia il pacchetto ufficiale installato per i runtime e il layer WSI, e viene usato esplicitamente dalla sessione. Il controllo del modulo verifica database pacman, binario, script e commit upstream. La rimozione elimina il solo pacchetto downstream. Il framework documenta e supporta l'hook post-install per i moduli.

La build è fissata a Gamescope 3.17.0 e alla revisione upstream `e6674a98118ca7b098b98a3874b8f195ae1bf750`. L'aggiornamento a nuove versioni richiede di aggiornare e verificare la patch, i test upstream e il pin nel PKGBUILD.

## File principali coinvolti

| File | Responsabilità |
|---|---|
| `modules/gamescope/module.conf`, `install.sh`, `package.sh`, `package-remove.sh` | Integrare build, verifica e rimozione nel lifecycle del modulo. |
| `modules/gamescope/files/ps5-gamescope-package` e `files/gamescope-session-ps5` | Costruire, installare e usare il binario patchato in percorsi privati. |
| `packaging/gamescope/PKGBUILD` | Produrre il pacchetto downstream basato su una revisione upstream fissata. |
| `lib/core/registry.sh`, `lib/core/installer.sh`, `bin/ps5-cachyos-tools` | Validare gli hook modulari e coordinare commit, finalize e rollback. |
| `tests/core/run-tests.sh`, `tests/gamescope-package-tests.sh`, `tests/graphics-modules-tests.sh` | Verificare lifecycle, rollback, package e regressioni grafiche. |

## Verifiche

- Suite core del framework: 65 test superati, inclusi rollback multi-hook dopo errore di commit.
- Suite moduli grafici: 36 test superati.
- Suite Gamescope package: superata con pacman simulato; copre cache symlinkata, rimozione `--sysroot`, ripristino dopo rimozione parziale, journal fino a `finalize` e rollback senza helper avviato.
- Runner completo `tests/run-tests.sh`: superato, exit code 0.
- `bash -n` sui file shell modificati, `git diff --check` e `makepkg --printsrcinfo`: superati.
- `makepkg --verifysource`: superato; le sorgenti upstream sono state validate e i checkout temporanei rimossi.
- Build completa del pacchetto: non eseguita perché non è stata avviata l'installazione della toolchain di build sull'host.
- Modeset e avvio 21:9 su PS5 reale: non eseguiti in questa sessione.

La logica e la configurazione hardware del modulo ventole non sono state modificate; i test ventole inclusi nella suite sono simulati.
