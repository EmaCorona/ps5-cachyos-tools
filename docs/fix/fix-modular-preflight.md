# Preflight e ordinamento dell'installazione modulare

## Problema

La prima transazione validava alcune parti del manifest durante l'applicazione. Un grafo non ordinabile o un hook obbligatorio mancante poteva quindi essere scoperto dopo l'inizio delle scritture. Il percorso boot veniva inoltre passato agli hook senza una forma canonicalizzata e un override amministrativo poteva tentare di cambiare la policy di un service.

## Correzione applicata

Il framework ora esegue discovery, validazione delle dipendenze, ordinamento topologico e controllo degli hook richiesti prima dello snapshot. L'applicazione usa lo stesso ordine topologico. Il boot target viene canonicalizzato e associato alla root offline; `REQUIRES_BOOT` viene verificato prima dell'apply. Gli override `RUN_POLICY` dei service sono rifiutati. In live viene memorizzato e ripristinato lo stato di abilitazione/attivazione della unit early in caso di rollback.

## Verifica

Eseguiti sintassi Bash, suite core (17/17), suite fan legacy (75/75), failure injection dell'hook e `git diff --check`. La CI remota, ShellCheck locale e l'avvio su PS5 reale restano non verificati.
