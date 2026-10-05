# Self-contained tests for tools/BayonettaKBMFix.ps1 (no Pester needed).
# Builds a fake Steam + Documents tree in a temp folder and runs Fix/Restore.
$ErrorActionPreference = 'Stop'
$script = Join-Path (Split-Path -Parent $PSScriptRoot) 'tools/BayonettaKBMFix.ps1'
$sep = [IO.Path]::DirectorySeparatorChar
$failures = 0
# TEST_SHELL=powershell runs the tool under Windows PowerShell 5.1 instead of pwsh.
$shell = if ($env:TEST_SHELL) { $env:TEST_SHELL } else { 'pwsh' }

function Assert($cond, $msg) {
    if ($cond) { Write-Host "PASS  $msg" -ForegroundColor Green }
    else { Write-Host "FAIL  $msg" -ForegroundColor Red; $script:failures++ }
}

function New-FakeEnv {
    $root  = Join-Path ([IO.Path]::GetTempPath()) ("bayofix-" + [guid]::NewGuid())
    $steam = Join-Path $root 'Steam'
    $lib2  = Join-Path $root 'Library 2'
    $docs  = Join-Path $root 'Docs'
    New-Item -ItemType Directory -Force -Path (Join-Path $steam 'steamapps') | Out-Null
    $game = Join-Path $lib2 'steamapps/common/Bayonetta'
    New-Item -ItemType Directory -Force -Path $game | Out-Null
    Set-Content (Join-Path $game 'Bayonetta.exe') 'x'
    Set-Content (Join-Path $lib2 'steamapps/appmanifest_460790.acf') "`"AppState`"`n{`n`t`"appid`"`t`t`"460790`"`n`t`"installdir`"`t`t`"Bayonetta`"`n}"
    $escaped = $lib2 -replace '\\', '\\\\'
    Set-Content (Join-Path $steam 'steamapps/libraryfolders.vdf') "`"libraryfolders`"`n{`n`t`"0`"`n`t{`n`t`t`"path`"`t`t`"$($steam -replace '\\','\\\\')`"`n`t}`n`t`"1`"`n`t{`n`t`t`"path`"`t`t`"$escaped`"`n`t}`n}"

    foreach ($uid in '11111', '22222') {
        $remote = Join-Path $steam "userdata/$uid/460790/remote"
        New-Item -ItemType Directory -Force -Path $remote | Out-Null
        Set-Content (Join-Path $remote 'system_data') "cloud-settings-$uid"
        Set-Content (Join-Path $remote 'savedata00') "save-$uid"
    }
    New-Item -ItemType Directory -Force -Path (Join-Path $steam 'userdata/33333/999') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $docs 'Bayonetta') | Out-Null
    Set-Content (Join-Path $docs 'Bayonetta/system_data') 'doc-settings'
    return [pscustomobject]@{ Root = $root; Steam = $steam; Docs = $docs; Game = $game }
}

function Invoke-Tool($envInfo, $action) {
    $out = & $shell -NoProfile -ExecutionPolicy Bypass -File $script -Action $action -SteamPath $envInfo.Steam -DocumentsPath $envInfo.Docs -Yes -NoPause -SkipProcessCheck 2>&1 | Out-String
    return [pscustomobject]@{ Code = $LASTEXITCODE; Output = $out }
}

# --- Fix ---------------------------------------------------------------------
$e = New-FakeEnv
$r = Invoke-Tool $e 'Fix'
Assert ($r.Code -eq 0) "Fix exits 0"
Assert ($r.Output -match [regex]::Escape($e.Game)) "Fix finds game in secondary library via libraryfolders.vdf"
Assert (-not (Test-Path (Join-Path $e.Docs 'Bayonetta/system_data'))) "Documents system_data removed"
Assert (-not (Test-Path (Join-Path $e.Steam 'userdata/11111/460790/remote/system_data'))) "Cloud system_data removed (user 1)"
Assert (-not (Test-Path (Join-Path $e.Steam 'userdata/22222/460790/remote/system_data'))) "Cloud system_data removed (user 2)"
Assert ((Get-Content (Join-Path $e.Steam 'userdata/11111/460790/remote/savedata00')) -eq 'save-11111') "Save slots untouched"
$backups = @(Get-ChildItem (Join-Path $e.Docs 'Bayonetta KBM Fix Backups') -Directory)
Assert ($backups.Count -eq 1) "One backup set created"
$files = @(Get-ChildItem $backups[0].FullName -File | Where-Object Name -ne 'manifest.json')
Assert ($files.Count -eq 3) "Backup contains 3 files"

# --- Fix again (nothing to do) ----------------------------------------------
$r = Invoke-Tool $e 'Fix'
Assert ($r.Code -eq 0 -and $r.Output -match 'already fresh') "Second Fix is a no-op"

# --- Restore -----------------------------------------------------------------
$r = Invoke-Tool $e 'Restore'
Assert ($r.Code -eq 0) "Restore exits 0"
Assert ((Get-Content (Join-Path $e.Docs 'Bayonetta/system_data')) -eq 'doc-settings') "Documents system_data restored"
Assert ((Get-Content (Join-Path $e.Steam 'userdata/22222/460790/remote/system_data')) -eq 'cloud-settings-22222') "Cloud system_data restored"

# --- Missing Steam -----------------------------------------------------------
# Linux only: on Windows the tool would fall back to the registry and could
# find (and reset) a real Steam install.
if (-not $IsWindows) {
    $r = & $shell -NoProfile -ExecutionPolicy Bypass -File $script -Action Fix -SteamPath (Join-Path $e.Root 'nope') -DocumentsPath $e.Docs -Yes -NoPause -SkipProcessCheck 2>&1 | Out-String
    Assert ($LASTEXITCODE -eq 1 -and $r -match 'Could not find your Steam folder') "Missing Steam fails cleanly"
}

# --- Restore with no backups -------------------------------------------------
$e2 = New-FakeEnv
$r = Invoke-Tool $e2 'Restore'
Assert ($r.Code -eq 1 -and $r.Output -match 'No backups found') "Restore without backups fails cleanly"

Remove-Item -Recurse -Force $e.Root, $e2.Root
if ($failures) { Write-Host "$failures test(s) failed" -ForegroundColor Red; exit 1 }
Write-Host 'All tests passed' -ForegroundColor Green
