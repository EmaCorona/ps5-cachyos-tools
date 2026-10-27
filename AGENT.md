# Istruzioni per gli agenti AI

## Ambito di questo repository

Questo repository contiene il framework modulare PS5 e il controller ventole, con documentazione/test relativi. Le istruzioni che nominano moduli del patcher originale si applicano soltanto come principi di processo: non copiare né modificare `cleanup.sh`, altri moduli o la pipeline di `ps5-cachy-os-patch`. Il modulo ventole deve rimanere installabile e disinstallabile in autonomia; nuovi moduli devono essere scoperti tramite manifest e non tramite liste hardcoded.

Questo file raccoglie le regole operative condivise per gli agenti AI che analizzano o modificano il repository. Le istruzioni sono organizzate in sezioni indipendenti, così da poterle ampliare nel tempo senza stravolgere la struttura esistente.

## Regola obbligatoria: Gitflow per ogni nuova feature, fix o branch di documentazione

**Ogni feature, fix o modifica alla documentazione deve essere implementata su un branch dedicato creato da `develop`. Non sviluppare direttamente su `develop` o `main`. `main` rappresenta la linea stabile: vi si integra soltanto una versione stabile e funzionante delle funzionalità già incluse, anche se il progetto non contiene ancora tutte le funzionalità pianificate.**

### Flusso operativo obbligatorio

1. **Parti da `develop` aggiornato.** Prima di iniziare, recupera lo stato remoto più recente e crea il branch di lavoro a partire da `origin/develop` (o dal `develop` locale verificato e aggiornato). `main` non è la base dei branch di lavoro.
2. **Crea un branch con il prefisso corretto.** Usa `feature/<slug-descrittivo>` per una nuova funzionalità, `fix/<slug-descrittivo>` per una correzione e `docs/<slug-descrittivo>` per modifiche o aggiunte alla documentazione. Scegli uno slug breve e specifico, coerente con lo stile Git del repository. Se esiste già un branch per lo stesso lavoro, verifica che sia quello giusto prima di riutilizzarlo.
3. **Sviluppa esclusivamente sul branch dedicato e sincronizza sempre il remoto.** Implementazione, test e documentazione correlata devono essere aggiunti lì. Non fare commit diretti su `develop` o `main`, non spostare questi branch e non integrare in anticipo modifiche solo perché i test automatici passano. Esegui la suite di test locale prima di ogni push. Se un test fallisce, individua e correggi la causa, quindi ripeti i test; pusha soltanto quando tutti i test applicabili passano. Non dichiarare superati test non eseguiti o non applicabili senza motivarlo. **Ogni commit creato in locale sul branch dedicato deve essere pushato sul corrispondente branch remoto (`origin/feature/...`, `origin/fix/...`, `origin/docs/...`) solo dopo questa verifica.** Non lasciare commit solo in locale.
4. **Mantieni documentazione e test nello stesso lavoro.** Per ogni fix rispetta la regola di documentazione in `docs/fix/` e aggiorna `docs/fix/README.md`; se sono interessati moduli, aggiorna anche le relative schede in `docs/modules/`. Aggiungi o aggiorna i test pertinenti e non dichiarare verifiche mai eseguite.
5. **Concludi l'implementazione senza fare merge.** Rivedi il diff, esegui le verifiche disponibili e comunica all'utente il branch, il riepilogo delle modifiche e i risultati dei test, distinguendo i test automatici dalle prove richieste sull'hardware reale. Lascia le modifiche sul branch dedicato (pushato su remoto) in attesa che l'utente possa testarle.
6. **Attendi l'approvazione esplicita dell'utente.** Il merge verso `develop` o `main` è vietato fino a quando l'utente non ha revisionato il lavoro e dato chiaramente l'OK all'integrazione. Test verdi, CI superata, una richiesta di implementazione o il silenzio dell'utente non equivalgono ad autorizzazione. Se l'OK non è stato dato, non fare merge, non chiudere il lavoro come integrato e non cancellare il branch.
7. **Dopo l'OK, prepara l'integrazione.** Per il normale sviluppo, integra il branch di lavoro in `develop`; porta il contenuto da `develop` a `main` solo quando la versione risultante è stabile e tutte le funzionalità già incluse sono funzionanti. Controlla che il branch di destinazione sia aggiornato, risolvi eventuali conflitti senza perdere il comportamento approvato ed esegui nuovamente i test locali prima del push.
8. **Prima di integrare, riduci il lavoro a un solo commit.** Tutti i commit appartenenti alla feature/fix/docs devono essere consolidati in un unico commit che rappresenti l'intero cambiamento approvato. Nel branch di destinazione deve arrivare un solo commit per quella feature/fix/docs, non la sequenza dei commit intermedi. Usa la modalità di squash/integrazione equivalente disponibile nel flusso Git del repository e verifica il risultato prima di aggiornare `develop` o, per una versione stabile, `main`.
9. **Scrivi un nuovo messaggio di commit descrittivo.** Il messaggio deve seguire lo stile del repository (per esempio `fix(area): descrizione della correzione`, `feat(area): descrizione della funzionalità` o `docs(area): descrizione della documentazione`) e spiegare il risultato ottenuto. **Non scrivere nel titolo o nel corpo che i commit sono stati squashati, accorpati o riscritti**, né indicare quanti commit originali erano presenti. Il messaggio deve descrivere esclusivamente la feature/fix/docs realizzata.
10. **Verifica il risultato dopo l'integrazione e pusha sul branch di destinazione.** Conferma che il commit sia pertinente, che documentazione e test siano inclusi e che il branch punti al risultato atteso. Riesegui i test locali prima di ogni push; poi pubblica il branch aggiornato su `origin` e comunica all'utente il commit finale e il link GitHub.
11. **Eliminazione del branch di lavoro integrato in `develop`.** Dopo aver integrato un branch di lavoro (`feature/*`, `fix/*`, `docs/*` o altro branch temporaneo) in `develop` e aver pubblicato con successo `develop`, elimina quel branch sia localmente sia da `origin`, salvo richiesta esplicita di conservarlo. La pulizia si applica ai branch integrati in `develop`, non a quelli integrati direttamente in `main`. I branch permanenti `develop` e `main` devono essere mantenuti.

**Regola universale di eliminazione:** ogni branch di lavoro integrato in `develop` deve essere eliminato dopo il push riuscito di `develop`, indipendentemente dal tipo o dal prefisso. La regola si applica anche a branch `chore/*`, `test/*`, `hotfix/*` e branch temporanei; vale sia localmente sia su `origin`. Non eliminare branch non integrati né branch integrati soltanto in `main`. `develop` e `main` sono branch permanenti e non devono essere eliminati.

### Regola specifica per i branch di documentazione (`docs/*`)

I branch con prefisso `docs/` seguono l'intero flusso Gitflow sopra descritto (partenza da `develop`, branch dedicato, test locali prima del push, divieto di merge anticipato, attesa approvazione esplicita dell'utente, squash a singolo commit prima del merge su `develop`).
A essi si applica una **regola tassativa aggiuntiva**:
- **Nei branch `docs/*` possono essere creati o modificati ESCLUSIVAMENTE file di documentazione** (come file Markdown `.md`, schede in `docs/`, `README.md`, guide e diagrammi).
- **È SEVERAMENTE VIETATO toccare, creare o modificare qualsiasi file contenente codice** (inclusi script shell `.sh`, sorgenti C/C++, Makefile, file di servizio systemd, configurazioni di sistema, ecc.), **neanche per cambiare commenti o docstring all'interno del codice sorgente**. Qualsiasi modifica che tocchi codice, commenti nel codice o file eseguibili deve obbligatoriamente passare da un branch `feature/` o `fix/`.

### Regola generale per ogni richiesta di squash

Ogni volta che l'utente chiede di squashare dei commit, applica sempre lo stesso criterio: crea un nuovo commit con un messaggio significativo e coerente con il contenuto effettivo delle modifiche, senza fare alcun riferimento allo squash o alla storia precedente dei commit. Non riutilizzare automaticamente un messaggio che descriva l'operazione Git invece del cambiamento prodotto.

### Eccezioni

Non saltare il branch dedicato o l'attesa di approvazione per comodità o per velocizzare il lavoro. Un'eventuale deroga è consentita soltanto quando l'utente la richiede esplicitamente. Le modifiche al solo documento di istruzioni richieste direttamente dall'utente possono essere applicate al branch su cui l'utente ha chiesto di aggiornarle; questa eccezione non autorizza a sviluppare feature/fix direttamente su `develop` o `main`.

## Regola obbligatoria: mantenere aggiornata la documentazione dei moduli

**Ogni volta che modifichi un modulo, aggiorna nella stessa modifica anche il relativo file di documentazione.** Questa regola è obbligatoria e si applica a modifiche funzionali, correzioni di bug, refactoring che cambiano il comportamento, aggiunte o rimozioni di opzioni, dipendenze, file generati, servizi o configurazioni.

Procedura da seguire:

1. **Individua la documentazione associata.** Consulta [`docs/modules/README.md`](docs/modules/README.md) per identificare il documento del modulo interessato.
2. **Aggiorna il documento del modulo.** Mantieni le informazioni coerenti con il codice effettivo, includendo quando pertinenti scopo, sequenza operativa, file e servizi coinvolti, variabili d'ambiente, dipendenze, condizioni di applicabilità, limiti, verifiche e comandi diagnostici.
3. **Aggiorna gli indici quando necessario.** Se aggiungi, rimuovi o rinomini un modulo, aggiorna anche l'indice `docs/modules/README.md`. Se cambia una funzionalità o un'informazione descritta nel README principale, aggiorna anche `README.md`.
4. **Mantieni codice e documentazione allineati.** Le modifiche al codice e alla documentazione correlata devono far parte dello stesso insieme di modifiche/commit; non rimandare la documentazione a un'attività successiva.
5. **Verifica il risultato.** Rileggi il diff, controlla i collegamenti Markdown e accertati che il documento descriva il comportamento realmente implementato. Esegui le verifiche disponibili e dichiara chiaramente eventuali test non eseguiti.

Se un modulo non dispone ancora di una scheda documentale, creala in `docs/modules/` seguendo lo stile delle schede esistenti e aggiungila all'indice. Non inventare comportamenti o risultati di test che non siano stati verificati.

## Regola obbligatoria: documentare ogni fix e aggiornare lo storico

**Ogni volta che realizzi una fix, devi documentarla in `docs/fix/` e aggiornare lo storico centrale.** La regola si applica a ogni correzione di bug, comportamento errato, regressione, errore di avvio, problema di compatibilità o caso limite, anche quando la modifica interessa più moduli. Non considerare conclusa una fix finché il codice, la documentazione del modulo interessato e lo storico delle fix non sono coerenti.

### Procedura obbligatoria

1. **Analizza la correzione reale.** Esamina il diff e identifica il sintomo, la causa tecnica supportata dalle evidenze, il comportamento precedente e quello corretto. Non limitarti a riscrivere il messaggio del commit: il testo deve spiegare cosa accadeva e perché la modifica risolve il problema.
2. **Crea una scheda dedicata per ogni fix logica.** Aggiungi un file Markdown in `docs/fix/`, seguendo struttura, chiarezza e livello di dettaglio delle schede già presenti. Usa il nome `fix-<sha12>-<slug-descrittivo>.md` quando lo SHA del commit di correzione è noto; lo slug deve essere breve, leggibile e specifico. Non accorpare fix indipendenti in una singola scheda.
3. **Mantieni lo standard documentale esistente.** Includi, quando applicabili:
   - titolo chiaro che descriva il problema corretto;
   - SHA completo o abbreviato del commit sorgente con collegamento GitHub, data e file principali coinvolti;
   - sezione **Problema** che descriva sintomi e impatto prima della fix;
   - sezione **Causa individuata** che spieghi il motivo tecnico, separando i fatti verificati dalle ipotesi;
   - sezione **Correzione applicata**, con i passaggi concreti e il comportamento risultante;
   - sezione **File coinvolti**, preferibilmente in tabella con percorso e responsabilità della modifica;
   - sezione **Verifica e limiti**, con test effettivamente eseguiti, risultati verificati, ciò che non è stato testato e le dipendenze dall'hardware o dall'ambiente;
   - collegamento alla fonte primaria (commit/diff) e ai sorgenti correnti pertinenti.
4. **Aggiorna sempre l'indice dello storico.** Aggiungi una voce in `docs/fix/README.md` con data, commit, descrizione concisa del problema e collegamento alla nuova scheda. Mantieni l'ordine cronologico inverso, evita duplicati e verifica che il collegamento funzioni. Se il file non esiste ancora, crealo con lo stesso stile degli indici già presenti.
5. **Mantieni aggiornati gli altri documenti interessati.** Applica anche la regola della documentazione dei moduli: aggiorna le schede in `docs/modules/` quando la fix cambia il loro comportamento. Aggiorna `README.md` se cambia una descrizione o una procedura destinata agli utenti. L'indice `docs/fix/README.md` non sostituisce la documentazione specifica dei moduli.
6. **Gestisci correttamente lo SHA.** Non inventare commit, date, risultati o link e non lasciare placeholder permanenti. Se lo SHA definitivo della correzione non è ancora disponibile, prepara la scheda con il contenuto verificato e completa il riferimento non appena il commit sorgente è definitivo. Poiché un commit non può contenere in modo stabile il proprio SHA nel contenuto che determina quello stesso SHA, quando serve un riferimento esatto organizza la correzione in modo che il commit di codice sia identificabile prima del successivo aggiornamento documentale, oppure aggiungi il riferimento esatto in un commit documentale successivo.
7. **Verifica prima di concludere.** Controlla la corrispondenza tra scheda e diff, la presenza della voce nell'indice, tutti i link relativi e GitHub, e lo stato finale dei file. Esegui i test disponibili pertinenti alla fix; distingui chiaramente i test automatici simulati dalle prove eseguite su hardware reale e dichiara quelli non eseguiti.

### Requisito di completamento

Una fix è documentata soltanto quando la scheda in `docs/fix/` e la voce in `docs/fix/README.md` sono state aggiunte o aggiornate, la documentazione del modulo interessato è allineata e i riferimenti sono stati verificati. Mantieni il livello di precisione, la struttura e il tono tecnico delle schede già presenti: descrizioni concrete e verificabili, nessuna affermazione non dimostrata e nessun test dichiarato come superato senza averne osservato il risultato.

## Gestione degli errori del controller

Questo repository non contiene la pipeline di patching host né moduli di cleanup del progetto originale. Gli errori del controller ventole devono essere gestiti dai propri artefatti: lock in `/run/ps5-fan`, stato runtime atomico, stato `DEGRADED`, disinstallazione dei soli file di proprietà e test deterministici. Non creare o importare componenti di boot cleanup estranei al controller.

## Regola per il recovery manuale Steam in `boot-cleanup`

Il recovery della cartella dump Steam deve restare un helper on-demand del modulo `boot-cleanup`, distinto dall'hook `early/always`. Non eseguirlo automaticamente dal boot hook. Prima di modificare `/tmp/dumps`, verificare in modo mirato che `steam` e `steamwebhelper` non siano attivi; se il controllo manca o restituisce un errore, interrompersi senza modifiche. Operare solo con l'UID dell'utente `steam`; intervenire solo sulla directory regolare `/tmp/dumps` posseduta da tale UID, normalizzando i permessi a `700` solo quando non sono già `700` o `1700`. È consentito creare la directory se manca; non cancellare, svuotare o sostituire una directory esistente, né rimuovere dump, log o marker `.crash`. Il marker `.crash` da solo non dimostra che la pulizia sia necessaria. Aggiornare insieme helper, test e `docs/modules/boot-cleanup.md` quando si cambia questa regola.

## Come estendere questo file

Per aggiungere nuove regole in futuro:

- crea una nuova sezione di primo livello usando un'intestazione Markdown `## Titolo della sezione`;
- raggruppa nella stessa sezione istruzioni che riguardano un unico ambito, con indicazioni concrete e verificabili;
- evita di duplicare regole già presenti: se una regola esistente cambia, aggiornala nella sua sezione invece di creare indicazioni contraddittorie;
- mantieni le istruzioni valide a livello di repository qui; le procedure specifiche di un singolo modulo vanno nella documentazione del modulo corrispondente.

Le sezioni nuove possono essere aggiunte dopo quelle esistenti senza modificare la regola obbligatoria sulla documentazione, a meno che una revisione esplicita non ne aggiorni il contenuto.
