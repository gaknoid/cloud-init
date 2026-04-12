[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$SettingsPath
)

$ErrorActionPreference = "Stop"

# Cache distro start checks so repeated profile references do not re-launch WSL probes.
$script:WslStartableCache = @{}

function Get-WindowsTerminalSettingsPaths {
    [OutputType([string[]])]
    param()

    $candidates = @(
        (Join-Path $env:LOCALAPPDATA "Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json")
        (Join-Path $env:LOCALAPPDATA "Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json")
    )

    return $candidates | Where-Object { Test-Path $_ }
}

function Get-WslDistros {
    [OutputType([string[]])]
    param()

    try {
        # Wrap in @() so empty output becomes an empty array (not $null).
        $raw = @(& wsl.exe --list --quiet 2>$null)
        if (-not $raw) {
            return @()
        }

        # Some Windows builds return wide-character output with embedded nulls.
        $distros = @(
            $raw |
                ForEach-Object { ($_ -replace '\0', '').Trim() } |
                Where-Object { $_ }
        )

        return $distros
    }
    catch {
        return @()
    }
}

function Get-CommandlineExecutable {
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Commandline
    )

    # Extract executable token from a shell command line.
    $trimmed = $Commandline.Trim()
    if (-not $trimmed) {
        return $null
    }

    if ($trimmed -match '^"([^"]+)"') {
        return $matches[1]
    }

    return ($trimmed -split '\s+', 2)[0]
}

function Test-ExecutableExists {
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ExecutableToken
    )

    $expanded = [Environment]::ExpandEnvironmentVariables($ExecutableToken)

    if ([IO.Path]::IsPathRooted($expanded) -or $expanded -match '^[A-Za-z]:\\') {
        return (Test-Path -LiteralPath $expanded)
    }

    return $null -ne (Get-Command -Name $expanded -ErrorAction SilentlyContinue)
}

function Get-WslDistroFromCommandline {
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Commandline
    )

    # Handle both: -d Name and --distribution Name.
    if ($Commandline -match '(?:^|\s)-d\s+"([^"]+)"') {
        return $matches[1]
    }
    if ($Commandline -match '(?:^|\s)-d\s+([^\s]+)') {
        return $matches[1]
    }
    if ($Commandline -match '(?:^|\s)--distribution\s+"([^"]+)"') {
        return $matches[1]
    }
    if ($Commandline -match '(?:^|\s)--distribution\s+([^\s]+)') {
        return $matches[1]
    }

    return $null
}

function Get-WslDistroFromProfile {
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$TerminalEntry
    )

    $commandline = $null
    $entryName = $null

    if ($TerminalEntry.PSObject.Properties["commandline"]) {
        $commandline = $TerminalEntry.PSObject.Properties["commandline"].Value
    }
    if ($TerminalEntry.PSObject.Properties["name"]) {
        $entryName = $TerminalEntry.PSObject.Properties["name"].Value
    }

    if ($commandline) {
        $distroFromCmd = Get-WslDistroFromCommandline -Commandline $commandline
        if ($distroFromCmd) {
            return $distroFromCmd
        }
    }

    if ($entryName) {
        return $entryName
    }

    return $null
}

function Test-WslDistroStartable {
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DistroName
    )

    if ($script:WslStartableCache.ContainsKey($DistroName)) {
        return [bool]$script:WslStartableCache[$DistroName]
    }

    $startable = $false
    try {
        # Use /bin/true as a fast, non-interactive probe for distro launchability.
        $null = & wsl.exe --distribution $DistroName --exec /bin/true 2>$null
        $startable = ($LASTEXITCODE -eq 0)
    }
    catch {
        $startable = $false
    }

    $script:WslStartableCache[$DistroName] = $startable
    return $startable
}

function Test-IsWslProfile {
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$TerminalEntry
    )

    $entrySource = $null
    $commandline = $null

    if ($TerminalEntry.PSObject.Properties["source"]) {
        $entrySource = $TerminalEntry.PSObject.Properties["source"].Value
    }
    if ($TerminalEntry.PSObject.Properties["commandline"]) {
        $commandline = $TerminalEntry.PSObject.Properties["commandline"].Value
    }

    if ($entrySource -eq "Microsoft.WSL" -or $entrySource -eq "Windows.Terminal.Wsl") {
        return $true
    }

    if ($commandline) {
        $distroFromCmd = Get-WslDistroFromCommandline -Commandline $commandline
        if ($distroFromCmd) {
            return $true
        }

        $exe = Get-CommandlineExecutable -Commandline $commandline
        if ($exe) {
            $exeName = [IO.Path]::GetFileNameWithoutExtension($exe)
            if ($exeName -and $exeName -ieq "wsl") {
                return $true
            }
        }
    }

    return $false
}

function Test-ProfileExists {
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$TerminalEntry,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$WslDistros
    )

    $commandline = $null
    if ($TerminalEntry.PSObject.Properties["commandline"]) {
        $commandline = $TerminalEntry.PSObject.Properties["commandline"].Value
    }

    if (Test-IsWslProfile -TerminalEntry $TerminalEntry) {
        $distroName = Get-WslDistroFromProfile -TerminalEntry $TerminalEntry
        if (-not $distroName) {
            return $false
        }

        return (Test-WslDistroStartable -DistroName $distroName)
    }

    if ($commandline) {
        $exe = Get-CommandlineExecutable -Commandline $commandline
        if ($exe) {
            return (Test-ExecutableExists -ExecutableToken $exe)
        }
    }

    # If there is no explicit commandline, avoid hiding dynamic profiles we cannot verify safely.
    return $true
}

function Test-ValidGuid {
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$GuidString
    )

    if ([string]::IsNullOrWhiteSpace($GuidString)) {
        return $false
    }

    # Attempt to parse the string as a GUID; return true only if successful.
    try {
        [Guid]::Parse($GuidString) | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

function Hide-MissingProfilesInSettings {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$WslDistros,
        [Parameter(Mandatory = $false)]
        [bool]$WriteChanges = $true
    )

    # Preserve JSON-first editing to avoid brittle line-by-line mutation.
    $rawJson = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $settings = $rawJson | ConvertFrom-Json

    if (-not $settings.profiles -or -not $settings.profiles.list) {
        return [pscustomobject]@{
            Path      = $Path
            Removed   = 0
            Processed = 0
        }
    }

    $removedCount = 0
    $processed = 0
    $removedGuids = @()
    $replacementGuids = @{}
    $updatedProfiles = @()
    $discoveredWslDistros = @{}
    $keptSourceGeneratedWslProfileGuids = @{}

    foreach ($distro in $WslDistros) {
        if (-not [string]::IsNullOrWhiteSpace($distro)) {
            $discoveredWslDistros[$distro.ToLowerInvariant()] = $true
        }
    }

    foreach ($entryId in $settings.profiles.list) {
        $processed++

        # Check for invalid GUID first; remove profile if GUID is malformed.
        $profileGuid = $null
        if ($entryId.PSObject.Properties["guid"]) {
            $profileGuid = $entryId.PSObject.Properties["guid"].Value
        }

        if (-not (Test-ValidGuid -GuidString $profileGuid)) {
            $removedCount++
            $name = $null
            if ($entryId.PSObject.Properties["name"]) {
                $name = $entryId.PSObject.Properties["name"].Value
            }
            if (-not $name) { $name = "<unnamed>" }
            Write-Host "  Removed profile with invalid GUID: $name (guid: $profileGuid)" -ForegroundColor Yellow

            if ($profileGuid) {
                $removedGuids += $profileGuid
            }

            continue
        }

        $isWslProfile = Test-IsWslProfile -TerminalEntry $entryId
        $name = $null
        if ($entryId.PSObject.Properties["name"]) {
            $name = $entryId.PSObject.Properties["name"].Value
        }
        if (-not $name) { $name = "<unnamed>" }

        if ($isWslProfile) {
            # Only make WSL-specific removal decisions when distro discovery succeeded.
            if ($discoveredWslDistros.Count -eq 0) {
                $updatedProfiles += $entryId
                continue
            }

            $distroName = Get-WslDistroFromProfile -TerminalEntry $entryId
            if (-not $distroName) {
                $removedCount++
                Write-Host "  Removed undetected WSL profile: $name" -ForegroundColor Yellow

                if ($profileGuid) {
                    $removedGuids += $profileGuid
                }

                continue
            }

            $normalizedDistroName = $distroName.ToLowerInvariant()
            if (-not $discoveredWslDistros.ContainsKey($normalizedDistroName)) {
                $removedCount++
                Write-Host "  Removed undetected WSL profile: $name" -ForegroundColor Yellow

                if ($profileGuid) {
                    $removedGuids += $profileGuid
                }

                continue
            }

            if (-not (Test-WslDistroStartable -DistroName $distroName)) {
                $removedCount++
                Write-Host "  Removed unstartable WSL profile: $name" -ForegroundColor Yellow

                if ($profileGuid) {
                    $removedGuids += $profileGuid
                }

                continue
            }

            $source = $null
            if ($entryId.PSObject.Properties["source"]) {
                $source = $entryId.PSObject.Properties["source"].Value
            }

            $hasCommandline = $false
            if ($entryId.PSObject.Properties["commandline"] -and $entryId.PSObject.Properties["commandline"].Value) {
                $hasCommandline = $true
            }

            $isSourceGeneratedWslProfile = (
                ($source -eq "Microsoft.WSL" -or $source -eq "Windows.Terminal.Wsl") -and
                -not $hasCommandline
            )

            if ($isSourceGeneratedWslProfile) {
                if ($keptSourceGeneratedWslProfileGuids.ContainsKey($normalizedDistroName)) {
                    $removedCount++
                    $removedGuids += $profileGuid
                    $replacementGuids[$profileGuid] = $keptSourceGeneratedWslProfileGuids[$normalizedDistroName]
                    Write-Host "  Removed duplicate WSL profile: $name" -ForegroundColor Yellow
                    continue
                }

                $keptSourceGeneratedWslProfileGuids[$normalizedDistroName] = $profileGuid
            }

            $updatedProfiles += $entryId
            continue
        }

        $exists = Test-ProfileExists -TerminalEntry $entryId -WslDistros $WslDistros

        if (-not $exists) {
            $removedCount++
            Write-Host "  Removed missing profile: $name" -ForegroundColor Yellow

            if ($profileGuid) {
                $removedGuids += $profileGuid
            }

            continue
        }

        $updatedProfiles += $entryId
    }

    $settings.profiles.list = @($updatedProfiles)

    if ($settings.PSObject.Properties["defaultProfile"] -and $settings.defaultProfile) {
        if ($replacementGuids.ContainsKey($settings.defaultProfile)) {
            $settings.defaultProfile = $replacementGuids[$settings.defaultProfile]
            Write-Host "  Repointed defaultProfile to the surviving WSL profile" -ForegroundColor Yellow
        }

        if ($removedGuids -contains $settings.defaultProfile) {
            Write-Host "  Removed invalid defaultProfile that pointed to a deleted WSL profile" -ForegroundColor Yellow
            $settings.defaultProfile = $null
        }
    }

    if ($WriteChanges) {
        # Always write a side-by-side backup before mutating settings.json.
        $backupPath = "$Path.bak"
        Copy-Item -LiteralPath $Path -Destination $backupPath -Force

        $updatedJson = $settings | ConvertTo-Json -Depth 50
        Set-Content -LiteralPath $Path -Value $updatedJson -Encoding UTF8
    }

    return [pscustomobject]@{
        Path      = $Path
        Removed   = $removedCount
        Processed = $processed
    }
}

$paths = if ($SettingsPath) {
    if (-not (Test-Path -LiteralPath $SettingsPath)) {
        throw "Specified settings path does not exist: $SettingsPath"
    }
    @($SettingsPath)
}
else {
    Get-WindowsTerminalSettingsPaths
}

if (-not $paths) {
    throw "No Windows Terminal settings.json files found. Install/open Windows Terminal first, or pass -SettingsPath."
}

$wslDistros = @(Get-WslDistros)

Write-Host "Discovered WSL distros: $($wslDistros -join ', ')" -ForegroundColor Cyan
if (-not $wslDistros -or $wslDistros.Count -eq 0) {
    Write-Host "Warning: WSL distro discovery returned no entries; strict start checks may remove all WSL profiles." -ForegroundColor Yellow
}

$totalRemoved = 0
$totalProcessed = 0

foreach ($path in $paths) {
    Write-Host "Processing settings: $path" -ForegroundColor Cyan
    $writeChanges = $PSCmdlet.ShouldProcess($path, "Write updated Windows Terminal settings")
    $result = Hide-MissingProfilesInSettings -Path $path -WslDistros $wslDistros -WriteChanges:$writeChanges
    $totalRemoved += $result.Removed
    $totalProcessed += $result.Processed
    Write-Host "  Summary for file: processed=$($result.Processed) removed=$($result.Removed)" -ForegroundColor Gray
}

Write-Host "Done. Total profiles processed=$totalProcessed removed=$totalRemoved" -ForegroundColor Green
