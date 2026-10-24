# Validazione configurazione e CLI

- Commit: [`e63668e`](../../commit/e63668e)
- Data: 2026-10-24

## Problema e causa

Parametri numerici non validi e fallimenti della selezione profilo potevano essere accettati senza un errore esplicito.

## Correzione e verifica

Il demone valida i parametri e la CLI propaga gli errori di scrittura. La suite include configurazione numerica invalida e fallimento CLI; il risultato corrente è 16 test superati, 0 falliti.

## File coinvolti

| File | Responsabilità |
|---|---|
| `bin/ps5-fan-daemon` | validazione dei parametri |
| `bin/ps5-fan` | propagazione degli errori CLI |

Fonte primaria: [commit e63668e](../../commit/e63668e) e il relativo diff nel repository locale.
