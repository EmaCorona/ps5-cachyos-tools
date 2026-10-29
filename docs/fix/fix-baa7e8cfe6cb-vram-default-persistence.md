# Default VRAM a 512 MiB e preservazione delle configurazioni

- Commit sorgente: [`baa7e8cfe6cbca75422d6883fccf4c19391a9634`](https://github.com/EmaCorona/ps5-cachyos-tools/commit/baa7e8cfe6cbca75422d6883fccf4c19391a9634)
- Data: 2026-10-29

## Problema

Le nuove installazioni del modulo `vram` impostavano 4 GiB (`0x100000000`) come fallback, mentre il loader SonicISO dichiara 512 MiB (`0x20000000`). Se `vram.conf` e `vram.txt` contenevano dimensioni valide differenti, l'installazione preferiva in silenzio la configurazione root e sovrascriveva il valore FAT letto dal loader. Inoltre il framework trattava `vram.conf` come artefatto posseduto dal modulo e lo rimuoveva anche con `remove --keep-config`.

La riserva E820 descritta dal sorgente SonicISO rende plausibile che una dimensione più grande riduca la RAM ordinaria disponibile; non dimostra che la configurazione VRAM abbia causato i crash osservati a 5 GiB.

## Causa individuata

- `modules/vram/install.sh` aveva un fallback hardcoded di 4 GiB e una precedenza fissa della configurazione root sul file FAT, senza rilevare divergenze.
- `modules/vram/module.conf` elencava `vram.conf` in `OWNED_PATHS`; il remover generico elimina i path owned senza considerare `--keep-config`.
- Non esisteva un hook di rimozione dedicato per applicare il contratto keep/purge al mirror root.

## Correzione applicata

- Le installazioni senza fonti persistenti usano 512 MiB. Una sola fonte valida viene mantenuta e specchiata; copie valide concordi restano stabili; copie valide discordi falliscono prima di qualunque scrittura. `--vram-size` esplicito risolve conflitti e conserva la precedente capacità di correggere il contenuto di file regolari malformati. Symlink e path non regolari sono rifiutati sempre.
- La configurazione root resta nei path transazionali ma non è più un artefatto rimosso genericamente. Il nuovo hook conserva `vram.conf` con `--keep-config`, la rimuove con `--purge-config` e lascia sempre intatto `vram.txt` sulla partizione boot.
- La documentazione aggiunge una procedura read-only per distinguere memoria richiesta, residente e uso GPU. Non attribuisce la dinamica al solo valore 512 MiB e classifica le misure insufficienti come inconclusive.

## File coinvolti

| File | Responsabilità |
|---|---|
| `modules/vram/install.sh` | Default, selezione delle fonti, protezione dai conflitti e sincronizzazione |
| `modules/vram/module.conf` | Mantiene la configurazione root nei path transazionali senza rimozione generica |
| `modules/vram/remove.sh` | Rispetta `--keep-config` e `--purge-config`; non rimuove la configurazione loader FAT |
| `tests/vram-module-tests.sh` | Default, fonti singole/concordi/discordi, override, input malformati/symlink, rollback, remove e lifecycle |
| `docs/modules/vram.md` | Comportamento, compatibilità, rimozione e diagnostica AMDGPU/GTT |

## Verifica e limiti

- `tests/vram-module-tests.sh`: 22 test superati, 0 falliti.
- `tests/run-tests.sh`: exit code 0; la suite completa ha terminato senza errori.
- `bash -n` su installer, hook di rimozione e test: superato.
- `git diff --check`: superato.
- Non sono stati eseguiti workload GPU, Gamescope, reboot o test comparativi a 5 GiB. Sul sistema PS5 erano presenti OOM kill recenti, quindi il gate di carico è rimasto `NO-GO`. La configurazione live era già 512 MiB; la dinamica AMDGPU oltre 512 MiB non è dimostrata da questa correzione.

## Fonti

- [Commit della correzione](https://github.com/EmaCorona/ps5-cachyos-tools/commit/baa7e8cfe6cbca75422d6883fccf4c19391a9634)
- [`modules/vram/install.sh`](../../modules/vram/install.sh)
- [`modules/vram/module.conf`](../../modules/vram/module.conf)
- [`modules/vram/remove.sh`](../../modules/vram/remove.sh)
- [`docs/modules/vram.md`](../modules/vram.md)
- [Sorgente loader SonicISO](https://github.com/soniciso1/ps5-linux-loader-10xx)

## Verifica hardware successiva al riavvio

Un test esplorativo il 2026-10-29 alle 02:12 sul boot `0bd971bd-8e69-44e5-9cd3-57155780fcdc` ha confermato fill GPU e readback di un buffer Vulkan da 640 MiB, ma non aveva uno snapshot del medesimo client prima dell'allocazione target. Il suo valore assoluto `drm-resident-gtt: 657752 KiB` non bastava a escludere residenza preesistente e non è usato da solo per il verdetto.

La verifica conclusiva monitorata è stata eseguita alle 02:32, lasciando VRAM a 512 MiB, profilo ventole low e sessione KDE. Vulkan RADV ha selezionato l'APU `1002:13db`, heap device-local da 5153 MiB e memory type host-visible/device-local; ha allocato e riempito con la GPU un buffer da 640 MiB, quindi verificato tre campioni di readback.

- Stesso processo PID 348072, client DRM 54 e pdev `0000:20:00.0` in tutti gli snapshot. `drm-resident-gtt` era 2056 KiB prima del buffer, 657512 KiB dopo allocazione/prima del submit, e 657752 KiB dopo il submit. L'incremento baseline→allocazione è 655456 KiB (640.09 MiB), quindi supera i 655360 KiB del buffer target.
- `drm-engine-gfx` non era presente prima del submit e valeva `1568199 ns` durante hold post-submit; `READBACK PASS samples=3 pattern=5a17c0de`; probe exit 0.
- Campi raw di supporto: `amd-requested-vram: 655656 KiB`, `amd-requested-gtt: 2152 KiB` pre-submit e `2392 KiB` post-submit, `amd-evicted-vram: 0 KiB`, `drm-total-gtt` 2152→2392 KiB e `drm-resident-vram: 296 KiB`. I contatori total e resident hanno semantiche distinte; il sorgente upstream AMDGPU lega i totali al placement preferito e i residenti alla collocazione effettiva ([sorgente](https://github.com/torvalds/linux/blob/master/drivers/gpu/drm/amd/amdgpu/amdgpu_vm.c)). Il sorgente esatto del kernel locale 7.1.7 non è stato reperito. Il PASS usa quindi il delta resident GTT dello stesso client, engine e readback, non un vincolo tra total-GTT e resident-GTT.
- VRAM totale è rimasta 536870912 byte; GTT totale 7569207296 byte. Un monitor ha raccolto 41 campioni a intervalli di circa un secondo: MemAvailable minima 8.42 GiB, temperatura APU 60.5–61.5 °C e ventole sempre `low/NORMAL`. Nel journal della finestra non sono comparsi nuovi OOM, page fault, reset, ring timeout o warning fence fallback. Dopo il rilascio `mem_info_gtt_used` era 569376768 byte.
- Esito: PASS per l'allocazione e residenza GTT oltre il carveout da 512 MiB, attività GPU, readback e stabilità durante questa prova breve. Non prova stabilità prolungata o ogni carico.
- Gli OOM del boot precedente `9e2c8c2237ae4764b7819d332cd1693a` (ChatGPT 00:42:39 e GhostOfTsushima 01:12:39 del 2026-10-29) restano separati dalla probe.
- Dopo la probe, alle 02:43:48 dello stesso boot corrente, un helper `wine64-preloader` di Proton Experimental per `rpcss.exe` ha prodotto SIGSYS/SYS_SECCOMP. Alle 02:44:49 il kernel ha terminato Ghost of Tsushima con OOM globale, swap assente e anon-RSS 3231084 KiB. Il valore `gpu_active` è aggregato e non consente di attribuire la memoria al gioco; i log non determinano da soli il nesso fra helper, GPU e OOM. L’utente riferisce che l’OOM è stato causato dal carico eccessivo imposto alla console durante il test: il kernel conferma l’OOM, ma non prova questa causa specifica. Steam ha inoltre registrato l’assertion overlay `libnvidia-ml.so.1` mancante e un minidump scartato. Questi eventi appartengono a una distinta esecuzione con Proton Experimental, successiva alla probe, e non dimostrano un difetto del modulo VRAM.
- Nel run ridotto successivo, Steam registra Ghost of Tsushima con Proton 11.0 dalle 03:02:46 alle 03:04:29 con exit code 0; KDE torna attivo alle 03:04:40. Non risultano nuovi OOM o coredump del run fra le 03:00 e le 03:06. Il run è avvenuto con `ps5-cachyos-gamescope 3.17.0-4`: il pacchetto installato possiede sia il binario usato dal percorso predefinito del wrapper sia `build-info`; `pacman -Qkk` riporta 47 file e 0 alterati. Il fingerprint installato registra upstream commit `e6674a98118ca7b098b98a3874b8f195ae1bf750`, patch SHA256 `aef0714d0301b396d1c0903939b5f236218ecf7e2e12c4a961330f93d78a42cd` e helper SHA256 `511ed608e3825e9a4573d2bcfda500f7dd71c0ee27b55a35a178eb60ad87b564`; entrambi i digest corrispondono ai file del branch. Durante Gamescope il portal GTK non riesce ad aprire il display e raggiunge `start-limit-hit`; dopo il ritorno a KDE si avviano il portal GTK e `plasma-xdg-desktop-portal-kde.service`. Nei log non compare un fallimento dello switch; l’avviso documenta però una possibile indisponibilità temporanea del portal GTK durante Gamescope. Il resoconto utente riferisce più giochi e nessuna perdita HDMI; i log locali attestano un solo gioco e non determinano la risoluzione di rendering interna.

Verifiche automatiche eseguite dopo l'allineamento documentale:

- `bash tests/vram-module-tests.sh`: 22 test superati, 0 falliti.
- `bash tests/run-tests.sh`: exit 0; suite completa terminata, compresi i 22 test VRAM e gli altri moduli.
- `bash tests/core/run-tests.sh`: 65 test superati, 0 falliti (21 test R4 inclusi).
- `bash -n` sui file elencati nel workflow CI: superato. `git diff --check` sul diff documentale: superato. Sul diff integrato completo il controllo segnala soltanto le righe di contesto e indentazione contenute nel file upstream `.patch` incorporato; sono sintassi del patch stesso, applicata correttamente dai test dedicati. ShellCheck non è stato eseguito perché il comando non è installato nell'ambiente locale.
