# VRAM

Il modulo `vram` configura il valore letto dal `ps5-linux-loader` prima dell'avvio di Linux. Scrive il numero esadecimale di byte nella radice della partizione FAT32 di boot, nel file `vram.txt`; il file è quindi un input del loader e la modifica ha effetto al successivo avvio Linux.

Per l'installazione live, indica esplicitamente il mountpoint FAT32. Il default del modulo è 4 GiB (`0x100000000`); i valori impostabili durante `install` sono `512MiB` e da `1GiB` a `8GiB` a passi di un GiB. Il valore loader standard `512MiB` (`0x20000000`) resta selezionabile e abilita l'allocazione dinamica secondo la documentazione del loader.

```bash
sudo ps5-cachyos-tools install --live --module vram --boot /boot/efi --vram-size 4GiB --dry-run
sudo ps5-cachyos-tools install --live --module vram --boot /boot/efi --vram-size 4GiB
```

Adatta `/boot/efi` al mountpoint reale della partizione FAT32: il framework richiede un mountpoint esplicito, scrivibile e riconosciuto come `vfat`; non scrive in una directory omonima non montata. Puoi omettere `--vram-size`: al primo setup viene usato 4 GiB. Se esiste già un `vram.txt` valido o una configurazione del modulo, il valore attuale viene mantenuto; un `--vram-size` esplicito lo sostituisce. Sono accettati valori da 512 MiB a 8 GiB, allineati a 1 MiB.

La transazione salva e ripristina anche `/vram.txt` sul mount boot in caso di errore. L'opzione `--boot` è supportata sia con `--live` sia con `--root`; per l'installazione offline deve indicare la partizione FAT32 montata separatamente. Se si omette `--module`, il modulo VRAM è compreso nell'installazione completa e richiede comunque `--boot`.

La rimozione del modulo conserva intenzionalmente `vram.txt`: il loader continua a usare l'ultimo valore configurato. I test automatizzati usano mount e filesystem simulati; la verifica dell'effetto sul loader richiede il successivo avvio sulla PS5.
