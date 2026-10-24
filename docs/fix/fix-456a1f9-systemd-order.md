# Ordinamento systemd del demone

- Commit: [`456a1f9`](../../commit/456a1f9)
- Data: 2026-10-24

## Problema e causa

Il servizio era agganciato a `multi-user.target` ma dichiarava `After=multi-user.target`, creando un ordinamento circolare nella transazione di avvio.

## Correzione e verifica

L'unità ora usa `After=local-fs.target`. È stato aggiunto un test statico che rifiuta il vecchio ordinamento; la suite corrente esegue 16 test superati e 0 falliti.

## File coinvolti

| File | Responsabilità |
|---|---|
| `systemd/ps5-fan-daemon.service` | ordinamento del servizio |
| `tests/run-tests.sh` | test anti-ciclo |

Fonte primaria: [commit 456a1f9](../../commit/456a1f9) e il relativo diff nel repository locale.
