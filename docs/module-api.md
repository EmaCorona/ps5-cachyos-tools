# Module API

Ogni modulo installabile ha una directory `modules/<id>/` con `module.conf` e hook opzionali `install.sh`, `boot.sh`, `check.sh`, `remove.sh`. Il manifest usa chiavi allowlistate (`ID`, `NAME`, `ENABLED`, `TYPE`, `RUN_POLICY`, `BOOT_PHASE`, `REVISION`, `DEPENDENCIES`, `SERVICE_UNIT`, `FAILURE_POLICY`).

`install.sh ROOT` prepara una rootfs idempotente. `boot.sh ROOT PHASE` è riservato ai moduli `TYPE=task`; il suo exit code determina `SUCCESS` o `FAILED`. I servizi permanenti sono dichiarati `TYPE=service`, `RUN_POLICY=always` e avviati da una unit systemd propria. Gli hook assenti sono validi quando non richiesti dal tipo.

Il parser rifiuta chiavi sconosciute, duplicati, ID non validi, dipendenze sconosciute, cicli e combinazioni servizio/`once`. Le configurazioni amministrative e le override saranno aggiunte in un passaggio successivo con allowlist separata.
