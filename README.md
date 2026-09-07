# Manjaro Update Script

A personal Bash maintenance and update script for a specific Manjaro Linux workstation. It combines system-update tasks, preflight safety checks, recovery information, snapshots, package maintenance, cleanup, configuration review, and several machine-specific workflows into one interactive maintenance routine.

## What it does

The script includes, among other things:

- clock/NTP sanity checks and single-instance locking before package operations,
- dependency detection with safety-gated installation after SMART/Snapper preflight,
- NVMe SMART health checks with retry/exit handling,
- Btrfs/Snapper snapshot inspection and automatic creation when no recent snapshot exists,
- GRUB regeneration when a new snapshot is created,
- Manjaro stable-update forum and mirror checks,
- repository-update dry runs with package count and download-size reporting,
- pacman updates with database-lock handling and PGP/keyring recovery options,
- a pre-update recovery manifest and last-success timestamp,
- AUR updates, missing-library/provider checks, and selective rebuild handling,
- optional replacement of AUR/Flatpak packages with official repository packages, with rollback on failed replacements,
- GNOME extension and Flatpak updates,
- optional Topgrade and firmware handling,
- package/cache/orphan cleanup and extended Flatpak cleanup,
- custom Pamac tray-icon patching with backup, verification, and restore safeguards,
- staged review and handling of `.pacnew` / `.pacsave` files,
- selected home-directory and orphaned application-config cleanup,
- final system statistics, repository-availability hints, and LTS-kernel checks,
- post-update package-database, AUR rebuild, systemd-service, and config-file health checks,
- logging and cleanup on exit.

## Important warning

**Do not run this script unless you have read the code and understand what it will do on your system.**

This is **not a universal Manjaro maintenance script**. It is tailored to a particular machine, software selection, filesystem layout, desktop environment, personal configuration, and maintenance workflow. It contains assumptions and operations that may be inappropriate or destructive on another installation.

In particular, it can perform privileged package operations, refresh or rebuild package keyrings, create snapshots, regenerate GRUB configuration, install or remove packages, remove cached or application data, delete selected files/directories, modify configuration/system files, and apply machine-specific customizations.

The script contains several defensive checks and rollback paths, but those do not make it portable or safe for an arbitrary Manjaro installation. If you want to reuse any part of it, review the relevant functions carefully and adapt them to your own system rather than executing it unchanged.

## Usage

The script is intentionally interactive and expects the Manjaro/GNOME/Btrfs/Snapper environment and dependencies assumed by the code.

The current source is stored verbatim as numbered text parts under [`source/`](./source/). Read them in numeric order. To reconstruct a single local file:

```bash
cat source/pacman.sh.part-*.txt > pacman.sh
```

The reconstructed file should have SHA-256:

`fad1951e55e51abb405e2592912fbb4fd78b520300b12e76c7a21909b8103ffa`

## License

Apache License 2.0.

[View the source parts](./source/)
