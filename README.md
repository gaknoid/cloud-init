# WSL Ubuntu cloud-init bootstrap

This repository contains cloud-init user-data
files for repeatable WSL Ubuntu setup on Windows.

## Repository contents

- `Ubuntu-22.04.user-data`
- `Ubuntu-24.04.user-data`
- `Ubuntu-26.04.user-data`

Notes:

- The three `Ubuntu-*.user-data` files are currently identical in content.
- Clone this repo to `%USERPROFILE%\.cloud-init` so the user-data files
  are easy to find and maintain.

## Quick start

1. Clone to `%USERPROFILE%\.cloud-init`.
2. Create/update `%USERPROFILE%\.wslconfig`.
3. Set required Windows environment variables.
4. Install Ubuntu (`wsl --install Ubuntu-26.04` or another version).
5. Optionally compact virtual disks later.

## 1) Clone or update this repository

Clone this repository to `%USERPROFILE%\.cloud-init`.

## 2) Configure WSL defaults (`%USERPROFILE%\.wslconfig`)

Create or update `%USERPROFILE%\.wslconfig`:

```ini
[wsl2]
defaultVhdSize=549755813888
networkingMode=Mirrored
firewall=false
autoProxy=false
# processors=8
# swap=4GB
# memory=16GB

[experimental]
autoMemoryReclaim=Disabled
hostAddressLoopback=true
```

Then restart WSL.

## 3) Windows preparation

Install `usbipd-win` from an elevated PowerShell terminal:

`winget install --id dorssel.usbipd-win --exact --accept-source-agreements --accept-package-agreements`

Set these user environment variables before first launch:

- `GNUPGHOME=%USERPROFILE%\\.gnupg`
- `WSLENV=USERNAME:USERPROFILE/p`

Open a new terminal session after updating environment variables.

## 5) Install Ubuntu distro

Install the target distro (example shown for 26.04):

`wsl.exe --install Ubuntu-24.04`

You can also choose `Ubuntu-26.04` or `Ubuntu-22.04`.

## 6) Optimize WSL virtual disks (optional)

Use your preferred disk-optimization workflow after provisioning.

Detailed guide: [Optimize WSL VHDX with PowerShell](wsl-optimize-vhdx.md)

## Cloud-init file behavior

Each `Ubuntu-*.user-data` file configures:

- Default user `user` with sudo access.
- `/etc/wsl.conf` defaults (automount/network/interop/time).
- Profile script to map several Linux dotfiles/directories to `%USERPROFILE%`.
- Sysctl tweak: `fs.inotify.max_user_watches=524288`.
- Optional SMB credentials and sample mounts.
- Dev/general/container/filesystem package installation.
- Podman-related setup and root mount propagation service.
- Final shutdown at end of first cloud-init run.

## Required customization before production use

Edit the selected `Ubuntu-*.user-data` file and replace placeholders:

- `/etc/smbcredentials` values (`windows_user` / `windows_password`)
- Any sample mounts and hostnames that are environment-specific

Security warning:

- The configured default user has passwordless sudo (`NOPASSWD`). Keep
  as-is only if this matches your security model.

## Recommended execution order

1. Clone/update this repository.
2. Configure `%USERPROFILE%\.wslconfig`.
3. Set required environment variables.
4. Install the target Ubuntu distro.
5. Perform optional disk optimization later.

## Troubleshooting

- `usbipd-win` setup fails:
  Ensure prerequisites are installed and retry in an elevated session if required.
- VHD optimization errors:
  Confirm required host features and retry with an elevated session if needed.

---

Last updated (site build date): {{ site.time | date: "%Y-%m-%d" }}
