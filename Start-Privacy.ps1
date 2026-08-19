<#
.SYNOPSIS
    Single entry point for the three-lane privacy browser plan.

.DESCRIPTION
    Runs preflight leak checks, then launches the right browser in the right
    lane with the right profile. Refuses to open Lanes 2 and 3 while the tunnel
    is down, so you never browse "privately" over your real IP by accident.

    This script LAUNCHES things and READS network state. It does not change any
    system setting -- that is scripts\Harden-Windows.ps1, which you run yourself.

.PARAMETER Lane
    Launch a lane directly and skip the menu: 1, 2, or 3.

.PARAMETER SkipPreflight
    Skip the network checks. Use only when you know the tunnel is fine and you
    want a fast launch.

.PARAMETER Force
    Launch Lane 2/3 even if no VPN interface is detected. Prints a warning.

.EXAMPLE
    .\Start-Privacy.ps1
    Interactive menu with a preflight report.

.EXAMPLE
    .\Start-Privacy.ps1 -Lane 3
    Preflight, then straight into the anonymous lane.

.NOTES
    No elevation required. Run with:
      powershell -ExecutionPolicy Bypass -File ".\Start-Privacy.ps1"
#>

[CmdletBinding()]
param(
    [ValidateSet('1','2','3')][string]$Lane,
    [switch]$SkipPreflight,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot

# ===========================================================================
#  CONFIG -- edit this block once
# ===========================================================================
$Config = @{
    # Country your exit IP should appear in (ISO code), for the coherence check.
    # Should match your system timezone. Leave '' to skip the check.
    ExpectedCountry = ''

    # Lane 2 browser: 'Firefox' or 'Brave'
    Lane2Browser    = 'Firefox'

    # Firefox profile names (created on first use if missing)
    Lane1Profile    = 'lane1-identity'
    Lane2Profile    = 'lane2-daily'

    # Brave gets its own user-data-dir for hard isolation
    BraveDataDir    = Join-Path $env:LOCALAPPDATA 'PrivacyPlan\brave-lane2'
}
# ===========================================================================

# ---------- browser discovery ----------------------------------------------
function Find-Browser {
    param([string[]]$Candidates)
    foreach ($c in $Candidates) {
        $p = [Environment]::ExpandEnvironmentVariables($c)
        if (Test-Path $p) { return $p }
    }
    return $null
}

$Browsers = @{
    Firefox = Find-Browser @(
        '%ProgramFiles%\Mozilla Firefox\firefox.exe'
        '%ProgramFiles(x86)%\Mozilla Firefox\firefox.exe'
        '%LOCALAPPDATA%\Mozilla Firefox\firefox.exe'
    )
    Brave = Find-Browser @(
        '%ProgramFiles%\BraveSoftware\Brave-Browser\Application\brave.exe'
        '%ProgramFiles(x86)%\BraveSoftware\Brave-Browser\Application\brave.exe'
        '%LOCALAPPDATA%\BraveSoftware\Brave-Browser\Application\brave.exe'
    )
    Edge = Find-Browser @(
        '%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe'
        '%ProgramFiles%\Microsoft\Edge\Application\msedge.exe'
    )
    Mullvad = Find-Browser @(
        '%ProgramFiles%\Mullvad Browser\mullvad-browser.exe'
        '%LOCALAPPDATA%\Mullvad Browser\mullvad-browser.exe'
        "$env:USERPROFILE\Desktop\Mullvad Browser\mullvad-browser.exe"
        '%ProgramFiles%\Mullvad Browser\Browser\firefox.exe'
    )
    Tor = Find-Browser @(
        "$env:USERPROFILE\Desktop\Tor Browser\Browser\firefox.exe"
        '%LOCALAPPDATA%\Tor Browser\Browser\firefox.exe'
    )
}

$InstallLinks = @{
    Firefox = 'https://www.mozilla.org/firefox/'
    Brave   = 'https://brave.com/download/'
    Mullvad = 'https://mullvad.net/en/browser'
    Tor     = 'https://www.torproject.org/download/'
    Edge    = 'ships with Windows'
}

# ---------- output helpers --------------------------------------------------
function Write-Head { param([string]$T)
    Write-Host ""
    Write-Host "  $T" -ForegroundColor White
    Write-Host "  $('-' * 68)" -ForegroundColor DarkGray
}
function Write-Row { param([string]$S,[string]$L,[string]$D,[string]$C='Gray')
    Write-Host ("  {0,-7} {1,-26} {2}" -f "[$S]", $L, $D) -ForegroundColor $C
}

# ---------- preflight -------------------------------------------------------
function Invoke-Preflight {
    Write-Head "Preflight"

    $state = [ordered]@{ VpnUp=$false; Ip=$null; Country=$null; Tz=(Get-TimeZone).Id; Coherent=$null }

    # VPN interface
    $vpn = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
        $_.Status -eq 'Up' -and (
            $_.InterfaceDescription -match 'WireGuard|OpenVPN|TAP|Wintun|Mullvad|Proton|IVPN|NordLynx' -or
            $_.Name -match 'WireGuard|VPN|Mullvad|Proton'
        )
    } | Select-Object -First 1

    if ($vpn) {
        $state.VpnUp = $true
        Write-Row 'OK' 'VPN interface' $vpn.Name 'Green'
    } else {
        Write-Row 'DOWN' 'VPN interface' 'no tunnel detected' 'Red'
    }

    # Default route through the tunnel?
    $def = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
           Sort-Object RouteMetric | Select-Object -First 1
    if ($def) {
        $ifn = (Get-NetAdapter -InterfaceIndex $def.ifIndex -ErrorAction SilentlyContinue).Name
        if ($vpn -and $ifn -eq $vpn.Name) { Write-Row 'OK' 'Default route' "via $ifn" 'Green' }
        else { Write-Row 'WARN' 'Default route' "via $ifn (not the VPN)" 'Yellow' }
    }

    # IPv6 escape path
    $def6 = Get-NetRoute -DestinationPrefix '::/0' -ErrorAction SilentlyContinue |
            Sort-Object RouteMetric | Select-Object -First 1
    if (-not $def6) {
        Write-Row 'OK' 'IPv6' 'no route (cannot leak)' 'Green'
    } else {
        $if6 = (Get-NetAdapter -InterfaceIndex $def6.ifIndex -ErrorAction SilentlyContinue).Name
        if ($vpn -and $if6 -eq $vpn.Name) { Write-Row 'OK' 'IPv6' "via $if6" 'Green' }
        else { Write-Row 'LEAK' 'IPv6' "via $if6 -- bypasses the tunnel" 'Red' }
    }

    # Public IP + country
    try {
        $trace = Invoke-RestMethod -Uri 'https://www.cloudflare.com/cdn-cgi/trace' -TimeoutSec 8
        $state.Ip      = (($trace -split "`n" | Where-Object { $_ -like 'ip=*'  }) -replace 'ip=','').Trim()
        $state.Country = (($trace -split "`n" | Where-Object { $_ -like 'loc=*' }) -replace 'loc=','').Trim()
        Write-Row 'INFO' 'Public IP' $state.Ip 'Gray'
        Write-Row 'INFO' 'Apparent country' $state.Country 'Gray'
    } catch {
        Write-Row 'WARN' 'Public IP' 'could not reach Cloudflare trace' 'Yellow'
    }

    # Coherence: country vs timezone
    Write-Row 'INFO' 'System timezone' $state.Tz 'Gray'
    if ($Config.ExpectedCountry -and $state.Country) {
        if ($state.Country -eq $Config.ExpectedCountry) {
            $state.Coherent = $true
            Write-Row 'OK' 'Coherence' "exit country matches expected ($($Config.ExpectedCountry))" 'Green'
        } else {
            $state.Coherent = $false
            Write-Row 'FAIL' 'Coherence' "exit=$($state.Country) expected=$($Config.ExpectedCountry)" 'Red'
        }
    } else {
        Write-Host "          Confirm timezone and exit country tell the same story." -ForegroundColor DarkGray
        Write-Host "          (Lane 3 is the exception -- it reports UTC on purpose.)" -ForegroundColor DarkGray
    }

    return $state
}

# ---------- launchers -------------------------------------------------------
function Assert-Tunnel {
    param([string]$LaneName,[bool]$VpnUp)
    if ($VpnUp -or $Force) {
        if (-not $VpnUp) { Write-Host "  -Force: launching without a tunnel." -ForegroundColor Yellow }
        return $true
    }
    Write-Host ""
    Write-Host "  No VPN detected. $LaneName over your real IP defeats the point." -ForegroundColor Red
    $a = Read-Host "  Launch anyway? (y/N)"
    return ($a -eq 'y')
}

function Start-Lane1 {
    Write-Head "Lane 1 -- Identity"
    $exe = $Browsers.Edge; $kind = 'Edge'
    if (-not $exe) { $exe = $Browsers.Firefox; $kind = 'Firefox' }
    if (-not $exe) { Write-Host "  No Firefox or Edge found." -ForegroundColor Red; return }

    Write-Host "  Real fingerprint, no spoofing, isolated profile." -ForegroundColor DarkGray
    Write-Host "  Use ONLY for banking / government / work." -ForegroundColor DarkGray
    Write-Host ""

    if ($kind -eq 'Firefox') {
        Ensure-FirefoxProfile $Config.Lane1Profile
        Start-Process $exe -ArgumentList @('-P', $Config.Lane1Profile)
    } else {
        $dir = Join-Path $env:LOCALAPPDATA 'PrivacyPlan\edge-lane1'
        Start-Process $exe -ArgumentList @("--user-data-dir=$dir")
    }
    Write-Host "  Launched $kind (Lane 1)." -ForegroundColor Green
}

function Start-Lane2 {
    param([bool]$VpnUp)
    Write-Head "Lane 2 -- Daily"
    if (-not (Assert-Tunnel 'Lane 2' $VpnUp)) { Write-Host "  Cancelled." -ForegroundColor Yellow; return }

    if ($Config.Lane2Browser -eq 'Brave' -and $Browsers.Brave) {
        New-Item -ItemType Directory -Path $Config.BraveDataDir -Force | Out-Null
        Start-Process $Browsers.Brave -ArgumentList @("--user-data-dir=$($Config.BraveDataDir)")
        Write-Host "  Launched Brave (Lane 2)." -ForegroundColor Green
        Write-Host "  Shields: Aggressive + Strict fingerprinting. WebRTC: disable non-proxied UDP." -ForegroundColor DarkGray
    }
    elseif ($Browsers.Firefox) {
        Ensure-FirefoxProfile $Config.Lane2Profile
        Start-Process $Browsers.Firefox -ArgumentList @('-P', $Config.Lane2Profile)
        Write-Host "  Launched Firefox (Lane 2)." -ForegroundColor Green

        $pdir = Get-FirefoxProfilePath $Config.Lane2Profile
        if ($pdir -and -not (Test-Path (Join-Path $pdir 'user.js'))) {
            Write-Host ""
            Write-Host "  This profile has no user.js yet. To harden it:" -ForegroundColor Yellow
            Write-Host "    1. Get arkenfox user.js + updater.ps1  https://github.com/arkenfox/user.js" -ForegroundColor Yellow
            Write-Host "    2. Copy lanes\user-overrides.js next to them" -ForegroundColor Yellow
            Write-Host "    3. Run updater.ps1 in:" -ForegroundColor Yellow
            Write-Host "       $pdir" -ForegroundColor Cyan
        }
    }
    else { Write-Host "  Lane 2 browser not found. Install: $($InstallLinks.Firefox)" -ForegroundColor Red }
}

function Start-Lane3 {
    param([bool]$VpnUp)
    Write-Head "Lane 3 -- Anonymous"
    if (-not (Assert-Tunnel 'Lane 3' $VpnUp)) { Write-Host "  Cancelled." -ForegroundColor Yellow; return }

    if ($Browsers.Mullvad) {
        Start-Process $Browsers.Mullvad
        Write-Host "  Launched Mullvad Browser (Lane 3)." -ForegroundColor Green
    } elseif ($Browsers.Tor) {
        Start-Process $Browsers.Tor
        Write-Host "  Launched Tor Browser (Lane 3)." -ForegroundColor Green
    } else {
        Write-Host "  Not installed. Get Mullvad Browser: $($InstallLinks.Mullvad)" -ForegroundColor Red
        return
    }

    Write-Host ""
    Write-Host "  RULES FOR THIS LANE:" -ForegroundColor Magenta
    Write-Host "    - Change NOTHING. No extensions, no theme, no resize, no about:config." -ForegroundColor Magenta
    Write-Host "    - Log into NOTHING you use in Lane 1 or 2." -ForegroundColor Magenta
    Write-Host "    - Letterbox margins and UTC clock are correct. Leave them." -ForegroundColor Magenta
    Write-Host "    - CAPTCHAs are the price of the crowd. Do not 'fix' them by customizing." -ForegroundColor Magenta
}

# ---------- firefox profile helpers ----------------------------------------
function Get-FirefoxProfilePath {
    param([string]$Name)
    $ini = Join-Path $env:APPDATA 'Mozilla\Firefox\profiles.ini'
    if (-not (Test-Path $ini)) { return $null }
    $lines = Get-Content $ini
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match "^Name=$([regex]::Escape($Name))$") {
            for ($j = $i; $j -lt [Math]::Min($i + 6, $lines.Count); $j++) {
                if ($lines[$j] -match '^Path=(.+)$') {
                    $p = $Matches[1] -replace '/', '\'
                    $isRel = $true
                    for ($k = $i; $k -lt [Math]::Min($i + 6, $lines.Count); $k++) {
                        if ($lines[$k] -match '^IsRelative=0') { $isRel = $false }
                    }
                    return $(if ($isRel) { Join-Path (Join-Path $env:APPDATA 'Mozilla\Firefox') $p } else { $p })
                }
            }
        }
    }
    return $null
}

function Ensure-FirefoxProfile {
    param([string]$Name)
    if (Get-FirefoxProfilePath $Name) { return }
    Write-Host "  Creating Firefox profile '$Name'..." -ForegroundColor Yellow
    Start-Process $Browsers.Firefox -ArgumentList @('-CreateProfile', $Name) -Wait
    Write-Host "  Created." -ForegroundColor Green
}

# ---------- info panels -----------------------------------------------------
function Show-Rotation {
    Write-Head "Does the fingerprint change every launch?"
    Write-Host ""
    Write-Host "  Lane 1  NO  -- real hardware, stable forever. Deliberate." -ForegroundColor Blue
    Write-Host "  Lane 2  PARTLY -- randomized vectors reseed per launch AND per site." -ForegroundColor Yellow
    Write-Host "  Lane 3  NO  -- uniform: same as every other user, every launch." -ForegroundColor Magenta
    Write-Host ""
    Write-Host "  What DOES reseed in Lane 2 (Brave farbling / Firefox FPP):" -ForegroundColor White
    Write-Host "    canvas readback, WebGL readback, audio stack, some timing" -ForegroundColor DarkGray
    Write-Host "    -> stable within a session, different per site, new seed on restart" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  What NEVER changes, in any lane:" -ForegroundColor White
    Write-Host "    JA4/TLS, HTTP/2 order, TCP/IP stack, screen size, fonts," -ForegroundColor DarkGray
    Write-Host "    timezone, CPU cores, RAM, user-agent, and your IP" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  So a fresh canvas hash does NOT make you a new person -- the stable" -ForegroundColor Yellow
    Write-Host "  vectors dominate. A new identity needs a new IP + new profile + new" -ForegroundColor Yellow
    Write-Host "  storage, not canvas noise." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  And rotation is not free: sites use a stable fingerprint as a" -ForegroundColor DarkGray
    Write-Host "  'trusted device' signal, so rotating it can mean MORE 2FA prompts." -ForegroundColor DarkGray
    Write-Host "  See docs\coherence-matrix.md." -ForegroundColor DarkGray
}

function Show-Status {
    Write-Head "Installed browsers"
    foreach ($k in 'Firefox','Brave','Edge','Mullvad','Tor') {
        if ($Browsers[$k]) { Write-Row 'OK' $k $Browsers[$k] 'Green' }
        else { Write-Row '--' $k "not found  $($InstallLinks[$k])" 'DarkGray' }
    }
    Write-Head "Lane 2 browser"
    Write-Host "  $($Config.Lane2Browser)   (change in the CONFIG block at the top of this file)" -ForegroundColor Gray
}

# ---------- menu ------------------------------------------------------------
function Show-Menu {
    param($State)
    Write-Head "Three-Lane Privacy Plan"
    $vpnTag = if ($State.VpnUp) { "VPN up" } else { "VPN DOWN" }
    $vpnCol = if ($State.VpnUp) { 'Green' } else { 'Red' }
    Write-Host "  Tunnel: " -NoNewline; Write-Host $vpnTag -ForegroundColor $vpnCol -NoNewline
    if ($State.Country) { Write-Host "   Exit: $($State.Country)   IP: $($State.Ip)" -ForegroundColor DarkGray }
    else { Write-Host "" }
    Write-Host ""
    Write-Host "   1   Lane 1  Identity    bank / gov / work      real fingerprint" -ForegroundColor Blue
    Write-Host "   2   Lane 2  Daily       shopping / social      hardened, coherent" -ForegroundColor Yellow
    Write-Host "   3   Lane 3  Anonymous   research / reading     uniform crowd" -ForegroundColor Magenta
    Write-Host ""
    Write-Host "   T   Run full leak test        (scripts\Test-Leaks.ps1)" -ForegroundColor Gray
    Write-Host "   H   Windows hardening, dry run (scripts\Harden-Windows.ps1)" -ForegroundColor Gray
    Write-Host "   F   Fingerprint rotation -- does it change every launch?" -ForegroundColor Gray
    Write-Host "   C   Open the verification checklist" -ForegroundColor Gray
    Write-Host "   S   Show installed browsers" -ForegroundColor Gray
    Write-Host "   R   Re-run preflight" -ForegroundColor Gray
    Write-Host "   Q   Quit" -ForegroundColor Gray
    Write-Host ""
}

# ===========================================================================
#  MAIN
# ===========================================================================
Clear-Host
Write-Host ""
Write-Host "  THREE-LANE PRIVACY PLAN" -ForegroundColor White
Write-Host "  $Root" -ForegroundColor DarkGray

$State = if ($SkipPreflight) {
    @{ VpnUp = $true; Ip = $null; Country = $null; Tz = (Get-TimeZone).Id }
} else { Invoke-Preflight }

if ($Lane) {
    switch ($Lane) {
        '1' { Start-Lane1 }
        '2' { Start-Lane2 -VpnUp $State.VpnUp }
        '3' { Start-Lane3 -VpnUp $State.VpnUp }
    }
    Write-Host ""
    return
}

while ($true) {
    Show-Menu -State $State
    $choice = (Read-Host "  Select").Trim().ToUpper()

    switch ($choice) {
        '1' { Start-Lane1 }
        '2' { Start-Lane2 -VpnUp $State.VpnUp }
        '3' { Start-Lane3 -VpnUp $State.VpnUp }
        'T' {
            $t = Join-Path $Root 'scripts\Test-Leaks.ps1'
            if (Test-Path $t) { & $t } else { Write-Host "  Not found: $t" -ForegroundColor Red }
        }
        'H' {
            $h = Join-Path $Root 'scripts\Harden-Windows.ps1'
            if (Test-Path $h) {
                Write-Host "  Dry run -- nothing will be changed." -ForegroundColor Yellow
                Start-Process powershell -ArgumentList @(
                    '-NoExit','-ExecutionPolicy','Bypass','-File',"`"$h`""
                ) -Verb RunAs
            } else { Write-Host "  Not found: $h" -ForegroundColor Red }
        }
        'F' { Show-Rotation }
        'C' {
            $c = Join-Path $Root 'testing\CHECKLIST.md'
            if (Test-Path $c) { Start-Process $c } else { Write-Host "  Not found: $c" -ForegroundColor Red }
        }
        'S' { Show-Status }
        'R' { $State = Invoke-Preflight }
        'Q' { Write-Host ""; return }
        default { Write-Host "  Unknown option." -ForegroundColor Red }
    }

    Write-Host ""
    Read-Host "  Press Enter to return to the menu" | Out-Null
    Clear-Host
}
