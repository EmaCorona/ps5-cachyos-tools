# Fix 082e173 — recupero target PS5 e readiness live

## Sintomo

Su hardware PS5 reale il driver può esporre inizialmente un `target_temp` fuori dalla curva supportata (per esempio 89–91). Il daemon restava in `DEGRADED` senza riuscire a scrivere un target sicuro. Inoltre l'health check di una nuova installazione rifiutava indefinitamente una nuova istanza quando non esisteva un PID precedente.

## Causa

Il percorso degradato generava un target solo con readback già valido e il readiness check trattava l'assenza di identificativi precedenti come condizione permanente di attesa.

## Correzione

- con sensore APU valido il daemon seleziona sempre un target fail-safe; usa 28/29 °C in emergenza e `DEGRADED_TARGET` fuori emergenza, quindi verifica il readback nel ciclo successivo;
- il readiness check accetta una nuova istanza quando il servizio era precedentemente inattivo, mantenendo i controlli anti-riuso quando esistono PID o instance id precedenti;
- i test isolano lock e destinazioni invalide e coprono il recupero del target fuori curva, inclusa la conferma su due cicli.

## Verifica

Suite fan 80/80, core 61/61 e regressioni R4 20/20. Installazione live su PS5 CFI-2016 B01Y riuscita: servizio `ps5-fan-daemon` enabled/active, stato runtime `NORMAL`, readiness `ready`, target verificato e profili low/high/balanced applicati. Il servizio alternativo `ps5fan.service` è rimasto disabled/inactive.

Commit: `082e173`.
