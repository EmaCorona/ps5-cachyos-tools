# Hardening finale del framework modulare

## Problema

La prima implementazione del framework non distingueva sempre gli antenati di un percorso dall'artefatto finale. Questo rendeva fragile l'upgrade di symlink systemd validi e lasciava incompleta la gestione di `OWNED_PATHS`, del reapply offline, degli update idempotenti e dei moduli selettivi.

## Correzione applicata

- validazione separata di root, mount boot, antenati e artefatti finali;
- symlink finali gestiti salvati e ripristinati senza seguirne il target, mentre i symlink negli antenati restano vietati;
- rifiuto di radici, directory di sistema, directory del framework e ownership sovrapposte nei manifest;
- supporto a rootfs e boot montati in directory separate;
- reapply offline registrato come richiesta persistente, senza eseguire `boot.sh` sul PC;
- reapply live limitato al modulo richiesto;
- copie idempotenti per la CLI installata e per le unit systemd, con conflitti estranei rifiutati;
- installazione selettiva senza copiare automaticamente gli artefatti fan;
- rimozione generica di artefatti e stato del modulo;
- snapshot e ripristino dello stato `active`/`enabled` dei servizi durante `remove`;
- resolver condiviso per unit dichiarate nel repository e nel runtime installato;
- conservazione del backup quando il rollback filesystem è parziale.

## Verifica e limiti

Eseguiti direttamente: `bash -n`, suite core e suite fan legacy. La validazione hardware PS5 e la CI remota richiedono ancora l'ambiente esterno. Il lifecycle live completo di un servizio generico deve essere verificato con un modulo service fittizio e systemd disponibile.

## File principali

`lib/core/target.sh`, `lib/core/registry.sh`, `lib/core/installer.sh`, `lib/core/service.sh`, `lib/core/boot-runner.sh`, `lib/core/dependencies.sh`, `bin/ps5-cachyos-tools` e `lib/modules/fan.sh`.
