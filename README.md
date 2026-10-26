# PS5 CachyOS Tools

> [!NOTE]
> **Piattaforma di destinazione**: Linux x86_64 su PlayStation 5, con particolare attenzione alle distribuzioni basate su CachyOS. La compatibilità effettiva dipende da kernel, driver, firmware e hardware; i test simulati non sostituiscono le verifiche sulla console.

<br>

Framework **modulare di post-installazione, manutenzione e diagnostica** per PS5 Linux. L'orchestratore installa e gestisce funzionalità indipendenti, ciascuna con un proprio manifest, senza dover modificare il core quando si aggiunge un modulo.

Il progetto comprende moduli indipendenti per il controllo termico (`fan`), il cleanup mirato al boot (`boot-cleanup`) e la sessione grafica (`kde`, `gamescope`, `session`). Deriva da [PS5 CachyOS Patch](https://github.com/EmaCorona/ps5-cachy-os-patch), ma ne adotta un'architettura modulare distinta.

<br>

> [!IMPORTANT]
> **Ambito e sicurezza**: questi strumenti operano su un'installazione Linux **già esistente**. Non installano CachyOS, non partizionano né formattano dischi, non preparano exploit o bootloader e non includono le altre patch del repository originale (rete, Bluetooth o migrazione M.2). Il modulo cleanup non è uno strumento generico di riparazione del boot. Le sessioni grafiche richiedono che Plasma, Gamescope, Steam e il login automatico TTY1 siano già configurati dalla distribuzione.

---

## ⚡ Guida Rapida all'Uso (Quick Start)

### 1. Installazione da PC Linux su Rootfs Montata (Consigliata)

Collega al PC il supporto con PS5 Linux (USB, SSD o NVMe accessibile dall'host) e **monta prima la partizione root**. Negli esempi `/mnt/ps5-root` è un mountpoint reale, non una directory vuota creata per simulare un'installazione.

```bash
git clone --branch feature/kde-gamescope-session-migration --single-branch https://github.com/EmaCorona/ps5-cachyos-tools.git
cd ps5-cachyos-tools

findmnt /mnt/ps5-root                # verifica che la rootfs sia montata
./bin/ps5-cachyos-tools list        # mostra i moduli presenti nel repository

sudo ./bin/ps5-cachyos-tools install --root /mnt/ps5-root --dry-run
sudo ./bin/ps5-cachyos-tools install --root /mnt/ps5-root
```

Senza `--module` vengono selezionati **tutti i moduli disponibili**. Il `--dry-run` esegue controlli preliminari e mostra il piano d'installazione senza applicare i moduli. Controlla il target e l'output prima della seconda esecuzione.

**Come funziona la modalità offline:** il framework verifica che `--root` sia un mountpoint assoluto, scrivibile, diverso da `/` e contenente `etc/os-release`; rifiuta i percorsi symlinkati non sicuri. Copia core, manifest, hook, comandi e unit systemd **solo nella rootfs destinazione**. Prepara i collegamenti di abilitazione dei servizi nel target, ma **non esegue i task di boot e non avvia systemd sul PC host**. `boot-cleanup` opererà al primo avvio del sistema destinazione; `fan` sarà gestito dalla relativa unit; i profili grafici saranno applicati dal login TTY1 al boot.

Se la partizione di boot è montata separatamente, puoi indicarla in modo esplicito:

```bash
sudo ./bin/ps5-cachyos-tools install --root /mnt/ps5-root --boot /mnt/ps5-boot
```

`--boot` è opzionale per i moduli correnti, che non richiedono modifiche alla partizione di boot. L'orchestratore **non rileva automaticamente** root e boot e non monta le partizioni al posto dell'utente.

### 2. Installazione Direttamente da PS5 Linux (Live)

Su PS5 Linux già avviato, clona il branch e installa sulla root del sistema attuale. **`--dry-run` e `install` non sono due installazioni**: il primo controlla il piano senza applicarlo, il secondo installa davvero.

```bash
git clone --branch feature/kde-gamescope-session-migration --single-branch https://github.com/EmaCorona/ps5-cachyos-tools.git
cd ps5-cachyos-tools

./bin/ps5-cachyos-tools list
sudo ./bin/ps5-cachyos-tools install --live --dry-run
sudo ./bin/ps5-cachyos-tools install --live
```

Senza `--module` vengono installati **tutti i moduli disponibili**, mentre `--live` indica che il target è la PS5 attualmente avviata (`/`), non una rootfs montata su un altro computer. Sono richiesti i privilegi amministrativi e il riconoscimento della piattaforma PS5.

| Modulo | Installazione | Attivazione |
| :--- | :--- | :--- |
| **`fan`** | Immediata | `ps5-fan-daemon.service` viene abilitato e avviato subito nella normale installazione live, se i controlli riescono. Continuerà a funzionare tramite systemd. |
| **`boot-cleanup`** | Immediata | L'hook di pulizia **non viene eseguito dall'installazione**: parte normalmente al boot successivo tramite `ps5-tools-early.service`, oppure manualmente con `reapply`. |
| **`kde`, `gamescope`, `session`** | Immediata | I task verificano gli artefatti al boot normale; il login TTY1 avvia KDE per default. Gamescope resta selezionabile e KDE è anche il fallback in caso di errore Gamescope. |

**Verifica immediata:**

```bash
sudo ps5-cachyos-tools status --live
sudo systemctl status ps5-fan-daemon.service
sudo systemctl is-enabled ps5-tools-early.service

# Opzionale: esegui il cleanup senza riavviare la console.
sudo ps5-cachyos-tools reapply boot-cleanup --live
```

Con `--no-start` il framework installa e abilita le unit senza avviare immediatamente il demone durante la procedura; **non** significa disabilitare i moduli al prossimo boot.

```bash
sudo ./bin/ps5-cachyos-tools install --live --no-start
```

`PS5_TOOLS_ALLOW_LIVE=1` disattiva il rilevamento PS5 solo per test controllati: non usarlo normalmente su un PC Linux.

### 3. Installare Solo un Modulo

**Solo controller ventole**, avviato immediatamente nella modalità live standard:

```bash
sudo ./bin/ps5-cachyos-tools install --live --module fan --dry-run
sudo ./bin/ps5-cachyos-tools install --live --module fan
```

**Solo pulizia al boot**, senza installare il controller ventole:

```bash
sudo ./bin/ps5-cachyos-tools install --live --module boot-cleanup --dry-run
sudo ./bin/ps5-cachyos-tools install --live --module boot-cleanup
```

Se invece la distro PS5 Linux è montata su un PC host, usa **`--root` al posto di `--live`**:

```bash
sudo ./bin/ps5-cachyos-tools install --root /mnt/ps5-root --module fan
sudo ./bin/ps5-cachyos-tools install --root /mnt/ps5-root --module boot-cleanup
```

Questi comandi sono **alternative**: esegui solo quello relativo al modulo desiderato oppure ometti `--module` per installarli entrambi. Le eventuali dipendenze vengono selezionate automaticamente; i moduli attuali non dipendono l'uno dall'altro.

### 4. Opzioni di Installazione Spiegate

| Opzione | Significato |
| :--- | :--- |
| `--live` | Installa nel sistema **attualmente avviato**; può abilitare e avviare subito i servizi. |
| `--root ROOT` | Installa su rootfs Linux **già montata**; non avvia i servizi sull'host. Incompatibile con `--live`. |
| `--boot BOOT` | Mountpoint separato della partizione boot; opzionale per i moduli attuali. |
| `--module fan` | Installa o aggiorna soltanto il controller ventole. |
| `--module boot-cleanup` | Installa o aggiorna soltanto il cleanup al boot. |
| `--dry-run` | Controlla target, manifest, dipendenze e piano senza modificare i moduli. |
| `--no-start` | Non avvia immediatamente i servizi durante l'installazione live, senza disabilitarli al boot. |

Dopo la prima installazione, `/usr/local/bin/ps5-cachyos-tools` è disponibile nel sistema PS5: per controllare, riapplicare e rimuovere moduli installati non occorre conservare il checkout Git. `list` legge il repository corrente, mentre `status` e `check` leggono il registry installato.

### 5. Verifica Dopo l'Installazione

```bash
sudo ps5-cachyos-tools status --live
sudo ps5-cachyos-tools check --live
sudo ps5-fan status
sudo ps5-temp
sudo journalctl -u ps5-tools-early.service -b --no-pager
```

`status` mostra moduli installati, policy e stato di esecuzione; `check` esegue gli hook dei moduli installati. **Prima della prima esecuzione del cleanup**, `check` può fallire semplicemente perché il file runtime `cleanup.state` non esiste ancora. `ps5-fan status` e `ps5-temp` verificano lo stato applicativo del controllo ventole, non soltanto che il servizio sia avviato.

---

## 🧩 Architettura e Moduli del Progetto

La struttura separa **orchestrazione**, **implementazione dei moduli** e **runtime**:

- **`bin/ps5-cachyos-tools`**: CLI per installazione, verifica, stato, riapplicazione e rimozione.
- **`lib/core/`**: discovery, validazione dei target, dipendenze, transazioni, registry, stato persistente e integrazione systemd.
- **`modules/<id>/`**: manifest `module.conf` e hook indipendenti (`install.sh`, `boot.sh`, `check.sh`, `remove.sh` e hook opzionali).
- **`lib/modules/fan.sh`**, **`bin/ps5-fan*`** e **`config/`**: adapter e implementazione autonoma del controller termico.
- **`systemd/`**: unit del runner di boot e del servizio ventole.

### Mappa dei Moduli Disponibili

| Modulo | Tipo / esecuzione | Funzionamento |
| :--- | :--- | :--- |
| **[`fan`](docs/modules/fan.md)** | `service` · `always` | Installa e gestisce `ps5-fan-daemon.service`: profili `low`, `balanced` e `high`, curva dinamica a 15 zone, lettura APU/Tctl, protezione di emergenza, diagnostica e cambio profilo senza restart. |
| **[`boot-cleanup`](docs/modules/boot-cleanup.md)** | `task` · `early` · `always` | Analizza esclusivamente record Steam allowlistati, verifica PID, identità del processo e proprietario, rimuove i soli file stale autorizzati e registra un resoconto del boot. Non termina processi né effettua pulizie globali. |
| **[`kde`](docs/modules/kde.md)** | `task` · `normal` · `always` | Predispone variabili KWin DRM, gruppi grafici e notifiche senza eliminare preferenze display personali. |
| **[`gamescope`](docs/modules/gamescope.md)** | `task` · `normal` · `always` | Rileva modalità DRM, avvia Steam su Gamescope, valida override e offre diagnostica video e integrità Steam. |
| **[`session`](docs/modules/session.md)** | `task` · `normal` · `always` | Coordina TTY1, preferenza Gamescope/KDE, switch bidirezionale e fallback KDE; dipende da KDE e Gamescope. |

Ogni modulo espone il proprio manifest e può essere installato selettivamente. `session` seleziona automaticamente le dipendenze `kde` e `gamescope`; nessuno dei tre grafici modifica `fan` o `boot-cleanup`. La directory `modules/_template/` offre un punto di partenza per nuove integrazioni.

### Avvio Automatico e Politiche di Esecuzione

```text
             [ Installazione offline o live ]
                           |
                [ Discovery manifest ]
                           |
          [ Preflight + transazione + hook ]
                           |
                 [ Sistema PS5 avviato ]
                           |
              +------------+-------------+
              |                          |
              v                          v
 [ ps5-tools-early.service ]    [ ps5-fan-daemon.service ]
              |                          |
       [ task early ]            [ controllo termico ]
              |                     [ continuo ]
       [ boot-cleanup ]
              |
       [ Stato del task ]
              |
 [ ps5-tools-boot.service ]
       [ task normal ]
       [ nessuno attuale ]
```

Le unit `ps5-tools-early.service` e `ps5-tools-boot.service` avviano il runner rispettivamente nelle fasi `early` e `normal`. Il controller ventole usa invece **una unit systemd autonoma**, non un task eseguito una volta sola. Il runner ordina i moduli in base alle dipendenze dichiarate e serializza le operazioni per evitare transazioni concorrenti.

Il manifest determina il comportamento: `TYPE=task` esegue un hook di boot, `TYPE=service` gestisce un servizio; `RUN_POLICY=always` si applica a ogni boot previsto, mentre `once` conserva il completamento per quella revisione finché non si richiede una riapplicazione esplicita. Per `boot-cleanup` la politica effettiva è **`early/always`**: un precedente `SUCCESS` **non lo fa saltare ai boot successivi**. La politica di errore è `continue` per il cleanup e `critical` per il manifest fan.

La documentazione tecnica completa è in [architettura](docs/architecture.md) e [contratto dei moduli](docs/module-api.md); consulta anche l'[indice dei moduli](docs/modules/README.md).

---

## 🌟 Funzionalità Principali Approfondite

### 1. Controllo Termico Dinamico a 15 Zone (`fan`)

`ps5-fan-daemon` legge prioritariamente un sensore **APU/Tctl** riconosciuto e calcola il target del controller ventole in base al profilo. Usa **interpolazione al grado**, isteresi, limiti alla riduzione del raffreddamento e cooldown per evitare oscillazioni continue. Il percorso hardware attivo è `/sys/bus/platform/devices/ps5-fan/target_temp`: **non scrive PWM hwmon** e non deduce RPM o percentuali reali da un valore di target.

Il profilo iniziale è `balanced`. I tre profili utilizzano gli stessi **15 punti di temperatura**, ma target differenti:

| Temperatura APU (°C) | `low` (°C) | `balanced` (°C) | `high` (°C) |
| :---: | :---: | :---: | :---: |
| 38 | 78 | 72 | 65 |
| 42 | 75 | 69 | 62 |
| 46 | 72 | 66 | 59 |
| 50 | 69 | 63 | 56 |
| 54 | 66 | 60 | 53 |
| 58 | 63 | 57 | 50 |
| 62 | 60 | 54 | 47 |
| 66 | 57 | 51 | 44 |
| 70 | 53 | 47 | 41 |
| 72 | 50 | 45 | 39 |
| 74 | 46 | 43 | 37 |
| 76 | 42 | 40 | 35 |
| 78 | 37 | 36 | 33 |
| 80 | 31 | 31 | 31 |
| 81 | 29 | 29 | 29 |

*Valori tratti dalle curve dei profili: sono **target del controller**, non temperature APU da raggiungere né velocità della ventola. Tra i punti viene interpolato il valore; isteresi e altre protezioni possono influenzare il target effettivamente applicato.*

**Profili:** `low` privilegia una risposta meno aggressiva, `balanced` è il compromesso predefinito, `high` richiede un raffreddamento più incisivo. Ogni profilo personalizza anche isteresi, passo di variazione, cooldown e intervallo di polling.

**Protezione di emergenza:** da **81 °C** entra in `EMERGENCY` con target 29 °C, portato a **28 °C da 82 °C**. L'ingresso bypassa i filtri di rallentamento; il rientro richiede almeno due campioni validi a **78 °C o meno** e applica nuovamente la limitazione graduale. In caso di perdita del sensore, errore di scrittura o readback non verificabile, lo stato diventa `DEGRADED`: il demone non dichiara un'applicazione riuscita e non alleggerisce un target hardware valido già più conservativo.

Gli stati applicativi sono `NORMAL`, `HEATING`, `EMERGENCY` e `DEGRADED`; la zona diventa `unknown` quando manca una misura affidabile.

#### Cambio Profilo e Configurazione

```bash
sudo ps5-fan profile set low
sudo ps5-fan profile set balanced
sudo ps5-fan profile set high

sudo ps5-fan status
sudo ps5-temp
```

La scelta è persistente in `/etc/ps5-fan/state` e viene riletta **a ogni ciclo del demone**, quindi non serve riavviare il servizio. Le impostazioni si trovano in `/etc/ps5-fan/fan.conf` e `/etc/ps5-fan/profiles/`; reinstallazioni e aggiornamenti preservano i file personalizzati e il profilo salvato.

`ps5-fan status` e `ps5-temp` espongono sensore, zona, profilo configurato/applicato, target desiderato/osservato/verificato, contatori e ultimi errori, senza presentare RPM fittizi. Per dettagli consulta la [documentazione del modulo fan](docs/modules/fan.md).

---

### 2. Boot Cleanup Conservativo (`boot-cleanup`)

`boot-cleanup` è progettato per rimuovere **solo residui Steam identificati con criteri verificabili**, non per cancellare genericamente cache, lock, log o dati di sistema. È un **task early eseguito a ogni boot**, ma le operazioni di migrazione vengono registrate separatamente per evitare lavoro inutile.

**Funzionamento effettivo:**

1. L'installazione prepara `/etc/ps5-cachyos-tools/boot-cleanup.conf` senza sovrascrivere una configurazione esistente.
2. Al boot viene acquisito un lock dedicato; la migrazione esamina esclusivamente i file regolari `/home/<utente>/.steam/steam.pid` e genera record controllati per i candidati compatibili. `steam.pipe` non viene letto o cancellato.
3. Viene esaminato `/run/ps5-cachyos-tools/boot-cleanup/steam-stale.list`, con record nel formato `pid starttime uid artifact command reason owner` e un limite di **128 record** per ciclo.
4. Ogni candidato deve rispettare una **allowlist di percorsi Steam**, PID, UID e comando ammessi; se un processo esiste, ne vengono confrontati start time, UID e comando. **I processi attivi non vengono terminati**.
5. Un residuo viene eliminato solo se il processo corrispondente è assente e il file è regolare, non symlinkato e posseduto dall'UID atteso. I record non sicuri vengono rifiutati e conteggiati.
6. L'esito viene scritto atomicamente in `/run/ps5-cachyos-tools/boot-cleanup/cleanup.state`, con `action`, `checked`, `removed`, `would_remove`, `active` e `rejected`.

La allowlist comprende i file runtime `/run/user/<uid>/steam-(runtime|webhelper|client)-<id>` e il file `steam.pid` nella home; **non** autorizza cancellazioni libere sotto `/run` o `/home`. Lo stato della migrazione viene conservato in `/var/lib/ps5-cachyos-tools/boot-cleanup/migration.state`; la verifica viene ripetuta se un `steam.pid` considerato risulta più recente del marker.

#### Modalità di Simulazione del Cleanup

La configurazione generata contiene:

```ini
STEAM_STALE_FILE=/run/ps5-cachyos-tools/boot-cleanup/steam-stale.list
DRY_RUN=0
```

Impostando `DRY_RUN=1` nel file oppure usando l'override `PS5_CLEANUP_DRY_RUN=1` durante l'esecuzione dell'hook, il task **non elimina i candidati** e registra `action=DRY_RUN` e `would_remove`. Questa simulazione del **modulo a runtime** è distinta da `install --dry-run`, che controlla soltanto l'installazione.

Un risultato `action=NO_ACTION` indica che nel ciclo non è stata eseguita alcuna rimozione; non equivale, da solo, a una verifica generale della salute del sistema. Il cleanup **non** termina Steam, non cancella coredump o journal, non modifica KDE/Gamescope e non interviene su filesystem, M.2, controller ventole o file estranei all'allowlist.

Per il comportamento e i limiti attuali consulta la [scheda boot-cleanup](docs/modules/boot-cleanup.md).

---

## ⚙️ Gestione dei Moduli e del Lifecycle

### Comandi della CLI

| Comando | Scopo |
| :--- | :--- |
| `list` | Scopre i moduli dal repository dal quale si esegue la CLI. |
| `install --root ROOT` / `install --live` | Installa tutti i moduli disponibili, oppure solo `--module ID` e le sue dipendenze. |
| `install ... --dry-run` | Controlla target, manifest e piano d'installazione senza applicarli. |
| `status --root ROOT` / `status --live` | Mostra moduli installati, policy, stato persistente e, live, disponibilità/readiness del servizio. |
| `check --root ROOT` / `check --live` | Esegue i check implementati dai moduli presenti nel target. |
| `reapply ID --live` | Riapplica il task richiesto o il lifecycle di un servizio sul sistema avviato. |
| `reapply ID --root ROOT` | Pianifica la riapplicazione di un **task** per il prossimo boot; non supporta i servizi offline. |
| `reset ID --root ROOT` / `reset ID --live` | Azzera lo stato registrato di un modulo; non è una reinstallazione. |
| `remove --module ID --root ROOT` / `remove --module ID --live` | Rimuove gli artefatti gestiti del modulo; di default conserva la configurazione. |

```bash
# Diagnostica sul sistema avviato
sudo ps5-cachyos-tools status --live
sudo ps5-cachyos-tools check --live

# Esegui di nuovo il cleanup sulla PS5, senza reinstallare tutto
sudo ps5-cachyos-tools reapply boot-cleanup --live

# Pianifica un nuovo passaggio del cleanup su rootfs offline
sudo ./bin/ps5-cachyos-tools reapply boot-cleanup --root /mnt/ps5-root

# Riavvia e verifica il lifecycle del controller già installato
sudo ps5-cachyos-tools reapply fan --live

# Rimuovi soltanto il controller ventole mantenendo la configurazione
sudo ps5-cachyos-tools remove --module fan --live

# Rimozione esplicita anche delle configurazioni fan
sudo ps5-cachyos-tools remove --module fan --live --purge-config
```

**Attenzione:** `check` esamina tutti i moduli installati che espongono un hook. Subito dopo l'installazione **offline**, prima del primo boot del target, `check --root` può fallire perché `boot-cleanup` non ha ancora prodotto `cleanup.state`. Per distinguere presenza e stato di esecuzione usa `status --root ROOT`.

### Abilitare e Disabilitare un Modulo Senza Rimuoverlo

**Disabilitare** un modulo conserva i suoi file e le sue configurazioni, ma impedisce l'esecuzione automatica. Il framework legge gli override dalla directory `/etc/ps5-cachyos-tools/modules.d/` del **sistema di destinazione**, in file chiamati `<id>.conf`. Il formato supporta `ENABLED=true|false`; per i soli task è previsto anche `RUN_POLICY=once|always`.

#### Disabilitare `boot-cleanup`

Da Linux avviato sulla PS5:

```bash
sudo install -d -m 755 /etc/ps5-cachyos-tools/modules.d
printf 'ENABLED=false\n' | sudo tee /etc/ps5-cachyos-tools/modules.d/boot-cleanup.conf
sudo ps5-cachyos-tools status --live
```

Al boot successivo il runner rilegge l'override, **salta il cleanup** e registra che il modulo è disabilitato. Non è necessario fermare un servizio dedicato, perché `boot-cleanup` è un task e non un demone residente.

Per **riabilitarlo**:

```bash
printf 'ENABLED=true\n' | sudo tee /etc/ps5-cachyos-tools/modules.d/boot-cleanup.conf
sudo ps5-cachyos-tools status --live
```

Dal prossimo boot il task riprende normalmente. Per avviarlo anche subito: `sudo ps5-cachyos-tools reapply boot-cleanup --live`.

#### Disabilitare `fan`

L'override impedisce che il framework lo riabiliti nelle installazioni successive, ma **non arresta da solo un demone già attivo**. Per fermarlo subito, dopo esserti assicurato che il raffreddamento hardware sia adeguato:

```bash
sudo install -d -m 755 /etc/ps5-cachyos-tools/modules.d
printf 'ENABLED=false\n' | sudo tee /etc/ps5-cachyos-tools/modules.d/fan.conf
sudo systemctl disable --now ps5-fan-daemon.service
sudo ps5-cachyos-tools status --live
sudo systemctl is-active ps5-fan-daemon.service
```

Per **riabilitare e avviare subito** il controller:

```bash
printf 'ENABLED=true\n' | sudo tee /etc/ps5-cachyos-tools/modules.d/fan.conf
sudo systemctl enable --now ps5-fan-daemon.service
sudo ps5-cachyos-tools status --live
sudo ps5-fan status
```

Verifica la readiness: un servizio `active` può essere `DEGRADED` se i sensori o il target non sono verificabili. In entrambi i casi gli override non cancellano la configurazione personale del profilo ventole.

**Disabilitazione offline:** quando la rootfs è montata su un PC, scrivi l'override in `/mnt/ps5-root/etc/ps5-cachyos-tools/modules.d/<id>.conf` anziché nella `/etc` del PC. Per i servizi, riesegui l'installazione selettiva su quella rootfs per riconciliare i collegamenti di abilitazione. Non usare `systemctl disable` sull'host per gestire le unit della distro PS5.

### Rimuovere Un Modulo: Comandi ed Effetti

**Rimuovere** è diverso da disabilitare: il framework cancella gli artefatti gestiti del modulo selezionato e il relativo stato di registry. Non cancella automaticamente altri moduli e non disinstalla l'intera distribuzione.

**Rimuovere soltanto `fan`**, conservando configurazioni e profili personalizzati:

```bash
sudo ps5-cachyos-tools remove --module fan --live
sudo ps5-cachyos-tools status --live
```

Per eliminare **anche la configurazione del controller ventole**:

```bash
sudo ps5-cachyos-tools remove --module fan --live --purge-config
```

`--purge-config` è una scelta esplicita e distruttiva delle personalizzazioni fan. Il comportamento predefinito equivale a `--keep-config`. La rimozione live del modulo fan arresta e disabilita la relativa unit prima di eliminare i file, con controlli preliminari e tentativo di rollback in caso di errore.

**Rimuovere soltanto `boot-cleanup`**:

```bash
sudo ps5-cachyos-tools remove --module boot-cleanup --live
sudo ps5-cachyos-tools status --live
```

Dopo la rimozione il runner non trova più il modulo e non ne esegue l'hook. Con `--keep-config` la configurazione `/etc/ps5-cachyos-tools/boot-cleanup.conf` viene conservata; con `--purge-config` viene eliminata. In entrambe le modalità il core rimuove i file runtime e `migration.state` registrati come artefatti del modulo; la directory persistente può rimanere vuota.

**Da PC host, sulla rootfs PS5 montata** (comandi alternativi):

```bash
sudo ./bin/ps5-cachyos-tools remove --module fan --root /mnt/ps5-root
sudo ./bin/ps5-cachyos-tools remove --module boot-cleanup --root /mnt/ps5-root
```

Scegli solo il modulo che vuoi rimuovere. Il comando offline non esegue `systemctl` sul PC host. Il core, la CLI comune, le unit condivise e gli altri moduli possono rimanere installati: **`remove` non è una disinstallazione globale del framework**.

### Riapplicare un Modulo o Resettarne lo Stato

```bash
# Esecuzione manuale del task cleanup, senza reinstallazione:
sudo ps5-cachyos-tools reapply boot-cleanup --live

# Riapplica il lifecycle del servizio ventole:
sudo ps5-cachyos-tools reapply fan --live

# Prenota l'esecuzione del task sul prossimo boot della rootfs:
sudo ./bin/ps5-cachyos-tools reapply boot-cleanup --root /mnt/ps5-root

# Azzera il marker di stato del modulo, senza disinstallarlo:
sudo ps5-cachyos-tools reset boot-cleanup --live
```

`reapply` non è `install`: in live richiama l'hook del task o il lifecycle del servizio; offline registra una richiesta valida **solo per i task**. `reset` rimuove lo stato persistente del modulo senza eliminare i suoi file. Il cleanup dispone già della policy `always`: non richiede una riapplicazione manuale dopo ogni accensione.

### Aggiornamenti e Rollback

Ripetere `install` sullo stesso target è il percorso per aggiornare il framework e i moduli. I passaggi puntano all'**idempotenza**: preservano le configurazioni personali, evitano di rieseguire dipendenze già valide e non riavviano inutilmente il demone se gli artefatti runtime e la unit non sono cambiati. Nel caso fan, la readiness controlla l'avanzamento effettivo del processo e distingue `ready` da `DEGRADED`.

L'installer usa snapshot e rollback per i file gestiti; nella modalità live include anche lo stato `enabled`/`active` delle unit interessate. Se il ripristino non è completo, conserva il backup transazionale e segnala un risultato parziale: **non assumere che ogni errore sia automaticamente risolto**.

`remove` elimina solo il modulo selezionato e non smonta né cancella il filesystem Linux. `--keep-config` è il comportamento predefinito; `--purge-config` richiede una scelta esplicita. Per `boot-cleanup`, `--purge-config` elimina `boot-cleanup.conf`; in entrambe le modalità vengono rimossi i file runtime e `migration.state` dichiarati in `OWNED_PATHS`, mentre le directory vuote non vengono eliminate esplicitamente. Per il modulo fan, la rimozione verifica prima gli artefatti posseduti; l'opzione di purge elimina le relative personalizzazioni quando autorizzata.

---

## 🔍 Risoluzione dei Problemi Comuni (Troubleshooting)

### 1. Installazione Offline Rifiutata

Se il framework segnala un mountpoint non valido, verifica `findmnt /mnt/ps5-root`, il file `/mnt/ps5-root/etc/os-release` e i permessi di scrittura. `--root /` non è ammesso in offline: sulla console in esecuzione usa `--live`. Non puntare a una semplice cartella di staging e non aggirare i controlli sui symlink.

### 2. Servizio Ventole Attivo ma Controllo Degradato

`systemctl is-active` indica soltanto che il servizio è in esecuzione; non certifica che il device termico sia utilizzabile. Verifica:

```bash
sudo systemctl status ps5-fan-daemon.service
sudo ps5-fan status
sudo ps5-temp
sudo journalctl -u ps5-fan-daemon.service -b --no-pager
```

`DEGRADED` segnala un problema con sensori, target o readback; `UNAVAILABLE` indica che manca uno stato runtime leggibile. Non considerare una temperatura o una velocità stimata come un valore fisico verificato. Se il device `target_temp` non è esposto dal kernel, il software non può crearlo.

### 3. Cleanup senza Rimozioni o Check Fallito

```bash
sudo ps5-cachyos-tools status --live
sudo cat /run/ps5-cachyos-tools/boot-cleanup/cleanup.state
sudo journalctl -u ps5-tools-early.service -b --no-pager
sudo journalctl -u ps5-tools-boot.service -b --no-pager
```

Un `NO_ACTION` è normale se non ci sono record eliminabili; un aumento di `rejected` richiede di esaminare gli input, non di ampliare indiscriminatamente la pulizia. Se `cleanup.state` non esiste, verifica che sia avvenuto almeno un boot con `ps5-tools-early.service` abilitato e che il modulo non sia stato disabilitato. Il `check` del cleanup richiede la presenza di quello stato.

---

## 🧪 Suite di Test Automatizzata (Hardware-Free)

```bash
bash tests/run-tests.sh
```

La suite comprende test con sensori e `target_temp` simulati, profili, stati termici, gestione degli errori, installazione e rollback, lifecycle del framework e casi di sicurezza del modulo cleanup. I test sono **simulati**: non dimostrano temperature, RPM, rumore, throttling né la compatibilità dei driver o il corretto avvio su ogni versione di PS5 Linux.

---

## 📋 Requisiti e Limiti

- **Target:** PS5 con una distribuzione Linux già installata, Bash, systemd e gli strumenti di base usati dagli script. Il controller fan richiede un'interfaccia kernel `ps5-fan/target_temp` e sensori supportati.
- **Installazione offline:** host Linux con privilegi amministrativi, `git` per ottenere il repository, utilità standard (`findmnt`, `flock`, `realpath` e coreutils) e rootfs **già montata**.
- **Partizione di boot:** opzionale per `fan` e `boot-cleanup`; il progetto non formatta, migra o ripara automaticamente partizioni.
- **Sessioni grafiche:** i test automatici non sostituiscono prove su PS5 con display collegato. Il software rileva readiness DRM ed errori di processo, ma non artefatti di colore né la qualità effettiva dell'handshake HDMI.
- **Perimetro:** nessuna modifica automatica alla configurazione di rete. Il cleanup non sostituisce `fsck`, un recupero di sistema o la diagnosi di errori hardware.

---

## ⚖️ Dichiarazione di Non Affiliazione e Disclaimer Legale

Progetto open source indipendente e non ufficiale, **non affiliato né approvato da Sony Interactive Entertainment Inc. o dal team CachyOS**. PlayStation e PS5 sono marchi dei rispettivi titolari, citati esclusivamente per identificare l'hardware interessato. Il repository non distribuisce firmware, chiavi proprietarie, immagini Linux o strumenti di exploit.

L'utente è responsabile di backup, scelta delle partizioni e verifiche su hardware reale. Le operazioni di amministrazione richiedono privilegi elevati e devono essere eseguite soltanto su sistemi di cui si possiede l'autorizzazione alla modifica.
