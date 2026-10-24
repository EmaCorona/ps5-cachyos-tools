# Logging dei profili invalidi senza spam

## Problema

Un profilo persistente invalido veniva ritentato e registrato a ogni ciclo di polling, producendo log ripetitivi senza nuova informazione.

## Correzione applicata

Il demone memorizza il profilo tentato e una firma del relativo file. Ritenta e registra nuovamente soltanto quando cambiano profilo o contenuto; quando la configurazione viene corretta registra un singolo evento di recupero e azzera l'errore di configurazione.

## Verifica e limiti

La suite esegue dieci cicli con profilo invalido e verifica un solo evento. I log journal reali e la rotazione sul target restano da verificare.

Commit: [`fb5e82d422f6345f7a5063b28ad7db6432e6d481`](https://github.com/EmaCorona/ps5-cachyos-tools/commit/fb5e82d422f6345f7a5063b28ad7db6432e6d481).
