# Optimize WSL VHDX with PowerShell

This guide provides a complete PowerShell workflow to compact WSL virtual disk files (`ext4.vhdx`) and recover unused space.

## Prerequisites

- Windows 11 (or recent Windows 10 with WSL updates).
- PowerShell 5.1 or PowerShell 7.
- Administrator PowerShell session for `Optimize-VHD`.
- Hyper-V PowerShell module available (feature: Hyper-V Management Tools).

## 1) Prepare inside the WSL distro before shutdown

Run these commands inside each WSL distro you plan to compact.
They help reclaim space and improve compaction results.

```bash
# Optional cleanup for apt-based distros (Ubuntu/Debian)
sudo apt-get autoremove -y
sudo apt-get clean

# Optional: clear old systemd journal files (if systemd is enabled)
sudo journalctl --vacuum-time=3d || true

# Ensure deleted blocks are discarded so the VHDX can shrink better
sudo fstrim -av
```

If you use Docker inside the distro, you can also prune unused data before shutdown:

```bash
docker system prune -af --volumes
```

## 2) Stop all WSL activity

Run in a regular PowerShell window:

```powershell
wsl --shutdown
```

If Docker Desktop or other tools are using WSL, close them first.

## 3) Locate your distro VHDX paths

List all installed distros:

```powershell
wsl -l -v
```

Typical per-user VHDX locations:

```powershell
$PossibleVhdxRoots = @(
    "$env:LOCALAPPDATA\\Packages",
    "$env:LOCALAPPDATA\\Docker\\wsl"
)

Get-ChildItem -Path $PossibleVhdxRoots -Filter ext4.vhdx -Recurse -ErrorAction SilentlyContinue |
    Select-Object FullName, Length |
    Sort-Object FullName
```

## 4) Compact VHDX files (Admin PowerShell)

Open an elevated PowerShell window and run:

```powershell
$VhdxFiles = Get-ChildItem -Path "$env:LOCALAPPDATA\\Packages" -Filter ext4.vhdx -Recurse -ErrorAction SilentlyContinue

foreach ($Vhdx in $VhdxFiles) {
    Write-Host "Compacting $($Vhdx.FullName)" -ForegroundColor Cyan
    Optimize-VHD -Path $Vhdx.FullName -Mode Full
}
```

To include Docker Desktop WSL disks as well:

```powershell
$VhdxFiles = Get-ChildItem -Path @(
    "$env:LOCALAPPDATA\\Packages",
    "$env:LOCALAPPDATA\\Docker\\wsl"
) -Filter ext4.vhdx -Recurse -ErrorAction SilentlyContinue

foreach ($Vhdx in $VhdxFiles) {
    Write-Host "Compacting $($Vhdx.FullName)" -ForegroundColor Cyan
    Optimize-VHD -Path $Vhdx.FullName -Mode Full
}
```

## 5) Optional fallback if Optimize-VHD is unavailable

If Hyper-V cmdlets are not available, use DiskPart from elevated PowerShell:

```powershell
$VhdPath = "C:\\Path\\To\\ext4.vhdx"

$DiskPartScript = @"
select vdisk file=`"$VhdPath`"
attach vdisk readonly
compact vdisk
detach vdisk
exit
"@

$ScriptFile = Join-Path $env:TEMP "diskpart-compact-wsl.txt"
$DiskPartScript | Set-Content -Path $ScriptFile -Encoding ascii

diskpart /s $ScriptFile
Remove-Item $ScriptFile -Force
```

## 6) Start WSL again and verify

```powershell
wsl
```

Check the file size after compaction:

```powershell
Get-ChildItem -Path "$env:LOCALAPPDATA\\Packages" -Filter ext4.vhdx -Recurse -ErrorAction SilentlyContinue |
    Select-Object FullName, @{Name='SizeGB';Expression={[math]::Round($_.Length / 1GB, 2)}} |
    Sort-Object FullName
```

## Troubleshooting

- `Optimize-VHD` not recognized:
  Enable Hyper-V management tools and restart PowerShell.
- `The process cannot access the file`:
  Ensure `wsl --shutdown` succeeded and close Docker Desktop.
- Access denied:
  Use an elevated PowerShell session.

## Safety notes

- Compaction is generally safe but should be done with WSL fully shut down.
- Keep backups for critical dev environments before disk operations.
- Do not compact while the distro is running.

---

Last updated (site build date): {{ site.time | date: "%Y-%m-%d" }}
