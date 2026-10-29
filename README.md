# PS5 CachyOS Tools

![Build status](https://img.shields.io/github/actions/workflow/status/EmaCorona/ps5-cachyos-tools/validate.yml?style=for-the-badge&logo=githubactions&logoColor=white&label=CI) ![GitHub stars](https://img.shields.io/github/stars/EmaCorona/ps5-cachyos-tools?style=for-the-badge&logo=github) ![GitHub forks](https://img.shields.io/github/forks/EmaCorona/ps5-cachyos-tools?style=for-the-badge&logo=github) ![GitHub issues](https://img.shields.io/github/issues/EmaCorona/ps5-cachyos-tools?style=for-the-badge&logo=github) ![Last commit](https://img.shields.io/github/last-commit/EmaCorona/ps5-cachyos-tools?style=for-the-badge&logo=github)

## 📑 Table of Contents

- [Description](#description)
- [Quick Start](#quick-start)
- [Project Structure](#project-structure)
- [Contributors](#contributors)
- [Contributing](#contributing)

## 📝 Description

Modular post-installation, maintenance, and diagnostics framework for **PS5 Linux**, with a focus on CachyOS-based distributions. The framework discovers modules through their manifests and manages installation, checks, status, reapplication, and removal without requiring changes to the core when a module is added.

The project includes independent modules for system management, graphics sessions, and loader memory configuration:

- **`boot-cleanup`** — conservative early-boot task that only removes verified stale Steam artifacts from an explicit allowlist. A separate manual helper normalizes `/tmp/dumps` permissions without deleting its contents.
- **`kde`, `gamescope`, and `session`** — prepare KDE Plasma Wayland and Gamescope DRM; the `session` supervisor launches KDE by default from a versioned TTY1 boot policy, handles live KDE/Gamescope switches, and falls back to KDE if Gamescope fails.
- **`vram`** — writes the selected allocation to `vram.txt` on the loader's FAT32 partition. When both configuration files are absent, a new installation defaults to **512 MiB**; valid existing values are preserved, and an explicit value can be selected during installation. Invalid or conflicting configurations fail closed unless an explicit value resolves them.

Gamescope selects the connected DRM/KMS mode with the highest resolution (then refresh rate), with optional overrides in `/etc/ps5-cachyos-tools/gamescope.conf`; if `modetest` is unavailable, its mode detector uses 60 Hz as a fallback. KDE selects from KScreen/EDID modes at desktop startup. Detection alone does not guarantee a working HDMI signal or a correctly scaled Steam UI.

The project operates on an **existing Linux installation**. It does not install CachyOS, partition or format disks, prepare an exploit or bootloader, or include the network, Bluetooth, display, and M.2 migration patches from the related [PS5 CachyOS Patch](https://github.com/EmaCorona/ps5-cachy-os-patch) repository. Hardware compatibility depends on the PS5 Linux kernel, drivers, firmware, and exposed device interfaces. Automated tests are hardware-free and do not replace tests on the console.

See the [architecture guide](docs/architecture.md), [module API](docs/module-api.md), and [module documentation index](docs/modules/README.md) for implementation details.

## ⚡ Quick Start

### Install on a mounted PS5 Linux root filesystem (offline)

Mount the existing Linux root filesystem and the loader's FAT32 partition before running the installer. In this example, `/mnt/ps5-root` and `/mnt/ps5-boot` must be actual mountpoints.

```bash
git clone --branch develop --single-branch https://github.com/EmaCorona/ps5-cachyos-tools.git
cd ps5-cachyos-tools

findmnt /mnt/ps5-root
findmnt /mnt/ps5-boot
./bin/ps5-cachyos-tools list

sudo ./bin/ps5-cachyos-tools install --root /mnt/ps5-root --boot /mnt/ps5-boot --dry-run
sudo ./bin/ps5-cachyos-tools install --root /mnt/ps5-root --boot /mnt/ps5-boot
```

Without `--module`, the installer selects all modules available in the checkout. The dry run validates the target and displays the plan without applying modules. Offline installation copies files and prepares systemd enablement links in the target; it does not run systemd or execute boot tasks on the host. Graphics integration files are installed into the target immediately; their normal-phase boot tasks check those artifacts. When a login shell starts on TTY1, the session supervisor selects KDE from the versioned boot policy and supports temporary switching to Gamescope.

### Install directly on a running PS5 Linux system (live)

The `--live` option targets the currently running root filesystem. Set `--boot` to the mounted FAT32 loader partition; `/boot/efi` is only an example and can differ by installation.

```bash
git clone --branch develop --single-branch https://github.com/EmaCorona/ps5-cachyos-tools.git
cd ps5-cachyos-tools

findmnt /boot/efi
sudo ./bin/ps5-cachyos-tools install --live --boot /boot/efi --dry-run
sudo ./bin/ps5-cachyos-tools install --live --boot /boot/efi
```

The live installer requires administrative privileges and PS5 platform detection. `boot-cleanup` runs through `ps5-tools-early.service` at a subsequent boot, or can be invoked with `reapply`. KDE, Gamescope, and session tasks validate their artifacts at normal boot; a login shell on TTY1 starts the session supervisor, which launches KDE by default, accepts temporary switches to Gamescope, and falls back to KDE if Gamescope fails. The KDE module does not install Plasma packages; the Gamescope module builds a separate patched package and keeps the distribution's `/usr/bin/gamescope` intact. The framework does not update Steam. The VRAM module writes the selected byte count in hexadecimal to `vram.txt`; when both root and FAT configuration files are absent, a new installation defaults to 512 MiB. Existing valid values are preserved; malformed or conflicting values fail closed unless explicitly resolved. The loader reads that file during a later Linux boot.

### Selective migration on PS5 Linux kernel 7.2.3

Select one module per command when a staged migration is needed. `session` resolves its `kde` and `gamescope` dependencies. Use the loader's verified FAT32 mount in place of `/boot/efi` if it differs.

```bash
findmnt /boot/efi
uname -r
for module in boot-cleanup kde gamescope session vram; do
  sudo ./bin/ps5-cachyos-tools install --live --boot /boot/efi --module "$module" --dry-run || exit
done
for module in boot-cleanup kde gamescope session vram; do
  sudo ./bin/ps5-cachyos-tools install --live --boot /boot/efi --module "$module" || exit
done
```

Repeated `--module` options in one invocation are rejected; each selected module is a separate transaction. Confirm display and session behavior on the connected console after installation.

### Install selected modules or set VRAM explicitly

Pass `--module` to install a specific module and any declared dependencies (`session` also selects `kde` and `gamescope`). The VRAM module requires `--boot`, whether installing live or offline; a full installation includes VRAM and therefore also requires `--boot`. The Gamescope module requires `/usr/bin/python3` in the target system.

```bash
# Boot cleanup only
sudo ./bin/ps5-cachyos-tools install --live --module boot-cleanup

# VRAM only, with an explicit value
sudo ./bin/ps5-cachyos-tools install --live --module vram --boot /boot/efi --vram-size 6GiB
```

Supported VRAM values are `512MiB` and `1GiB` through `8GiB`. If `--vram-size` is omitted, the module preserves a valid existing configuration or `vram.txt`; if both files are absent on first installation, it uses 512 MiB. Malformed or conflicting configurations fail closed unless explicitly resolved. `512MiB` is the loader's dynamic-allocation setting. The `vram.txt` file is retained when the module is removed, so the loader continues to use the last configured value.

### Switch between KDE and Gamescope

Once the session supervisor is running on TTY1, use the session selector to switch the active session:

```bash
steamos-session-select gamescope
steamos-session-select desktop
```

These switches are temporary and require a running supervisor. The compatibility options `--default` and `--once` also request only a live switch: **neither changes the next boot**. The initial session is selected exclusively by `modules/session/files/session-policy` (installed at `/usr/local/libexec/ps5-cachyos-tools/session-policy`), which currently selects KDE. To make Gamescope the boot default, change that versioned policy to output `gamescope` and reinstall the `session` module. The project does not configure TTY1 autologin itself; see the [session module documentation](docs/modules/session.md).

### Inspect the installation

```bash
sudo ps5-cachyos-tools status --live
sudo ps5-cachyos-tools check --live
sudo journalctl -u ps5-tools-early.service -b --no-pager
```

`status` reports installed modules and their recorded state; `check` runs available module checks. The cleanup check may report missing runtime state until the target has completed its first boot task.

## 📁 Project Structure

```text
.
├── AGENT.md
├── bin/
│   └── ps5-cachyos-tools       # Module framework CLI
├── docs/
│   ├── architecture.md
│   ├── module-api.md
│   ├── e2e/
│   ├── fix/
│   └── modules/                # boot-cleanup, KDE, Gamescope, session, and VRAM guides
├── lib/
│   └── core/                   # Discovery, target checks, transactions, state, systemd
├── modules/
│   ├── _template/              # Example manifest and hook
│   ├── boot-cleanup/           # Conservative early-boot cleanup task
│   ├── gamescope/              # Gamescope DRM session and diagnostics
│   ├── kde/                    # KDE Wayland/DRM integration
│   ├── session/                # TTY1 session selection and switching
│   └── vram/                   # Loader VRAM configuration task
├── systemd/                    # Boot runners and module services
└── tests/                      # Hardware-free automated test suites
```

Each module is discovered from `modules/<id>/module.conf` and supplies its own lifecycle hooks. `session` automatically selects the `kde` and `gamescope` dependencies; the other modules remain independently selectable. `boot-cleanup`, graphics setup, and `vram` are tasks dispatched by the framework at their declared boot phase. The session module installs the TTY1 supervisor that selects KDE by default and supports switching between KDE and Gamescope. See the [module API](docs/module-api.md) before adding a module.

## 👥 Contributors

Thanks to everyone who has contributed to this project:

<p align="left">
<a href="https://github.com/EmaCorona" title="EmaCorona"><img src="https://avatars.githubusercontent.com/u/137076097?v=4&s=64" width="64" height="64" alt="EmaCorona" style="border-radius:50%" /></a>
</p>

[See the full list of contributors →](https://github.com/EmaCorona/ps5-cachyos-tools/graphs/contributors)

## 👥 Contributing

Contributions are welcome. A typical contribution flow is:

1. **Fork** the repository.
2. **Clone** your fork: `git clone https://github.com/<your-user>/ps5-cachyos-tools.git`.
3. **Create a branch**: `git checkout -b feature/your-feature` (or use `fix/` or `docs/` for those changes).
4. **Implement the change** and update the relevant documentation. New modules should follow the manifest-driven module API.
5. **Run the hardware-free tests**: `bash tests/run-tests.sh && bash tests/core/run-tests.sh`.
6. **Commit and push** your branch, then open a pull request.

Please do not treat simulated tests as hardware validation. Changes involving PS5-specific interfaces should also be checked on the target hardware when available.

---

<div align="center">

[![Made with ReadmeBuddy](https://img.shields.io/badge/Made%20with-ReadmeBuddy-8B5CFF?style=for-the-badge&logo=markdown&logoColor=white)](https://readmebuddy.com)

<sub>Generate beautiful READMEs in seconds → <a href="https://readmebuddy.com">readmebuddy.com</a></sub>

</div>
