# VRAM

Il modulo `vram` configura il valore letto dal `ps5-linux-loader` prima dell'avvio di Linux. Scrive il numero esadecimale di byte in `/vram.txt` sulla partizione FAT32 di boot e in `/etc/ps5-cachyos-tools/vram.conf`; il file FAT è l'input del loader e la modifica ha effetto al successivo avvio Linux.

## Valore predefinito e configurazioni persistenti

Per una nuova installazione usa 512 MiB (`VRAM_BYTES=0x20000000`) solo quando mancano entrambe le configurazioni persistenti (`/etc/ps5-cachyos-tools/vram.conf` e `vram.txt` sul loader). Il default non migra le installazioni esistenti; configurazioni valide vengono preservate, mentre configurazioni malformate o discordanti falliscono in modo chiuso se non risolte esplicitamente. Sono accettati valori da 512 MiB a 8 GiB, allineati a 1 MiB; durante `install` la CLI conserva i valori ammessi `512MiB` e da `1GiB` a `8GiB` a passi di un GiB.

Per l'installazione, indica esplicitamente il mountpoint FAT32:

```bash
sudo ps5-cachyos-tools install --live --module vram --boot /boot/efi --dry-run
sudo ps5-cachyos-tools install --live --module vram --boot /boot/efi
sudo ps5-cachyos-tools install --live --module vram --boot /boot/efi --vram-size 4GiB
```

Adatta `/boot/efi` al mountpoint reale. Il framework richiede un mountpoint esplicito, scrivibile e riconosciuto come `vfat`; non scrive in una directory omonima non montata. Senza `--vram-size`, il modulo mantiene la configurazione valida presente in una sola fonte, creando o aggiornando il mirror nell'altra; se entrambi i file sono validi e uguali li conserva. Se le due copie valide discordano, l'installazione si interrompe prima di scrivere e chiede di risolvere esplicitamente il conflitto con `--vram-size`. Un file esistente malformato viene rifiutato senza `--vram-size`; un valore CLI valido e esplicito può correggere contenuti malformati di file regolari. Path non regolari o symlinkati sono rifiutati anche con l'override e non vengono modificati. Un'opzione `--vram-size` valida risolve inoltre un conflitto tra due configurazioni valide.

Le scritture restano nella transazione del framework: un errore successivo all'hook ripristina sia `vram.conf` sia `vram.txt`. L'installazione completa include `vram` secondo il manifest e richiede comunque `--boot`.

## Rimozione e lifecycle

`remove --module vram` conserva `vram.conf` per impostazione predefinita e mantiene sempre `vram.txt` sulla partizione FAT, così il loader continua a usare il valore configurato. `--purge-config` elimina il mirror root `vram.conf`; non elimina `vram.txt`, perché la rimozione non richiede un mount boot. Le opzioni amministrative `ENABLED` in `modules.d/vram.conf` e nel manifest controllano il task del framework; non esiste un comando CLI `enable/disable` né una unit systemd del modulo. Disabilitare il task produce `SKIPPED_DISABLED`; una riattivazione automatica avviene al boot successivo. `reapply --live` può rieseguire il task nello stesso boot; `reset` azzera lo stato, ma non avvia il task.

## Diagnostica e verifica dinamica

Il valore configurato a 512 MiB e il fatto che AMDGPU esponga memoria GTT non provano da soli che un carico stia usando memoria GPU aggiuntiva. Per una verifica hardware, raccogliere snapshot prima, durante e dopo un carico rappresentativo che allochi, renda residenti e usi effettivamente buffer complessivi oltre 512 MiB.

1. Identificare la scheda AMD interessata (su PS5 l'ID PCI è `1002:13db`) e il kernel/driver in uso:

   ```bash
   for dev in /sys/class/drm/card*/device; do
       [ -r "$dev/vendor" ] && [ "$(cat "$dev/vendor")" = 0x1002 ] || continue
       printf '%s %s:%s\n' "$dev" "$(cat "$dev/vendor")" "$(cat "$dev/device")"
       readlink -f "$dev/driver"
   done
   uname -a
   ```

2. Leggere, se esposti dal kernel, `mem_info_vram_total`, `mem_info_vram_used`, `mem_info_gtt_total` e `mem_info_gtt_used` dalla directory `device` della scheda identificata. Questi valori aggregati descrivono i pool; non sono da soli prova dell'uso da parte dell'app.
3. Per il PID del carico, leggere i file `/proc/<pid>/fdinfo/*` cercando coppie chiave/valore separate da due punti, per esempio `drm-driver: amdgpu` e `drm-pdev: 0000:20:00.0`. Registrare `drm-total-*`, `drm-resident-*`, `drm-active-*` quando esposto, `amd-requested-*`, `amd-evicted-vram` e i contatori `drm-engine-*`. I contatori di memoria possono avere suffisso `KiB` o `MiB` (in assenza del suffisso l'unità è byte); i contatori `drm-engine-*` sono espressi in ns. Non sommare fd duplicati: raggruppare per PID, `drm-client-id` e `drm-pdev`. I contatori engine sono cumulativi: confrontare i delta tra snapshot. La sintassi e le unità standard sono descritte nella [specifica DRM fdinfo](https://docs.kernel.org/gpu/drm-usage-stats.html).
4. Registrare gli errori del boot e l'intervallo della prova:

   ```bash
   journalctl -k -b --no-pager | grep -Ei 'amdgpu|drm|out of memory|oom|gpu reset|page fault|ring.*timeout'
   ```

5. Inventariare in sola lettura i registri diagnostici AMDGPU realmente accessibili e correlabili alla prova. Registrarli come `UNAVAILABLE` se non sono esposti o non leggibili con i permessi già disponibili; non elevare privilegi e non scrivere in debugfs. Se mancano metriche di residenza/uso sufficienti o registri richiesti non sono correlabili, classificare il risultato `INCONCLUSIVE`.

Dichiarare `PASS` per la dinamica solo quando il carico dimostra, rispetto al baseline dello stesso client, un aumento coerente di memoria residente accessibile alla GPU oltre il carveout, attività GPU e risultato applicativo corretto, senza errori di allocazione, page fault, reset, ring timeout o OOM. In AMDGPU il totale richiesto può essere contabilizzato secondo il placement preferito mentre la residenza segue il placement effettivo; quindi una differenza tra `drm-total-*` e `drm-resident-*` non va interpretata da sola come errore o prova d'uso. `drm-active-*` può non essere disponibile. Non inferire l'uso reale dal solo totale GTT o dal solo `vram_total=512 MiB`. Per i dettagli implementativi upstream, vedere [`amdgpu_vm_update_stats_locked`](https://github.com/torvalds/linux/blob/master/drivers/gpu/drm/amd/amdgpu/amdgpu_vm.c); la versione del kernel locale può avere differenze.

### Esito hardware PS5 — 2026-10-29

Dopo il riavvio, kernel 7.1.7 e AMDGPU riportano VRAM totale 512 MiB (536870912 byte) e GTT totale 7218 MiB (7569207296 byte). La verifica Vulkan RADV monitorata delle 02:32 (boot ID `0bd971bd-8e69-44e5-9cd3-57155780fcdc`) ha selezionato esclusivamente l'APU `1002:13db`, heap device-local da 5153 MiB, e ha riempito un buffer GPU da 640 MiB. Il client DRM 54 su `0000:20:00.0` è stato osservato prima dell'allocazione target, dopo l'allocazione e dopo il submit, deduplicando per PID/client-id/pdev.

I campi fdinfo raw riportano `drm-resident-gtt: 2056 KiB` al baseline pre-allocazione, `657512 KiB` dopo l'allocazione e prima del submit, e `657752 KiB` dopo il submit. Il delta baseline→allocazione è 655456 KiB (640.09 MiB), superiore ai 655360 KiB del buffer da 640 MiB; dopo il submit il delta è 655696 KiB (640.33 MiB). Il readback dei campioni iniziale, centrale e finale ha restituito il pattern atteso. `drm-engine-gfx` non era presente prima del submit ed era `1568199 ns` durante l'hold post-submit. I campi richiesti riportavano `amd-requested-vram: 655656 KiB`, `amd-requested-gtt: 2152 KiB` prima del submit e `2392 KiB` durante hold, `amd-evicted-vram: 0 KiB`; `drm-total-gtt` era 2152→2392 KiB e `drm-resident-vram` 296 KiB. I contatori total e resident descrivono aspetti diversi: il sorgente upstream AMDGPU contabilizza il totale secondo il placement preferito e il residente secondo la collocazione effettiva. Il sorgente esatto del kernel locale 7.1.7 non è stato reperito; perciò l'esito si basa sul delta resident GTT dello stesso client, attività engine e readback, non sul rapporto tra total-GTT e resident-GTT.

La probe è rimasta in hold 20 secondi, poi ha rilasciato il buffer. Un monitor ha raccolto 41 campioni a intervalli di circa un secondo: temperatura APU 60.5–61.5 °C, MemAvailable minima 8.42 GiB e ventole sempre `low/NORMAL`. Nel journal della finestra di prova non sono comparsi nuovi OOM, page fault, reset GPU, ring timeout o warning di fence fallback. Dopo il rilascio, `mem_info_gtt_used` era 569376768 byte e `mem_info_vram_total` era ancora 536870912 byte. Esito: `PASS` per l'allocazione e la residenza GTT oltre il carveout, il completamento del comando GPU, il readback e la stabilità osservata durante questa prova breve; non dimostra stabilità prolungata o comportamento di ogni gioco. I warning sdma0 delle 01:52:15 e gli OOM del boot precedente restano separati da questo risultato.

Gli OOM precedenti del boot `9e2c8c2237ae4764b7819d332cd1693a` hanno terminato ChatGPT alle 00:42:39 e GhostOfTsushima alle 01:12:39 del 2026-10-29; non si attribuisce loro una causa sulla base della probe.

Dopo la probe, nel boot `0bd971bd-8e69-44e5-9cd3-57155780fcdc`, è stata registrata una distinta esecuzione di Ghost of Tsushima con Proton Experimental: alle 02:43:48 `wine64-preloader` per `rpcss.exe` è terminato con SIGSYS/SYS_SECCOMP; alle 02:44:49 il kernel ha attivato OOM globale senza swap e terminato il processo principale (`anon-rss` 3231084 KiB). `gpu_active` era un valore aggregato e non identifica il processo consumatore; i log da soli non determinano il nesso fra helper, memoria GPU e OOM. L’utente riferisce che l’OOM è stato causato dal carico eccessivo imposto alla console durante il test; questa attribuzione è il resoconto dell’operatore, non una conclusione ricavabile dai contatori kernel. La Steam overlay ha segnalato l’assenza di `libnvidia-ml.so.1`, con minidump scartato. Questi eventi non sono avvenuti durante la probe Vulkan delle 02:32 e non dimostrano un difetto del modulo VRAM.

Nel successivo test Gamescope delle 03:00–03:06, Ghost of Tsushima con Proton 11.0 è terminato con codice 0 e il passaggio di ritorno a KDE è riuscito; non sono stati registrati nuovi OOM, coredump del run, reset o page fault nella finestra. Durante Gamescope il portal GTK non riesce ad aprire il display e raggiunge `start-limit-hit`; dopo il ritorno a KDE si avviano il portal GTK e `plasma-xdg-desktop-portal-kde.service`. Nei log non compare un fallimento dello switch; il warning documenta una possibile indisponibilità temporanea del portal GTK in Gamescope. L’utente riferisce anche altri giochi e nessuna perdita di segnale, ma i log disponibili documentano un solo gioco e non attestano la risoluzione interna del renderer.

I test automatizzati del modulo usano root e mount fixture e non dimostrano da soli stabilità prolungata o l’effetto dinamico per ogni gioco.
# Verifica sul kernel 7.2.3 (29 ottobre 2026)

Il valore valido preesistente `0x20000000` (512 MiB) è stato preservato in `/boot/efi/vram.txt` e `/etc/ps5-cachyos-tools/vram.conf`, anche durante rimozione e reinstallazione. AMDGPU espone `536870912` byte di VRAM e `7585812480` byte di GTT. Il loader dopo riavvio e l'allocazione dinamica sotto carico non sono stati verificati; il solo file non costituisce prova di comportamento dinamico. Si veda il [report E2E](../e2e/2026-10-29-kernel-7.2.3-migration.md).
