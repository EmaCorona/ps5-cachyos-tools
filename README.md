# ps5-cachyos-tools

Framework modulare per configurare e mantenere PS5 Linux, con il controller termico `ps5-fan` come modulo compatibile. Il progetto è stato estratto da `ps5-cachy-os-patch` alla revisione `aa555bacfb343ddae02e32784dc4e46d964c6e32`; il repository originale non viene modificato.

## Stato

Questa implementazione è pronta per test simulati e revisione, ma non certifica temperature, rumore, throttling o compatibilità del driver su hardware reale.

Se il device `target_temp` non esiste, contiene un valore invalido o non è leggibile, il demone non può dichiarare verificato il target: registra `DEGRADED`, conserva l'ultimo target verificato solo come informazione storica e non presenta un falso successo.

- 15 zone con interpolazione intera al grado.
- Profili `low`, `balanced` e `high`; `balanced` è il default.
- `target_temp` è l'unico percorso attivo per PS5; PWM hwmon non viene scritto.
- Perdita dei sensori o readback fallito porta a `DEGRADED`; con un target hardware valido non viene mai scelto un valore numericamente più alto, quindi non si alleggerisce il raffreddamento già applicato.
- `EMERGENCY` usa target 29 °C a 81 °C e 28 °C da 82 °C, scavalcando filtri e slew-rate in ingresso; l'uscita richiede due campioni validi a 78 °C o meno e rispetta lo slew-rate.
- `RECOVERY_VALID_SAMPLES` richiede da 2 a 10 campioni validi consecutivi prima del ritorno da `DEGRADED` a `NORMAL` (default: 2).
- Il profilo persistente non viene sovrascritto durante la reinstallazione.
- Il profilo viene riletto a ogni ciclo; `ps5-fan profile set ...` non riavvia il servizio.
- Gli stati runtime sono `NORMAL`, `HEATING`, `EMERGENCY` e `DEGRADED`.
- Il sensore APU/Tctl è selezionato con priorità deterministica; NVMe e hwmon non riconosciuti non sono fallback termici. Se il sensore manca, la zona è `unknown`.
- Low/Balanced/High definiscono anche isteresi, slew-step e cooldown.

## Installazione

Il nuovo orchestratore scopre i moduli tramite manifest sotto `modules/<id>/`:

```bash
sudo ./bin/ps5-cachyos-tools list
sudo ./bin/ps5-cachyos-tools install --root /mnt/ps5-root --module fan
sudo ./bin/ps5-cachyos-tools install --root /mnt/ps5-root --dry-run
sudo ./bin/ps5-cachyos-tools install --root /mnt/ps5-root --boot /mnt/ps5-boot --module fan
sudo ./bin/ps5-cachyos-tools install --live --module fan
```

Dopo un'installazione offline o live la CLI generale è disponibile anche come `/usr/local/bin/ps5-cachyos-tools`, quindi il target può essere amministrato senza conservare la checkout Git. `list`, `check`, `status`, `reset`, `reapply` e `remove --module <id>` usano il registry installato; `reapply` è il solo percorso esplicito per rieseguire un task `once` completato.

`--root` richiede una rootfs già montata, diversa da `/`; in modalità offline il runner e le unit vengono copiati soltanto nel target e nessun hook di boot viene eseguito sul PC. `--live` è esplicito e opera sulla root avviata; `check --live` esegue i check disponibili sulla root corrente. Il contratto dei manifest e degli hook è descritto in [docs/module-api.md](docs/module-api.md); l'architettura è in [docs/architecture.md](docs/architecture.md).

`--boot` è opzionale e può indicare una partizione boot montata separatamente. Il framework non formatta partizioni e non deduce automaticamente l'associazione da un filesystem: la selezione dei mountpoint resta esplicita.

Il modulo `lib/modules/fan.sh` può essere chiamato da un orchestratore oppure direttamente:

```bash
source lib/modules/fan.sh
module_fan_run /mnt/ps5-root
module_fan_check /mnt/ps5-root
```

Su una PS5 già avviata, installare i file nella root del sistema con privilegi amministrativi e abilitare `ps5-fan-daemon.service`. Il comando `ps5-fan profile set high` aggiorna la scelta persistente senza modificare i default dei file di profilo.

Per installazione offline usare `module_fan_run /mnt/ps5-root`. Per installazione live, eseguire il modulo con root `/`; in tal caso ricarica systemd e abilita il servizio. Gli aggiornamenti preservano `fan.conf`, i profili e `state` già presenti.

La rimozione live è `sudo ps5-fan uninstall`; la CLI modulare `remove --module fan --root ROOT` conserva la configurazione per default e accetta `--purge-config` solo per una cancellazione esplicita. La rimozione offline diretta è `module_fan_remove /mnt/ps5-root 1` per conservare i file. Entrambi i percorsi condividono il preflight del modulo, richiedono un manifest di ownership completo e rifiutano la rimozione prima di arrestare il servizio se il manifest è assente, alterato o non coerente con gli artefatti.

## Diagnostica

`sudo ps5-fan status` distingue `profile_configured` da `profile_applied`, target desiderato, osservato e ultimo verificato, sensore, zona, cooldown, contatore di cicli ed errori runtime/configurazione. `sudo ps5-temp` stampa lo stesso stato senza inventare RPM o percentuali. La diagnostica è amministrativa per design; gli utenti non privilegiati non possono modificare profili, target o servizio. I log vanno letti con `journalctl -u ps5-fan-daemon.service`.

## Limiti e rollback

Il controller non può creare un device sysfs mancante: in quel caso registra `DEGRADED` e non dichiara applicato un target non verificato. La validazione fisica di temperatura, RPM, rumore, throttling e driver PS5 resta necessaria. Gli aggiornamenti creano un backup timestampato in `/var/lib/ps5-cachyos-tools/backups/` e ripristinano i file gestiti se un passaggio dell'installazione fallisce; rieseguire `module_fan_check` dopo il ripristino.

## Verifica

```bash
tests/run-tests.sh
```

I test usano file temporanei per simulare hwmon e `target_temp`; la suite corrente verifica 75 casi, incluse readiness per istanza, stato profilo obbligatorio, parsing decimale del timeout derivato dal polling, compatibilità legacy, logging senza spam, rollback di aggiornamenti parziali, isolamento della rootfs, soglie personalizzate e diagnostica separata. La pipeline GitHub Actions ripete sintassi Bash, ShellCheck, suite, unit systemd e controllo whitespace sul diff effettivo di ogni push e pull request, incluso il caso del commit radice. La validazione su console reale resta necessaria.
## Framework modulare: lifecycle e sicurezza

Il framework supporta installazione offline su rootfs montata e installazione live con `--live`. Le installazioni selettive includono le dipendenze transitive in ordine topologico e riusano quelle già valide. Il mutex per target serializza install, remove, reset, reapply e boot runner; le transazioni live conservano anche lo stato `enabled`/`active` delle unit interessate per il rollback.

I moduli `service` con `ENABLED=false` restano installati ma non vengono abilitati né avviati. `reapply` offline è disponibile per i task; per i servizi viene rifiutato esplicitamente. La rimozione conserva le configurazioni fan per default: usare `--purge-config` soltanto quando si desidera eliminarle.
