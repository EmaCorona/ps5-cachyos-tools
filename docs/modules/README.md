# Moduli

- [vram](vram.md): configurazione VRAM del loader dalla partizione FAT32.
- [boot-cleanup](boot-cleanup.md): pulizia limitata a PID allowlistati e helper manuale per la directory dump Steam.
- [kde](kde.md): compatibilità KDE Plasma Wayland/DRM e notifiche desktop.
- [gamescope](gamescope.md): sessione Gamescope DRM, configurazione display e diagnostica.
- [session](session.md): selezione TTY1, switch bidirezionale e fallback KDE.
- Il framework scopre i moduli sotto `modules/<id>/` tramite `module.conf`.

Le regole copiate in `AGENT.md` che riguardano moduli assenti del patcher originale sono fuori ambito per questo repository; valgono qui solo le regole di processo, testing e revisione applicabili ai file presenti.
