# Modulo `gamescope`

Il modulo predispone Gamescope DRM e i tool di supporto. La sessione predefinita e il fallback sono responsabilità separate del modulo [`session`](session.md).

## Funzioni

- Installa `/usr/local/libexec/ps5-cachyos-tools/gamescope-session`: controlla i binari essenziali e il device DRM, registra un candidato diagnostico tra i modi KMS (`modetest`) privilegiando quello marcato nativo/preferred e, in assenza del flag, la maggiore risoluzione con refresh più alto. Nel percorso automatico non passa dimensioni, refresh o connettore fissati all'avvio: il backend DRM di Gamescope seleziona il modo KMS preferito e gestisce gli eventi di hotplug. Avvia Steam con `-gamepadui -steamos`.
- Usa composizione forzata, layer disabilitati e impostazioni SDR/non-HDR per la pipeline AMDGPU/PS5. Rileva alcuni crash Steam (`SIGBUS`, `SIGSEGV`, `core dumped`) nei nuovi log della console e restituisce un codice d'errore al supervisore.
- Non considera l'assenza di rete un errore. Non esegue aggiornamenti o bootstrap Steam durante installazione o boot.
- Installa `ps5-cachyos-tools-video-diag` (lettura DRM, eventuale `modetest`, processi e log), `ps5-cachyos-tools-steam-verify-repair` (verifica in-process le dimensioni nei manifest `.installed`, senza un processo `stat` per voce; invalida solo il marker con una discrepanza confermata, lasciando a Steam la verifica dei contenuti) e `ps5-cachyos-tools-drm-setup` (sola lettura predefinita; `--apply` è esplicito e può modificare proprietà KMS runtime).
- Installa il profilo XDG portal Gamescope con `gtk` come portal predefinito.

## Configurazione

`/etc/ps5-cachyos-tools/gamescope.conf` viene creato soltanto se assente. Supporta gli override facoltativi `PS5_OUTPUT_WIDTH` e `PS5_OUTPUT_HEIGHT` (da impostare insieme), `PS5_NESTED_WIDTH` e `PS5_NESTED_HEIGHT` (da impostare insieme), `PS5_REFRESH_RATE` e `PS5_OUTPUT_CONN`. In assenza di override il wrapper lascia modalità, rapporto d'aspetto, frequenza e scelta del connettore al backend DRM di Gamescope, così gli eventi di hotplug possono essere gestiti dal backend senza mantenere le preferenze dimensionali iniziali. Il detector KMS resta diagnostico: usa soltanto modalità esposte dal kernel, privilegia il modo indicato come preferred, e non prova a forzare timing presenti solo nell'EDID ma rifiutati dal DRM/KMS. Un connettore esplicito non disponibile causa un errore chiaro. I valori sono validati e non vengono interpretati come codice shell.

La presenza di un timing nell’EDID non dimostra che il driver possa impostarlo. La patch downstream in [`packaging/gamescope`](../../packaging/gamescope/README.md) consente al Gamescope integrato di provare tutti i DTD progressivi digitali con atomic `TEST_ONLY`, mantenendo il fallback sulle modalità KMS disponibili. Il PKGBUILD applica la patch con `-p0`, coerente con gli header che riportano percorsi completi dalla radice del sorgente, e installa il binario da `build/src/gamescope`, la directory creata da Meson. Dopo la build, il helper seleziona l’archivio con il nome esatto nei metadati pacman e ignora il pacchetto debug. In installazione live oppure offline su Arch/CachyOS x86_64, il modulo costruisce e installa automaticamente `ps5-cachyos-gamescope` con pacman. Il preflight richiede `makepkg`; il helper assicura temporaneamente il meta-pacchetto `base-devel` (che include gli strumenti standard come `debugedit`, `fakeroot`, `patch` e `pkgconf`) e le `makedepends` dichiarate nel PKGBUILD. Registra e rimuove al termine solo i pacchetti non presenti prima della build. Il binario patchato e gli script restano in percorsi privati del progetto e la sessione li seleziona esplicitamente; non viene sovrascritto `/usr/bin/gamescope`. `check` verifica che il pacchetto downstream sia installato e che il binario, gli script e il commit atteso siano presenti. Un aggiornamento upstream richiede l’aggiornamento verificato del pin e della patch; la build rimane invece disponibile attraverso una normale installazione del repository. La modalità di sessione continua a derivare dimensioni, formato e refresh dal display e dal driver. Per confrontare EDID e modalità effettive usare `ps5-cachyos-tools-video-diag` e `modetest -M amdgpu -c`; confermare sempre i modeset dai log del kernel e di KWin/Gamescope.

La verifica dei manifesti usa `/usr/bin/python3` e la sola libreria standard: l'installer rifiuta il modulo se il runtime manca e `check` lo verifica anche nei target offline. Il controllo resta sincrono a ogni avvio. Solo `ENOENT` confermato o una dimensione letta e diversa possono invalidare il marker; errori di permesso/I/O producono un warning, conservano i marker e restituiscono un codice diagnostico non-zero. Il wrapper registra in modalità fail-open il risultato e continua ad avviare Gamescope.

I log di sessione e wrapper includono `boot_id`, `session_id` e `monotonic_ms`; il clock deriva da `/proc/uptime` e ha risoluzione di 10 ms. Il wrapper registra inizio/fine del controllo e durata dell'esecuzione di Gamescope. Questi eventi misurano il tempo fino all'avvio/uscita del processo Gamescope, non il primo frame della UI Steam. Per misurare UI-ready serve acquisizione video timestampata; non viene inferita dal solo processo o socket.

Il modulo non assegna capability al binario `gamescope` né installa un servizio DRM early-boot. In questo modo non modifica capability di pacchetti preesistenti e non esegue `proptest` mentre il kernel inizializza KMS. Per consultare proprietà: `sudo ps5-drm-setup --check`; `--apply` va usato solo dopo aver esaminato l'output.

## Lifecycle e diagnosi

Manifest, `install.sh`, `check.sh`, `boot.sh` e `remove.sh` sono gestiti dal framework. La configurazione viene preservata da reinstallazione e rimozione predefinita; `--purge-config` la elimina. La rimozione disinstalla soltanto `ps5-cachyos-gamescope`; lascia il pacchetto Gamescope ufficiale, Steam e i dati Steam intatti. Mantiene l’archivio downstream in cache sotto `/var/lib/ps5-cachyos-tools/gamescope/packages` per poter compensare un rollback della rimozione.

```bash
/usr/local/bin/ps5-cachyos-tools-video-diag
/usr/local/bin/ps5-cachyos-tools-steam-verify-repair /home/steam/.local/share/Steam
journalctl -b --no-pager | grep -Ei 'gamescope|drm|amdgpu|steam'
tail -n 100 /home/steam/.gamescope.log
```

I test automatici simulano sysfs, modalità preferred, rapporti d'aspetto, validazione config e codici di errore. Non verificano acquisizione reale del master DRM, eventi fisici hotplug, modeset, colori, handshake del collegamento, performance o disponibilità delle opzioni Gamescope della build installata: questi aspetti richiedono PS5 e display reali.
