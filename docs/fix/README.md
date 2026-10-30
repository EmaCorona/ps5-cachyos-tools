# Registro fix

- 2026-10-30 — [[`3b0f89595ea3`](https://github.com/EmaCorona/ps5-cachyos-tools/commit/3b0f89595ea3b59433ce9c3619aa1a53bc4fd173): [sessione di avvio configurabile e ripristino da TTY secondaria](fix-3b0f89595ea3-configurable-boot-session-and-tty-recovery.md): `session.conf` decide KDE/Gamescope al boot (KDE di default), `steamos-session-select --default/--once` persistono la scelta anche senza supervisore o da `tty2`, ownership `steam:steam` corretta.

- 2026-10-29 — [`fa1f59273bda`](https://github.com/EmaCorona/ps5-cachyos-tools/commit/fa1f59273bdafdc4f94fb9b5fbffa87194eb692b): [rimozione del modulo ventole dal checkout](fix-fa1f59273bda-fan-module-removal.md), degli artefatti standalone e dei riferimenti speciali dal framework e dalla CI.

- 2026-10-29 — [`ea9738987eb2`](https://github.com/EmaCorona/ps5-cachyos-tools/commit/ea9738987eb20594c59f5f258cc5b0dd5d86f48e): [riuso della dipendenza Gamescope già valida](fix-ea9738987eb2-reused-gamescope-dependency-posthook.md): `session` evita la ricompilazione del pacchetto e salta i post-hook della dipendenza non modificata.

- 2026-10-29 — [`ea9738987eb2`](https://github.com/EmaCorona/ps5-cachyos-tools/commit/ea9738987eb20594c59f5f258cc5b0dd5d86f48e): [selezione ripetuta dei moduli nella migrazione 7.2.3](fix-ea9738987eb2-kernel-7.2.3-selective-cli.md): la CLI rifiuta più opzioni `--module` anziché applicare silenziosamente solo l'ultima.

- 2026-10-29 — [`baa7e8cfe6cb`](https://github.com/EmaCorona/ps5-cachyos-tools/commit/baa7e8cfe6cbca75422d6883fccf4c19391a9634): [default VRAM 512 MiB e configurazioni persistenti](fix-baa7e8cfe6cb-vram-default-persistence.md), conflitti root/FAT fail-closed, rimozione keep/purge coerente e runbook AMDGPU; probe Vulkan conferma 640 MiB residenti in GTT con carveout da 512 MiB. Una partita Proton Experimental precedente al run ridotto ha avuto un OOM globale che l’utente attribuisce al carico eccessivo; il run ridotto seguente termina normalmente. Il runtime Gamescope usa il pacchetto 3.17.0-4 con fingerprint del patch corrispondente al branch.

- 2026-10-29 — [`46dcb0011a7e`](https://github.com/EmaCorona/ps5-cachyos-tools/commit/46dcb0011a7ec6e6913e19f8dbcb69a46b690eca): [override diagnostico reversibile KWin](fix-46dcb0011a7e-kde-amdgpu-ra24-software-cursor.md) per errori AMDGPU RA24; A/B hardware 16:9 ancora da eseguire.

- 2026-10-28 — [diagnostica DRM ultrawide Gamescope](fix-gamescope-ultrawide-drm-diagnostics.md): telemetria opt-in e limitata di commit, flip e scanout; build e test software superati, acquisizione hardware non eseguita.

- 2026-10-28 — [`e262376`](https://github.com/EmaCorona/ps5-cachyos-tools/commit/e262376): [switch KDE/Gamescope: verifica KWin e preservazione override](fix-kde-gamescope-black-screen-switch-gate.md), sostituito il proxy `loginctl seat-status [MASTER]` con lo stato systemd di KWin, ignorate le unità portal opzionali non installate e mantenuti gli override KWin solo nei processi KDE.

- 2026-10-27 — [`64c2fd6`](https://github.com/EmaCorona/ps5-cachyos-tools/commit/64c2fd6a4ef023402467a0bdc49465c693db60b7): [selezione pacchetto principale Gamescope](fix-gamescope-debug-package-selection.md), escluso l’archivio debug dalla build installabile.

- 2026-10-27 — [`b83135d`](https://github.com/EmaCorona/ps5-cachyos-tools/commit/b83135da2e82aefd5675f7d4b0633055ce2de8ec): [percorso binario Gamescope nel packaging](fix-b83135d-gamescope-meson-binary-path.md), allineato alla directory di build Meson.

- 2026-10-27 — [`7e0fc79`](https://github.com/EmaCorona/ps5-cachyos-tools/commit/7e0fc799e126dd4b5c44a1f35cc2d8aa4b116a6f): [livello di strip della patch Gamescope](fix-7e0fc79-gamescope-patch-strip-level.md), corretto `-p0` per i percorsi completi negli header.

- 2026-10-27 — [`3e190ab`](https://github.com/EmaCorona/ps5-cachyos-tools/commit/3e190ab), [`6395ba3`](https://github.com/EmaCorona/ps5-cachyos-tools/commit/6395ba346a965b916da23d35490a295fb937d9dc), [`93deb1b`](https://github.com/EmaCorona/ps5-cachyos-tools/commit/93deb1bbcb29bc0f5a4a6a8e69008f24fc15bcd6): [dipendenze makepkg di Gamescope](fix-3e190ab-gamescope-makepkg-prerequisites.md), bootstrap temporaneo di `base-devel` e cleanup pacman mirata.
- 2026-10-27 — [`dfdfe85ed1fc`](https://github.com/EmaCorona/ps5-cachyos-tools/commit/dfdfe85ed1fcf81895fc91630eb7ec7f92323907): [Gamescope all-in-one](fix-dfdfe85ed1fc-gamescope-all-in-one-install.md), installazione e verifica automatica del pacchetto downstream con selezione EDID.

- 2026-10-27 — [`b3844c7`](fix-b3844c740280-gamescope-dynamic-edid-modes.md): Gamescope prova in sequenza i timing EDID accettati dal DRM e mantiene il fallback KMS.

- 2026-10-27 — [`84ffe90`](fix-gamescope-edid-dtd.md): Gamescope può provare il DTD preferito dell’EDID con atomic test-only e mantenere il fallback KMS.

- 2026-10-27 — [`7b93e2d86e2b`](fix-7b93e2d86e2b-generic-gamescope-modes.md): rimosse le preferenze Gamescope automatiche fisse per seguire modalità DRM native e hotplug.

- 2026-10-26 — [`08f967d83253`](fix-08f967d83253-session-live-switch.md): ripristinato il cambio live KDE↔Gamescope senza modificare la policy di boot.

- 2026-10-26 — [`66f508025ad4`](fix-66f508025ad4-session-policy-authority.md): selezione boot esclusivamente dalla policy versionata, indipendente dalle preferenze persistenti e dal selettore legacy.

- 2026-10-26 — [`d097e93`](fix-d097e9363852-framework-fan-remove.md): rimozione live del modulo fan coordinata con la disabilitazione systemd del framework.

- 2026-10-26 — [`082e173`](fix-082e173-live-ps5-e2e.md): recupero del target PS5 fuori curva e readiness corretto per nuove installazioni live.

- 2026-10-26 — [`611e217`](fix-611e217ec5f-test-runner-mode.md): ripristinato il bit eseguibile del test runner dopo un mode errato nel tree pubblicato.
- 2026-10-26 — [`d779fa8`](fix-d779fa8-fan-directory-target.md): il modulo fan rifiuta destinazioni-directory e il rollback non lascia residui.
- 2026-10-26 — [`8b93ac6`](fix-8b93ac65cb9b-boot-cleanup-purge-docs.md): README allineato al comportamento effettivo di `--purge-config` per boot-cleanup.

- 2026-10-24 — [`0853437`](fix-085343759bd7-architecture-security-review.md): hardening architetturale, isolamento rootfs/live, manifest, rollback selettivo e recovery reapply.

- 2026-10-24 — [`ed240b2`](fix-modular-final-hardening-v2.md): root live, dipendenze selettive, stato once/always, service, rollback, lock condiviso, CLI e regressioni concorrenti.

- 2026-10-24 — [hardening finale del framework modulare](fix-modular-final-hardening.md): symlink gestiti, ownership dei manifest, reapply offline/live, installazioni idempotenti, mount separati e modularità selettiva.

- 2026-10-24 — [preflight installazione modulare](fix-modular-preflight.md): dipendenze, hook obbligatori, boot target e rollback live.

- 2026-10-24 — [completamento framework modulare](fix-modular-framework-completion.md): transazioni con ownership, CLI installata, stato once/always, override e isolamento target; CI remota e hardware ancora da verificare.

- 2026-10-24 — [refactor del framework modulare](fix-modular-framework.md): discovery, target offline/live, state store e runner iniziali; validazione hardware ancora da eseguire.

- 2026-10-24 — [`3392ca1`](fix-3392ca142be6f-profile-state-required.md): daemon e readiness rifiutano lo stato profilo assente.
- 2026-10-24 — [`a16699c`](fix-a16699c48105c-profile-polling-validation.md): nessun fallback per stato readiness assente e polling override coerente; rollback update coperto.
- 2026-10-24 — [`b899122`](fix-b899122836c1-decimal-timeout.md): parsing decimale e validazione coerente dei timeout di readiness.
- 2026-10-24 — [`25c048e`](fix-25c048e73a8a-ci-root-commit.md): fallback CI per commit radice e rifiuto degli override health vuoti.
- 2026-10-24 — [`fb5e82d`](fix-fb5e82d422f6-readiness-instance.md): readiness per istanza, timeout coerente, compatibilità legacy, logging senza spam e diff CI effettivo.

Il commit iniziale introduce il controller autonomo; non è una correzione applicata al repository sorgente.

## Registro

- 2026-10-24 — [`aee7fda`](fix-runtime-controller-hardening.md): hardening finale del controller, preflight uninstall, rollback transazionale, soglie emergency coerenti, logging e test multi-ciclo.

- 2026-10-24 — [`runtime-controller-hardening`](fix-runtime-controller-hardening.md): hardening del reload profilo, stati termici, lock, installazione e test runtime.
- 2026-10-24 — `d847228`: manifest di ownership validato e disinstallazione prudente.
- 2026-10-24 — `d6dce2a`: pre-validazione atomica del manifest prima della disinstallazione.
- 2026-10-24 — `fa35847`: verifica completa del manifest prima della rimozione.
- 2026-10-24 — `92613a8`: rifiuto di manifest troncati o incompleti.
- 2026-10-24 — `53d7fbe`: test completo di `--keep-config` con controllo del codice di ritorno.
- 2026-10-24 — [`456a1f9`](fix-456a1f9-systemd-order.md): correzione dell'ordinamento systemd e test anti-ciclo.
- 2026-10-24 — [`ab7054b`](fix-ab7054b-rootfs-check.md): verifica corretta dei symlink nel rootfs.
- 2026-10-24 — [`23652e7`](fix-23652e7-hardware-config.md): rifiuto delle configurazioni hardware invalide.
- 2026-10-24 — [`e63668e`](fix-e63668e-config-validation.md): validazione numerica e propagazione degli errori CLI.
- 2026-10-24 — [`c2a4145`](fix-c2a4145-runtime-hardening.md): hardening dell'installazione, del parser e del runtime.
- 2026-10-24 — [`r3-final-architecture-review`](fix-r3-final-architecture-review.md): chiusura MOD-R3-01…11, reinstallazione idempotente, lifecycle, recovery, policy, rollback e readiness.
- 2026-10-24 — [`r4-runtime-readiness-rollback`](fix-r4-runtime-readiness-rollback.md): restart runtime, readiness applicativa, rollback fan, request reapply e snapshot systemd.
