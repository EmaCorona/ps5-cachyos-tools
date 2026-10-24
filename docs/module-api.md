# Module API

Ogni modulo installabile ha una directory `modules/<id>/` con `module.conf` e hook opzionali `install.sh`, `boot.sh`, `check.sh`, `remove.sh`, `readiness.sh`. Il manifest usa chiavi allowlistate (`ID`, `NAME`, `ENABLED`, `TYPE`, `RUN_POLICY`, `BOOT_PHASE`, `REVISION`, `DEPENDENCIES`, `SERVICE_UNIT`, `FAILURE_POLICY`, `REQUIRES_BOOT`, `OWNED_PATHS`, `READINESS_HOOK`, `INSTALL_WHEN_DISABLED`). `OWNED_PATHS` dichiara i percorsi assoluti posseduti dal modulo e consente al framework di includerli nello snapshot e nel rollback.

`install.sh ROOT` prepara una rootfs idempotente. `boot.sh ROOT PHASE` è riservato ai moduli `TYPE=task`; il suo exit code determina `SUCCESS` o `FAILED`. I servizi permanenti sono dichiarati `TYPE=service`, `RUN_POLICY=always` e avviati da una unit systemd propria. Gli hook assenti sono validi quando non richiesti dal tipo.

Il parser rifiuta chiavi sconosciute, duplicati, ID non validi, dipendenze sconosciute, cicli e combinazioni `TYPE`/`BOOT_PHASE` non eseguibili: i task usano `early` o `normal`, i service usano esclusivamente `service`. Le unit service devono essere univoche, non riservate al core e dichiarate anche in `OWNED_PATHS` come `/etc/systemd/system/<unit>`. Gli hook ricevono anche `CORE_INSTALL_MODE`, `CORE_TARGET_ROOT`, `CORE_BOOT_TARGET`, `CORE_MODULE_ID` e `CORE_DRY_RUN`; queste variabili costituiscono il contesto standard e non devono essere recuperate dalla directory corrente. Gli override amministrativi allowlistati (`ENABLED`, `RUN_POLICY`) si trovano in `/etc/ps5-cachyos-tools/modules.d/<id>.conf` e non vengono interpretati con `source` o `eval`.

Un hook di installazione deve restituire zero solo dopo aver completato tutte le modifiche dichiarate. Gli errori interrompono la transazione; gli artefatti recuperabili devono essere elencati in `OWNED_PATHS`. Le configurazioni utente non elencate restano preservate durante gli aggiornamenti. In un'installazione selettiva il preflight e l'apply usano lo stesso ordine topologico; le dipendenze già valide vengono mantenute senza rieseguire il loro hook.

`OWNED_PATHS` deve contenere artefatti esatti (file o symlink) sotto il target; non può indicare `/`, directory di sistema, directory del framework o percorsi sovrapposti ad altri moduli. I symlink finali sono rifiutati salvo i wants-link systemd con destinazione testuale esatta; un symlink in un antenato viene sempre rifiutato.

`reapply ID --live` invoca soltanto l'hook del modulo richiesto nella sua fase, oppure il lifecycle systemd per un service. `reapply ID --root ROOT` registra una richiesta in `var/lib/ps5-cachyos-tools/state/reapply/` per i task e non esegue hook runtime sul PC; la richiesta viene consumata dal runner al boot successivo. Lo stato persistente segue `REQUESTED → RUNNING → APPLIED → COMPLETED`: se il runner viene interrotto dopo `APPLIED`, riconcilia la richiesta senza rieseguire l'hook; se viene interrotto durante l'hook, la request resta pendente e il retry successivo è esplicito nel journal/stato. Per un service offline il comando rifiuta esplicitamente la richiesta, perché il runner non consuma reapply di servizi.

In modalità offline `--root` e `--boot` possono riferirsi a mount separati. Entrambi devono essere directory assolute, esistenti, non symlink e diverse da `/`; il controllo del mountpoint è obbligatorio fuori dai fixture di test. Gli hook fan applicano lo stesso controllo a directory, configurazioni, manifest e profili prima di scrivere. I servizi dichiarati dal manifest vengono copiati nel target e abilitati soltanto quando `ENABLED=true`, senza chiamare `systemctl` sull'host.

La modalità `--live` richiede root e un segnale PS5 riconoscibile da `/sys` o dai metadati di piattaforma. Su un ambiente non riconosciuto deve essere usato `--root` oppure l'override esplicito `PS5_TOOLS_ALLOW_LIVE=1`.

Per un modulo `service`, la rimozione salva prima gli artefatti e lo stato operativo, arresta e disabilita la unit in modalità live, esegue l'hook e ripristina file e stato systemd se un passaggio fallisce. Una unit può provenire da `systemd/<unit>` oppure dal runtime `usr/lib/ps5-cachyos-tools/systemd/<unit>`; preflight e installazione usano lo stesso resolver. `remove` conserva le configurazioni per default (`--keep-config`); `--purge-config` passa al modulo l'autorizzazione esplicita a rimuoverle.

## Readiness dei service

Un modulo `service` può dichiarare `READINESS_HOOK=readiness.sh`. Il framework esegue l'hook dopo `systemctl is-active` nelle installazioni e nei `reapply` live; l'hook deve restituire zero soltanto quando il servizio è applicativamente pronto. In offline il controllo non viene falsamente dichiarato: la verifica resta demandata al boot/live target.

Un modulo disabilitato esegue l'hook di installazione soltanto se dichiara esplicitamente `INSTALL_WHEN_DISABLED=true`; questo contratto serve agli adapter che devono predisporre artefatti senza prendere decisioni sul lifecycle del servizio.
