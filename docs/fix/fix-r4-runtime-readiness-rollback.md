# Fix R4 — runtime, readiness e rollback

La revisione R4 ha richiesto di chiudere i percorsi di aggiornamento live e di rimozione che potevano lasciare uno stato amministrativo incoerente.

- Il controller fan segnala al lifecycle generico il cambio degli artefatti runtime tramite `CORE_RUNTIME_CHANGED_FILE`; il core distingue il cambio della unit dal cambio del processo ed esegue un solo restart.
- `modules/fan/readiness.sh` riusa `module_fan_wait_ready`, verifica PID/istanza/cicli e profilo applicato. `DEGRADED` è un warning osservabile, non un comando di arresto del raffreddamento.
- Il preflight valida esistenza, tipo regolare e permessi eseguibili di ogni `READINESS_HOOK` dichiarato.
- Lo snapshot install include tutti gli artefatti fan, configurazioni e profili creati dall'adapter; il marker runtime temporaneo viene rimosso durante il rollback.
- Lo snapshot remove include la richiesta reapply pendente; il remove la annulla dopo l'hook e il rollback la ripristina in caso di errore.
- La deduplicazione delle unit systemd confronta il primo campo strutturato invece di trattare `^` come testo letterale con `grep -F`.

La suite R4 verifica readiness preflight, remove con request pendente e fallimento dopo l'hook fan.
