# Modulo `gamescope`

Il modulo predispone Gamescope DRM e i tool di supporto. La sessione predefinita e il fallback sono responsabilità separate del modulo [`session`](session.md).

## Funzioni

- Installa `/usr/local/libexec/ps5-cachyos-tools/gamescope-session`: controlla i binari essenziali e il device DRM, sceglie la risoluzione DRM più ampia connessa e la frequenza dai modi effettivamente enumerati da KMS (`modetest`), applica gli override e avvia Gamescope in backend DRM con Steam `-gamepadui -steamos`. Se `modetest` non è disponibile, conserva la risoluzione DRM e usa 60 Hz come fallback prudente.
- Usa composizione forzata, layer disabilitati e impostazioni SDR/non-HDR per la pipeline AMDGPU/PS5. Rileva alcuni crash Steam (`SIGBUS`, `SIGSEGV`, `core dumped`) nei nuovi log della console e restituisce un codice d'errore al supervisore.
- Non considera l'assenza di rete un errore. Non esegue aggiornamenti o bootstrap Steam durante installazione o boot.
- Installa `ps5-cachyos-tools-video-diag` (lettura DRM, eventuale `modetest`, processi e log), `ps5-cachyos-tools-steam-verify-repair` (verifica in-process le dimensioni nei manifest `.installed`, senza un processo `stat` per voce; invalida solo il marker con una discrepanza confermata, lasciando a Steam la verifica dei contenuti) e `ps5-cachyos-tools-drm-setup` (sola lettura predefinita; `--apply` è esplicito e può modificare proprietà KMS runtime).
- Installa il profilo XDG portal Gamescope con `gtk` come portal predefinito.

## Configurazione

`/etc/ps5-cachyos-tools/gamescope.conf` viene creato soltanto se assente. Supporta `PS5_OUTPUT_WIDTH`, `PS5_OUTPUT_HEIGHT`, `PS5_NESTED_WIDTH`, `PS5_NESTED_HEIGHT`, `PS5_REFRESH_RATE` e `PS5_OUTPUT_CONN`. Se omessi, dimensioni e frequenza vengono rilevate tramite i modi effettivamente esposti dal kernel DRM; il valore `-r` limita il refresh annidato e, nel backend DRM Gamescope upstream, è passato anche come refresh preferito d'uscita e usato per cercare il timing corrispondente. Il rilevamento resta allineato al connettore configurato; un connettore esplicito non disponibile causa un errore chiaro. I valori sono validati e non vengono interpretati come codice shell; 1920×1080@60 è il fallback solo se il controllo DRM viene esplicitamente saltato.

La verifica dei manifesti usa `/usr/bin/python3` e la sola libreria standard: l'installer rifiuta il modulo se il runtime manca e `check` lo verifica anche nei target offline. Il controllo resta sincrono a ogni avvio. Solo `ENOENT` confermato o una dimensione letta e diversa possono invalidare il marker; errori di permesso/I/O producono un warning, conservano i marker e restituiscono un codice diagnostico non-zero. Il wrapper registra in modalità fail-open il risultato e continua ad avviare Gamescope.

I log di sessione e wrapper includono `boot_id`, `session_id` e `monotonic_ms`; il clock deriva da `/proc/uptime` e ha risoluzione di 10 ms. Il wrapper registra inizio/fine del controllo e durata dell'esecuzione di Gamescope. Questi eventi misurano il tempo fino all'avvio/uscita del processo Gamescope, non il primo frame della UI Steam. Per misurare UI-ready serve acquisizione video timestampata; non viene inferita dal solo processo o socket.

Il modulo non assegna capability al binario `gamescope` né installa un servizio DRM early-boot. In questo modo non modifica capability di pacchetti preesistenti e non esegue `proptest` mentre il kernel inizializza KMS. Per consultare proprietà: `sudo ps5-drm-setup --check`; `--apply` va usato solo dopo aver esaminato l'output.

## Lifecycle e diagnosi

Manifest, `install.sh`, `check.sh`, `boot.sh` e `remove.sh` sono gestiti dal framework. La configurazione viene preservata da reinstallazione e rimozione predefinita; `--purge-config` la elimina. La rimozione non tocca pacchetti Gamescope/Steam né dati Steam.

```bash
/usr/local/bin/ps5-cachyos-tools-video-diag
/usr/local/bin/ps5-cachyos-tools-steam-verify-repair /home/steam/.local/share/Steam
journalctl -b --no-pager | grep -Ei 'gamescope|drm|amdgpu|steam'
tail -n 100 /home/steam/.gamescope.log
```

I test automatici simulano sysfs, modalità, validazione config e codici di errore. Non verificano acquisizione reale del master DRM, colori, EDID, handshake HDMI, performance o disponibilità delle opzioni Gamescope della build installata: questi aspetti richiedono PS5 e display reali.
