# Rifiuto della configurazione hardware invalida

- Commit: [`23652e7`](../../commit/23652e7)
- Data: 2026-10-24

## Problema e causa

Profilo, `ENABLE_PWM` e percorsi hardware non validi non erano tutti rifiutati prima del loop.

## Correzione e verifica

La configurazione viene validata prima di leggere lo stato persistente e i test coprono profilo e `ENABLE_PWM` invalidi. L'hardware PS5 reale resta non verificato.

## File coinvolti

| File | Responsabilità |
|---|---|
| `bin/ps5-fan-daemon` | validazione profile, PWM e percorsi hardware |
| `tests/run-tests.sh` | casi avversari di configurazione |

Fonte primaria: [commit 23652e7](../../commit/23652e7) e il relativo diff nel repository locale.
