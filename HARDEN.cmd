@echo off
REM ==========================================================================
REM  BULKHEAD -- OS HARDENING
REM
REM  Double-click. Windows will ask for administrator permission (UAC), then
REM  you'll see EXACTLY what will change before anything is touched.
REM
REM  Closes the machine-layer gaps no browser setting can reach:
REM    - mDNS off                 stops advertising this device to the LAN
REM    - Multi-homed DNS off      the classic Windows VPN DNS leak
REM    - NetBIOS off              stops broadcasting your hostname
REM    - LLMNR off                stops broadcasting your queries
REM    - Telemetry + ad ID off
REM
REM  Everything is recorded to scripts\revert-state.json.
REM  To undo:  scripts\Revert-Hardening.ps1 -Apply   (elevated)
REM ==========================================================================

setlocal
title Bulkhead -- OS Hardening
cd /d "%~dp0"

REM --- Self-elevate: relaunch through UAC if not already administrator -----
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo   Requesting administrator permission...
    echo   These are system settings, so Windows will ask you to approve.
    echo.
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

if not exist "%~dp0scripts\Harden-Windows.ps1" (
    echo.
    echo   ERROR: scripts\Harden-Windows.ps1 not found.
    echo.
    pause
    exit /b 1
)

set "PS=powershell"
where pwsh >nul 2>&1
if %errorlevel%==0 set "PS=pwsh"

echo.
echo  ========================================================================
echo   STEP 1 of 2 -- DRY RUN. Nothing is changed yet.
echo   Read what it proposes, then decide.
echo  ========================================================================
echo.

%PS% -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Harden-Windows.ps1"

echo.
echo  ========================================================================
echo   STEP 2 of 2 -- APPLY
echo  ========================================================================
echo.
set /p CONFIRM=  Apply the changes listed above? (y/N):

if /i not "%CONFIRM%"=="y" (
    echo.
    echo   Cancelled. Nothing was changed.
    echo.
    pause
    exit /b 0
)

echo.
%PS% -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Harden-Windows.ps1" -Apply

echo.
echo  ========================================================================
echo   Done. REBOOT for the NetBIOS changes to take effect.
echo.
echo   To undo everything:
echo     scripts\Revert-Hardening.ps1 -Apply     (in an elevated PowerShell)
echo  ========================================================================
echo.
pause
endlocal
