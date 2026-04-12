[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateSet("Quick", "Full")]
    [string]$Mode = "Full"
)

# Ensure script stops on errors.
$ErrorActionPreference = "Stop"

# Optimize-VHD comes from the Windows feature:
# - Microsoft-Hyper-V-Management-PowerShell
# Runtime execution additionally requires Hyper-V platform/WMI provider availability.
# If platform pieces are missing or unavailable on this edition, the script falls back to diskpart compact.

function Test-IsAdministrator {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($currentIdentity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-WslVhdxFiles {
    [OutputType([System.IO.FileInfo[]])]
    param()

    # Gather distro base paths from registry for installed-user distros.
    $registryBasePaths = @()
    $lxssRoot = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss"
    if (Test-Path $lxssRoot) {
        $registryBasePaths = Get-ChildItem $lxssRoot -ErrorAction SilentlyContinue |
            ForEach-Object {
                (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).BasePath
            } |
            Where-Object { $_ -and (Test-Path $_) }
    }

    # Also scan all user profiles for modern Store WSL disk locations.
    $allUsersWslPaths = @()
    if (Test-Path "C:\Users") {
        $allUsersWslPaths = Get-ChildItem -Path "C:\Users" -Directory -ErrorAction SilentlyContinue |
            ForEach-Object { Join-Path $_.FullName "AppData\Local\wsl" } |
            Where-Object { Test-Path $_ }
    }

    $pathsToScan = @(
        (Join-Path $env:LOCALAPPDATA "Packages")
        (Join-Path $env:LOCALAPPDATA "wsl")
        (Join-Path $env:LOCALAPPDATA "Docker\wsl")
        (Join-Path $env:PROGRAMDATA "DockerDesktop\vm-data")
    ) + $registryBasePaths + $allUsersWslPaths |
        Where-Object { $_ -and (Test-Path $_) } |
        Sort-Object -Unique

    if (-not $pathsToScan) {
        return @()
    }

    # Common WSL and WSL-adjacent virtual disk naming patterns.
    $filePatterns = @("*.vhdx", "*.vhd")
    $nameFilters = @("ext4.vhdx", "disk.vhdx", "docker_data.vhdx", "docker-desktop-data.vhdx")

    # Build a broad candidate set, then narrow using common WSL naming/location patterns.
    $results = foreach ($path in $pathsToScan) {
        foreach ($pattern in $filePatterns) {
            Get-ChildItem -Path $path -Recurse -File -Filter $pattern -ErrorAction SilentlyContinue
        }
    }

    $results |
        Where-Object {
            $_.Length -gt 0 -and (
                $nameFilters -contains $_.Name -or
                $_.DirectoryName -match "LocalState|\\wsl\\\{" -or
                $_.FullName -match "\\Docker\\wsl\\"
            )
        } |
        Sort-Object -Property FullName -Unique
}

function Invoke-DiskPartCompact {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $scriptPath = Join-Path $env:TEMP ("diskpart-compact-" + [guid]::NewGuid().ToString("N") + ".txt")
    # Read-only attach is enough for compact and reduces risk of accidental writes.
    $diskpartScript = @(
        "select vdisk file=`"$Path`""
        "attach vdisk readonly"
        "compact vdisk"
        "detach vdisk"
    )

    try {
        Set-Content -Path $scriptPath -Value $diskpartScript -Encoding ASCII
        $output = & diskpart.exe /s $scriptPath 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            throw "diskpart failed with exit code $LASTEXITCODE. Output: $output"
        }

        if ($output -notmatch "DiskPart successfully compacted the virtual disk file") {
            throw "diskpart did not report successful compact. Output: $output"
        }
    }
    finally {
        Remove-Item -Path $scriptPath -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-WslLinuxCleanup {
    [OutputType([void])]
    param()

    # wsl --list --quiet may return UTF-16 wide chars on some Windows builds; strip null bytes.
    $rawList = & wsl.exe --list --quiet 2>$null
    $distros = $rawList -replace '\0', '' | ForEach-Object { $_.Trim() } | Where-Object { $_ }

    if (-not $distros) {
        Write-Host "No WSL distributions found for Linux pre-cleanup." -ForegroundColor Yellow
        return
    }

    # Ordered: free space first, then TRIM so the compactor sees zeroed blocks.
    # Keep this sequence conservative and non-fatal per step to maximize compaction odds.
    $cleanupSteps = @(
        @{ Desc = "Remove APT package cache";      Cmd = "apt-get clean -y 2>/dev/null || true" }
        @{ Desc = "Remove orphaned packages";      Cmd = "apt-get autoremove -y 2>/dev/null || true" }
        @{ Desc = "Truncate systemd journal";      Cmd = "journalctl --vacuum-size=50M 2>/dev/null || true" }
        @{ Desc = "Clear temporary files";         Cmd = "rm -rf /tmp/* /var/tmp/* 2>/dev/null || true" }
        @{ Desc = "Prune Docker resources";        Cmd = "command -v docker >/dev/null 2>&1 && docker system prune -f || true" }
        @{ Desc = "TRIM free blocks (fstrim)";     Cmd = "fstrim -av 2>/dev/null || true" }
    )

    foreach ($distro in $distros) {
        Write-Host "Running Linux cleanup on: $distro" -ForegroundColor Cyan
        foreach ($step in $cleanupSteps) {
            Write-Host "  [$distro] $($step.Desc)..." -ForegroundColor Gray
            try {
                & wsl.exe -d $distro -u root -- bash -c $step.Cmd 2>&1 | Out-Null
            }
            catch {
                Write-Host "  [$distro] '$($step.Desc)' failed (non-fatal): $($_.Exception.Message)" -ForegroundColor DarkYellow
            }
        }
        Write-Host "  [$distro] Linux cleanup complete." -ForegroundColor Green
    }
}

try {
    if (-not (Test-IsAdministrator)) {
        Write-Error "This script requires elevated privileges. Start PowerShell with 'Run as Administrator' and run the script again."
        exit 1
    }

    # Command availability check: this is true when Hyper-V PowerShell management module is installed.
    $canUseOptimizeVhd = $null -ne (Get-Command -Name "Optimize-VHD" -ErrorAction SilentlyContinue)

    Write-Host "Running Linux filesystem cleanup in WSL distributions..." -ForegroundColor Yellow
    Invoke-WslLinuxCleanup

    # Ensure guest writes are flushed before host-side compaction starts.
    Write-Host "Stopping all WSL instances..." -ForegroundColor Yellow
    & wsl.exe --shutdown

    Write-Host "Searching for WSL virtual disks..." -ForegroundColor Yellow
    $vhdxFiles = Get-WslVhdxFiles

    if (-not $vhdxFiles) {
        throw "No WSL virtual disks were found under expected locations."
    }

    $optimized = 0
    $failed = 0

    foreach ($file in $vhdxFiles) {
        $target = $file.FullName
        if ($PSCmdlet.ShouldProcess($target, "Optimize WSL disk")) {
            try {
                Write-Host "Optimizing disk: $target" -ForegroundColor Cyan

                if ($canUseOptimizeVhd) {
                    try {
                        Optimize-VHD -Path $target -Mode $Mode
                        Write-Host "Optimization complete via Optimize-VHD: $target" -ForegroundColor Green
                    }
                    catch {
                        # Common failure case: Hyper-V WMI/provider classes are unavailable.
                        Write-Host "Optimize-VHD failed, falling back to diskpart compact for: $target" -ForegroundColor Yellow
                        Invoke-DiskPartCompact -Path $target
                        Write-Host "Optimization complete via diskpart: $target" -ForegroundColor Green
                    }
                }
                else {
                    Write-Host "Optimize-VHD not available, using diskpart compact for: $target" -ForegroundColor Yellow
                    Invoke-DiskPartCompact -Path $target
                    Write-Host "Optimization complete via diskpart: $target" -ForegroundColor Green
                }

                $optimized++
            }
            catch {
                Write-Host "Failed to optimize $target : $($_.Exception.Message)" -ForegroundColor Red
                $failed++
            }
        }
    }

    Write-Host "Optimization summary: optimized=$optimized failed=$failed total=$($vhdxFiles.Count)" -ForegroundColor Yellow

    if ($failed -gt 0) {
        exit 1
    }
}
catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
