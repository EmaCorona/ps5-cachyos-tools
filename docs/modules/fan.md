# Modulo ventole

Prima di ogni scrittura l'adapter verifica gli antenati di `/etc/ps5-fan`, `profiles`, configurazione, stato, manifest, directory systemd/udev e binari. Un symlink finale è ammesso soltanto per il wants-link systemd con destinazione `/etc/systemd/system/ps5-fan-daemon.service`; directory `profiles`, `fan.conf`, profili e manifest symlinkati verso l'host causano il rifiuto senza scritture.

`modules/fan/` espone il modulo di tipo `service`; il framework lo scopre dal manifest e delega l'installazione all'adapter `lib/modules/fan.sh`, che installa esclusivamente i componenti del progetto autonomo. Il demone identifica il sensore APU/Tctl per nome e label, applica la curva del profilo persistente e scrive soltanto il file `target_temp` configurato.

`/etc/ps5-fan/fan.conf` contiene le impostazioni globali del controller; le curve `ZONE_TEMPS` e `ZONE_TARGETS` appartengono esclusivamente ai file di profilo in `/etc/ps5-fan/profiles/`. Le chiavi curva in `fan.conf` sono rifiutate esplicitamente: non vengono accettate per poi essere sostituite silenziosamente dal profilo selezionato.

## Curve profili aggiornate

Le curve mantengono le 15 soglie termiche e cambiano solo `ZONE_TARGETS`. La prima revisione ha usato il vecchio `low` e il margine di setpoint `I = 78 - target`, con 78 °C massimo ammesso dal validatore, scalando il proxy a 0,8 (`high`), 0,7 (`balanced`) e 0,6 (`low`). Per questa revisione, a ogni curva già presente è applicato un ulteriore fattore 0,85: `new_target = round(78 - 0,85 × (78 - current_target))`. Quindi il proxy è ridotto del 15% in ciascun profilo. Prima degli arrotondamenti, i fattori complessivi rispetto al vecchio `low` sono 0,68, 0,595 e 0,51. L’arrotondamento è al grado intero più vicino (mezzi gradi verso l’alto). La soglia critica a 81 °C resta 29 °C in tutti i profili, coerente con l’ingresso `EMERGENCY`; a 82 °C il controller imposta 28 °C indipendentemente dal profilo.

| Zona temperatura (°C) | Vecchio `low` (°C) | Nuovo `high` (°C) | Nuovo `balanced` (°C) | Nuovo `low` (°C) |
|---:|---:|---:|---:|---:|
| 38 | 78 | 78 | 78 | 78 |
| 42 | 75 | 76 | 76 | 76 |
| 46 | 72 | 73 | 74 | 74 |
| 50 | 69 | 71 | 72 | 73 |
| 54 | 66 | 68 | 70 | 71 |
| 58 | 63 | 66 | 68 | 69 |
| 62 | 60 | 64 | 65 | 67 |
| 66 | 57 | 61 | 63 | 65 |
| 70 | 53 | 58 | 61 | 63 |
| 72 | 50 | 56 | 58 | 61 |
| 74 | 46 | 52 | 56 | 59 |
| 76 | 42 | 49 | 53 | 56 |
| 78 | 37 | 45 | 49 | 53 |
| 80 | 31 | 40 | 45 | 50 |
| 81 | 29 | 29 | 29 | 29 |

`78 - target` è un proxy lineare della distanza del setpoint dal massimo configurabile, non una misura degli RPM, della potenza di raffreddamento o del rumore. Perciò “−20%” è una stima matematica del setpoint e non certifica un −20% effettivo della ventola. L’ordine impostato è `high` (target più basso) → `balanced` → `low`; le curve interpolano come prima. La validazione termica prolungata resta distinta dai test software e deve interrompersi al limite conservativo preregistrato, senza indebolire `EMERGENCY` o `DEGRADED`.

La seconda revisione produce queste curve ai 15 punti di temperatura:

| Zona temperatura (°C) | `high` precedente → nuovo | `balanced` precedente → nuovo | `low` precedente → nuovo |
|---:|---:|---:|---:|
| 38 | 78 → 78 | 78 → 78 | 78 → 78 |
| 42 | 76 → 76 | 76 → 76 | 76 → 76 |
| 46 | 73 → 74 | 74 → 75 | 74 → 75 |
| 50 | 71 → 72 | 72 → 73 | 73 → 74 |
| 54 | 68 → 70 | 70 → 71 | 71 → 72 |
| 58 | 66 → 68 | 68 → 70 | 69 → 70 |
| 62 | 64 → 66 | 65 → 67 | 67 → 69 |
| 66 | 61 → 64 | 63 → 65 | 65 → 67 |
| 70 | 58 → 61 | 61 → 64 | 63 → 65 |
| 72 | 56 → 59 | 58 → 61 | 61 → 64 |
| 74 | 52 → 56 | 56 → 59 | 59 → 62 |
| 76 | 49 → 53 | 53 → 57 | 56 → 59 |
| 78 | 45 → 50 | 49 → 53 | 53 → 57 |
| 80 | 40 → 46 | 45 → 50 | 50 → 54 |
| 81 | 29 → 29 | 29 → 29 | 29 → 29 |

Questo ulteriore “−15%” è una stima matematica del proxy, non una misura di RPM, potenza di raffreddamento o rumore effettivi. La trasformazione mantiene `high` (target più basso) → `balanced` → `low`; al punto di protezione le tre curve coincidono intenzionalmente.

La perdita dei sensori o del readback non usa una temperatura inventata: lo stato diventa `DEGRADED`, la zona diventa `unknown`, il target desiderato resta conservativo e un target hardware valido più basso ha sempre precedenza. Lo stato runtime distingue `target_desired`, `target_observed` e `target_last_verified`; quando il readback è invalido non viene pubblicato un target verificato. Il ritorno a `NORMAL` richiede almeno due campioni validi consecutivi (`RECOVERY_VALID_SAMPLES`). Le scritture PWM hwmon sono intenzionalmente escluse.

La risposta `EMERGENCY` usa `EMERGENCY_TEMP` (default 81 °C), un delta di recupero `EMERGENCY_RECOVERY_DELTA` (default 3 °C) e quindi la soglia critica a 82 °C e l'uscita a 78 °C. I target sono rispettivamente 29 °C e 28 °C. L'ingresso è immediato; l'uscita richiede i campioni validi configurati e applica lo slew-rate del profilo. `HEATING` risponde agli aumenti significativi; `DEGRADED` segnala l'errore di interfaccia e non autorizza un alleggerimento rispetto al target hardware osservato. Il profilo persistente viene riletto a ogni ciclo senza modificare lo stato termico: una curva non valida non sostituisce quella attiva.

`EMERGENCY_TEMP` può essere anticipata a 80 °C, ma non può essere impostata oltre 81 °C: il limite è una protezione indipendente dai profili e non è una certificazione del driver. Il demone pubblica separatamente `last_runtime_error` e `last_config_error`; `last_error` espone quello prioritario. Un profilo invalido non sovrascrive la configurazione valida né viene perso al ciclo successivo.

La directory runtime è amministrativa (`0750`) e i file di stato sono creati dal servizio. Per evitare di confondere “servizio funzionante” con “hardware disponibile”, usare `sudo ps5-fan status` o `sudo ps5-temp`: uno stato `DEGRADED` indica che il processo è vivo ma la regolazione termica non è confermata; `UNAVAILABLE` indica invece che il demone non ha completato l'avvio. Anche gli errori di parsing e degli override numerici vengono pubblicati nello stato prima dell'uscita. Il campo `instance_id` cambia a ogni avvio del processo; la readiness dell'installer usa l'identità dell'istanza, non confronti impropri tra contatori di processi diversi. Il timeout è derivato dal `POLL_INTERVAL` del profilo selezionato in `/etc/ps5-fan/state`, con numeri normalizzati in base 10 anche quando hanno zeri iniziali o sono quotati. Lo stato profilo deve essere presente e leggibile sia per il daemon sia per l'installer: se manca, il daemon pubblica `profile-state-missing` e non parte, mentre l'installer interrompe il calcolo. Un `POLL_INTERVAL` invalido, un profilo persistente inesistente o un override `PS5_FAN_POLL_SEC` fuori range interrompono il calcolo senza fallback silenzioso; un override presente ma vuoto è invalido sia per daemon sia per installer. Il timeout può essere limitato esplicitamente con `PS5_FAN_HEALTH_TIMEOUT`, anch'esso validato e normalizzato.

Le installazioni precedenti possono conservare `SENSOR_FAILURE_LIMIT`: la chiave numerica viene accettata come deprecata, ignorata dalla politica e registrata una sola volta. Altre chiavi sconosciute continuano a invalidare la configurazione.

Gli aggiornamenti preservano la configurazione utente e lasciano un backup timestampato di tutti gli artefatti gestiti quando esistono già. Se una nuova installazione fallisce, vengono rimossi anche configurazione, profili e stato creati dalla transazione; se esiste un backup, sono ripristinati. La rimozione esegue un preflight completo prima di fermare il servizio, condivide la stessa validazione tra CLI e modulo, elimina soltanto gli artefatti del modulo e conserva i file personalizzati. Il rollback pubblica esiti distinti (`ROLLBACK_COMPLETED`, `ROLLBACK_FILES_RESTORED_SERVICE_FAILED`, `ROLLBACK_PARTIAL`, `ROLLBACK_FAILED`) e verifica separatamente file, `daemon-reload`, enabled e active. Un aggiornamento live riavvia il servizio se cambia o viene riparato un artefatto runtime e attende uno stato applicativo valido; `DEGRADED` viene riportato come servizio vivo ma hardware non confermato. Il demone scrive nel journal solo cambi di profilo/stato e nuovi errori significativi. I test automatici simulano sensori APU/NVMe, profili, cambio runtime, stati critici, reload corrotto, readback, soglie personalizzate, diagnostica separata e installazione. Driver, temperatura fisica, RPM, rumore e throttling devono ancora essere verificati su console reale.

Nel framework modulare il manifest fan viene rispettato anche per `ENABLED=false`: gli artefatti possono essere installati senza abilitare la unit. La rimozione tramite CLI conserva `fan.conf`, profili e stato per default (`--keep-config`); `--purge-config` è l'unica opzione esplicita per rimuoverli. Le transazioni concorrenti condividono il lock del framework e il rollback conserva gli artefatti utente quando l'hook fallisce.
Quando il fan è installato dal framework, l'adapter prepara soltanto gli artefatti e il framework gestisce enable/disable/start/stop della unit. L'installazione autonoma continua invece a gestire il lifecycle live per compatibilità legacy. Lo snapshot di `remove --purge-config` include anche `fan.conf`, `state` e i profili, così un errore successivo può ripristinare le configurazioni personalizzate.
Durante `remove` gestito dal framework, il core arresta e disabilita prima la unit; l'hook fan rimuove quindi soltanto le configurazioni richieste da `--purge-config` (oppure le conserva con `--keep-config`) e lascia al core la rimozione della unit, del wants-link e degli artefatti dichiarati. Questo evita di trattare come errore il wants-link già rimosso dal lifecycle systemd.
Il manifest dichiara `READINESS_HOOK=readiness.sh`: dopo un restart il controllo richiede una nuova istanza e uno stato runtime aggiornato; senza restart richiede invece progresso del processo già attivo. `NORMAL`, `HEATING`, `EMERGENCY` e `DEGRADED` sono stati applicativi distinti: `DEGRADED` viene riportato come warning e non causa lo stop del controller. Quando il solo demone o una unit cambia, il modulo segnala il runtime al core tramite `CORE_RUNTIME_CHANGED_FILE`, che esegue il restart una sola volta.
Le copie atomiche degli artefatti trattano la destinazione come percorso esatto: directory e altri tipi non regolari già presenti vengono rifiutati, mentre `mv -T` e `ln -sT` impediscono che il file o link temporaneo venga inserito dentro una directory concorrente o preesistente. Il test di rollback controlla che un conflitto con una directory preservi i suoi permessi e non lasci file residui.
