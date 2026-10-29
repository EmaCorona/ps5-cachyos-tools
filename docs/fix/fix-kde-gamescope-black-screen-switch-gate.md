# Switch KDE/Gamescope: verifica del compositor e ambiente reversibile

Commit sorgente: [`e262376`](https://github.com/EmaCorona/ps5-cachyos-tools/commit/e262376) — 2026-10-28.

## Sintomi e causa

Durante il tentativo di switch del 2026-10-28, il supervisore ha registrato `systemctl stop` con `exit=5` e ha poi rifiutato Gamescope perché `loginctl seat-status seat0` continuava a mostrare `[MASTER] drm:card0`. Una delle unità incluse nel comando di stop (`xdg-desktop-portal-kde.service`) non era installata (`LoadState=not-found`), sufficiente a far fallire il comando aggregato. L'etichetta `[MASTER]` riflette il tag `master-of-seat` assegnato dal sistema al device per la gestione del seat; non indica il DRM master posseduto da un processo. `seat-status` è inoltre output umano, non uno stato strutturato del compositor. Il vecchio gate quindi usava un'osservazione non pertinente e poteva bloccare ogni switch. [Documentazione systemd `loginctl`](https://www.freedesktop.org/software/systemd/man/latest/loginctl.html) descrive `seat-status` come output leggibile e il tag `master-of-seat` come proprietà del dispositivo.

Un ulteriore problema nel lifecycle dell'ambiente: `clear_kde_environment` cancellava i parametri KWin anche dall'ambiente del supervisore permanente. Un override diagnostico poteva così non essere più presente quando il supervisore avviava nuovamente KDE.

## Modifiche

- Lo stop esamina le unità Plasma/portal una per una e salta quelle `not-found`; gli errori sulle unità installate restano registrati.
- Prima di avviare Gamescope il gate interroga `plasma-kwin_wayland.service` tramite `systemctl --user show`, attendendo `LoadState=loaded` e `ActiveState=inactive` o `failed`. Stato sconosciuto o ancora attivo mantiene il fallback sicuro su KDE.
- Il controllo avviene sia subito dopo il cleanup KDE, sia prima di qualsiasi avvio Gamescope, compreso quello selezionato dalla policy di boot.
- Gli override KWin sono tolti da systemd/D-Bus e non vengono passati a Gamescope, ma restano nel supervisore per il ritorno alla sessione KDE.
- `KWIN_FORCE_SW_CURSOR` resta predefinito a `0`; la modifica non abilita il workaround senza prova A/B hardware.

## Verifiche

- `tests/graphics-modules-tests.sh`: 42 superati, 0 falliti, inclusi switch KDE→Gamescope→KDE, unità portal opzionale assente, override KWin `1` presente nei due avvii Plasma e assente da Gamescope, e KWin attivo che blocca Gamescope.
- `bash -n` sui file shell modificati: superato.
- Non verificato su hardware reale in questo task: la prova visiva del passaggio e la conferma che non appaia schermo nero richiedono uno switch effettivo sulla PS5 collegata al display. I test mock non attestano il rilascio DRM né il primo frame visibile.

## Ambito

Nessun file, servizio o configurazione del modulo ventole è stato modificato o interrogato. Non è stato eseguito un push.
