# Hardening architetturale e isolamento dei target

**Commit sorgente:** [`0853437`](https://github.com/EmaCorona/ps5-cachyos-tools/commit/0853437)
**Data:** 24 ottobre 2026

## Problema

La review finale aveva rilevato rischi P0/P1 nel confine della rootfs, nella validazione dei manifest, nel lifecycle systemd, nel rollback selettivo e nel consumo delle richieste `reapply`. La CI precedente non esercitava tutti questi casi.

## Causa individuata

- La costruzione dei percorsi per `root=/` produceva doppi slash durante il controllo degli antenati.
- Un symlink finale poteva essere validato senza una policy esplicita del tipo di artefatto; l'adapter fan preparava directory e profili senza un preflight completo degli antenati.
- Il resolver consumava una process substitution e non verificava in modo affidabile il codice dell'ordinamento.
- Il registry non imponeva la matrice `TYPE`/`BOOT_PHASE`, l'unicità delle unità e la coerenza unità/ownership.
- Lo snapshot includeva tutti i moduli scoperti e il rollback live duplicava il ripristino delle unità core.
- `ENABLED=false`, rimozione, request reapply e riconoscimento live non avevano una riconciliazione completa.

## Correzione applicata

- Percorsi live/offline normalizzati e symlink finali limitati ai wants-link systemd previsti; il live su host non riconosciuto viene rifiutato salvo `PS5_TOOLS_ALLOW_LIVE=1`.
- L'adapter fan verifica directory, file, manifest e profili prima di creare o sovrascrivere artefatti.
- Il resolver separa esecuzione, exit code e consumo dell'ordine topologico.
- I manifest rifiutano combinazioni di fase non eseguibili, unità duplicate/riservate e ownership incoerente.
- Snapshot, rollback e rimozione verificano gli artefatti effettivamente coinvolti; le directory framework create dalla transazione vengono ripulite senza includere moduli indipendenti.
- Il lifecycle service riconcilia disabilitazione, unità e stato; il restore systemd usa una sola fonte per unità.
- Le request `reapply` persistono le fasi `REQUESTED`, `RUNNING`, `APPLIED` e `COMPLETED`, registrano l'identificatore applicato e, dopo un crash post-successo, vengono consumate senza rieseguire l'hook; una nuova request resta rieseguibile.

## File coinvolti

| Area | File | Responsabilità |
|---|---|---|
| Target e sicurezza | `lib/core/target.sh`, `lib/modules/fan.sh` | confini rootfs, symlink e preflight adapter |
| Registry e dipendenze | `lib/core/registry.sh`, `lib/core/dependencies.sh` | matrice manifest, ownership e topological ordering |
| Transazioni | `lib/core/installer.sh`, `lib/core/service.sh` | snapshot selettivo, rollback e lifecycle service |
| Stato e CLI | `lib/core/state.sh`, `lib/core/boot-runner.sh`, `bin/ps5-cachyos-tools` | recovery reapply, diagnostica e dry-run |
| Test | `tests/core/run-tests.sh`, `tests/run-tests.sh` | regressioni manifest/symlink/live/profiles |
| Contratto | `README.md`, `docs/architecture.md`, `docs/module-api.md`, `docs/modules/fan.md` | semantica aggiornata |

## Verifica e limiti

Eseguiti direttamente:

- `bash -n` su sorgenti e test: PASS.
- Suite core: **47 test superati, 0 falliti**.
- Suite fan: **77 test superati, 0 falliti**.
- `git diff --check`: PASS.
- `systemd-analyze verify` su root staging con unit e runner: PASS.

ShellCheck locale non disponibile; la pipeline CI deve eseguire il controllo remoto. Boot, driver, sensori, temperature, RPM e comportamento termico reale sulla PS5 restano da verificare su hardware.

## Fonte primaria

[Diff del commit `0853437`](https://github.com/EmaCorona/ps5-cachyos-tools/commit/0853437)
