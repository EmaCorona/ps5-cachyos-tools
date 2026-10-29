# Rimozione del modulo ventole dal checkout

## Problema

Il branch conteneva ancora il modulo `fan`, i suoi binari, le configurazioni, le unità systemd e le suite dedicate. Questo manteneva il controller disponibile nella discovery e lasciava riferimenti a file che non appartengono più al perimetro del branch.

## Correzione applicata

Sono stati eliminati il manifest e tutti gli hook del modulo, l'adapter legacy, le CLI e configurazioni del controller, le unità systemd e la suite di test dedicata. Il core conserva soltanto il lifecycle generico per moduli `service`, readiness, runtime hook, rollback e discovery tramite manifest. Sono stati rimossi anche i rami speciali fan da installer, registry, servizio e comando `status`.

La suite core R4 è stata ridotta ai controlli generici di sicurezza del registry e dei percorsi; i test dei moduli rimanenti continuano a verificare installazione, rollback e lifecycle. La CI non cita più file o unità del controller.

## File coinvolti

La modifica interessa `modules/fan/`, `lib/modules/fan.sh`, `bin/ps5-fan*`, `bin/ps5-temp`, `config/fan.conf`, `config/profiles/`, le unità `ps5-fan`, la documentazione del modulo, gli agganci nel core e i runner di test/CI. I report storici in `docs/fix/` e `docs/e2e/` restano conservati come cronologia; i link ai sorgenti rimossi sono puntati ai commit storici.

## Verifica e limiti

- `bash tests/run-tests.sh`: suite boot-cleanup 26/26, VRAM 22/22 e grafica 49/49; le suite Python e Gamescope incluse hanno superato i controlli disponibili; il test EDID è stato riportato come `SKIP` con codice 77 perché `g++` non è installato.
- `bash tests/core/run-tests.sh`: 61 test superati, 0 falliti, inclusi i controlli R4 generici.
- `bash tests/core/r4-tests.sh`: 9 test superati, 0 falliti.
- `bash -n` sugli script modificati e `git diff --check`: PASS.
- ShellCheck non è disponibile nell'ambiente locale; la compilazione C++ del test EDID non è stata eseguita perché `g++` non è installato e non sono disponibili privilegi per installarlo.
- Questa modifica riguarda il checkout e non disinstalla né arresta eventuali componenti ventole già presenti sul sistema live.
