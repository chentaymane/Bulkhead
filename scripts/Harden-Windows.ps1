<#
.SYNOPSIS
    Layer-2 / OS hardening for the three-lane privacy browser plan.

.DESCRIPTION
    Handles the machine-and-local-network layer that no browser setting can reach:
    MAC randomization, hostname, local-network name-resolution leaks, Windows
    telemetry, and (optionally) a firewall kill switch.

    RUNS IN DRY-RUN MODE BY DEFAULT. Nothing is changed unless you pass -Apply.
    Read the output of a dry run before applying anything.

    Every change made is logged to a revert file so Revert-Hardening.ps1 can undo it.

.PARAMETER Apply
    Actually make changes. Without this, the script only reports what it would do.

.PARAMETER NewHostname
    Rename the computer to a neutral string. Requires a reboot.
    Your hostname is broadcast on every network you join via DHCP option 12,
    mDNS, and NetBIOS -- and it is very often your real name.

.PARAMETER InstallKillSwitch
    Install Windows Firewall rules that block outbound traffic on any interface
    except the named VPN interface. READ THE WARNING IN THAT SECTION FIRST.

.PARAMETER VpnInterfaceAlias
    Interface alias for your VPN adapter, required with -InstallKillSwitch.
    Find it with:  Get-NetAdapter | Select-Object Name, InterfaceAlias, Status

.EXAMPLE
    .\Harden-Windows.ps1
    Dry run. Shows every proposed change. Changes nothing.

.EXAMPLE
    .\Harden-Windows.ps1 -Apply -NewHostname "DESKTOP-7K2M9X"
    Applies the hardening and renames the machine.

.NOTES
    Run in an ELEVATED PowerShell session.
    Reboot required for hostname and NetBIOS changes to take effect.
#>

[CmdletBinding()]
param(
    [switch]$Apply,
    [string]$NewHostname,
    [switch]$InstallKillSwitch,
    [string]$VpnInterfaceAlias
)

$ErrorActionPreference = 'Stop'
$script:RevertLog = Join-Path $PSScriptRoot 'revert-state.json'
$script:Changes    = @()
$script:Mode       = if ($Apply) { 'APPLY' } else { 'DRY-RUN' }

function Write-Section { param([string]$Text)
    Write-Host ""
    Write-Host ("=" * 74) -ForegroundColor DarkCyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host ("=" * 74) -ForegroundColor DarkCyan
}

function Write-Action { param([string]$Text)
    $tag = if ($Apply) { "[APPLY] " } else { "[WOULD] " }
    $col = if ($Apply) { 'Green' } else { 'Yellow' }
    Write-Host "$tag$Text" -ForegroundColor $col
}

function Write-Info { param([string]$Text)
    Write-Host "        $Text" -ForegroundColor DarkGray
}

# Set a registry value, recording the previous state so it can be reverted.
function Set-HardenedRegValue {
    param(
        [string]$Path, [string]$Name,
        $Value, [string]$Type = 'DWord',
        [string]$Because
    )

    $old = $null
    if (Test-Path $Path) {
        try { $old = (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name } catch { $old = $null }
    }

    if ($old -eq $Value) { Write-Info "already set: $Name = $Value"; return }

    Write-Action "$Path\$Name = $Value  (was: $(if ($null -eq $old) {'<unset>'} else {$old}))"
    if ($Because) { Write-Info $Because }

    $script:Changes += [pscustomobject]@{
        Kind = 'Registry'; Path = $Path; Name = $Name
        OldValue = $old; NewValue = $Value; Type = $Type
    }

    if ($Apply) {
        if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
    }
}

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "  Windows hardening -- mode: $($script:Mode)" -ForegroundColor White
if (-not $Apply) {
    Write-Host "  No changes will be made. Re-run with -Apply once you've read the output." -ForegroundColor Yellow
}

$admin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { throw "Run this in an elevated PowerShell session." }


# ===========================================================================
Write-Section "1. MAC address randomization"
# ===========================================================================
# REALITY CHECK: your MAC address NEVER reaches a website. It is a layer-2
# identifier, stripped and replaced at the first router hop. Randomizing it
# does nothing for web fingerprinting or website bans.
#
# It matters to a different audience: Wi-Fi access points (which see your
# device even when you don't connect, via probe requests), captive portals,
# your router, and network administrators. That is a genuine physical-location
# tracking surface, and worth closing.

Write-Info "Note: MAC is not visible to websites. This defeats Wi-Fi/venue tracking."
Write-Host ""

$wifi = Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
        Where-Object { $_.MediaType -eq 'Native 802.11' -or $_.PhysicalMediaType -like '*802.11*' }

if (-not $wifi) {
    Write-Info "No Wi-Fi adapter detected -- skipping."
} else {
    foreach ($a in $wifi) {
        Write-Host "  Adapter: $($a.Name)  [$($a.InterfaceDescription)]" -ForegroundColor White
        Write-Info "Current MAC: $($a.MacAddress)"

        # Windows exposes per-network random MACs through the Settings UI. Some
        # drivers also expose it as an advanced property; try that first.
        $prop = Get-NetAdapterAdvancedProperty -Name $a.Name -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -match 'Random|Locally Administered|Network Address' }

        if ($prop) {
            Write-Info "Driver exposes: $($prop.DisplayName) = $($prop.DisplayValue)"
            Write-Action "Enable random hardware address on '$($a.Name)'"
        } else {
            Write-Info "Driver does not expose a randomization property."
        }

        Write-Host "  MANUAL STEP (most reliable, per-network):" -ForegroundColor Magenta
        Write-Host "    Settings > Network & Internet > Wi-Fi" -ForegroundColor Magenta
        Write-Host "      -> 'Random hardware addresses' = On" -ForegroundColor Magenta
        Write-Host "      -> per network: Properties > 'Random hardware addresses' = Change daily" -ForegroundColor Magenta
    }
}

Write-Host ""
Write-Info "Also worth doing: forget saved networks you no longer use."
Write-Info "Your device broadcasts saved SSIDs in probe requests -- that list is"
Write-Info "a location history. Review with:  netsh wlan show profiles"


# ===========================================================================
Write-Section "2. Hostname"
# ===========================================================================
# Broadcast via DHCP option 12, mDNS, LLMNR and NetBIOS on every network you
# join. Very frequently contains the owner's real name. Often leaks more than
# the MAC does.

$current = $env:COMPUTERNAME
Write-Info "Current hostname: $current"

if ($current -match '(?i)chent|laptop-|desktop-\w*[a-z]{4}') {
    Write-Host "  NOTE: this hostname may contain identifying information." -ForegroundColor Yellow
}

if ($NewHostname) {
    Write-Action "Rename computer: $current -> $NewHostname  (reboot required)"
    $script:Changes += [pscustomobject]@{ Kind='Hostname'; OldValue=$current; NewValue=$NewHostname }
    if ($Apply) { Rename-Computer -NewName $NewHostname -Force -ErrorAction Stop }
} else {
    Write-Info "Pass -NewHostname to change it. A neutral Windows-default-looking"
    Write-Info "name blends in best, e.g. DESKTOP-7K2M9X (do not invent something exotic)."
}


# ===========================================================================
Write-Section "3. Local-network name-resolution leaks"
# ===========================================================================
# These protocols broadcast your queries -- and your hostname -- to everyone on
# the local network, and can route DNS around your VPN.

$dnsPol = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient'

Set-HardenedRegValue -Path $dnsPol -Name 'EnableMulticast' -Value 0 `
    -Because "Disables LLMNR -- stops broadcasting name queries to the LAN."

Set-HardenedRegValue -Path $dnsPol -Name 'EnableMDNS' -Value 0 `
    -Because "Disables mDNS -- stops advertising this device to the LAN."

Set-HardenedRegValue -Path $dnsPol -Name 'DisableSmartNameResolution' -Value 1 `
    -Because "Stops Windows sending DNS out EVERY interface in parallel -- the classic VPN DNS leak."

Set-HardenedRegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters' `
    -Name 'DisableParallelAandAAAA' -Value 1 `
    -Because "Stops parallel A/AAAA races that can escape the tunnel."

# NetBIOS over TCP/IP, per interface. 2 = disabled.
Write-Host ""
Write-Info "NetBIOS over TCP/IP (broadcasts hostname on the LAN):"
$nbRoot = 'HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces'
if (Test-Path $nbRoot) {
    foreach ($iface in Get-ChildItem $nbRoot) {
        Set-HardenedRegValue -Path $iface.PSPath -Name 'NetbiosOptions' -Value 2 `
            -Because "Disable NetBIOS on $($iface.PSChildName)"
    }
}


# ===========================================================================
Write-Section "4. Windows telemetry and advertising ID"
# ===========================================================================

Set-HardenedRegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' `
    -Name 'AllowTelemetry' -Value 0 -Because "Minimize diagnostic data upload."

Set-HardenedRegValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' `
    -Name 'Enabled' -Value 0 -Because "Disable the per-user advertising ID shared across apps."

Set-HardenedRegValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' `
    -Name 'TailoredExperiencesWithDiagnosticDataEnabled' -Value 0 `
    -Because "Stop tailoring based on diagnostic data."

Set-HardenedRegValue -Path 'HKCU:\Software\Microsoft\Input\TIPC' `
    -Name 'Enabled' -Value 0 -Because "Disable inking and typing telemetry."

Set-HardenedRegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' `
    -Name 'AllowCortana' -Value 0 -Because "Disable Cortana."

Set-HardenedRegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' `
    -Name 'ConnectedSearchUseWeb' -Value 0 `
    -Because "Stop Start-menu searches being sent to Bing."


# ===========================================================================
Write-Section "5. Firewall kill switch (optional)"
# ===========================================================================
# WARNING -----------------------------------------------------------------
# These rules block ALL outbound traffic on every interface except your VPN
# adapter. If the VPN is down, you have NO internet -- which is the point, and
# also how people lock themselves out.
#
# STRONGLY PREFER your VPN client's built-in kill switch, or the WireGuard
# Windows client's "Block untunneled traffic" checkbox. Use this only as a
# third layer, and only after you've confirmed Revert-Hardening.ps1 works.
# -------------------------------------------------------------------------

if (-not $InstallKillSwitch) {
    Write-Info "Not requested. Use your VPN client's kill switch instead -- it handles"
    Write-Info "reconnects, sleep/wake and network changes properly. Pass"
    Write-Info "-InstallKillSwitch -VpnInterfaceAlias '<name>' to add firewall rules too."
} else {
    if (-not $VpnInterfaceAlias) { throw "-InstallKillSwitch requires -VpnInterfaceAlias." }

    $vpnAdapter = Get-NetAdapter -Name $VpnInterfaceAlias -ErrorAction SilentlyContinue
    if (-not $vpnAdapter) {
        Write-Host "  Interface '$VpnInterfaceAlias' not found. Available:" -ForegroundColor Red
        Get-NetAdapter | Format-Table Name, InterfaceAlias, Status -AutoSize | Out-String | Write-Host
        throw "Fix -VpnInterfaceAlias and re-run."
    }

    Write-Host "  This will block outbound traffic on all interfaces except:" -ForegroundColor Yellow
    Write-Host "    $($vpnAdapter.Name)  [$($vpnAdapter.InterfaceDescription)]" -ForegroundColor Yellow
    Write-Host ""

    Write-Action "Create firewall rule 'PrivacyPlan-KillSwitch-Block' (block all outbound)"
    Write-Action "Create firewall rule 'PrivacyPlan-KillSwitch-AllowVPN' (allow on VPN iface)"
    Write-Action "Create firewall rule 'PrivacyPlan-KillSwitch-AllowLAN' (allow RFC1918, for router access)"

    $script:Changes += [pscustomobject]@{ Kind='Firewall'; NewValue='PrivacyPlan-KillSwitch-*' }

    if ($Apply) {
        # Allow rules must exist BEFORE the block rule, or you drop your own session.
        New-NetFirewallRule -DisplayName 'PrivacyPlan-KillSwitch-AllowVPN' `
            -Direction Outbound -Action Allow -InterfaceAlias $VpnInterfaceAlias `
            -Profile Any -Enabled True | Out-Null

        New-NetFirewallRule -DisplayName 'PrivacyPlan-KillSwitch-AllowLAN' `
            -Direction Outbound -Action Allow `
            -RemoteAddress @('192.168.0.0/16','10.0.0.0/8','172.16.0.0/12') `
            -Profile Any -Enabled True | Out-Null

        New-NetFirewallRule -DisplayName 'PrivacyPlan-KillSwitch-Block' `
            -Direction Outbound -Action Block -Profile Any -Enabled True | Out-Null

        Write-Host "  Kill switch active. Test it: disconnect the VPN, then try to browse." -ForegroundColor Green
        Write-Host "  Remove it with: .\Revert-Hardening.ps1" -ForegroundColor Green
    }
}


# ===========================================================================
Write-Section "Summary"
# ===========================================================================

Write-Host "  Mode:            $($script:Mode)"
Write-Host "  Changes staged:  $($script:Changes.Count)"

if ($Apply -and $script:Changes.Count -gt 0) {
    $script:Changes | ConvertTo-Json -Depth 5 | Set-Content -Path $script:RevertLog -Encoding UTF8
    Write-Host "  Revert data:     $($script:RevertLog)" -ForegroundColor Green
    Write-Host ""
    Write-Host "  REBOOT to activate hostname and NetBIOS changes." -ForegroundColor Yellow
} elseif (-not $Apply) {
    Write-Host ""
    Write-Host "  Dry run complete. Nothing was changed." -ForegroundColor Yellow
    Write-Host "  Re-run with -Apply to make these changes." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "  Next: complete the manual Wi-Fi MAC step above, then run the"
Write-Host "  verification gauntlet in ..\testing\CHECKLIST.md"
Write-Host ""
