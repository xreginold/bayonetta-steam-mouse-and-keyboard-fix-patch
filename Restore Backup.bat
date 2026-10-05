@echo off
rem Undo "Fix Bayonetta Keyboard and Mouse.bat" by restoring the backed-up settings.
title Bayonetta Keyboard ^& Mouse Fix - Restore
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\BayonettaKBMFix.ps1" -Action Restore
