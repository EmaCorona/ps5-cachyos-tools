# Modulo `session`

Il modulo Session è l'unico orchestratore dell'avvio grafico automatico su TTY1. KDE e Gamescope restano responsabili dei rispettivi ambienti; Session dipende da entrambi, ma installare KDE o Gamescope da soli non attiva l'autologin grafico.

## Policy esclusiva di avvio

La scelta automatica al boot è definita esclusivamente dal file versionato `modules/session/files/session-policy`, installato come `/usr/local/libexec/ps5-cachyos-tools/session-policy`. La versione del repository seleziona `desktop` (KDE). Per passare a Gamescope, modificare l'output della policy in `gamescope` nel branch e reinstallare/aggiornare il modulo Session. Il supervisore accetta solo `desktop` o `gamescope`; se la policy manca o restituisce un valore invalido, registra l'errore e avvia KDE.

`DEFAULT_SESSION`, `NEXT_SESSION`, `~/.config/ps5-next-session` e ogni valore scritto da precedenti versioni di `steamos-session-select` sono legacy: non vengono consultati per decidere il boot. Il file `session.conf` può restare sul sistema per compatibilità con installazioni precedenti, ma non ha autorità sulla sessione automatica.

La policy repository controlla la sessione iniziale a ogni boot. Dopo l’avvio, il supervisore resta attivo e gestisce il cambio live tra KDE e Gamescope. `steamos-session-select [desktop|gamescope]`, `--default <session>` e `--once <session>` inviano una richiesta volatile al supervisore: avviano la transizione corrente, ma non scrivono `session.conf`, `DEFAULT_SESSION`, `NEXT_SESSION` o la policy. `--default` è mantenuto per compatibilità con i chiamanti legacy e non imposta il default del boot. Senza un supervisore attivo, il comando fallisce e non salva alcuna scelta. Il cambio della sessione predefinita al boot richiede sempre una modifica versionata alla policy e la distribuzione del modulo.

Il canale live usa una directory privata sotto `$XDG_RUNTIME_DIR/ps5-cachyos-tools`, un PID file e un file richiesta atomico; il supervisore controlla le richieste ogni 200 ms durante una sessione e durante il polling DRM quando attende Gamescope. Un lock impedisce due supervisori concorrenti. Le richieste non sopravvivono al riavvio e non possono prevalere sulla policy repository al boot. Il supervisore carica i parametri del profilo KDE e li importa nell'ambiente systemd/D-Bus della sessione KDE. Prima di avviare Gamescope rimuove questi parametri dagli ambienti condivisi e li filtra dal processo Gamescope, mantenendoli però nel supervisore per il successivo ritorno a KDE.

## Avvio e fallback

`/etc/profile.d/ps5-tty-session.sh` limita l'avvio automatico a una shell login su `/dev/tty1`; questa invoca il supervisore, che legge la sola policy repository. Il supervisore lancia KDE o Gamescope in un process group controllato, attende `/dev/dri/card0` e un connettore collegato con modalità stabile prima di avviare Gamescope e reagisce alle richieste live fermando la sessione attuale prima di avviare quella richiesta. Nel passaggio KDE→Gamescope confronta l’elenco `loginctl list-sessions` con la proprietà logind delle sessioni dell’utente e verifica che il login attivo sia l’unica sessione utente dello stesso UID; poi arresta i servizi Plasma tramite systemd senza `pkill` UID-wide. Se trova un’altra sessione utente o non può verificare un elenco coerente e completo, lascia KDE attivo e rifiuta lo switch. Dopo la richiesta di arresto, interroga `plasma-kwin_wayland.service` con il manager systemd utente e attende che KWin risulti caricato ma `inactive` o `failed`. Unità opzionali non installate (per esempio il portal KDE) vengono saltate, evitando che il loro stato `not-found` faccia fallire il comando aggregato di arresto. Se lo stato KWin è attivo o non verificabile entro il timeout di 10 s (`PS5_SESSION_SEAT_RELEASE_TIMEOUT_SEC`, 1–60), Gamescope non viene avviato e il supervisore ripristina KDE. Il controllo precedente su `loginctl seat-status` è stato rimosso: `[MASTER]` indica che il dispositivo è marcato `master-of-seat` per l'assegnazione del seat, non che un processo detenga il DRM master né che il servizio KWin sia attivo. Timeout DRM predefinito: 30 s; intervallo: 0,1 s (il tempo minimo con 3 campioni stabili è quindi ~0,2 s); campioni stabili: 3. Nel ritorno da Gamescope a KDE il supervisore chiede prima a `steam` (SIGTERM, fino a `PS5_SESSION_STEAM_SHUTDOWN_TIMEOUT_SEC`, default 4 s) di chiudersi in modo ordinato, così Steam non rileva uno shutdown sporco al lancio successivo; poi termina il process group. Le unità KDE vengono fermate con un unico comando systemd e il leader terminato viene raccolto subito, senza attese fisse. Sono configurabili `PS5_SESSION_DRM_READY_TIMEOUT_SEC` (1–600), `PS5_SESSION_DRM_POLL_INTERVAL_SEC` e `PS5_SESSION_DRM_STABLE_SAMPLES`. Durante l’attesa DRM una richiesta di passaggio a KDE viene rilevata al successivo controllo e avvia KDE senza attendere il timeout completo.

Se la policy seleziona Gamescope, timeout DRM, device assente, wrapper assente, exit non zero di Gamescope/Steam o crash Steam riconoscibile avviano KDE, scrivono `~/.gamescope-session.log` e `~/.gamescope-fallback.log` e creano un avviso desktop. Il fallback non cambia la policy; al boot seguente viene quindi ritentata la scelta versionata. La pulizia termina il process group Gamescope prima di lanciare Plasma.

Una terminazione normale di Gamescope (exit 0) avvia KDE senza segnalarla come errore. Lo shutdown non avvia una seconda sessione. Se KDE non è disponibile, il processo termina lasciando accessibile il login testuale TTY1.

Un errore visivo come colori separati o un handshake HDMI apparentemente pronto non è rilevabile in modo affidabile via shell: richiede diagnosi su display/PS5.

## Lifecycle e verifica

Il modulo installa il profilo login, il supervisore, la policy e il selettore compatibile per le richieste live. Il boot hook valida gli artefatti; non introduce un secondo manager grafico systemd. La vecchia configurazione viene mantenuta da reinstallazione e rimozione normale; la rimozione con `--purge-config` può eliminarla.

Le righe di log includono `boot_id`, `session_id` e `monotonic_ms`, così le richieste di cambio, il gate DRM e l'avvio del wrapper Gamescope si possono correlare nello stesso boot e nella stessa sessione. Il clock monotono deriva da `/proc/uptime` e ha risoluzione di 10 ms. La readiness del compositor e il primo frame visibile della UI Steam non sono dedotti dalla sola esistenza dei processi; per misurare il frame serve una registrazione video timestampata.

```bash
cat /usr/local/libexec/ps5-cachyos-tools/session-policy
tail -n 100 /home/steam/.gamescope-session.log
tail -n 100 /home/steam/.gamescope-fallback.log
```

I test mock verificano che `DEFAULT_SESSION` e `NEXT_SESSION` non prevalgano sulla policy e coprono il cambio live KDE→Gamescope→KDE, il rifiuto senza supervisore, la presenza di KWin, l'assenza di unità portal opzionali, la conservazione degli override KWin e i fallback. La conferma di Plasma/Gamescope, DRM, HDMI e comportamento al reboot richiede una prova sul sistema PS5; i test mock non dimostrano il boot hardware.
# Verifica sul kernel 7.2.3 (29 ottobre 2026)

La policy installata restituisce `desktop`; il boot hook, `reapply` e `check --live` passano. Rimozione e reinstallazione ripristinano e conservano gli originali dello script TTY e del selettore. Il supervisore non è ancora in esecuzione nella sessione aperta prima dell'installazione: switch, fallback reale, timeout e primo avvio Steam sono non verificati. Si veda il [report E2E](../e2e/2026-10-29-kernel-7.2.3-migration.md).
