# WSL Ubuntu cloud-init bootstrap

This repository contains PowerShell helpers and cloud-init user-data
files for repeatable WSL Ubuntu setup on Windows.

## Repository contents

- `Ubuntu-22.04.user-data`
- `Ubuntu-24.04.user-data`
- `Ubuntu-26.04.user-data`
- `WSL2-Install-PreSetup.ps1`
- `WSL2-Optimize-VHDX.ps1`

Notes:

- The three `Ubuntu-*.user-data` files are currently identical in content.
- Clone this repo to `%USERPROFILE%\.cloud-init` so the user-data files
  are easy to find and maintain.

## Quick start

1. Clone to `%USERPROFILE%\.cloud-init`.
2. Create/update `%USERPROFILE%\.wslconfig`.
3. Set required Windows environment variables.
4. Run `WSL2-Install-PreSetup.ps1`.
5. Install Ubuntu (`wsl --install Ubuntu-26.04` or another version).
6. Optionally run `WSL2-Optimize-VHDX.ps1` later to compact disks.

## 1) Clone or update this repository

```powershell
Set-Location $env:USERPROFILE
if (Test-Path .cloud-init) {
  Rename-Item .cloud-init .cloud-init.orig -Force
}
git clone https://github.com/gaknoid/cloud-init .cloud-init
```

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

Then restart WSL:

```powershell
wsl.exe --shutdown
```

## 3) Windows preparation

Run these once in PowerShell:

```powershell
setx.exe GNUPGHOME "$env:USERPROFILE\.gnupg"
setx.exe WSLENV "USERNAME:USERPROFILE/p"
```

Open a new terminal session after `setx` so variables are available.

## 4) Run pre-setup script

From this repository directory:

```powershell
Set-Location $env:USERPROFILE\.cloud-init
.\WSL2-Install-PreSetup.ps1
```

What it does:

- Installs Ubuntu Mono fonts (per-user by default, system-wide when
  elevated or with `-SystemWide`).
- Installs `usbipd-win` from the latest GitHub release (requires elevation).
- Sets Ubuntu Insights consent opt-out in the current user registry.

Useful options:

```powershell
.\WSL2-Install-PreSetup.ps1 -WhatIf
.\WSL2-Install-PreSetup.ps1 -SystemWide
```

## 5) Install Ubuntu distro

Install the target distro (example shown for 26.04):

```powershell
wsl.exe --install Ubuntu-24.04
```

You can also choose `Ubuntu-24.04` or `Ubuntu-22.04`.

## 6) Optimize WSL virtual disks (optional)

Run in an elevated PowerShell session:

```powershell
.\WSL2-Optimize-VHDX.ps1
```

What it does:

- Runs cleanup commands inside each detected WSL distro (`apt clean`,
  `autoremove`, `fstrim`, etc.).
- Shuts down WSL.
- Finds WSL-related VHD/VHDX files.
- Compacts disks with `Optimize-VHD` when available, with automatic
  fallback to `diskpart compact`.

Mode options:

```powershell
.\WSL2-Optimize-VHDX.ps1 -Mode Quick
.\WSL2-Optimize-VHDX.ps1 -Mode Full
```

Use `-WhatIf` to preview actions.

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

- `plain_text_passwd: password`
- `/etc/smbcredentials` values (`windows_user` / `windows_password`)
- Any sample mounts and hostnames that are environment-specific

Security warning:

- The configured default user has passwordless sudo (`NOPASSWD`). Keep
  as-is only if this matches your security model.

## Recommended execution order

```powershell
Set-Location $env:USERPROFILE\.cloud-init
wsl.exe --shutdown
.\WSL2-Install-PreSetup.ps1
wsl.exe --install Ubuntu-26.04
# Later, when needed (elevated):
.\WSL2-Optimize-VHDX.ps1 -Mode Full
```

## Troubleshooting

- `usbipd-win` install fails:
  Run PowerShell as Administrator and rerun `WSL2-Install-PreSetup.ps1`.
- VHD optimization errors:
  Confirm elevated PowerShell and retry; script already includes
  `diskpart` fallback.
