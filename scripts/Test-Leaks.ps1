<#
.SYNOPSIS
    Local leak checks for the network layer. Read-only -- changes nothing.

.DESCRIPTION
    Checks the things you can test from the OS without a browser:
    public IP (v4 and v6), DNS resolvers in use, VPN interface state, routing
    table sanity, and the local-network leak settings.

    This covers L1 only. The browser-layer gauntlet is manual -- see
    ..\testing\CHECKLIST.md.

.EXAMPLE
    .\Test-Leaks.ps1

.NOTES
    Does not require elevation. Makes outbound requests to ifconfig.me and
    ipify.org to discover your public IP -- that is the point of the test.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
$pass = 0; $fail = 0; $warn = 0

function Test-Result {
    param([string]$Name, [ValidateSet('PASS','FAIL','WARN','INFO')][string]$Status, [string]$Detail)
    $col = switch ($Status) { 'PASS'{'Green'} 'FAIL'{'Red'} 'WARN'{'Yellow'} default{'DarkGray'} }
    Write-Host ("  {0,-6} {1,-34} {2}" -f "[$Status]", $Name, $Detail) -ForegroundColor $col
    switch ($Status) { 'PASS'{$script:pass++} 'FAIL'{$script:fail++} 'WARN'{$script:warn++} }
}

Write-Host ""
Write-Host "  Network leak check" -ForegroundColor White
Write-Host "  " ("-" * 70) -ForegroundColor DarkGray
Write-Host ""

# --- 1. Public IP -----------------------------------------------------------
Write-Host "  Public address" -ForegroundColor Cyan

$ip4 = $null; $ip6 = $null
try   { $ip4 = (Invoke-RestMethod -Uri 'https://api.ipify.org' -TimeoutSec 10).Trim() }
catch { }
try   { $ip6 = (Invoke-RestMethod -Uri 'https://api6.ipify.org' -TimeoutSec 8).Trim() }
catch { }

if ($ip4) { Test-Result 'Public IPv4' 'INFO' $ip4 }
else      { Test-Result 'Public IPv4' 'WARN' 'could not determine' }

if ($ip6) {
    Test-Result 'Public IPv6' 'WARN' "$ip6  <- verify this is your VPN, not your ISP"
} else {
    Test-Result 'Public IPv6' 'PASS' 'no IPv6 reachable (no v6 leak path)'
}

if ($ip4 -and $ip6) {
    Write-Host "         Both stacks are reachable. Confirm BOTH resolve to your VPN" -ForegroundColor DarkGray
    Write-Host "         at https://ipleak.net -- a v6 leak defeats a v4 tunnel." -ForegroundColor DarkGray
}

# --- 2. Geolocation ---------------------------------------------------------
Write-Host ""
Write-Host "  Apparent location" -ForegroundColor Cyan
try {
    $trace = Invoke-RestMethod -Uri 'https://www.cloudflare.com/cdn-cgi/trace' -TimeoutSec 10
    $loc = ($trace -split "`n" | Where-Object { $_ -like 'loc=*' }) -replace 'loc=',''
    $warpFlag = ($trace -split "`n" | Where-Object { $_ -like 'warp=*' }) -replace 'warp=',''
    Test-Result 'Country (per Cloudflare)' 'INFO' $loc
    $tz = (Get-TimeZone).Id
    Test-Result 'System timezone' 'INFO' $tz
    Write-Host "         COHERENCE: these two must tell the same story." -ForegroundColor DarkGray
    Write-Host "         IP country '$loc' vs timezone '$tz' -- do they match?" -ForegroundColor DarkGray
} catch {
    Test-Result 'Cloudflare trace' 'WARN' 'unreachable'
}

# --- 3. VPN interface -------------------------------------------------------
Write-Host ""
Write-Host "  VPN interface" -ForegroundColor Cyan

$vpnLike = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
    $_.Status -eq 'Up' -and (
        $_.InterfaceDescription -match 'WireGuard|OpenVPN|TAP|Wintun|Mullvad|Proton|IVPN|NordLynx' -or
        $_.Name -match 'WireGuard|VPN|Mullvad|Proton'
    )
}

if ($vpnLike) {
    foreach ($v in $vpnLike) { Test-Result 'VPN adapter up' 'PASS' "$($v.Name) [$($v.InterfaceDescription)]" }
} else {
    Test-Result 'VPN adapter' 'FAIL' 'no VPN interface detected -- is the tunnel up?'
}

# --- 4. Default route -------------------------------------------------------
Write-Host ""
Write-Host "  Routing" -ForegroundColor Cyan

$defRoutes = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
             Sort-Object RouteMetric
if ($defRoutes) {
    $primary = $defRoutes | Select-Object -First 1
    $ifName = (Get-NetAdapter -InterfaceIndex $primary.ifIndex -ErrorAction SilentlyContinue).Name
    $isVpn = $vpnLike | Where-Object { $_.ifIndex -eq $primary.ifIndex }
    if ($isVpn) { Test-Result 'Default route (IPv4)' 'PASS' "via $ifName (VPN)" }
    else        { Test-Result 'Default route (IPv4)' 'FAIL' "via $ifName -- NOT the VPN" }
}

$defRoutes6 = Get-NetRoute -DestinationPrefix '::/0' -ErrorAction SilentlyContinue
if ($defRoutes6) {
    $p6 = $defRoutes6 | Sort-Object RouteMetric | Select-Object -First 1
    $if6 = (Get-NetAdapter -InterfaceIndex $p6.ifIndex -ErrorAction SilentlyContinue).Name
    $isVpn6 = $vpnLike | Where-Object { $_.ifIndex -eq $p6.ifIndex }
    if ($isVpn6) { Test-Result 'Default route (IPv6)' 'PASS' "via $if6 (VPN)" }
    else         { Test-Result 'Default route (IPv6)' 'FAIL' "via $if6 -- IPv6 bypasses the tunnel" }
} else {
    Test-Result 'Default route (IPv6)' 'PASS' 'none (IPv6 disabled or unrouted)'
}

# --- 5. DNS resolvers -------------------------------------------------------
Write-Host ""
Write-Host "  DNS resolvers in use" -ForegroundColor Cyan

$servers = Get-DnsClientServerAddress -ErrorAction SilentlyContinue |
    Where-Object { $_.ServerAddresses.Count -gt 0 } |
    ForEach-Object {
        $ad = Get-NetAdapter -InterfaceIndex $_.InterfaceIndex -ErrorAction SilentlyContinue
        if ($ad -and $ad.Status -eq 'Up') {
            [pscustomobject]@{ Adapter = $ad.Name; Servers = ($_.ServerAddresses -join ', ') }
        }
    } | Sort-Object Adapter -Unique

foreach ($s in $servers) { Test-Result "DNS on $($s.Adapter)" 'INFO' $s.Servers }
Write-Host "         Confirm ONLY your VPN's resolver appears. Verify externally at" -ForegroundColor DarkGray
Write-Host "         https://dnsleaktest.com (extended test)." -ForegroundColor DarkGray

# --- 6. Local leak settings -------------------------------------------------
Write-Host ""
Write-Host "  Local-network leak settings" -ForegroundColor Cyan

function Test-RegSetting {
    param([string]$Path,[string]$Name,$Want,[string]$Label)
    $val = $null
    if (Test-Path $Path) { try { $val = (Get-ItemProperty $Path -Name $Name -EA Stop).$Name } catch {} }
    if ($val -eq $Want) { Test-Result $Label 'PASS' "= $val" }
    else { Test-Result $Label 'FAIL' "= $(if($null -eq $val){'<unset>'}else{$val}), want $Want -- run Harden-Windows.ps1" }
}

$dnsPol = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient'
Test-RegSetting $dnsPol 'EnableMulticast'            0 'LLMNR disabled'
Test-RegSetting $dnsPol 'EnableMDNS'                 0 'mDNS disabled'
Test-RegSetting $dnsPol 'DisableSmartNameResolution' 1 'Smart multi-homed res. off'

# --- Summary ----------------------------------------------------------------
Write-Host ""
Write-Host "  " ("-" * 70) -ForegroundColor DarkGray
Write-Host ("  {0} passed   {1} failed   {2} warnings" -f $pass, $fail, $warn) -ForegroundColor White

if ($fail -gt 0) {
    Write-Host ""
    Write-Host "  Fix the failures before configuring browsers." -ForegroundColor Red
    Write-Host "  Browser hardening on a leaking tunnel is decoration." -ForegroundColor Red
}

Write-Host ""
Write-Host "  This covers the network layer only. The browser-layer checks" -ForegroundColor DarkGray
Write-Host "  (fingerprint, WebRTC, JA4, CreepJS) are manual:" -ForegroundColor DarkGray
Write-Host "    ..\testing\CHECKLIST.md" -ForegroundColor Cyan
Write-Host ""
