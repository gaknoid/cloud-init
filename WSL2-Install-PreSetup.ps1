[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$SystemWide
)

# Ensure script stops on errors.
$ErrorActionPreference = "Stop"

# Force TLS 1.2+ for all web requests.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

function Test-IsAdministrator {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($currentIdentity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-OsArchitecture {
    [OutputType([string])]
    param()

    # Detect OS architecture rather than process bitness.
    $osArch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLowerInvariant()
    switch ($osArch) {
        "x64"   { return "x64" }
        "arm64" { return "arm64" }
        default {
            throw "Unsupported OS architecture for usbipd-win MSI selection: $osArch"
        }
    }
}

function Get-RegistryStringValue {
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

    try {
        $value = (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name
    }
    catch {
        return ""
    }

    if ($null -eq $value) {
        return ""
    }

    return ([string]$value) -replace '[\x00-\x1F\x7F]', ''
}

function Install-UsbipdWin {
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [bool]$IsAdministrator
    )

    # Keep install/skip/failure counters consistent with the font-install summary style.
    $result = [ordered]@{
        Installed = 0
        Skipped   = 0
        Failed    = 0
    }

    # Any resolvable usbipd command means the tool is already available.
    if ($null -ne (Get-Command -Name "usbipd" -ErrorAction SilentlyContinue)) {
        Write-Host "usbipd-win is already installed, skipping." -ForegroundColor Gray
        $result.Skipped++
        return [pscustomobject]$result
    }

    if (-not $IsAdministrator) {
        Write-Host "usbipd-win install requires an elevated PowerShell session. Re-run as Administrator." -ForegroundColor Red
        $result.Failed++
        return [pscustomobject]$result
    }

    # Stage MSI in a unique temp directory and always clean it up in finally.
    $usbipdTempDir = Join-Path $env:TEMP ("usbipd-win-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $usbipdTempDir -Force | Out-Null

    try {
        $targetArch = Get-OsArchitecture
        Write-Host "Detected OS architecture: $targetArch" -ForegroundColor Gray

        Write-Host "Resolving latest usbipd-win MSI from GitHub releases..." -ForegroundColor Gray
        $release = Invoke-RestMethod -Uri "https://api.github.com/repos/dorssel/usbipd-win/releases/latest" -Headers @{ "User-Agent" = "PowerShell" }
        $msiAssets = $release.assets | Where-Object { $_.name -match "\\.msi$" }
        $msiAsset = $msiAssets | Where-Object { $_.name -match "(?i)(^|[-_.])$targetArch([-.]|\\.msi$)" } | Select-Object -First 1

        if (-not $msiAsset -and $msiAssets.Count -eq 1) {
            # Fallback when a release exposes exactly one MSI.
            $msiAsset = $msiAssets[0]
            Write-Host "No architecture tag found in MSI name; using sole MSI asset: $($msiAsset.name)" -ForegroundColor Yellow
        }

        if (-not $msiAsset) {
            $available = ($msiAssets | ForEach-Object { $_.name }) -join ", "
            Write-Host "Unable to locate a usbipd-win MSI for architecture '$targetArch'. Available MSI assets: $available" -ForegroundColor Red
            $result.Failed++
            return [pscustomobject]$result
        }

        $msiPath = Join-Path $usbipdTempDir $msiAsset.name

        if ($PSCmdlet.ShouldProcess("$($msiAsset.browser_download_url)", "Download usbipd-win MSI")) {
            Write-Host "Downloading: $($msiAsset.name)..." -ForegroundColor Gray
            Invoke-WebRequest -Uri $msiAsset.browser_download_url -OutFile $msiPath -UseBasicParsing
        }

        if ($PSCmdlet.ShouldProcess($msiPath, "Install usbipd-win MSI")) {
            $msiArgs = @("/i", "`"$msiPath`"", "/qn", "/norestart")
            $proc = Start-Process -FilePath "msiexec.exe" -ArgumentList $msiArgs -Wait -PassThru -NoNewWindow

            if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010) {
                Write-Host "usbipd-win installed successfully." -ForegroundColor Green
                if ($proc.ExitCode -eq 3010) {
                    Write-Host "A reboot is required to complete installation changes." -ForegroundColor Yellow
                }
                $result.Installed++

                try {
                    $usbipdVersion = (& usbipd --version 2>$null | Select-Object -First 1).Trim()
                    if ($usbipdVersion) {
                        Write-Host "usbipd-win version: $usbipdVersion" -ForegroundColor Green
                    }
                    else {
                        Write-Host "usbipd-win installed, but version output was empty." -ForegroundColor Yellow
                    }
                }
                catch {
                    Write-Host "usbipd-win installed, but failed to read version: $($_.Exception.Message)" -ForegroundColor Yellow
                }
            }
            else {
                Write-Host "usbipd-win MSI installation failed with exit code $($proc.ExitCode)." -ForegroundColor Red
                $result.Failed++
            }
        }
    }
    catch {
        Write-Host "usbipd-win installation failed: $($_.Exception.Message)" -ForegroundColor Red
        $result.Failed++
    }
    finally {
        Remove-Item -Path $usbipdTempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    return [pscustomobject]$result
}

# Ubuntu Mono font files sourced from the Google Fonts repository (Ubuntu Font Licence).
$fontFiles = @(
    @{ Name = "UbuntuMono-Regular.ttf";     Url = "https://github.com/google/fonts/raw/main/ufl/ubuntumono/UbuntuMono-Regular.ttf"    }
    @{ Name = "UbuntuMono-Bold.ttf";        Url = "https://github.com/google/fonts/raw/main/ufl/ubuntumono/UbuntuMono-Bold.ttf"       }
    @{ Name = "UbuntuMono-Italic.ttf";      Url = "https://github.com/google/fonts/raw/main/ufl/ubuntumono/UbuntuMono-Italic.ttf"     }
    @{ Name = "UbuntuMono-BoldItalic.ttf";  Url = "https://github.com/google/fonts/raw/main/ufl/ubuntumono/UbuntuMono-BoldItalic.ttf" }
)

# Registry display names used by Windows font enumeration.
$fontRegistryNames = @{
    "UbuntuMono-Regular.ttf"    = "Ubuntu Mono Regular (TrueType)"
    "UbuntuMono-Bold.ttf"       = "Ubuntu Mono Bold (TrueType)"
    "UbuntuMono-Italic.ttf"     = "Ubuntu Mono Italic (TrueType)"
    "UbuntuMono-BoldItalic.ttf" = "Ubuntu Mono Bold Italic (TrueType)"
}

$isAdmin = Test-IsAdministrator

if ($SystemWide -and -not $isAdmin) {
    Write-Error "System-wide installation requires elevated privileges. Run as Administrator or omit -SystemWide for a per-user install."
    exit 1
}

# Determine install destination and registry hive.
if ($SystemWide -or $isAdmin) {
    $fontDestination  = "$env:SystemRoot\Fonts"
    $registryPath     = "HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Fonts"
    $installScope     = "system-wide"
}
else {
    $fontDestination  = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Fonts"
    $registryPath     = "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts"
    $installScope     = "per-user"
}

if (-not (Test-Path $fontDestination)) {
    New-Item -ItemType Directory -Path $fontDestination -Force | Out-Null
}

# Persist key variables for future shells and WSL sessions.
Write-Host "Setting Windows environment variables (setx)..." -ForegroundColor Cyan
if ($PSCmdlet.ShouldProcess("GNUPGHOME", "setx.exe GNUPGHOME `"$env:USERPROFILE\.gnupg`"")) {
    try {
        & setx.exe GNUPGHOME "$env:USERPROFILE\.gnupg" | Out-Null
        Write-Host "GNUPGHOME set to $env:USERPROFILE\.gnupg" -ForegroundColor Green
    }
    catch {
        Write-Host "Failed to set GNUPGHOME: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

if ($PSCmdlet.ShouldProcess("WSLENV", "setx.exe WSLENV `"USERNAME:USERPROFILE/p`"")) {
    try {
        & setx.exe WSLENV "USERNAME:USERPROFILE/p" | Out-Null
        Write-Host "WSLENV set to USERNAME:USERPROFILE/p" -ForegroundColor Green
    }
    catch {
        Write-Host "Failed to set WSLENV: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

Write-Host "Updating WSL components..." -ForegroundColor Cyan
if ($PSCmdlet.ShouldProcess("WSL", "wsl.exe --update")) {
    try {
        & wsl.exe --update | Out-Null
        Write-Host "WSL update completed." -ForegroundColor Green
    }
    catch {
        Write-Host "Failed to update WSL: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

Write-Host "Installing Ubuntu Mono fonts ($installScope) to: $fontDestination" -ForegroundColor Cyan

$tempDir = Join-Path $env:TEMP ("ubuntu-mono-fonts-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

try {
    $installed = 0
    $skipped   = 0
    $failed    = 0

    foreach ($font in $fontFiles) {
        $destPath = Join-Path $fontDestination $font.Name
        $regName = $fontRegistryNames[$font.Name]
        $existingRegistryValue = if ($regName) { Get-RegistryStringValue -Path $registryPath -Name $regName } else { "" }
        $expectedRegistryValue = if ($installScope -eq "per-user") { $destPath } else { $font.Name }

        # Treat file + expected registry value as the idempotency check for an installed font.
        if ((Test-Path $destPath) -and (($regName -and $existingRegistryValue -eq $expectedRegistryValue) -or -not $regName)) {
            Write-Host "  Already installed, skipping: $($font.Name)" -ForegroundColor Gray
            $skipped++
            continue
        }

        $tempPath = Join-Path $tempDir $font.Name

        Write-Host "  Downloading: $($font.Name)..." -ForegroundColor Gray
        try {
            Invoke-WebRequest -Uri $font.Url -OutFile $tempPath -UseBasicParsing
        }
        catch {
            Write-Host "  Failed to download $($font.Name): $($_.Exception.Message)" -ForegroundColor Red
            $failed++
            continue
        }

        if ($PSCmdlet.ShouldProcess($destPath, "Install font")) {
            try {
                Copy-Item -Path $tempPath -Destination $destPath -Force

                if ($regName) {
                    # Per-user registry stores the full path; system registry stores only the filename.
                    $regValue = $expectedRegistryValue
                    Set-ItemProperty -Path $registryPath -Name $regName -Value $regValue -Type String -Force
                }

                Write-Host "  Installed: $($font.Name)" -ForegroundColor Green
                $installed++
            }
            catch {
                Write-Host "  Failed to install $($font.Name): $($_.Exception.Message)" -ForegroundColor Red
                $failed++
            }
        }
    }

    Write-Host ""
    Write-Host "Font installation summary: installed=$installed skipped=$skipped failed=$failed" -ForegroundColor Yellow

    Write-Host ""
    Write-Host "Installing usbipd-win..." -ForegroundColor Cyan
    $usbipdResult = Install-UsbipdWin -IsAdministrator:$isAdmin
    Write-Host "usbipd-win summary: installed=$($usbipdResult.Installed) skipped=$($usbipdResult.Skipped) failed=$($usbipdResult.Failed)" -ForegroundColor Yellow

    Write-Host ""
    Write-Host "Setting Ubuntu Insights consent to opt-out (n)..." -ForegroundColor Cyan
    if ($PSCmdlet.ShouldProcess("HKCU:\Software\Canonical\Ubuntu\UbuntuInsightsConsent", "Set Ubuntu Insights consent to 0")) {
        try {
            if (-not (Test-Path -Path "HKCU:\Software\Canonical\Ubuntu")) {
                New-Item -Path "HKCU:\Software\Canonical\Ubuntu" -Force | Out-Null
            }
            Set-ItemProperty -Path "HKCU:\Software\Canonical\Ubuntu" -Name UbuntuInsightsConsent -Value 0
            Write-Host "Ubuntu Insights consent set to 0 (opt-out)." -ForegroundColor Green
        }
        catch {
            Write-Host "Failed to set Ubuntu Insights consent: $($_.Exception.Message)" -ForegroundColor Red
            $failed++
        }
    }

    # Bubble up any partial failure so automation can stop early.
    $totalFailed = $failed + $usbipdResult.Failed

    if ($totalFailed -gt 0) {
        exit 1
    }

    if ($installed -gt 0) {
        Write-Host "Ubuntu Mono fonts installed successfully. Applications may need to be restarted to pick up new fonts." -ForegroundColor Green
    }
}
finally {
    Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
