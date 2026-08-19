<#
.SYNOPSIS
    Undo everything Harden-Windows.ps1 changed.

.DESCRIPTION
    Reads revert-state.json (written by Harden-Windows.ps1 -Apply) and restores
    every registry value to what it was, removes the kill-switch firewall rules,
    and reports the hostname change for manual reversal.

    Also dry-run by default. Pass -Apply to actually revert.

.PARAMETER Apply
    Actually revert. Without this, only reports what would be undone.

.PARAMETER RemoveKillSwitchOnly
    Emergency use: remove ONLY the firewall kill-switch rules and nothing else.
    Use this if the kill switch locked you out of the network.
    This one applies immediately -- no -Apply needed, because if you need it,
    you need it now.

.EXAMPLE
    .\Revert-Hardening.ps1
    Show what would be reverted.

.EXAMPLE
    .\Revert-Hardening.ps1 -Apply
    Revert everything.

.EXAMPLE
    .\Revert-Hardening.ps1 -RemoveKillSwitchOnly
    Panic button: restore network access.

.NOTES
    Run elevated.
#>

[CmdletBinding()]
param(
    [switch]$Apply,
    [switch]$RemoveKillSwitchOnly
)

$ErrorActionPreference = 'Stop'
$RevertLog = Join-Path $PSScriptRoot 'revert-state.json'

$admin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { throw "Run this in an elevated PowerShell session." }

# --- Panic button: always applies immediately -------------------------------
if ($RemoveKillSwitchOnly) {
    Write-Host ""
    Write-Host "  Removing kill-switch firewall rules..." -ForegroundColor Yellow
    $n = 0
    foreach ($rule in 'PrivacyPlan-KillSwitch-Block',
                      'PrivacyPlan-KillSwitch-AllowVPN',
                      'PrivacyPlan-KillSwitch-AllowLAN') {
        try {
            Remove-NetFirewallRule -DisplayName $rule -ErrorAction Stop
            Write-Host "    removed: $rule" -ForegroundColor Green
            $n++
        } catch {
            Write-Host "    not present: $rule" -ForegroundColor DarkGray
        }
    }
    Write-Host ""
    Write-Host "  $n rule(s) removed. Network access should be restored." -ForegroundColor Green
    Write-Host ""
    return
}

# --- Normal revert ----------------------------------------------------------
if (-not (Test-Path $RevertLog)) {
    Write-Host ""
    Write-Host "  No revert-state.json found at:" -ForegroundColor Yellow
    Write-Host "    $RevertLog"
    Write-Host "  Either nothing was applied, or the file was moved." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  To remove the kill switch regardless, run:" -ForegroundColor Cyan
    Write-Host "    .\Revert-Hardening.ps1 -RemoveKillSwitchOnly" -ForegroundColor Cyan
    Write-Host ""
    return
}

$changes = Get-Content $RevertLog -Raw | ConvertFrom-Json
$mode = if ($Apply) { 'APPLY' } else { 'DRY-RUN' }

Write-Host ""
Write-Host "  Reverting hardening -- mode: $mode" -ForegroundColor White
Write-Host "  $($changes.Count) change(s) recorded" -ForegroundColor DarkGray
Write-Host ""

foreach ($c in $changes) {
    switch ($c.Kind) {

        'Registry' {
            $shown = if ($null -eq $c.OldValue) { '<delete value>' } else { $c.OldValue }
            Write-Host "  [$mode] $($c.Path)\$($c.Name) -> $shown" -ForegroundColor Yellow

            if ($Apply) {
                if ($null -eq $c.OldValue) {
                    # It didn't exist before -- remove it.
                    Remove-ItemProperty -Path $c.Path -Name $c.Name -ErrorAction SilentlyContinue
                } else {
                    if (-not (Test-Path $c.Path)) { New-Item -Path $c.Path -Force | Out-Null }
                    New-ItemProperty -Path $c.Path -Name $c.Name -Value $c.OldValue `
                        -PropertyType $c.Type -Force | Out-Null
                }
            }
        }

        'Firewall' {
            Write-Host "  [$mode] remove firewall rules PrivacyPlan-KillSwitch-*" -ForegroundColor Yellow
            if ($Apply) {
                foreach ($rule in 'PrivacyPlan-KillSwitch-Block',
                                  'PrivacyPlan-KillSwitch-AllowVPN',
                                  'PrivacyPlan-KillSwitch-AllowLAN') {
                    Remove-NetFirewallRule -DisplayName $rule -ErrorAction SilentlyContinue
                }
            }
        }

        'Hostname' {
            Write-Host "  [MANUAL] hostname was changed: $($c.OldValue) -> $($c.NewValue)" -ForegroundColor Magenta
            Write-Host "           to restore:  Rename-Computer -NewName '$($c.OldValue)' -Force" -ForegroundColor Magenta
            Write-Host "           (not done automatically -- it needs a reboot)" -ForegroundColor DarkGray
        }
    }
}

Write-Host ""
if ($Apply) {
    Remove-Item $RevertLog -Force
    Write-Host "  Revert complete. State file removed." -ForegroundColor Green
    Write-Host "  Reboot to fully restore NetBIOS settings." -ForegroundColor Yellow
} else {
    Write-Host "  Dry run complete. Nothing was changed." -ForegroundColor Yellow
    Write-Host "  Re-run with -Apply to revert." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "  Note: MAC randomization and Wi-Fi settings changed through the" -ForegroundColor DarkGray
Write-Host "  Settings UI are not tracked here -- revert those in Settings." -ForegroundColor DarkGray
Write-Host ""
