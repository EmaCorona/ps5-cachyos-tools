# Gamescope: selezione del pacchetto principale dopo makepkg

Commit sorgente: [`64c2fd6`](https://github.com/EmaCorona/ps5-cachyos-tools/commit/64c2fd6a4ef023402467a0bdc49465c693db60b7) · 2026-10-27.

## Problema

La build Gamescope e la creazione del pacchetto principale terminavano, ma il helper rifiutava il risultato perché `makepkg` produceva anche `ps5-cachyos-gamescope-debug`.

## Causa individuata

Il helper cercava un archivio tramite prefisso del nome e prendeva il primo risultato, senza controllare i metadati pacman. Il pacchetto debug condivide il prefisso e può essere restituito per primo.

## Correzione applicata

La ricerca ora ispeziona i metadati di ogni archivio candidato e accetta solo quello il cui nome pacman è esattamente `ps5-cachyos-gamescope`. Un test con entrambi gli archivi verifica che il pacchetto debug venga ignorato.

## File coinvolti

| File | Modifica |
|---|---|
| `modules/gamescope/files/ps5-gamescope-package` | Selezione dell’archivio tramite nome dichiarato nei metadati pacman. |
| `tests/gamescope-package-tests.sh` | Caso regressione con pacchetto principale e pacchetto debug. |
| `docs/modules/gamescope.md` | Documentato il filtro del pacchetto buildato. |
| `packaging/gamescope/README.md` | Documentata la selezione del pacchetto principale. |

## Verifica e limiti

- `tests/gamescope-package-tests.sh` e `bash -n` sui file interessati sono passati.
- Il tentativo live precedente ha compilato e creato entrambi i pacchetti ma è stato annullato prima dell’installazione; il nuovo tentativo dovrà verificare build, installazione e configurazione completa.
