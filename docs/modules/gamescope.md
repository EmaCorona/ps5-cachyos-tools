# Modulo `gamescope`

Il modulo predispone Gamescope DRM e i tool di supporto. La sessione predefinita e il fallback sono responsabilità separate del modulo [`session`](session.md).

## Funzioni

- Installa `/usr/local/libexec/ps5-cachyos-tools/gamescope-session`: controlla i binari essenziali, il device DRM, rileva connettori e modalità da sysfs (priorità `DP-1` e `HDMI-A-1`), applica gli override e avvia Gamescope in backend DRM con Steam `-gamepadui -steamos`.
- Usa composizione forzata, layer disabilitati e impostazioni SDR/non-HDR per la pipeline AMDGPU/PS5. Rileva alcuni crash Steam (`SIGBUS`, `SIGSEGV`, `core dumped`) nei nuovi log della console e restituisce un codice d'errore al supervisore.
- Non considera l'assenza di rete un errore. Non esegue aggiornamenti o bootstrap Steam durante installazione o boot.
- Installa `ps5-cachyos-tools-video-diag` (lettura DRM, eventuale `modetest`, processi e log), `ps5-cachyos-tools-steam-verify-repair` (verifica dimensioni nei manifest `.installed`; invalida solo il marker corrotto per lasciare che Steam verifichi i contenuti) e `ps5-cachyos-tools-drm-setup` (sola lettura predefinita; `--apply` è esplicito e può modificare proprietà KMS runtime).
- Installa il profilo XDG portal Gamescope con `gtk` come portal predefinito.

## Configurazione

`/etc/ps5-cachyos-tools/gamescope.conf` viene creato soltanto se assente. Supporta `PS5_OUTPUT_WIDTH`, `PS5_OUTPUT_HEIGHT`, `PS5_NESTED_WIDTH`, `PS5_NESTED_HEIGHT`, `PS5_REFRESH_RATE` e `PS5_OUTPUT_CONN`. I valori sono validati e non vengono interpretati come codice shell; con le dimensioni non specificate si usa la modalità DRM rilevata, quindi 1920×1080 come fallback se il controllo è esplicitamente saltato.

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
