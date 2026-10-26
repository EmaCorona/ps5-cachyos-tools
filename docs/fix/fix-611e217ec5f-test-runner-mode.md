# Ripristino del bit eseguibile del test runner

- Commit: [`611e217ec5f816f1f164f6bb08f3f06087b0dfbf`](https://github.com/EmaCorona/ps5-cachyos-tools/commit/611e217ec5f816f1f164f6bb08f3f06087b0dfbf)
- Data: 2026-10-26

## Problema

Dopo la pubblicazione del branch, `./tests/run-tests.sh` terminava con `Permission denied`. L'invocazione esplicita `bash tests/run-tests.sh` continuava a funzionare, ma il test runner non rispettava il mode eseguibile presente nel branch locale e richiesto dall'uso diretto documentato.

## Causa individuata

Durante il ripristino del contenuto trasferito incompleto, l'elemento `tests/run-tests.sh` del tree remoto è stato creato con mode Git `100644`, sebbene il blob fosse corretto e il file fosse `100755` nel checkout locale. La modalità era quindi un errore di pubblicazione del tree, non un difetto del contenuto dello script.

## Correzione applicata

Il commit sorgente imposta il mode Git di `tests/run-tests.sh` a `100755` senza modificare il blob. Il branch remoto è stato letto nuovamente e `git ls-tree` conferma `100755` con blob `17f376d0a1cefdb370ae80f2547f99ef4b474b4e`.

## File coinvolti

| File | Responsabilità |
|---|---|
| `tests/run-tests.sh` | Mode Git ripristinato da `100644` a `100755`; contenuto invariato. |

## Verifica e limiti

- Prima della correzione, `./tests/run-tests.sh` falliva con `Permission denied`; `bash tests/run-tests.sh` passava.
- Dopo la correzione, `test -x tests/run-tests.sh` passa e `umask 077 ./tests/run-tests.sh` termina con 78 test superati e 0 falliti.
- `./tests/core/run-tests.sh`: 56 core + 20 R4 superati, 0 falliti.
- Il mode e il blob sono stati verificati sul branch remoto dopo il push; il checkout locale è allineato al remoto.
- Questo fix riguarda solo l'eseguibilità del test runner; non certifica l'esecuzione fisica del controller fan.

Fonti: [commit del ripristino mode](https://github.com/EmaCorona/ps5-cachyos-tools/commit/611e217ec5f816f1f164f6bb08f3f06087b0dfbf), [`tests/run-tests.sh`](../../tests/run-tests.sh).
