# Verifica dei symlink nel rootfs

- Commit: [`ab7054b`](../../commit/ab7054b)
- Data: 2026-10-24

## Problema e causa

La diagnostica usava `-e` sul symlink assoluto del target systemd e poteva segnalare erroneamente un'installazione valida come incompleta.

## Correzione e verifica

`module_fan_check` usa `-L` e confronta il target con il percorso atteso; controlla inoltre il file di profilo persistente. Il controllo è stato eseguito su rootfs temporaneo.

## File coinvolti

| File | Responsabilità |
|---|---|
| `lib/modules/fan.sh` | verifica artefatti, symlink e stato persistente |

Fonte primaria: [commit ab7054b](../../commit/ab7054b) e il relativo diff nel repository locale.
