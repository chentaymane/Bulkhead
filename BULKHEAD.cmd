@echo off
REM ==========================================================================
REM  BULKHEAD -- one script, everything.
REM
REM  Double-click       -> automatic: check, fix, open the browser
REM  BULKHEAD.cmd menu  -> full menu (lanes, audit, harden, VPN, install)
REM
REM  Runs UNELEVATED on purpose. Browsers must never run as administrator.
REM  The one part that needs admin (Windows hardening) opens its own
REM  elevated window from inside the menu.
REM ==========================================================================

setlocal
title BULKHEAD
cd /d "%~dp0"

REM UTF-8 so the banner renders as block characters instead of mojibake.
chcp 65001 >nul 2>&1

if not exist "%~dp0Bulkhead.ps1" (
    echo.
    echo   ERROR: Bulkhead.ps1 not found next to this file.
    echo   Keep BULKHEAD.cmd in the same folder.
    echo.
    pause
    exit /b 1
)

REM Prefer PowerShell 7, fall back to the Windows built-in.
set "PS=powershell"
where pwsh >nul 2>&1
if %errorlevel%==0 set "PS=pwsh"

REM "menu" as the first argument opens the full menu instead of auto mode.
if /i "%~1"=="menu" (
    %PS% -NoProfile -ExecutionPolicy Bypass -File "%~dp0Bulkhead.ps1"
) else (
    %PS% -NoProfile -ExecutionPolicy Bypass -File "%~dp0Bulkhead.ps1" -Auto
)

endlocal
