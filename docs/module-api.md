# Module API

Ogni modulo installabile ha una directory `modules/<id>/` con `module.conf` e hook opzionali `install.sh`, `boot.sh`, `check.sh`, `remove.sh`. Il manifest usa chiavi allowlistate (`ID`, `NAME`, `ENABLED`, `TYPE`, `RUN_POLICY`, `BOOT_PHASE`, `REVISION`, `DEPENDENCIES`, `SERVICE_UNIT`, `FAILURE_POLICY`, `REQUIRES_BOOT`, `OWNED_PATHS`). `OWNED_PATHS` dichiara i percorsi assoluti posseduti dal modulo e consente al framework di includerli nello snapshot e nel rollback.

`install.sh ROOT` prepara una rootfs idempotente. `boot.sh ROOT PHASE` è riservato ai moduli `TYPE=task`; il suo exit code determina `SUCCESS` o `FAILED`. I servizi permanenti sono dichiarati `TYPE=service`, `RUN_POLICY=always` e avviati da una unit systemd propria. Gli hook assenti sono validi quando non richiesti dal tipo.

Il parser rifiuta chiavi sconosciute, duplicati, ID non validi, dipendenze sconosciute, cicli e combinazioni servizio/`once`. Gli hook ricevono anche `CORE_INSTALL_MODE`, `CORE_TARGET_ROOT`, `CORE_BOOT_TARGET`, `CORE_MODULE_ID` e `CORE_DRY_RUN`; queste variabili costituiscono il contesto standard e non devono essere recuperate dalla directory corrente. Gli override amministrativi allowlistati (`ENABLED`, `RUN_POLICY`) si trovano in `/etc/ps5-cachyos-tools/modules.d/<id>.conf` e non vengono interpretati con `source` o `eval`.

Un hook di installazione deve restituire zero solo dopo aver completato tutte le modifiche dichiarate. Gli errori interrompono la transazione; gli artefatti recuperabili devono essere elencati in `OWNED_PATHS`. Le configurazioni utente non elencate restano preservate durante gli aggiornamenti.

`OWNED_PATHS` deve contenere artefatti esatti (file o symlink) sotto il target; non può indicare `/`, directory di sistema, directory del framework o percorsi sovrapposti ad altri moduli. Il symlink finale è accettato soltanto se la sua destinazione rimane nel target; un symlink in un antenato viene sempre rifiutato.

`reapply ID --live` invoca soltanto l'hook del modulo richiesto nella sua fase. `reapply ID --root ROOT` registra una richiesta in `var/lib/ps5-cachyos-tools/state/reapply/` e non esegue hook runtime sul PC; la richiesta viene consumata dal runner al boot successivo.

In modalità offline `--root` e `--boot` possono riferirsi a mount separati. Entrambi devono essere directory assolute, esistenti, non symlink e diverse da `/`. I servizi dichiarati dal manifest vengono copiati e abilitati nel target senza chiamare `systemctl` sull'host.
