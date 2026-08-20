@echo off
REM ==========================================================================
REM  THE BUTTON
REM
REM  Double-click this file. It checks everything, fixes what it can, and
REM  opens your hardened browser. No menu, no options, no typing.
REM
REM  For the full menu (install browsers, leak test, Windows hardening),
REM  run Start-Bulkhead.ps1 directly instead.
REM ==========================================================================

setlocal
title Bulkhead -- Automatic
cd /d "%~dp0"

if not exist "%~dp0Start-Bulkhead.ps1" (
    echo.
    echo   ERROR: Start-Bulkhead.ps1 not found next to this file.
    echo   Keep RUN.cmd in the same folder as the rest of the plan.
    echo.
    pause
    exit /b 1
)

REM Prefer PowerShell 7 if installed, otherwise use the Windows built-in.
where pwsh >nul 2>&1
if %errorlevel%==0 (
    pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-Bulkhead.ps1" -Auto
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-Bulkhead.ps1" -Auto
)

endlocal
