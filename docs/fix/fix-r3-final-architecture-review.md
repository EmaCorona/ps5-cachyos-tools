# MOD-R3 final architecture review

## Scope

Chiusura dei rilievi MOD-R3-01…11 della revisione finale del framework modulare. Il refactor conserva il controller fan standalone, la CLI legacy, i profili e la macchina a stati termica.

## Correzioni

- Copie identity-aware per core, manifest, hook, unit e adapter fan; reinstallazione dalla CLI installata sulla stessa rootfs idempotente.
- Lifecycle systemd centralizzato nel framework: un modulo `service` disabilitato non viene avviato e un fan gestito dal framework non esegue `enable --now` dall'adapter.
- Recovery reapply associato all'identificatore persistente della richiesta; una richiesta B non può consumare lo stato `APPLIED(A)`.
- `FAILURE_POLICY` applicata anche a dipendenze bloccate, timeout e hook mancanti; budget globale del runner.
- Override orphan conservati e ignorati nella discovery; override invalidi dei moduli esistenti restano errori.
- Snapshot di remove fan esteso a configurazione, stato e profili utente per rollback di `--purge-config`.
- Validazione delle dipendenze installate estesa a manifest, hook, contenuto, tipo e permessi; wants-link systemd verificati per identità esatta.
- Contratto opzionale `READINESS_HOOK` per service live.

## Verifiche

- Suite core: 53 test superati, 0 falliti.
- Suite fan: 77 test superati, 0 falliti.
- Sintassi Bash, `git diff --check` e verifica unit systemd in rootfs di staging: PASS.
- CI GitHub Actions e review indipendente devono essere eseguite sulla versione committata finale.
- Boot, sensori, RPM, temperature, Gamescope/KDE e comportamento termico restano da verificare sulla PS5 reale.
