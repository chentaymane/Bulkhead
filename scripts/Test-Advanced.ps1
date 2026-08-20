<#
.SYNOPSIS
    Audit the advanced privacy layer: disk, firmware, DNS, ECH, tunnel features.

.DESCRIPTION
    Read-only. Changes nothing. Checks the technologies in
    ..\docs\technology-stack.md and tells you which you have, which you're
    missing, and what to do about each.

    Some checks (BitLocker, TPM, Secure Boot) need elevation. Without it they
    report "needs admin" rather than failing.

.EXAMPLE
    .\Test-Advanced.ps1

.NOTES
    For the full picture also run Test-Leaks.ps1 (network layer).
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
$todo = @()

$IsAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

function Section { param([string]$T)
    Write-Host ""
    Write-Host "  $T" -ForegroundColor Cyan
    Write-Host "  $('-' * 68)" -ForegroundColor DarkGray
}
function Item {
    param([string]$Status,[string]$Name,[string]$Detail,[string]$Fix)
    $col = switch ($Status) {
        'OK'   { 'Green' }  'MISS' { 'Red' }
        'PART' { 'Yellow' } 'ADMIN'{ 'DarkGray' } default { 'Gray' }
    }
    Write-Host ("  {0,-7} {1,-30} {2}" -f "[$Status]", $Name, $Detail) -ForegroundColor $col
    if ($Fix -and $Status -in 'MISS','PART') { $script:todo += $Fix }
}

Write-Host ""
Write-Host "  Advanced privacy audit" -ForegroundColor White
if (-not $IsAdmin) {
    Write-Host "  (not elevated -- disk/firmware checks will be skipped)" -ForegroundColor DarkGray
}

# =========================================================================
Section "Hardware and disk"
# =========================================================================

# Full-disk encryption -- the highest-value item in the whole plan
if ($IsAdmin) {
    try {
        $vols = Get-BitLockerVolume -ErrorAction Stop
        $sys  = $vols | Where-Object { $_.VolumeType -eq 'OperatingSystem' } | Select-Object -First 1
        if ($sys -and $sys.ProtectionStatus -eq 'On') {
            Item 'OK' 'Full-disk encryption' "BitLocker on ($($sys.MountPoint), $($sys.EncryptionMethod))"
        } elseif ($sys) {
            Item 'MISS' 'Full-disk encryption' "BitLocker OFF on $($sys.MountPoint)" `
                 'Enable BitLocker (or VeraCrypt). Without it every other layer is theatre if your laptop is taken.'
        } else {
            Item 'MISS' 'Full-disk encryption' 'no OS volume reported' 'Enable BitLocker or VeraCrypt on the system drive.'
        }
    } catch {
        Item 'PART' 'Full-disk encryption' 'BitLocker cmdlets unavailable (Home edition?)' `
             'Windows Home has no BitLocker. Use VeraCrypt for full-disk encryption: https://veracrypt.io'
    }
} else { Item 'ADMIN' 'Full-disk encryption' 'needs elevation' }

# Secure Boot
if ($IsAdmin) {
    try {
        $sb = Confirm-SecureBootUEFI -ErrorAction Stop
        if ($sb) { Item 'OK' 'Secure Boot' 'enabled' }
        else { Item 'PART' 'Secure Boot' 'disabled' 'Enable Secure Boot in UEFI -- blocks bootkits and evil-maid persistence.' }
    } catch { Item 'PART' 'Secure Boot' 'legacy BIOS or unsupported' 'Machine is not UEFI; Secure Boot unavailable.' }
} else { Item 'ADMIN' 'Secure Boot' 'needs elevation' }

# TPM
if ($IsAdmin) {
    try {
        $tpm = Get-Tpm -ErrorAction Stop
        if ($tpm.TpmPresent -and $tpm.TpmReady) { Item 'OK' 'TPM' "present and ready" }
        elseif ($tpm.TpmPresent) { Item 'PART' 'TPM' 'present, not ready' 'Initialize the TPM (tpm.msc) to back BitLocker keys in hardware.' }
        else { Item 'MISS' 'TPM' 'not present' 'No TPM -- BitLocker will need a password/USB key instead.' }
    } catch { Item 'ADMIN' 'TPM' 'unavailable' }
} else { Item 'ADMIN' 'TPM' 'needs elevation' }

# =========================================================================
Section "DNS"
# =========================================================================

# Windows DoH templates known to the system
try {
    $doh = Get-DnsClientDohServerAddress -ErrorAction Stop
    if ($doh) { Item 'INFO' 'DoH templates known' "$($doh.Count) resolver(s) registered" }
} catch { }

# Is DoH actually in use on an up adapter?
$dohActive = $false
try {
    $ups = Get-NetAdapter | Where-Object Status -eq 'Up'
    foreach ($a in $ups) {
        $k = "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters\$($a.InterfaceGuid)\DohInterfaceSettings"
        if (Test-Path $k) { $dohActive = $true }
    }
} catch { }
if ($dohActive) { Item 'OK' 'Encrypted DNS (DoH)' 'configured on an active adapter' }
else { Item 'MISS' 'Encrypted DNS (DoH)' 'not configured' `
       'Settings > Network > adapter > DNS server assignment > Manual > DNS over HTTPS: On (Quad9 9.9.9.9). REQUIRED for ECH.' }

# The leak paths
$dnsPol = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient'
foreach ($c in @(
    @{N='EnableMulticast';            W=0; L='LLMNR disabled'; F='Run Harden-Windows.ps1 -Apply (LLMNR broadcasts your queries to the LAN).'}
    @{N='EnableMDNS';                 W=0; L='mDNS disabled';  F='Run Harden-Windows.ps1 -Apply (mDNS advertises this device to the LAN).'}
    @{N='DisableSmartNameResolution'; W=1; L='Multi-homed DNS off'; F='Run Harden-Windows.ps1 -Apply -- this is the classic Windows VPN DNS leak.'}
)) {
    $v = $null
    if (Test-Path $dnsPol) { try { $v = (Get-ItemProperty $dnsPol -Name $c.N -EA Stop).($c.N) } catch {} }
    if ($v -eq $c.W) { Item 'OK' $c.L "= $v" } else { Item 'MISS' $c.L 'not set' $c.F }
}

# =========================================================================
Section "ECH (Encrypted Client Hello)"
# =========================================================================
# ECH encrypts the SNI -- the last cleartext hostname field in HTTPS.

$braveLocalState = Join-Path $env:LOCALAPPDATA 'PrivacyPlan\brave-lane2\Local State'
if (Test-Path $braveLocalState) {
    try {
        $ls = Get-Content $braveLocalState -Raw | ConvertFrom-Json
        $labs = $ls.browser.enabled_labs_experiments
        if ($labs -and ($labs -join ',') -match 'encrypted-client-hello') {
            Item 'OK' 'ECH (Brave Lane 2)' 'flag enabled'
        } else {
            Item 'MISS' 'ECH (Brave Lane 2)' 'flag not enabled' `
                 'brave://flags > search "Encrypted ClientHello" > Enabled. Needs encrypted DNS to work at all.'
        }
    } catch { Item 'PART' 'ECH (Brave Lane 2)' 'could not read Local State' }
} else { Item 'INFO' 'ECH (Brave Lane 2)' 'Lane 2 profile not found' }

Write-Host "        Verify live at https://crypto.cloudflare.com/cdn-cgi/trace" -ForegroundColor DarkGray
Write-Host "        Look for sni=encrypted. If it says plaintext, ECH is not active." -ForegroundColor DarkGray

# =========================================================================
Section "Tunnel features"
# =========================================================================

$vpn = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
    $_.Status -eq 'Up' -and (
        $_.InterfaceDescription -match 'WireGuard|OpenVPN|TAP|Wintun|Mullvad|Proton|IVPN|NordLynx' -or
        $_.Name -match 'WireGuard|VPN|Mullvad|Proton'
    )
} | Select-Object -First 1

if ($vpn) {
    Item 'OK' 'VPN interface' $vpn.Name
    Write-Host "        Enable in your VPN client (all free, none raise ban risk):" -ForegroundColor DarkGray
    Write-Host "          Quantum-resistant tunnel  -- defeats harvest-now-decrypt-later" -ForegroundColor DarkGray
    Write-Host "          DAITA                     -- defeats ML traffic-analysis fingerprinting" -ForegroundColor DarkGray
    Write-Host "          Multihop                  -- splits jurisdiction (optional)" -ForegroundColor DarkGray
    Write-Host "          Kill switch               -- required" -ForegroundColor DarkGray
} else {
    Item 'MISS' 'VPN interface' 'no tunnel' `
         'No VPN. Post-quantum, DAITA and multihop are all unavailable until you have one.'
}

# =========================================================================
Section "Identity layer"
# =========================================================================
Write-Host "  Not machine-detectable -- audit yourself against docs\technology-stack.md:" -ForegroundColor DarkGray
Write-Host ""
Write-Host "    [ ] Email aliasing (SimpleLogin / addy.io) -- unique address per site" -ForegroundColor Gray
Write-Host "        Your email is a STRONGER cross-site key than any fingerprint." -ForegroundColor DarkGray
Write-Host "    [ ] Separate email identity per lane" -ForegroundColor Gray
Write-Host "    [ ] Password manager, unique password everywhere" -ForegroundColor Gray
Write-Host "    [ ] Virtual / single-use payment cards" -ForegroundColor Gray
Write-Host "    [ ] Private search (already default in Brave)" -ForegroundColor Gray

# =========================================================================
Write-Host ""
Write-Host "  $('=' * 68)" -ForegroundColor DarkCyan
if ($todo.Count) {
    Write-Host "  DO THESE, in order:" -ForegroundColor White
    Write-Host ""
    $i = 0
    foreach ($t in ($todo | Select-Object -Unique)) { $i++; Write-Host "   $i. $t" -ForegroundColor Yellow }
} else {
    Write-Host "  Advanced layer complete." -ForegroundColor Green
}
Write-Host ""
Write-Host "  Full technology inventory: docs\technology-stack.md" -ForegroundColor DarkGray
Write-Host "  Beating Tor, honestly:     docs\beyond-tor.md" -ForegroundColor DarkGray
Write-Host ""
