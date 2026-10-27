# Gamescope: livello di strip corretto per la patch EDID

Commit sorgente: [`7e0fc79`](https://github.com/EmaCorona/ps5-cachyos-tools/commit/7e0fc799e126dd4b5c44a1f35cc2d8aa4b116a6f) · 2026-10-27.

## Problema

Durante l’installazione live pulita, il build downstream di Gamescope si è interrotto in `prepare()`. Il comando `patch` chiedeva interattivamente un file da modificare e poi ignorava tutti gli hunk; il framework ha annullato la transazione.

## Causa individuata

Gli header del diff usano percorsi come `src/Backends/DRMBackend.cpp`, senza i prefissi `a/` e `b/`. Il PKGBUILD invocava `patch -Np1`, che rimuoveva il componente iniziale `src/` e cercava `Backends/DRMBackend.cpp` dalla radice del sorgente. Il file effettivo è invece `src/Backends/DRMBackend.cpp`.

## Correzione applicata

Il PKGBUILD applica ora la patch con `patch -Np0`, mantenendo il percorso completo dichiarato dagli header. Il test della patch controlla anche che il livello di strip configurato nel PKGBUILD resti coerente con la patch.

Il rollback della seconda installazione live è stato verificato: nessun modulo è rimasto registrato, `ps5-cachyos-gamescope` e le dipendenze temporanee di build non risultavano installati e il valore `/boot/efi/vram.txt` è rimasto `0x140000000`.

## File coinvolti

| File | Modifica |
|---|---|
| `packaging/gamescope/PKGBUILD` | Corretto il livello di strip per gli header della patch EDID. |
| `tests/gamescope-upstream-patch-tests.sh` | Aggiunta l’asserzione sul comando `patch` del PKGBUILD. |
| `docs/modules/gamescope.md` | Documentato il livello di strip applicato dal build downstream. |
| `packaging/gamescope/README.md` | Documentata la correzione applicata durante `prepare()`. |

## Verifica e limiti

- La suite completa `tests/run-tests.sh` è passata: 88 test superati, 0 falliti.
- `tests/gamescope-upstream-patch-tests.sh` è passato sul commit upstream `e6674a98118ca7b098b98a3874b8f195ae1bf750`.
- `makepkg --printsrcinfo` e `git diff --check` sono passati.
- Il controllo diretto del comando `patch` non era eseguibile dopo il rollback, perché `patch` era stato rimosso insieme al bootstrap temporaneo `base-devel`; la successiva installazione live deve verificare l’applicazione reale e la compilazione.
- La nuova installazione live è ancora da completare e verificare, così come i controlli hardware al boot.
