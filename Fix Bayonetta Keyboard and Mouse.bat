@echo off
rem One-click fix for Bayonetta (Steam) empty / disappearing keyboard bindings.
title Bayonetta Keyboard ^& Mouse Fix
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\BayonettaKBMFix.ps1" -Action Fix
