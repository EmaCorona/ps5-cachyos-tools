# Refactor del framework modulare

## Problema

Il repository esponeva soltanto il percorso autonomo del modulo ventole e non aveva discovery, contratto manifest, runner di boot o separazione esplicita tra staging offline e sistema live.

## Correzione applicata

È stato aggiunto un nucleo modulare incrementale con parser allowlistato, discovery dinamica sotto `modules/<id>/`, ordinamento delle dipendenze, target resolver offline/live, state store atomico e runner per fasi `early`/`normal`. Il modulo `fan` è un adapter: riusa `lib/modules/fan.sh` e mantiene la unit permanente del demone. Le nuove unit oneshot non sostituiscono il servizio fan.

## Verifica e limiti

La suite core verifica discovery, dry-run, isolamento della rootfs, staging delle unit, esecuzione `once`, skip al secondo boot e rifiuto di una chiave manifest sconosciuta. La suite fan legacy resta separata e deve essere eseguita insieme ai controlli Bash e systemd. La prova su PS5 reale e la verifica live del grafo systemd restano da eseguire.
