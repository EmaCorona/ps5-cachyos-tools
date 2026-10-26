# Modulo `session`

Il modulo Session è l'unico orchestratore dell'avvio grafico automatico su TTY1. KDE e Gamescope restano responsabili dei rispettivi ambienti. Session dipende da entrambi nel manifest, ma l'installazione selettiva di KDE o Gamescope non attiva l'autologin grafico.

## Preferenza e comandi

Il file unico `/home/steam/.config/ps5-cachyos-tools/session.conf` contiene `DEFAULT_SESSION` e `NEXT_SESSION`. Alla prima installazione la sessione predefinita è Gamescope. Il file è preservato da reinstallazione e rimozione normale.

```bash
# Cambio permanente e transizione alla sessione richiesta
steamos-session-select gamescope
steamos-session-select desktop

# Cambia solo la prossima sessione; poi torna al default persistente
steamos-session-select --once desktop
steamos-session-select --once gamescope

# Alias esplicito del cambio permanente
steamos-session-select --default desktop
```

Sono mantenuti gli alias legacy `plasma` e `gamescope-wayland`. Senza argomenti il comando continua a selezionare `desktop`. Le richieste sono scritte atomicamente; input non riconosciuti vengono rifiutati. KDE→Gamescope termina l'attuale sessione Plasma e si affida al normale login automatico TTY1 della distribuzione; Gamescope→KDE termina il compositor e il supervisore avvia Plasma nello stesso ciclo, senza reboot.

## Avvio e fallback

`/etc/profile.d/ps5-tty-session.sh` limita l'avvio automatico a una shell login su `/dev/tty1`. Il supervisore consuma l'override one-shot, attende `/dev/dri/card0` e un connettore collegato con modalità stabile, poi avvia `gamescope-session-ps5`. Timeout predefinito DRM: 30 s; intervallo: 1 s; campioni stabili: 3. I parametri sono configurabili tramite `PS5_SESSION_DRM_READY_TIMEOUT_SEC` (1–600), `PS5_SESSION_DRM_POLL_INTERVAL_SEC` e `PS5_SESSION_DRM_STABLE_SAMPLES`.

Timeout o device DRM assente, wrapper assente, exit non zero di Gamescope/Steam o crash Steam riconoscibile avviano KDE, scrivono `~/.gamescope-session.log` e `~/.gamescope-fallback.log` e creano un avviso desktop. La pulizia termina il process group Gamescope prima di lanciare Plasma. La preferenza persistente non viene cambiata dal fallback; dopo un errore il successivo avvio ritenta quindi la preferenza Gamescope e l'utente può cambiarla con `steamos-session-select desktop`.

Una terminazione volontaria/normalmente riuscita (exit 0), lo switch esplicito a KDE e lo shutdown non sono registrati come errori. All'uscita normale il supervisore apre KDE senza modificare il default. Non c'è un ciclo interno di reboot o retry Gamescope. Se KDE non è disponibile, il processo termina lasciando il login testuale TTY1 accessibile.

Un errore visivo come colori separati o un handshake HDMI che appare con output software apparentemente pronto non è rilevabile in modo affidabile via shell: richiede diagnosi sul display/PS5 e resta fuori dal trigger automatico.

## Lifecycle e verifica

Il modulo installa il profilo login, il selettore e il supervisore tramite hook del framework. Il boot hook normale valida gli artefatti; non avvia un secondo manager grafico systemd e non sostituisce l'autologin TTY1 della distro. La configurazione sessione viene mantenuta da `remove` e cancellata solo con `--purge-config`.

```bash
cat /home/steam/.config/ps5-cachyos-tools/session.conf
tail -n 100 /home/steam/.gamescope-session.log
tail -n 100 /home/steam/.gamescope-fallback.log
steamos-session-select --once desktop
```

I test simulati verificano selezione, persistenza, timeout, avvio nominale, fallback e switch tramite config. Avvio reale Plasma/Gamescope, acquisizione DRM, segnale HDMI e affidabilità su reboot devono essere provati su PS5; non sono deducibili dai test mock.
