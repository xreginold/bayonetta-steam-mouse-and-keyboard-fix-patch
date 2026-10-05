@echo off
rem Launch Bayonetta with Windows mouse acceleration off; restores it when the game exits.
title Bayonetta - mouse acceleration off (keep open while playing)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\BayonettaKBMFix.ps1" -Action Play
