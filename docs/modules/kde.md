# Modulo `kde`

Il modulo prepara KDE Plasma Wayland come sessione desktop e percorso di recupero per Gamescope. Non installa pacchetti: Plasma, D-Bus, Python 3, `kscreen-doctor`, `kdialog` o `notify-send` devono essere forniti dalla distribuzione.

## Configurazione

- Aggiunge l'utente `steam` ai gruppi `render`, `video`, `seat` e `input` soltanto se esistono e se l'utente non ne fa già parte. Registra solo le appartenenze aggiunte dal modulo; la rimozione toglie esclusivamente quelle.
- Installa `/etc/profile.d/ps5-kde-environment.sh`, che definisce i default KWin `KWIN_DRM_PREFER_COLOR_DEPTH=24`, `KWIN_DRM_NO_DIRECT_SCANOUT=1`, `KWIN_FORCE_ASSUME_HDR_SUPPORT=0` e `KWIN_FORCE_SW_CURSOR=0`, rispettando i valori già impostati. `KWIN_FORCE_SW_CURSOR=1` è un override diagnostico reversibile proposto per indagare gli errori AMDGPU `Unsupported screen format RA24` associati a fallimenti di atomic modeset; non è predefinito e resta opt-in finché un confronto A/B su hardware 16:9 non ne conferma l'efficacia. Il cursore software può aumentare il lavoro di compositing. Il supervisore Session conserva gli override tra i cambi sessione, li applica a KDE e li esclude dal processo Gamescope.
- Installa un avvio automatico KDE che legge le modalità KScreen e i timing dettagliati EDID dei monitor collegati. Quando KScreen omette una modalità dettagliata EDID compatibile con CVT reduced-blanking v1, prova ad aggiungerla con quel timing; poi applica la modalità con più pixel e, a parità di risoluzione, con refresh più alto. Le modalità CTA/TV già esposte da KScreen partecipano alla stessa scelta; i DTD interlacciati non vengono sintetizzati. Se KScreen non è disponibile, la configurazione resta invariata; se EDID non è leggibile, il modulo usa soltanto le modalità già esposte da KScreen.
- L'avvio automatico rispetta `PS5_KDE_AUTO_DISPLAY_MODE=0` per disattivare la selezione automatica. Il processo attende al massimo 10 secondi KScreen e usa un lock per evitare esecuzioni concorrenti.
- Installa `/usr/local/bin/ps5-cachyos-tools-desktop-notify` e un avvio automatico XDG per gli avvisi di fallback presenti in `~/.config/ps5-cachyos-tools/alert.txt`.
- Non cancella `kwinoutputconfig.json` né altre preferenze video dell'utente; la selezione automatica all'avvio KDE può cambiare la modalità attiva a quella migliore rilevata.

Il profilo KWin evita la richiesta di formati a 10 bit/HDR nella pipeline PS5 e disabilita il direct scanout per ridurre incompatibilità del percorso DRM/KMS. La selezione automatica agisce solo sulle modalità annunciate dall'EDID o già pubblicate da KScreen; un controllo software non può certificare la qualità del segnale HDMI o correggere un guasto del bridge/display.

## Lifecycle

Il manifest scoperto dal registry installa il modulo tramite `install.sh`; `check.sh` verifica gli artefatti, il task normal controlla che siano presenti e `remove.sh` ripristina le sole appartenenze ai gruppi aggiunte dal modulo. Configurazioni KWin personali restano fuori dall'ownership. In installazione selettiva, KDE non installa né avvia Session.

## Verifica

```bash
ps5-cachyos-tools check --live
grep -E '^(render|video|seat|input):' /etc/group
cat /etc/profile.d/ps5-kde-environment.sh
```

I test automatici verificano il parsing EDID, il fallback alle modalità KScreen, l'applicazione/rollback simulati e l'installazione/rimozione su rootfs fixture. La scelta effettiva della modalità e l'handshake EDID richiedono verifica su PS5 con monitor/TV collegato.
# Verifica sul kernel 7.2.3 (29 ottobre 2026)

La PS5 espone `DP-1` connesso e la sessione corrente ha `kwin_wayland` e `plasmashell` attivi; KScreen indica l'output abilitato. Il boot hook KDE e `check --live` sono riusciti. La sessione corrente precede l'installazione del supervisore, quindi il nuovo avvio automatico in KDE e il segnale HDMI dopo uno switch restano da verificare. Dettagli nel [report E2E](../e2e/2026-10-29-kernel-7.2.3-migration.md).
