# Bayonetta (Steam) – Keyboard & Mouse Fix

A fix for the Steam release of **Bayonetta (2009)** (AppID 460790): keyboard
and mouse bindings show up **empty**, or **keep disappearing**, so the game can
only be played with a controller.

## Quick start

1. Download the ZIP (Releases page, or **Code → Download ZIP**) and extract it anywhere.
2. Double-click **`Fix Bayonetta Keyboard and Mouse.bat`**.
   It asks to close Steam if it is open, makes a backup, and resets the broken settings.
3. Launch Bayonetta → **Options → Controls → Keyboard/Mouse** → press **HOME**
   on your keyboard (`Pos1` on German keyboards). All bindings fill in.
   Rebind anything you like, then back out so the game saves.

You only have to do this once. If Steam shows a **Cloud Conflict** window the first
time you launch, pick the files on **this computer** (local).

> **Why does step 3 have to be done in the game?** The game's default bindings
> only exist inside `Bayonetta.exe`, and the settings file is encrypted, so no
> outside tool can safely write the defaults. Pressing HOME tells the game to
> load its own built-in defaults, which is the only reliable way to do it.

### What's in the folder

| File | What it does |
|---|---|
| `Fix Bayonetta Keyboard and Mouse.bat` | **The fix.** Backs up, then resets the corrupted settings file. |
| `Restore Backup.bat` | Undo: puts back the files the fix backed up. |
| `Play Bayonetta (No Mouse Accel).bat` | Optional launcher (details below). |
| `tools/BayonettaKBMFix.ps1` | The script all three `.bat` files run. Plain text, so you can read it. |

## What's actually wrong (research summary)

* **No default bindings.** The PC port starts with an empty keyboard/mouse
  binding table. Nothing responds to the keyboard until it gets filled in. The
  game's hidden fix is the **HOME key** on the Controls screen, which loads
  its built-in defaults. The game never tells you this.
* **Bindings disappear later.** All settings, including bindings, are stored
  in one encrypted file, `system_data`. Once that file breaks, the bindings
  come back empty every time you launch. The documented fix is to delete it
  and let the game make a new one.
* **Steam Cloud brings the broken file back.** The game keeps **two** copies:
  * `%USERPROFILE%\Documents\Bayonetta\system_data`
  * `<Steam>\userdata\<your id>\460790\remote\system_data` (synced by Steam Cloud)

  Deleting only the Documents copy, which is what most forum posts say, often
  doesn't stick: the cloud copy is still there and gets restored. This tool
  backs up and removes **both**, for every Steam account on the PC, with Steam
  closed so it can't sync in between.
* **Rebinding trap.** The game won't accept a key in one column while *both*
  columns of that action are empty. That's why rebinding from a blank table
  seems broken. Press HOME first, then rebind.

### What the fix touches

* Only files named exactly `system_data`. **Save slots are never touched**
  (they are separate files in the same `remote` folder).
* Before deleting anything, it copies every file to
  `Documents\Bayonetta KBM Fix Backups\<date-time>\` and writes a
  `manifest.json` there, so `Restore Backup.bat` knows where each file goes.
* It doesn't change `Bayonetta.exe`, game files, or the registry.
* Resetting `system_data` also resets your other options (graphics, audio,
  camera) to their defaults.

### Optional: `Play Bayonetta (No Mouse Accel).bat`

Players report that the mouse camera feels accelerated, and that
sensitivity jumps after a dodge. The game has no setting for this. The
launcher turns off Windows **"Enhance pointer precision"** (the mouse
acceleration setting), starts the game through Steam, and turns it back on
when you quit. The change is never saved to your Windows profile, so if the
window gets closed early, signing out or rebooting brings your old setting back.

This helps if the acceleration you feel comes from Windows. It cannot remove
acceleration that is coded into the game itself, so treat it as worth a try.
Keep the window open while you play.

## Troubleshooting

| Problem | What to do |
|---|---|
| "Could not find your Steam folder" | Steam is installed somewhere unusual. Open PowerShell in this folder and run `powershell -ExecutionPolicy Bypass -File tools\BayonettaKBMFix.ps1 -SteamPath "D:\Your\Steam"` |
| Bindings are still empty after the fix | You still need to press **HOME** on the Controls → Keyboard screen (step 3). |
| Bindings vanish again after a while | Run the fix again. If it keeps coming back, turn off Steam Cloud for Bayonetta (Library → right-click → Properties → General → *Keep game saves in the Steam Cloud*), run the fix, then turn it back on. |
| Keyboard stops responding while a controller is connected | Try turning off Steam Input for Bayonetta (Properties → Controller → *Disable Steam Input*), or unplug the controller. |
| HP bars / HUD vanished | That's **F8**, which toggles the HUD. Press it again. |
| Windows SmartScreen warning | Click *More info → Run anyway*. The `.bat` files only call the included `.ps1` script, which you can read. |

## Advanced usage

```
powershell -ExecutionPolicy Bypass -File tools\BayonettaKBMFix.ps1 [-Action Fix|Restore|Play]
           [-SteamPath <dir>] [-DocumentsPath <dir>] [-Yes] [-NoPause]
```

## Development

Run the tests (needs PowerShell 7 `pwsh`; they build a fake Steam folder in your temp directory):

```
pwsh ./tests/Run-Tests.ps1
# run the tool under Windows PowerShell 5.1 instead:
$env:TEST_SHELL = 'powershell'; pwsh ./tests/Run-Tests.ps1
```

CI runs the tests on Windows PowerShell 5.1, PowerShell 7 on Windows, and
PowerShell 7 on Linux, then packages the release ZIP. Pushing a tag like `v1.0.0`
attaches the ZIP to a GitHub release.

## Sources

* PCGamingWiki – [Bayonetta](https://www.pcgamingwiki.com/wiki/Bayonetta)
  (config/save locations, encrypted `system_data`, HOME-key reset, two-column rebinding bug, mouse acceleration)
* Steam Community – [Bayonetta Troubleshooting Guide](https://steamcommunity.com/sharedfiles/filedetails/?id=3156924632)
  (HOME/Pos1 fix for vanishing bindings, F8 HUD toggle)
* Steam discussions – [keyboard has no defaults](https://steamcommunity.com/app/460790/discussions/0/135514507322155875),
  [bindings reset](https://steamcommunity.com/app/460790/discussions/0/135514402722031362),
  [system_data deletion](https://steamcommunity.com/app/460790/discussions/0/1729827777349790792)
* [BayoHook](https://github.com/SSSiyan/BayoHook) (save folder layout, Steam executable research)

Not affiliated with PlatinumGames, SEGA or Valve.
