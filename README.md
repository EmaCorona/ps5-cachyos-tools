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

The `feature/vram-management` branch includes three independent modules:

- **`fan`** — PS5 thermal controller with 15 temperature zones and `low`, `balanced`, and `high` profiles. It runs as a systemd service and reports readiness and degraded states.
- **`boot-cleanup`** — conservative early-boot task that only removes verified stale Steam artifacts from an explicit allowlist. It does not terminate processes or perform general system cleanup.
- **`vram`** — writes the selected allocation to `vram.txt` on the loader's FAT32 partition. Its first-install default is **4 GiB**; the value can be selected during installation.

The project operates on an **existing Linux installation**. It does not install CachyOS, partition or format disks, prepare an exploit or bootloader, or include the network, Bluetooth, display, Gamescope, KDE, and M.2 migration patches from the related [PS5 CachyOS Patch](https://github.com/EmaCorona/ps5-cachy-os-patch) repository. Hardware compatibility depends on the PS5 Linux kernel, drivers, firmware, and exposed device interfaces. Automated tests are hardware-free and do not replace tests on the console.

See the [architecture guide](docs/architecture.md), [module API](docs/module-api.md), and [module documentation index](docs/modules/README.md) for implementation details.

## ⚡ Quick Start

### Install on a mounted PS5 Linux root filesystem (offline)

Mount the existing Linux root filesystem and the loader's FAT32 partition before running the installer. In this example, `/mnt/ps5-root` and `/mnt/ps5-boot` must be actual mountpoints.

```bash
git clone --branch feature/vram-management --single-branch https://github.com/EmaCorona/ps5-cachyos-tools.git
cd ps5-cachyos-tools

findmnt /mnt/ps5-root
findmnt /mnt/ps5-boot
./bin/ps5-cachyos-tools list

sudo ./bin/ps5-cachyos-tools install --root /mnt/ps5-root --boot /mnt/ps5-boot --dry-run
sudo ./bin/ps5-cachyos-tools install --root /mnt/ps5-root --boot /mnt/ps5-boot
```

Without `--module`, the installer selects all modules available in the checkout. The dry run validates the target and displays the plan without applying modules. Offline installation copies files and prepares systemd enablement links in the target; it does not run systemd or execute boot tasks on the host. The `fan` service and boot tasks run when the target system starts.

### Install directly on a running PS5 Linux system (live)

The `--live` option targets the currently running root filesystem. Set `--boot` to the mounted FAT32 loader partition; `/boot/efi` is only an example and can differ by installation.

```bash
git clone --branch feature/vram-management --single-branch https://github.com/EmaCorona/ps5-cachyos-tools.git
cd ps5-cachyos-tools

findmnt /boot/efi
sudo ./bin/ps5-cachyos-tools install --live --boot /boot/efi --dry-run
sudo ./bin/ps5-cachyos-tools install --live --boot /boot/efi
```

The live installer requires administrative privileges and PS5 platform detection. It enables and starts the fan service after successful installation. `boot-cleanup` runs through `ps5-tools-early.service` at a subsequent boot, or can be invoked with `reapply`. The VRAM module writes the selected byte count in hexadecimal to `vram.txt`; its initial default is 4 GiB. The loader reads that file during a later Linux boot.

### Install selected modules or set VRAM explicitly

Pass `--module` to install only the requested module. The VRAM module requires `--boot`, whether installing live or offline.

```bash
# Fan controller only
sudo ./bin/ps5-cachyos-tools install --live --module fan --dry-run
sudo ./bin/ps5-cachyos-tools install --live --module fan

# Boot cleanup only
sudo ./bin/ps5-cachyos-tools install --live --module boot-cleanup

# VRAM only, with an explicit value
sudo ./bin/ps5-cachyos-tools install --live --module vram --boot /boot/efi --vram-size 6GiB
```

Supported VRAM values are `512MiB` and `1GiB` through `8GiB`. If `--vram-size` is omitted, the module preserves a valid existing configuration or `vram.txt`; if neither exists on first installation, it uses 4 GiB. `512MiB` is the loader's dynamic-allocation setting. The `vram.txt` file is retained when the module is removed, so the loader continues to use the last configured value.

### Inspect the installation

```bash
sudo ps5-cachyos-tools status --live
sudo ps5-cachyos-tools check --live
sudo systemctl status ps5-fan-daemon.service
sudo journalctl -u ps5-tools-early.service -b --no-pager
```

`status` reports installed modules and their recorded state; `check` runs available module checks. The cleanup check may report missing runtime state until the target has completed its first boot task. For fan diagnostics, use `sudo ps5-fan status` and `sudo ps5-temp`.

## 📁 Project Structure

```text
.
├── AGENT.md
├── bin/
│   ├── ps5-cachyos-tools       # Module framework CLI
│   ├── ps5-fan                 # Fan controller management CLI
│   ├── ps5-fan-daemon          # Long-running thermal controller
│   └── ps5-temp                # Temperature and controller diagnostics
├── config/
│   ├── fan.conf
│   └── profiles/               # low, balanced, and high fan profiles
├── docs/
│   ├── architecture.md
│   ├── module-api.md
│   ├── e2e/
│   ├── fix/
│   └── modules/                # fan, boot-cleanup, and vram guides
├── lib/
│   ├── core/                   # Discovery, target checks, transactions, state, systemd
│   └── modules/                # Framework adapters for modules
├── modules/
│   ├── _template/              # Example manifest and hook
│   ├── boot-cleanup/           # Conservative early-boot cleanup task
│   ├── fan/                    # Fan service installation and runtime hooks
│   └── vram/                   # Loader VRAM configuration task
├── systemd/                    # Boot runners and fan service
└── tests/                      # Hardware-free automated test suites
```

Each module is discovered from `modules/<id>/module.conf` and supplies its own lifecycle hooks. Modules currently have no dependencies on one another. `fan` is a persistent service; `boot-cleanup` and `vram` are tasks dispatched by the framework at their declared boot phase. See the [module API](docs/module-api.md) before adding a module.

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
5. **Run the hardware-free tests**: `bash tests/run-tests.sh`.
6. **Commit and push** your branch, then open a pull request.

Please do not treat simulated tests as hardware validation. Changes involving PS5-specific interfaces should also be checked on the target hardware when available.

---

<div align="center">

[![Made with ReadmeBuddy](https://img.shields.io/badge/Made%20with-ReadmeBuddy-8B5CFF?style=for-the-badge&logo=markdown&logoColor=white)](https://readmebuddy.com)

<sub>Generate beautiful READMEs in seconds → <a href="https://readmebuddy.com">readmebuddy.com</a></sub>

</div>
