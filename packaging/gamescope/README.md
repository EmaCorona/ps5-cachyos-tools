# Patch downstream per Gamescope

`patches/0001-drm-use-preferred-edid-dtd.patch` estende il backend DRM di Gamescope 3.17.0 (sorgente upstream `e6674a98118ca7b098b98a3874b8f195ae1bf750`). Il repository `ps5-cachyos-tools` installa il wrapper e gli helper, ma non possiede né compila il pacchetto `/usr/bin/gamescope`: questa patch va quindi applicata dal processo che crea il pacchetto Gamescope, prima della compilazione.

La patch estrae dal DTD preferito dell'EDID i timing digitali progressivi, conserva pixel clock e porches esatti e li sottopone a un commit atomico `TEST_ONLY | ALLOW_MODESET`. Se il kernel rifiuta il candidato o l'EDID non contiene un DTD idoneo, Gamescope continua a selezionare una modalità KMS enumerate. La selezione avviene all'inizializzazione e quando il backend rilegge un connettore dopo un cambio; il comportamento KMS standard resta il fallback.

Per controllare l'applicabilità contro il sorgente Gamescope 3.17.0 già estratto:

```bash
tests/gamescope-upstream-patch-tests.sh /percorso/al/sorgente/gamescope-3.17.0
```

Il test richiede il commit upstream fissato sopra e non scarica né installa dipendenze. Dopo aver applicato la patch al pacchetto, compilazione, installazione e prova di modeset reale sono verifiche distinte. Non installare il pacchetto ricostruito sopra quello di sistema senza un piano di rollback e una verifica manuale del display. La patch non cambia il modulo ventole e non viene applicata automaticamente dal modulo Gamescope di questo repository.
