# Architettura modulare

Il framework installa core, manifest e hook nella rootfs target sotto `/usr/lib/ps5-cachyos-tools/`. La discovery legge esclusivamente manifest INI allowlistati: non usa `source`, `eval` o una lista `ALL_MODULES`.

L'installazione, il task di boot e il servizio persistente sono responsabilità distinte. `ps5-tools-early.service` e `ps5-tools-boot.service` invocano il runner per le fasi `early` e `normal`; `ps5-fan-daemon.service` resta una unit `Type=simple` autonoma del modulo fan.

In modalità offline `--root` deve essere una rootfs Linux già montata e diversa da `/`; il core copia file e symlink soltanto nel target e non invoca systemd sull'host. In modalità live è richiesto `--live` e root amministrativa: `/` è un target valido e i percorsi vengono normalizzati senza il doppio slash, mantenendo i controlli sui symlink e sui confini della root offline.

Lo state store usa file atomici sotto `/var/lib/ps5-cachyos-tools/state/modules/<id>.state`. I task `once` vengono marcati `SUCCESS` solo dopo exit 0; i task `always` non usano un marker di completamento per sostituire l'esecuzione per boot. Una dipendenza `once` è soddisfatta dal completamento persistente della stessa revisione, anche se l'ultimo evento è `SKIPPED_DISABLED`; una dipendenza `always` richiede invece il successo nel boot corrente. Le richieste di reapply sono consumate dopo il commit del risultato e vengono ricreate se la riconciliazione fallisce.

Installazione, remove, reset, reapply e boot runner condividono il mutex `/run/ps5-cachyos-tools/transaction.lock` per target e non sovrappongono transazioni. Le installazioni selettive applicano le dipendenze in ordine topologico; una dipendenza già installata con manifest e artefatti validi non viene rieseguita inutilmente. Per le transazioni live lo snapshot include, per ogni unit interessata, presenza, enabled e active, così il rollback può ripristinare gli stati originali.

Un modulo `TYPE=service` con `ENABLED=false` installa la unit ma non crea il wants link né la avvia. `reapply` offline dei service è rifiutato perché non esiste un consumer deferred dedicato; `reapply` live usa il lifecycle systemd. La rimozione generica conserva le configurazioni utente per default; `--purge-config` abilita esplicitamente la loro eliminazione.
