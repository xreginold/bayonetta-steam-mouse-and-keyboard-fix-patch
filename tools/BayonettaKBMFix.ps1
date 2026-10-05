<#
.SYNOPSIS
    Bayonetta (Steam, AppID 460790) keyboard & mouse fix.

.DESCRIPTION
    Fixes the long-standing "keyboard bindings are empty / keep disappearing"
    bug in the Steam release of Bayonetta, and provides an optional launcher
    that disables Windows mouse acceleration while the game runs.

    Actions:
      Fix      (default) Back up and reset the corrupted settings file
               "system_data" in BOTH places the game keeps it:
                 * %USERPROFILE%\Documents\Bayonetta\system_data
                 * <Steam>\userdata\<id>\460790\remote\system_data (Steam Cloud)
               Save slots are never touched - only the file named system_data.
      Restore  Put back the files saved by a previous Fix run.
      Play     Launch the game through Steam with "Enhance pointer precision"
               turned off, then restore the user's setting when the game exits.

    Written for Windows PowerShell 5.1 (ships with Windows 10/11). ASCII only
    on purpose so 5.1 reads it correctly without a BOM.
#>
[CmdletBinding()]
param(
    [ValidateSet('Fix', 'Restore', 'Play')]
    [string]$Action = 'Fix',

    # Overrides, mainly for testing or unusual setups.
    [string]$SteamPath,
    [string]$DocumentsPath,

    # Answer "yes" to every prompt (non-interactive).
    [switch]$Yes,
    # Do not wait for a key press before exiting.
    [switch]$NoPause,
    # Skip checks for running Steam / Bayonetta processes (testing only).
    [switch]$SkipProcessCheck
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$AppId          = '460790'
$SettingsFile   = 'system_data'
$GameExeName    = 'Bayonetta'
$BackupDirName  = 'Bayonetta KBM Fix Backups'
$ManifestName   = 'manifest.json'

# ---------------------------------------------------------------- output ----

function Write-Banner {
    Write-Host ''
    Write-Host '=============================================================' -ForegroundColor Magenta
    Write-Host '   Bayonetta (Steam) - Keyboard & Mouse Fix' -ForegroundColor Magenta
    Write-Host '=============================================================' -ForegroundColor Magenta
    Write-Host ''
}
function Write-Step($m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Write-Info($m) { Write-Host "    $m" }
function Write-Ok($m)   { Write-Host "    [OK] $m" -ForegroundColor Green }
function Write-Warn2($m){ Write-Host "    [!]  $m" -ForegroundColor Yellow }
function Write-Err($m)  { Write-Host "    [X]  $m" -ForegroundColor Red }

function Confirm-Choice([string]$Question) {
    if ($Yes) { return $true }
    $answer = Read-Host "$Question [Y/n]"
    return ($answer -eq '' -or $answer -match '^(y|yes)$')
}

function Exit-Script([int]$Code) {
    if (-not $NoPause) {
        Write-Host ''
        Read-Host 'Press Enter to close this window' | Out-Null
    }
    exit $Code
}

# --------------------------------------------------------------- discovery ---

function Get-RegistryValue([string]$Key, [string]$Name) {
    try {
        if (Test-Path -LiteralPath $Key) {
            $item = Get-ItemProperty -LiteralPath $Key -ErrorAction Stop
            if ($item.PSObject.Properties[$Name]) { return [string]$item.$Name }
        }
    } catch { }
    return $null
}

function Get-SteamRoot {
    $candidates = @()
    if ($SteamPath) { $candidates += $SteamPath }
    $candidates += Get-RegistryValue 'HKCU:\Software\Valve\Steam' 'SteamPath'
    $candidates += Get-RegistryValue 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' 'InstallPath'
    $candidates += Get-RegistryValue 'HKLM:\SOFTWARE\Valve\Steam' 'InstallPath'
    if (${env:ProgramFiles(x86)}) { $candidates += (Join-Path ${env:ProgramFiles(x86)} 'Steam') }
    if ($env:ProgramFiles)        { $candidates += (Join-Path $env:ProgramFiles 'Steam') }

    foreach ($c in $candidates) {
        if (-not $c) { continue }
        $p = $c -replace '/', [IO.Path]::DirectorySeparatorChar
        if (Test-Path -LiteralPath (Join-Path $p 'steamapps')) { return $p }
        if (Test-Path -LiteralPath (Join-Path $p 'userdata'))  { return $p }
    }
    return $null
}

function Get-SteamLibraries([string]$SteamRoot) {
    $libs = New-Object System.Collections.Generic.List[string]
    $libs.Add($SteamRoot)
    $vdf = Join-Path (Join-Path $SteamRoot 'steamapps') 'libraryfolders.vdf'
    if (Test-Path -LiteralPath $vdf) {
        $text = Get-Content -LiteralPath $vdf -Raw
        foreach ($m in [regex]::Matches($text, '"path"\s+"([^"]+)"')) {
            $p = $m.Groups[1].Value -replace '\\\\', '\'
            $p = $p -replace '[\\/]', [IO.Path]::DirectorySeparatorChar
            if (-not $libs.Contains($p)) { $libs.Add($p) }
        }
    }
    return $libs
}

function Find-GameDir([string]$SteamRoot) {
    foreach ($lib in (Get-SteamLibraries $SteamRoot)) {
        $apps = Join-Path $lib 'steamapps'
        $acf  = Join-Path $apps "appmanifest_$AppId.acf"
        $installDir = 'Bayonetta'
        if (Test-Path -LiteralPath $acf) {
            $m = [regex]::Match((Get-Content -LiteralPath $acf -Raw), '"installdir"\s+"([^"]+)"')
            if ($m.Success) { $installDir = $m.Groups[1].Value }
        }
        $dir = Join-Path (Join-Path $apps 'common') $installDir
        if (Test-Path -LiteralPath (Join-Path $dir "$GameExeName.exe")) { return $dir }
    }
    return $null
}

function Get-CloudDirs([string]$SteamRoot) {
    $result = @()
    $userdata = Join-Path $SteamRoot 'userdata'
    if (-not (Test-Path -LiteralPath $userdata)) { return $result }
    foreach ($user in (Get-ChildItem -LiteralPath $userdata -Directory -ErrorAction SilentlyContinue)) {
        $remote = Join-Path (Join-Path $user.FullName $AppId) 'remote'
        if (Test-Path -LiteralPath $remote) {
            $result += [pscustomobject]@{ UserId = $user.Name; Path = $remote }
        }
    }
    return $result
}

function Get-DocumentsRoots {
    $roots = New-Object System.Collections.Generic.List[string]
    $candidates = @()
    if ($DocumentsPath) {
        $candidates += $DocumentsPath
    } else {
        # MyDocuments follows OneDrive / folder redirection; the others catch
        # setups where the game resolved Documents differently.
        $candidates += [Environment]::GetFolderPath('MyDocuments')
        if ($env:USERPROFILE) { $candidates += (Join-Path $env:USERPROFILE 'Documents') }
        if ($env:OneDrive)    { $candidates += (Join-Path $env:OneDrive 'Documents') }
    }
    foreach ($c in $candidates) {
        if ($c -and -not $roots.Contains($c)) { $roots.Add($c) }
    }
    return $roots
}

# --------------------------------------------------------------- processes ---

function Test-ProcessRunning([string]$Name) {
    return [bool](Get-Process -Name $Name -ErrorAction SilentlyContinue)
}

function Wait-ProcessGone([string]$Name, [int]$Seconds) {
    for ($i = 0; $i -lt $Seconds; $i++) {
        if (-not (Test-ProcessRunning $Name)) { return $true }
        Start-Sleep -Seconds 1
    }
    return -not (Test-ProcessRunning $Name)
}

function Assert-GameAndSteamClosed([string]$SteamRoot) {
    if ($SkipProcessCheck) { return }

    if (Test-ProcessRunning $GameExeName) {
        Write-Warn2 'Bayonetta is running. Please quit the game first.'
        if (-not $Yes) { Read-Host 'Close Bayonetta, then press Enter to continue' | Out-Null }
        if (-not (Wait-ProcessGone $GameExeName 10)) {
            Write-Err 'Bayonetta is still running. Nothing was changed.'
            Exit-Script 2
        }
    }

    if (Test-ProcessRunning 'steam') {
        Write-Info 'Steam is running. It must be closed so Steam Cloud cannot'
        Write-Info 'put the broken settings file straight back.'
        if (-not (Confirm-Choice '    Close Steam now?')) {
            Write-Err 'Steam must be closed. Nothing was changed.'
            Exit-Script 2
        }
        $steamExe = Join-Path $SteamRoot 'steam.exe'
        if (Test-Path -LiteralPath $steamExe) {
            Start-Process -FilePath $steamExe -ArgumentList '-shutdown' | Out-Null
        }
        Write-Info 'Waiting for Steam to shut down...'
        if (-not (Wait-ProcessGone 'steam' 60)) {
            Write-Err 'Steam did not close. Exit it from the tray icon and run this again.'
            Exit-Script 2
        }
        Write-Ok 'Steam closed.'
    }
}

# ------------------------------------------------------------------ actions --

function Get-BackupBase {
    $docs = @(Get-DocumentsRoots)[0]
    return (Join-Path $docs $BackupDirName)
}

function Invoke-Fix {
    Write-Step 'Locating Steam'
    $steamRoot = Get-SteamRoot
    if (-not $steamRoot) {
        Write-Err 'Could not find your Steam folder.'
        Write-Info 'Run again with:  -SteamPath "D:\Path\To\Steam"'
        Exit-Script 1
    }
    Write-Ok "Steam: $steamRoot"

    $gameDir = Find-GameDir $steamRoot
    if ($gameDir) { Write-Ok "Bayonetta: $gameDir" }
    else          { Write-Warn2 'Bayonetta install folder not found (continuing; only settings are touched).' }

    Assert-GameAndSteamClosed $steamRoot

    Write-Step 'Looking for the broken settings file (system_data)'
    $targets = @()
    foreach ($root in (Get-DocumentsRoots)) {
        $f = Join-Path (Join-Path $root 'Bayonetta') $SettingsFile
        if (Test-Path -LiteralPath $f) {
            $targets += [pscustomobject]@{ Label = 'Documents'; Path = (Resolve-Path -LiteralPath $f).Path }
        }
    }
    foreach ($cloud in (Get-CloudDirs $steamRoot)) {
        $f = Join-Path $cloud.Path $SettingsFile
        if (Test-Path -LiteralPath $f) {
            $targets += [pscustomobject]@{ Label = "SteamCloud-$($cloud.UserId)"; Path = (Resolve-Path -LiteralPath $f).Path }
        }
    }
    # The same file can be reached through two Documents paths.
    $targets = @($targets | Sort-Object -Property Path -Unique)

    if ($targets.Count -eq 0) {
        Write-Ok 'No system_data found - your settings are already fresh.'
    } else {
        foreach ($t in $targets) { Write-Info "found: $($t.Path)" }

        Write-Step 'Backing up'
        $stamp     = Get-Date -Format 'yyyyMMdd-HHmmss'
        $backupDir = Join-Path (Get-BackupBase) $stamp
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        $manifest = @()
        $i = 0
        foreach ($t in $targets) {
            $i++
            $name = "$i-$($t.Label)-$SettingsFile"
            Copy-Item -LiteralPath $t.Path -Destination (Join-Path $backupDir $name) -Force
            $manifest += [pscustomobject]@{ Backup = $name; Original = $t.Path }
        }
        ConvertTo-Json -InputObject @($manifest) | Set-Content -LiteralPath (Join-Path $backupDir $ManifestName) -Encoding UTF8
        Write-Ok "Backup saved to: $backupDir"

        Write-Step 'Resetting settings'
        foreach ($t in $targets) {
            Remove-Item -LiteralPath $t.Path -Force
            Write-Ok "removed $($t.Path)"
        }
    }

    Write-Host ''
    Write-Host '=============================================================' -ForegroundColor Green
    Write-Host '  DONE. One last step inside the game (takes 5 seconds):' -ForegroundColor Green
    Write-Host '=============================================================' -ForegroundColor Green
    Write-Host @'

  1. Start Steam and launch Bayonetta.
     If Steam shows a "Cloud Conflict" window, choose the files on
     THIS COMPUTER (local), not the cloud copy.
  2. Main menu -> Options -> Controls -> Keyboard / Mouse.
  3. Press the HOME key on your keyboard (near Page Up / End;
     labelled "Pos1" on German keyboards).
     All bindings fill in with the defaults.
  4. Change any keys you want, then back out so the game saves.

  Rebinding tip: the game will not accept a key in one column while
  BOTH columns of that action are empty. Press HOME first, then rebind.

  To undo: double-click "Restore Backup.bat".
'@
    if ($gameDir) {
        Write-Host '  Optional: "Play Bayonetta (No Mouse Accel).bat" starts the game with'
        Write-Host '  Windows mouse acceleration off and turns it back on afterwards.'
    }
}

function Invoke-Restore {
    $base = Get-BackupBase
    Write-Step "Looking for backups in $base"
    $sets = @()
    if (Test-Path -LiteralPath $base) {
        $sets = @(Get-ChildItem -LiteralPath $base -Directory |
                  Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName $ManifestName) } |
                  Sort-Object Name -Descending)
    }
    if ($sets.Count -eq 0) {
        Write-Err 'No backups found.'
        Exit-Script 1
    }

    $chosen = $sets[0]
    if (-not $Yes -and $sets.Count -gt 1) {
        for ($i = 0; $i -lt $sets.Count; $i++) { Write-Info "[$($i + 1)] $($sets[$i].Name)" }
        $pick = Read-Host '    Which backup? (Enter = newest)'
        if ($pick -match '^\d+$' -and [int]$pick -ge 1 -and [int]$pick -le $sets.Count) {
            $chosen = $sets[[int]$pick - 1]
        }
    }
    Write-Ok "Using backup $($chosen.Name)"

    $steamRoot = Get-SteamRoot
    Assert-GameAndSteamClosed $steamRoot

    $entries = Get-Content -LiteralPath (Join-Path $chosen.FullName $ManifestName) -Raw | ConvertFrom-Json
    foreach ($e in @($entries)) {
        $src = Join-Path $chosen.FullName $e.Backup
        $dir = Split-Path -Parent $e.Original
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Copy-Item -LiteralPath $src -Destination $e.Original -Force
        Write-Ok "restored $($e.Original)"
    }
    Write-Host ''
    Write-Ok 'Restore complete.'
}

$MouseNative = @'
using System;
using System.Runtime.InteropServices;
public static class BayoMouse {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SystemParametersInfo(uint action, uint param, int[] vparam, uint winIni);
    public const uint SPI_GETMOUSE = 0x0003;
    public const uint SPI_SETMOUSE = 0x0004;
    public const uint SPIF_SENDCHANGE = 0x0002;
}
'@

function Invoke-Play {
    $isWin = ($env:OS -eq 'Windows_NT')
    if (-not $isWin) { Write-Err 'Play mode only works on Windows.'; Exit-Script 1 }

    Add-Type -TypeDefinition $MouseNative
    $original = New-Object int[] 3
    [void][BayoMouse]::SystemParametersInfo([BayoMouse]::SPI_GETMOUSE, 0, $original, 0)
    Write-Step "Current mouse settings: threshold $($original[0]), $($original[1]); acceleration $($original[2])"

    # Not persisted to the user profile (no SPIF_UPDATEINIFILE), so even if this
    # window is closed early, a sign-out or reboot brings the old setting back.
    $flat = [int[]](0, 0, 0)
    [void][BayoMouse]::SystemParametersInfo([BayoMouse]::SPI_SETMOUSE, 0, $flat, [BayoMouse]::SPIF_SENDCHANGE)
    Write-Ok 'Mouse acceleration ("Enhance pointer precision") disabled.'

    try {
        Write-Step 'Launching Bayonetta through Steam'
        Start-Process "steam://rungameid/$AppId" | Out-Null
        $started = $false
        for ($i = 0; $i -lt 180; $i++) {
            if (Test-ProcessRunning $GameExeName) { $started = $true; break }
            Start-Sleep -Seconds 1
        }
        if (-not $started) {
            Write-Warn2 'Bayonetta did not start within 3 minutes.'
        } else {
            Write-Ok 'Game running. Leave this window open; it restores your mouse setting when you quit.'
            while (Test-ProcessRunning $GameExeName) { Start-Sleep -Seconds 2 }
        }
    } finally {
        [void][BayoMouse]::SystemParametersInfo([BayoMouse]::SPI_SETMOUSE, 0, $original, [BayoMouse]::SPIF_SENDCHANGE)
        Write-Ok 'Mouse settings restored.'
    }
}

# --------------------------------------------------------------------- main --

Write-Banner
try {
    switch ($Action) {
        'Fix'     { Invoke-Fix }
        'Restore' { Invoke-Restore }
        'Play'    { Invoke-Play; $NoPause = $true }
    }
} catch {
    Write-Err $_.Exception.Message
    Write-Info 'Stopped. Any files backed up before the error are in:'
    Write-Info (Get-BackupBase)
    Exit-Script 1
}
Exit-Script 0
