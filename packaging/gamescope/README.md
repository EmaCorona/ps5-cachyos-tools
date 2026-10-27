# Patch downstream per Gamescope

`0001-drm-use-preferred-edid-dtd.patch`, `EDIDModeSelection.h` e il `PKGBUILD` aggiornato estendono Gamescope 3.17.0 (sorgente upstream `e6674a98118ca7b098b98a3874b8f195ae1bf750`). Il PKGBUILD crea il pacchetto dedicato `ps5-cachyos-gamescope`, installato e aggiornato tramite pacman accanto al Gamescope ufficiale. Il modulo `gamescope` installa wrapper e helper, quindi costruisce e installa automaticamente questa build durante l’installazione live o offline su Arch/CachyOS x86_64. Il binario patchato e gli script sono collocati in percorsi privati del progetto, senza sovrascrivere `/usr/bin/gamescope`; la sessione usa esplicitamente il binario privato. Il pacchetto Gamescope ufficiale resta installato per le dipendenze, il layer WSI e gli altri runtime.

Durante `prepare()`, il PKGBUILD applica la patch EDID con `patch -Np0`: i percorsi negli header sono relativi alla radice del sorgente e non includono un componente `a/` o `b/` da rimuovere.

La fase `build()` crea il binario in `build/src/gamescope`; `package()` installa da quel percorso nel pacchetto privato del progetto.

Il helper usa i metadati dell’archivio per selezionare il solo pacchetto `ps5-cachyos-gamescope`, ignorando l’eventuale archivio `ps5-cachyos-gamescope-debug` prodotto da makepkg.

La patch legge dall'EDID tutti i timing dettagliati digitali progressivi validi, mantenendone l'ordine (preferred per primo) e scartando duplicati o timing non rappresentabili nei campi DRM. Per ogni modalità non già enumerata da KMS esegue un atomic `TEST_ONLY | ALLOW_MODESET`; se una modalità viene rifiutata prova la successiva. Se tutte sono rifiutate, l'EDID non contiene candidati utilizzabili o il test non è possibile, Gamescope mantiene la modalità KMS selezionata. In questo modo dimensioni, rapporto d'aspetto e refresh non dipendono da un monitor specifico. La selezione viene ripetuta quando il backend aggiorna il connettore dopo un cambio/hotplug; i candidati vengono ricostruiti dal nuovo EDID.

Per installarlo manualmente, il comando equivalente gestito dal modulo è:

```bash
cd packaging/gamescope
makepkg -si
```

Il flusso del modulo richiede `makepkg` e lo esegue come utente non root; assicura temporaneamente il meta-pacchetto `base-devel` e le dipendenze dichiarate nel PKGBUILD, controlla architettura e spazio temporaneo, installa il pacchetto prodotto con pacman e verifica database, binario e fingerprint del sorgente/patch. Al termine rimuove solo i pacchetti che non risultavano installati prima della build. Per un target offline usa `pacman --sysroot` sul root montato. Gli errori di build o post-installazione fanno fallire il modulo e il helper tenta di ripristinare il pacchetto precedente dalla cache. La rimozione del modulo elimina il pacchetto downstream con un hook post-rimozione compensabile; conserva l’archivio nella cache privata del modulo per poterlo reinstallare in caso di rollback. Il pacchetto ufficiale e Steam restano intatti. L’aggiornamento upstream è intenzionalmente pinning a Gamescope 3.17.0: ogni nuova release richiede aggiornamento del commit, revisione della patch e test prima di cambiare il pin.

Per controllare l'applicabilità contro il sorgente Gamescope 3.17.0 già estratto:

```bash
tests/gamescope-upstream-patch-tests.sh /percorso/al/sorgente/gamescope-3.17.0
```

Il test verifica il commit fissato, l'applicazione della patch, l'iterazione di tutti i DTD, l'aggiornamento dei candidati e il fallback KMS. Non compila né esegue un modeset. Compilazione e prova di modeset reale restano verifiche distinte; non installare un pacchetto ricostruito senza verificare prima le dipendenze e mantenere disponibile il pacchetto precedente per il rollback. La patch non cambia il modulo ventole.
