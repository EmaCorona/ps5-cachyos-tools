# Evidenza live CLEAN-01 — 2026-10-26

## Ambiente e precondizioni verificate

- Host reale: Sony PlayStation 5 CFI-2016 B01Y, CachyOS x86_64; esecuzione privilegiata via `sudo -n bash`.
- Hook dal branch `feature/boot-cleanup-migration`: `/home/steam/Development/repository/ps5-cachyos-tools/modules/boot-cleanup/boot.sh / early`.
- Prima del test erano assenti `/etc/ps5-cachyos-tools`, `/run/ps5-cachyos-tools`, `/var/lib/ps5-cachyos-tools` e i percorsi specifici di configurazione, runtime e persistenza (`boot-cleanup.conf`, `cleanup.state`, `steam-stale.list`, `migration.state`). Il test ha interrotto l'esecuzione se uno di questi esisteva.
- PID sintetico `1792972625292865` assente da `/proc`; il relativo file `/run/user/1000/steam-runtime-1792972625292865` era assente prima della creazione. Dopo la creazione era un file regolare posseduto da UID 1000.
- Precondizione di migrazione verificata secondo il codice: il hook confronta l'mtime di ogni `~/.steam/steam.pid` regolare con l'mtime di `migration.state`; non usa il campo `updated_at` per questa decisione. Al test, l'mtime massimo dei file legacy regolari trovati era `1792967566`; l'mtime effettivo (`stat -c %Y`) del marker temporaneo era `1792976225`. Tutti i candidati esistenti erano quindi più vecchi del marker.
- Il marker conteneva `updated_at=1792972625`, valore irrilevante per il confronto. Il suo mtime è stato impostato separatamente a `1792976225`. Nessun file Steam reale è stato modificato.
- Record stale unico: `1792972625292865 0 1000 /run/user/1000/steam-runtime-1792972625292865 steam e2e e2e-test`. `starttime=0` identifica correttamente un processo assente nel ramo del codice; non è un tempo Unix.

## Procedura riproducibile

1. Con privilegi root, verificare che i tre alberi globali e i quattro percorsi specifici sopra elencati non esistano; verificare che PID e sentinella non siano già presenti.
2. Leggere `stat -c %Y` di ogni `/home/*/.steam/steam.pid` regolare non symlinkato. Creare il `migration.state` temporaneo, impostarne l'mtime a un valore futuro con `touch -d @<epoch_futuro>`, poi verificare con `stat -c %Y` che sia maggiore di tutti gli mtime legacy letti.
3. Creare `boot-cleanup.conf` con `DRY_RUN=0` e il solo percorso stale allowlistato; creare la sentinella posseduta da UID 1000 e inserirne l'unico record nel `steam-stale.list`.
4. Eseguire `sudo -n /home/steam/Development/repository/ps5-cachyos-tools/modules/boot-cleanup/boot.sh / early`. Leggere il file `cleanup.state` prodotto e verificare la rimozione della sentinella.
5. Rimuovere solo i file creati dal test e le directory test ormai vuote; verificare che i tre alberi globali siano assenti.

## Stato scritto dal hook

Contenuto effettivo di `cleanup.state` letto subito dopo l'esecuzione:

```text
action=COMPLETED
checked=1
removed=1
would_remove=0
active=0
rejected=0
updated_at=1792972625
```

## Assertion del wrapper e cleanup successivo

Questi dati sono verifiche del wrapper della prova, non contenuto prodotto dal hook:

```text
PRECONDITION pid_absent=yes artifact_absent_before_create=yes migration_mtime=1792976225 latest_regular_steam_pid_mtime=1792967566
sentinel_pid=1792972625292865
sentinel_artifact=/run/user/1000/steam-runtime-1792972625292865
sentinel_removed=yes
LIVE_E2E_BOOT_CLEANUP=PASS
ROOT_COMMAND_EXIT=0
POST_CLEANUP_ABSENT=/etc/ps5-cachyos-tools
POST_CLEANUP_ABSENT=/run/ps5-cachyos-tools
POST_CLEANUP_ABSENT=/var/lib/ps5-cachyos-tools
```

## Valutazione e limiti

Esito **PASS live limitato**: il hook reale ha valutato e rimosso un solo file temporaneo stale (`checked=1`, `removed=1`), senza record attivi o rifiutati. La motivazione della migrazione inerte è dimostrata dal confronto degli mtime, non dal campo `updated_at`. Configurazione, state, lista stale, marker e sentinella sono stati rimossi; il wrapper ha verificato l'assenza degli alberi globali. Il servizio fan alternativo non è stato modificato.

Questa prova non installa né avvia unit del framework, non verifica un boot reale, non esercita file Steam reali e non sostituisce i test di sicurezza su input avversi eseguiti su root temporanee.
