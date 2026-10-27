# Gamescope: percorso del binario nel packaging Meson

Commit sorgente: [`b83135d`](https://github.com/EmaCorona/ps5-cachyos-tools/commit/b83135da2e82aefd5675f7d4b0633055ce2de8ec) · 2026-10-27.

## Problema

La compilazione di Gamescope terminava con successo, ma la fase `package()` falliva perché non trovava il binario da installare.

## Causa individuata

Il PKGBUILD esegue `arch-meson gamescope build` dalla radice della directory sorgente. Meson crea quindi il binario in `build/src/gamescope`, mentre `package()` cercava `gamescope/build/src/gamescope`.

## Correzione applicata

Il percorso usato da `package()` ora corrisponde alla directory di build effettiva. Il test del PKGBUILD verifica esplicitamente questo percorso insieme al livello di strip della patch EDID.

## File coinvolti

| File | Modifica |
|---|---|
| `packaging/gamescope/PKGBUILD` | Installa il binario dalla directory `build/` di Meson. |
| `tests/gamescope-upstream-patch-tests.sh` | Impedisce regressioni sul percorso del binario e sulla patch EDID. |
| `docs/modules/gamescope.md` | Descrive i percorsi del build privato. |
| `packaging/gamescope/README.md` | Documenta il layout Meson usato dal packaging. |

## Verifica e limiti

- Il test mirato sul sorgente upstream Gamescope 3.17.0 è passato.
- `makepkg --printsrcinfo`, `bash -n` sul test e `git diff --check` sono passati.
- Il precedente tentativo live ha compilato Gamescope, ma è fallito nel packaging; la nuova installazione live deve verificare che il pacchetto venga creato e installato.
