# Privileged session selector probe

Date: 2026-10-30. Branch: `feature/ps5-linux-kernel-7.2.3-migration`.

The reproducible harness is [`session-selector-rootless-test.sh`](session-selector-rootless-test.sh); its raw `bash -x` output is in [`session-selector-rootless-test.log`](session-selector-rootless-test.log).

This probe exercised the selector's `EUID == 0` branch in a rootless user and
mount namespace. `/home/steam` was bind-mounted to a temporary fixture. The
selector was given `XDG_CONFIG_HOME`, `XDG_RUNTIME_DIR`, `PS5_SESSION_CONFIG`,
and `PS5_SESSION_RUNTIME` values pointing outside that fixture. The namespace
does not permit `runuser` to call `initgroups` (`setgroups=deny`), so a test
shim validated the exact `runuser -u steam -- env ...` arguments and dropped
the process to UID/GID 1000:1000 with `setpriv`. The repository selector and
`session-common.sh` were the files executed.

Observed output:

```text
Supervisore Session non attivo; sessione predefinita di avvio impostata a gamescope per il prossimo boot.
PASS root namespace selector persisted only to steam home with steam ownership/mode; XDG/config/runtime overrides ignored
```

Result: assertions in the probe verified `DEFAULT_SESSION=gamescope`, an empty
`NEXT_SESSION`, owner `1000:1000`, mode `0600`, owner/mode `1000:1000`/`0700`
for the config directory, and no writes to the foreign XDG/config targets.
The namespace runtime path had no supervisor, so the selector correctly saved
the next-boot default and exited successfully.

Limit: this does not execute util-linux `runuser` itself or test live IPC
under `sudo`; the namespace rejects `runuser`'s supplementary-group setup.
That path still needs validation on a normal root-capable target environment.
