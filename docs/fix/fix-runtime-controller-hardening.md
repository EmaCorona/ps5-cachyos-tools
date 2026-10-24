# Hardening del controller runtime

- Data: 2026-10-24
- File principali: `bin/ps5-fan-daemon`, `bin/ps5-fan`, `lib/modules/fan.sh`, `tests/run-tests.sh`

## Problema

Il cambio profilo a runtime non proteggeva sempre lo stato già valido da una curva corrotta; inoltre i confini della curva High, il recupero da `EMERGENCY`, gli override numerici e la disinstallazione richiedevano controlli più rigorosi.

## Correzione

Il daemon separa target desiderato, osservato e ultimo verificato: ogni ciclo valida il readback prima delle decisioni termiche, entra in `DEGRADED` anche se il target desiderato non cambia e non aumenta il target rispetto a un valore hardware valido. Il cambio profilo non resetta lo stato né i contatori di recovery e registra gli eventi di profilo, stato ed errore nel journal. Il recovery richiede almeno due campioni validi consecutivi; l'ingresso in `EMERGENCY` è immediato e l'uscita usa `EMERGENCY_RECOVERY_DELTA` (default 3 °C, quindi 78 °C) rispettando lo slew-rate. Il daemon valida e ricarica atomicamente i profili, mantiene il profilo precedente se il nuovo file è invalido, gli override e i parametri numerici sono validati, il lock runtime impedisce istanze concorrenti, la zona è `unknown` senza sensore, la selezione APU è deterministica, il sensore NVMe non è un fallback APU e l'installer preserva configurazioni e file utente, creando backup timestampati di tutti gli artefatti gestiti e ripristinandoli in caso di errore parziale. La CLI usa il preflight condiviso e implementa `--keep-config`.

## Verifica e limiti

`bash -n`, `git diff --check` e `tests/run-tests.sh` sono stati eseguiti con esito positivo: 61 test superati, 0 falliti. Sono stati aggiunti il limite prudente di `EMERGENCY_TEMP`, la diagnostica persistente separata anche per errori di avvio/override, lo stato `UNAVAILABLE` distinto da `DEGRADED`, il rilevamento dei runtime artifact mancanti/tipo/permessi, l'health check applicativo per istanza post-restart, il timeout derivato dal polling, la compatibilità legacy, il logging senza spam, gli esiti strutturati di rollback e la pipeline `.github/workflows/validate.yml`. La verifica systemd con rootfs di staging passa; non sono state eseguite prove systemd live o su hardware PS5 reale; driver, temperature, RPM, rumore e throttling restano da verificare nell'ambiente reale.

I riferimenti di versione sono `cc0ef89` (`fix(fan): close review gaps for install and sensors`), `d847228` (`fix(fan): make uninstall ownership-aware`), `d6dce2a` (`fix(fan): validate ownership manifest paths`), `fa35847` (`fix(fan): prevalidate uninstall manifest`), `92613a8` (`fix(fan): require complete ownership manifest`) e `53d7fbe` (`test(fan): cover complete keep-config manifest`). Il manifest contiene sette percorsi di proprietà, incluso `/usr/lib/ps5-cachyos-tools/fan.sh`, e viene validato interamente prima della disinstallazione. Il backup è esplicito: una nuova installazione senza backup rimuove solo gli artefatti creati dalla transazione corrente e non costruisce mai percorsi a partire da una stringa vuota.
