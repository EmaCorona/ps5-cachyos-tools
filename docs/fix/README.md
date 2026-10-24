# Registro fix

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
