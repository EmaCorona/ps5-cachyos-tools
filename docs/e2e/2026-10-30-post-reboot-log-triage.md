# Log dopo il riavvio e i passaggi KDE/Gamescope — 30 ottobre 2026

Sistema PS5 con kernel `7.2.3`, boot ID `90252007-f50f-4cba-85f5-ff92f843fe55`. Il repository esaminato è il branch `feature/ps5-linux-kernel-7.2.3-migration`. Le correzioni ai servizi di sistema sono locali a questa installazione; i servizi `grow-rootfs` e `ps5-stage-firmware` provengono dall'immagine PS5, non dal modulo Session.

## Errori corretti o mitigati

| Evidenza nei log | Diagnosi | Intervento | Verifica disponibile |
| --- | --- | --- | --- |
| Ciclo `sysinit.target` → `systemd-modules-load` → `ps5-stage-firmware` | Il servizio era voluto da `sysinit.target`, ma `DefaultDependencies=yes` lo ordinava dopo `basic.target`/`sysinit.target` | Drop-in `/etc/systemd/system/ps5-stage-firmware.service.d/10-early.conf` con `DefaultDependencies=no` | `systemd-analyze verify` non segnala più cicli; resta la verifica al prossimo boot |
| `grow-rootfs.service` fallito nei boot esaminati | `sfdisk` e `parted` non riconoscono una tabella standard su `/dev/nvme0n1`; la partizione root occupa quasi tutto il disco | Servizio disabilitato e stato failed azzerato; nessuna modifica manuale alla partizione | `systemctl is-enabled grow-rootfs.service` restituisce `disabled` |
| `systemd-networkd-wait-online` in timeout nel boot precedente | La rete è gestita da NetworkManager, mentre `networkctl` indica il link unmanaged | Disabilitato il waiter networkd e abilitato `NetworkManager-wait-online` | `nm-online -s -q -t 5` termina con codice 0 |
| `FAT-fs (sda2): Volume was not properly unmounted` | Bit dirty della partizione EFI | Immagine integrale di `/dev/sda2` salvata in `/var/backups/ps5-cachyos-tools/efi-sda2-before-fsck-20261030.img`; `fsck.fat -a` a volume smontato | Controllo successivo `fsck.fat -n` a volume smontato: codice 0; EFI rimontata |
| Discover non carica `libpackagekitqt6.so.2` | `packagekit-qt6` assente | Installato `packagekit-qt6` e dipendenze | `ldd` del plugin Discover risolve ora la libreria |
| `regulatory.db` assente | `wireless-regdb` assente | Installato `wireless-regdb` | `/usr/lib/firmware/regulatory.db` presente |
| `xdg-desktop-portal-gtk.service` esce con `Broken pipe` al ritorno da Gamescope | Il supervisore chiudeva il socket Wayland di Gamescope prima di fermare il portale; il nesso causale con l'errore è plausibile, da confermare | Il supervisore ora ferma i portali dopo il tentativo di chiusura ordinata di Steam ma prima di terminare Gamescope; revisione modulo Session `10` | Test di sequenza con mock e suite grafica: 59 superati, 0 falliti; verifica reale al prossimo switch |

## Problema display ancora da convalidare

Al boot iniziale KDE il kernel registra 444 `Unsupported screen format RA24` e KWin 89 `Modeset failed: Invalid argument`; il primo switch verso Gamescope avviene solo dopo questo intervallo. Al ritorno a KDE non compaiono nuovi RA24. Nei cinque boot esaminati RA24 compare in quattro: 426, 419, 389, 0 e 444 eventi. Il cursor plane espone `AR24` ma non `RA24`; un coinvolgimento del cursore hardware è plausibile, non dimostrato.

Il file locale `/etc/profile.d/ps5-kde-ra24-test.sh` imposta `KWIN_FORCE_SW_CURSOR=1` prima che `ps5-tty-session.sh` avvii il supervisore al prossimo login. Il default del modulo KDE nel repository resta `0`. L'efficacia richiede un nuovo avvio con controllo dell'immagine e dei log, idealmente ripetuto perché un boot con valore `0` era già riuscito. Per annullare la prova, rimuovere il file e riavviare la sessione.

## Errori che richiedono un altro livello di intervento

- `Unpatched return thunk in use` nasce durante il caricamento di `moal.ko` incluso in `linux-ps5`: il modulo richiama `__x86_return_thunk` ma non contiene `.return_sites`. Occorre ricostruire il driver nel progetto che produce il pacchetto kernel; disabilitare le mitigazioni o il Wi-Fi non è una correzione.
- Gli errori ACPI/SCI appartengono al percorso firmware/kernel PS5. Il primo `xhci_hcd ... -517` viene seguito da inizializzazione riuscita del controller Salina nello stesso avvio. I due avvisi SDMA non sono seguiti da reset GPU nei log esaminati.
- `hci1` segnala un timeout e il DualSense un timeout di service discovery; l'altro controller Bluetooth è alimentato. Non è dimostrato un guasto persistente del Bluetooth da correggere senza una prova funzionale.
- Gli avvisi XKB indicano esplicitamente che non sono fatali. Il portale GTK riparte dopo il fallimento; la verifica del nuovo ordine di arresto resta necessaria. `Steam is not running` compare alle 03:02:22, subito dopo l'avvio Gamescope: può essere una corsa con l'avvio di Steam, ma il log non identifica il chiamante né dimostra la causa.

Nessuna delle modifiche locali sopra elencate prova da sola che il prossimo boot sia pulito. Servono nuovi log dopo il riavvio e una prova visiva KDE/Gamescope/KDE.
