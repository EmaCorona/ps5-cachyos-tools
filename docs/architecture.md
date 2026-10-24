# Architettura modulare

Il framework installa core, manifest e hook nella rootfs target sotto `/usr/lib/ps5-cachyos-tools/`. La discovery legge esclusivamente manifest INI allowlistati: non usa `source`, `eval` o una lista `ALL_MODULES`.

L'installazione, il task di boot e il servizio persistente sono responsabilità distinte. `ps5-tools-early.service` e `ps5-tools-boot.service` invocano il runner per le fasi `early` e `normal`; `ps5-fan-daemon.service` resta una unit `Type=simple` autonoma del modulo fan.

In modalità offline `--root` deve essere una rootfs Linux già montata e diversa da `/`; il core copia file e symlink soltanto nel target e non invoca systemd sull'host. In modalità live è richiesto `--live` e root amministrativa.

Lo state store usa file atomici sotto `/var/lib/ps5-cachyos-tools/state/modules/<id>.state`. I task `once` vengono marcati `SUCCESS` solo dopo exit 0; i task `always` non usano un marker di completamento per sostituire l'esecuzione per boot. I lock del runner sono in `/run/ps5-cachyos-tools`.
