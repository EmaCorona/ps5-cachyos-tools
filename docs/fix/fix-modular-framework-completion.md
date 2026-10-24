# Completamento del framework modulare

## Problema

Il primo refactor introdusse discovery e runner, ma lasciava fuori dalla transazione gli artefatti dei moduli e le unit core, nascondeva gli errori di copia degli hook e non rendeva autosufficiente la CLI installata. Lo stato `once` poteva inoltre perdere il completamento quando il modulo veniva disabilitato.

## Correzione applicata

- Le unit `early` e `normal` hanno un ordinamento esplicito e `early` disabilita le dipendenze predefinite per evitare il ciclo con `basic.target`.
- I percorsi target vengono validati prima di ogni scrittura; i manifest dichiarano `OWNED_PATHS`, inclusi nello snapshot e nel rollback.
- L'installazione coordina core, CLI, hook, manifest, unit e symlink; gli errori degli hook propagano il codice e attivano il ripristino.
- La CLI viene installata in `/usr/local/bin/ps5-cachyos-tools` con un runtime autosufficiente e dispatch generico per `remove`/`reapply`.
- Lo stato separa il completamento persistente dall'ultimo risultato operativo; gli override `ENABLED`/`RUN_POLICY` sono allowlistati sotto `/etc/ps5-cachyos-tools/modules.d/`.

## File coinvolti

Sono interessati `lib/core/{target,installer,service,registry,state,boot-runner}.sh`, `bin/ps5-cachyos-tools`, le unit systemd, il manifest fan, i test core e la documentazione del framework/modulo.

## Verifica e limiti

Verificati direttamente: sintassi Bash, `git diff --check`, suite core (17 test), suite fan legacy (75 test), staging offline, rollback con failure injection, override, stato once/always e `systemd-analyze verify` su root staging con target systemd stub. ShellCheck non è disponibile nell'ambiente locale; CI remota e test su PS5 reale non sono stati eseguiti.
