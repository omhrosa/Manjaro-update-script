# Manjaro Update Script

A personal Bash maintenance and update script for a specific Manjaro Linux workstation. It combines system-update tasks, health checks, snapshot handling, package maintenance, cleanup, configuration review, and several machine-specific workflows into one interactive maintenance routine.

## What it does

The script includes, among other things:

- clock/NTP sanity checks before package operations,
- dependency checks and optional installation,
- single-instance locking,
- NVMe SMART health checks,
- Btrfs/Snapper snapshot inspection and creation,
- GRUB regeneration when a new snapshot is created,
- Manjaro stable-update forum checks,
- mirror refresh and validation,
- pacman repository updates,
- AUR updates and rebuild checks,
- optional replacement of AUR/Flatpak packages with official repository packages,
- GNOME extension and Flatpak updates,
- optional Topgrade and firmware handling,
- package/cache/orphan cleanup,
- Flatpak cleanup,
- custom Pamac tray-icon patching,
- review and handling of `.pacnew` / `.pacsave` files,
- selected home-directory cleanup,
- final system statistics and LTS-kernel checks,
- logging and cleanup on exit.

## Important warning

**Do not run this script unless you have read the code and understand what it will do on your system.**

This is **not a universal Manjaro maintenance script**. It is tailored to a particular machine, software selection, filesystem layout, desktop environment, personal configuration, and maintenance workflow. It contains assumptions and operations that may be inappropriate or destructive on another installation.

In particular, it can perform privileged package operations, create snapshots, regenerate GRUB configuration, remove packages and cached data, delete selected files/directories, modify system files, and apply machine-specific customizations.

If you want to reuse any part of it, review the relevant functions carefully and adapt them to your own system rather than executing the script unchanged.

## Usage

The script is intentionally interactive and expects a Manjaro environment with the dependencies and configuration assumed by the code. Read `pacman.sh` first.

## License

Apache License 2.0.

[View the full script](./pacman.sh)
