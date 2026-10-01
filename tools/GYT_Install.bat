@echo off
title GYT EA Installer
echo Installing GYT EA into MetaTrader 5, please wait...
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { iex (irm 'https://raw.githubusercontent.com/sotsarangyt/GYT/main/tools/install.ps1') } catch { Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red }"
echo.
pause
