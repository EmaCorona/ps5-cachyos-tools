# Modulo `kde`

Il modulo prepara KDE Plasma Wayland come sessione desktop e percorso di recupero per Gamescope. Non installa pacchetti: Plasma, D-Bus, `kdialog` o `notify-send` devono essere forniti dalla distribuzione.

## Configurazione

- Aggiunge l'utente `steam` ai gruppi `render`, `video`, `seat` e `input` soltanto se esistono e se l'utente non ne fa già parte. Registra solo le appartenenze aggiunte dal modulo; la rimozione toglie esclusivamente quelle.
- Installa `/etc/profile.d/ps5-kde-environment.sh`, che fornisce i default KWin `KWIN_DRM_PREFER_COLOR_DEPTH=24`, `KWIN_DRM_NO_DIRECT_SCANOUT=1` e `KWIN_FORCE_ASSUME_HDR_SUPPORT=0` senza sovrascrivere valori già impostati.
- Installa `/usr/local/bin/ps5-cachyos-tools-desktop-notify` e un avvio automatico XDG per gli avvisi di fallback presenti in `~/.config/ps5-cachyos-tools/alert.txt`.
- Non cancella `kwinoutputconfig.json` né altre preferenze video dell'utente.

Il profilo KWin evita la richiesta di formati a 10 bit/HDR nella pipeline PS5 e disabilita il direct scanout per ridurre incompatibilità del percorso DRM/KMS. Un controllo software non può certificare la qualità del segnale HDMI o correggere un guasto del bridge/display.

## Lifecycle

Il manifest scoperto dal registry installa il modulo tramite `install.sh`; `check.sh` verifica gli artefatti, il task normal controlla che siano presenti e `remove.sh` ripristina le sole appartenenze ai gruppi aggiunte dal modulo. Configurazioni KWin personali restano fuori dall'ownership. In installazione selettiva, KDE non installa né avvia Session.

## Verifica

```bash
ps5-cachyos-tools check --live
grep -E '^(render|video|seat|input):' /etc/group
cat /etc/profile.d/ps5-kde-environment.sh
```

I test automatici verificano aggiunta idempotente e rimozione selettiva dei gruppi su rootfs di fixture. Avvio Plasma e output video richiedono verifica su PS5.
