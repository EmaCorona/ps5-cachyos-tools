# Rifiuto delle destinazioni-directory nell'installazione fan

- Commit: [`62beb947300686ab3748ac0cf8e12dd4beaae931`](https://github.com/EmaCorona/ps5-cachyos-tools/commit/62beb947300686ab3748ac0cf8e12dd4beaae931)
- Data: 2026-10-26

## Problema

La fixture di aggiornamento creava una directory al percorso della regola udev per forzare un'installazione fallita. L'helper di copia poteva però trattare quella directory come contenitore: il file temporaneo finiva al suo interno e il successivo `chmod` cambiava i permessi della directory. La suite riportava i test come superati, ma il trap finale non riusciva a rimuovere il residuo (`Permission denied`).

Questo difetto riprodotto spiega l'anomalia del test di rollback, ma non dimostra la causa dell'errore fan hardware segnalato in precedenza: il relativo stack trace non è disponibile nel repository né nel journal della unit del controller.

## Causa individuata

`module_fan_install_copy()` rifiutava i symlink finali ma non gli altri tipi non regolari. `module_fan_restore_copy()` usava `mv -f` verso un percorso descriptor-relative; quando il nome esistente era una directory, GNU `mv` interpretava la directory come destinazione contenitore e vi spostava il temporaneo. Il `chmod` successivo operava quindi sulla directory stessa.

## Correzione applicata

L'helper di installazione rifiuta una destinazione esistente che non sia un file regolare. Le sostituzioni atomiche usano `mv -fT`, il link usa `ln -sT`, così ogni operazione tratta il nome come percorso esatto anche in caso di directory preesistente o comparsa concorrente. Il test controlla che il rollback conservi la directory `0755`, vuota, e gli artefatti persistenti preesistenti.

## File coinvolti

| File | Responsabilità |
|---|---|
| `lib/modules/fan.sh` | Rifiuta target non regolari e impone le operazioni atomiche sul percorso esatto. |
| `tests/run-tests.sh` | Verifica rollback, permessi, assenza di file residui e fixture deterministica rispetto all'`umask`. |
| `docs/modules/fan.md` | Documenta il comportamento di copia e rollback. |

## Verifica e limiti

- Riproduzione isolata su root temporanea prima della correzione: copia terminata con codice `0`, directory trasformata in `0644` e file temporaneo annidato; dopo la correzione la destinazione viene rifiutata e la directory resta `0755` e vuota.
- `tests/run-tests.sh` con `umask 077`: PASS, 78 test superati e 0 falliti; include 18 test boot-cleanup e il caso di rollback aggiornato.
- `tests/core/run-tests.sh`: PASS, 56 test core e 20 test R4 superati, 0 falliti.
- `bash -n` sugli script shell e `git diff --check`: PASS.
- Hardware: DMI identifica una PS5 Sony CFI-2016 B01Y. Il framework di questo repository non è installato, `ps5-fan-daemon.service` non è presente e il journal della unit non contiene eventi. `ps5fan.service` dell'installazione è enabled e active/exited; non è stato modificato. Nessun avvio o test del controllo fan fisico è stato eseguito. La causa dell'errore hardware riportato in precedenza resta non determinata in assenza dei suoi log.

Fonti: [commit della correzione](https://github.com/EmaCorona/ps5-cachyos-tools/commit/62beb947300686ab3748ac0cf8e12dd4beaae931), [`module_fan_install_copy()`](../../lib/modules/fan.sh), [suite fan](../../tests/run-tests.sh) e [documentazione del modulo](../modules/fan.md).
