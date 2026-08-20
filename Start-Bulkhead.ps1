<#
.SYNOPSIS
    Single entry point for Bulkhead -- the four-lane privacy browser plan.

.DESCRIPTION
    Runs preflight leak checks, then launches the right browser in the right
    lane with the right profile. Refuses to open Lanes 2 and 3 while the tunnel
    is down, so you never browse "privately" over your real IP by accident.

    This script LAUNCHES things and READS network state. It does not change any
    system setting -- that is scripts\Harden-Windows.ps1, which you run yourself.

.PARAMETER Auto
    One-button mode. Runs every check, fixes what it can (configures the Lane 2
    profile if needed), then opens the browser. No menu, no prompts.
    This is what RUN.cmd calls.

.PARAMETER Lane
    Launch a lane directly and skip the menu: 1, 2, or 3.

.PARAMETER SkipPreflight
    Skip the network checks. Use only when you know the tunnel is fine and you
    want a fast launch.

.PARAMETER Force
    Launch Lane 2/3 even if no VPN interface is detected. Prints a warning.

.EXAMPLE
    .\Start-Bulkhead.ps1
    Interactive menu with a preflight report.

.EXAMPLE
    .\Start-Bulkhead.ps1 -Lane 3
    Preflight, then straight into the anonymous lane.

.NOTES
    No elevation required. Run with:
      powershell -ExecutionPolicy Bypass -File ".\Start-Bulkhead.ps1"
#>

[CmdletBinding()]
param(
    [ValidateSet('1','2','3')][string]$Lane,
    [switch]$Auto,
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
    Lane2Browser    = 'Brave'

    # Firefox profile names (created on first use if missing)
    Lane1Profile    = 'lane1-identity'
    Lane2Profile    = 'lane2-daily'

    # Brave gets its own user-data-dir for hard isolation
    BraveDataDir    = Join-Path $env:LOCALAPPDATA 'Bulkhead\brave-lane2'

    # ---- IDENTITY MODE ----------------------------------------------------
    # 'Persistent' : one profile, kept forever. Logins/cookies/history survive.
    #                Fingerprint randomization still reseeds every launch.
    #                Best for a daily driver with pseudonymous accounts.
    #
    # 'Fresh'      : NEW IDENTITY EVERY LAUNCH. A clean profile is built from a
    #                configured template each time; the previous one is deleted.
    #                No cookies, no history, no logins carried over.
    #
    #                READ THIS: a fresh profile does NOT change your IP. Without
    #                a VPN this buys you almost nothing -- sites link you by IP
    #                in one step. It also means zero history, which reads as
    #                automation (docs/antipatterns.md #12), so expect more
    #                CAPTCHAs. Lane 3 (Mullvad Browser) does this natively and
    #                better, because it also gives you a uniform fingerprint.
    IdentityMode    = 'Fresh'

    # Where the pristine configured template lives, and where per-launch
    # sessions are created. Only used when IdentityMode = 'Fresh'.
    BraveTemplate   = Join-Path $env:LOCALAPPDATA 'Bulkhead\brave-template'
    BraveSessions   = Join-Path $env:LOCALAPPDATA 'Bulkhead\sessions'

    # On the FIRST launch of a freshly configured Lane 2 profile, open three
    # verification tabs (CreepJS, WebRTC leak, ipleak) so the setup proves
    # itself instead of just claiming to be hardened. Happens once, not every
    # launch. Set to $false to never open them.
    OpenVerifyTabsOnFirstRun = $true
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
    # NB: the real install path is Mullvad\MullvadBrowser\Release\ and the exe
    # is "mullvadbrowser.exe" -- no hyphen. The hyphenated / "Mullvad Browser"
    # variants below are legacy fallbacks only.
    Mullvad = Find-Browser @(
        '%LOCALAPPDATA%\Mullvad\MullvadBrowser\Release\mullvadbrowser.exe'
        '%ProgramFiles%\Mullvad\MullvadBrowser\Release\mullvadbrowser.exe'
        '%ProgramFiles%\Mullvad Browser\mullvadbrowser.exe'
        '%LOCALAPPDATA%\Mullvad Browser\mullvadbrowser.exe'
        '%ProgramFiles%\Mullvad Browser\mullvad-browser.exe'
        '%LOCALAPPDATA%\Mullvad Browser\mullvad-browser.exe'
        "$env:USERPROFILE\Desktop\Mullvad Browser\mullvad-browser.exe"
    )
    Tor = Find-Browser @(
        "$env:USERPROFILE\Desktop\Tor Browser\Browser\firefox.exe"
        '%LOCALAPPDATA%\Tor Browser\Browser\firefox.exe'
        "$env:USERPROFILE\Downloads\Tor Browser\Browser\firefox.exe"
    )
}

# VPN client applications -- the GUI, not the tunnel interface.
$VpnApps = @{
    Mullvad = Find-Browser @(
        '%ProgramFiles%\Mullvad VPN\Mullvad VPN.exe'
        '%ProgramFiles(x86)%\Mullvad VPN\Mullvad VPN.exe'
    )
    Proton = Find-Browser @(
        '%ProgramFiles%\Proton\VPN\ProtonVPN.exe'
        '%ProgramFiles(x86)%\Proton\VPN\ProtonVPN.exe'
        '%LOCALAPPDATA%\Programs\Proton\VPN\ProtonVPN.exe'
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
# Clear-Host throws when there is no real console handle (redirected output,
# scheduled task, CI). Never let a cosmetic call kill the run.
function Clear-Screen { try { Clear-Host } catch { Write-Host "" } }

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
        $dir = Join-Path $env:LOCALAPPDATA 'Bulkhead\edge-lane1'
        Start-Process $exe -ArgumentList @("--user-data-dir=$dir")
    }
    Write-Host "  Launched $kind (Lane 1)." -ForegroundColor Green
}

function Start-Lane2 {
    param([bool]$VpnUp)
    Write-Head "Lane 2 -- Daily"
    if (-not (Assert-Tunnel 'Lane 2' $VpnUp)) { Write-Host "  Cancelled." -ForegroundColor Yellow; return }

    if ($Config.Lane2Browser -eq 'Brave' -and $Browsers.Brave) {
        # Auto-configure on first use so the lane is never launched unhardened.
        $prefs = Join-Path $Config.BraveDataDir 'Default\Preferences'
        $configured = $false
        if (Test-Path $prefs) {
            try {
                $j = Get-Content $prefs -Raw | ConvertFrom-Json
                $configured = ($j.webrtc.ip_handling_policy -eq 'disable_non_proxied_udp')
            } catch { $configured = $false }
        }
        if (-not $configured) {
            Write-Host "  Profile not configured yet -- applying Lane 2 settings..." -ForegroundColor Yellow
            $cfg = Join-Path $Root 'scripts\Configure-Brave.ps1'
            if (Test-Path $cfg) { & $cfg -DataDir $Config.BraveDataDir -SkipVerify }
            else { Write-Host "  Missing: $cfg" -ForegroundColor Red }
        }

        # Honour IdentityMode so the menu and RUN.cmd behave identically.
        $profileDir = $Config.BraveDataDir
        if ($Config.IdentityMode -eq 'Fresh') {
            try {
                $tpl = Initialize-Template
                $profileDir = New-FreshIdentity -Template $tpl -SessionRoot $Config.BraveSessions
                Write-Host "  Fresh identity: $(Split-Path $profileDir -Leaf) (previous session deleted)" -ForegroundColor Magenta
                if (-not $VpnUp) {
                    Write-Host "  NOTE: your IP is unchanged -- no tunnel. Not really a new identity." -ForegroundColor Red
                }
            } catch {
                Write-Host "  Fresh identity failed ($($_.Exception.Message)); using persistent profile." -ForegroundColor Red
                $profileDir = $Config.BraveDataDir
            }
        }

        New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
        Start-Process $Browsers.Brave -ArgumentList @(
            "--user-data-dir=$profileDir", '--no-default-browser-check'
        )
        Write-Host "  Launched Brave (Lane 2)." -ForegroundColor Green
        Write-Host "  WebRTC sealed. Fingerprinting on Standard (farbling) -- correct for this lane." -ForegroundColor DarkGray
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

function Start-Lane4 {
    Write-Head "Lane 4 -- Maximum"
    Write-Host "  Tor, plus isolation that Tor Browser alone does not have." -ForegroundColor Magenta
    Write-Host ""
    Write-Host "  Lane 4 is not a browser you launch from Windows -- it is a" -ForegroundColor White
    Write-Host "  different operating system. That IS the upgrade: plain Tor Browser" -ForegroundColor White
    Write-Host "  is one process on your normal PC, so a browser exploit reaches your" -ForegroundColor White
    Write-Host "  real IP and your real disk. Lane 4 removes that." -ForegroundColor White
    Write-Host ""
    Write-Host "    Tails         live USB, amnesic, nothing survives reboot" -ForegroundColor Gray
    Write-Host "                  best forensic resistance; runs on any PC" -ForegroundColor DarkGray
    Write-Host "                  https://tails.net" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "    Whonix        two VMs -- the Workstation cannot reach the network" -ForegroundColor Gray
    Write-Host "                  except through the Tor Gateway, so it does not KNOW" -ForegroundColor DarkGray
    Write-Host "                  your real IP even if it is fully compromised" -ForegroundColor DarkGray
    Write-Host "                  https://www.whonix.org" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "    Qubes-Whonix  Whonix inside per-application VM isolation." -ForegroundColor Gray
    Write-Host "                  The strongest generally-available configuration." -ForegroundColor DarkGray
    Write-Host "                  https://www.qubes-os.org  (check the HCL first)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Build guide: lanes\lane4-maximum.md" -ForegroundColor Yellow
    Write-Host "  Honest comparison with Tor: docs\beyond-tor.md" -ForegroundColor Yellow
    Write-Host ""

    if ($Browsers.Tor) {
        Write-Host "  You have Tor Browser installed. It is NOT Lane 4 -- it has no" -ForegroundColor DarkGray
        Write-Host "  isolation -- but it is the strongest thing available right now." -ForegroundColor DarkGray
        $a = Read-Host "  Launch Tor Browser? (y/N)"
        if ($a -eq 'y') {
            Start-Process $Browsers.Tor
            Write-Host "  Launched Tor Browser. Change nothing. Log into nothing." -ForegroundColor Green
        }
    }
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

# ---------- fresh-identity profiles ----------------------------------------
# Rather than reconfiguring Brave from scratch every launch (slow, and it would
# re-trigger the first-run experience), we keep ONE configured template and
# stamp a clean session profile from it. Only the config files are copied --
# Brave regenerates caches and databases itself, so the session starts with no
# cookies, no history and no logins.
function New-FreshIdentity {
    param([string]$Template, [string]$SessionRoot)

    if (-not (Test-Path (Join-Path $Template 'Default\Preferences'))) {
        throw "No configured template at $Template"
    }

    # Delete previous sessions. This is the point of the mode -- and it also
    # means no forensic residue is left sitting on disk.
    if (Test-Path $SessionRoot) {
        Get-ChildItem $SessionRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            try { Remove-Item $_.FullName -Recurse -Force -ErrorAction Stop }
            catch { Write-Host "    could not remove old session $($_.Name) (in use?)" -ForegroundColor DarkGray }
        }
    }

    $session = Join-Path $SessionRoot ("s{0}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    New-Item -ItemType Directory -Path (Join-Path $session 'Default') -Force | Out-Null

    # First Run sentinel: without it Brave shows onboarding on every launch.
    Set-Content -Path (Join-Path $session 'First Run') -Value '' -NoNewline

    Copy-Item (Join-Path $Template 'Default\Preferences') (Join-Path $session 'Default\Preferences') -Force
    if (Test-Path (Join-Path $Template 'Local State')) {
        Copy-Item (Join-Path $Template 'Local State') (Join-Path $session 'Local State') -Force
    }

    return $session
}

# Ensure a configured template exists, building it from the persistent profile
# or from scratch if this is the first Fresh-mode run.
function Initialize-Template {
    $tpl = $Config.BraveTemplate
    if (Test-Path (Join-Path $tpl 'Default\Preferences')) { return $tpl }

    Write-Host "  Building the identity template (one time)..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Path (Join-Path $tpl 'Default') -Force | Out-Null

    $src = Join-Path $Config.BraveDataDir 'Default\Preferences'
    if (Test-Path $src) {
        # Reuse the already-configured persistent profile as the template.
        Set-Content -Path (Join-Path $tpl 'First Run') -Value '' -NoNewline
        Copy-Item $src (Join-Path $tpl 'Default\Preferences') -Force
        $ls = Join-Path $Config.BraveDataDir 'Local State'
        if (Test-Path $ls) { Copy-Item $ls (Join-Path $tpl 'Local State') -Force }
        Write-Host "  Template built from the existing Lane 2 profile." -ForegroundColor Green
    } else {
        # Nothing to copy -- configure a fresh one.
        $cfg = Join-Path $Root 'scripts\Configure-Brave.ps1'
        if (Test-Path $cfg) { & $cfg -DataDir $tpl -SkipVerify | Out-Null }
        else { throw "Cannot build template: $cfg missing" }
    }
    return $tpl
}

# ---------- VPN control -----------------------------------------------------
function Start-Vpn {
    Write-Head "VPN"

    $app = $null; $name = $null
    foreach ($k in 'Mullvad','Proton') { if ($VpnApps[$k]) { $app = $VpnApps[$k]; $name = $k; break } }

    if (-not $app) {
        Write-Host "  No VPN client installed." -ForegroundColor Red
        Write-Host "  Press I in the menu to install one, or:" -ForegroundColor Yellow
        Write-Host "    winget install --id MullvadVPN.MullvadVPN --exact" -ForegroundColor Cyan
        Write-Host "    winget install --id Proton.ProtonVPN --exact       (free tier)" -ForegroundColor Cyan
        return
    }

    Write-Row 'OK' "$name client installed" $app 'Green'

    # The daemon runs as a service; the GUI is a separate process. A running
    # daemon with no GUI is exactly why "I can't find Mullvad" happens.
    $daemon = Get-Service -Name 'MullvadVPN' -ErrorAction SilentlyContinue
    if ($daemon) { Write-Row 'OK' 'Background service' $daemon.Status 'Green' }

    $gui = Get-Process -Name '*mullvad*','*proton*' -ErrorAction SilentlyContinue |
           Where-Object { $_.MainWindowTitle -or $_.ProcessName -notlike '*daemon*' }
    if ($gui) { Write-Row 'OK' 'App window' 'already running (check the system tray)' 'Green' }
    else      { Write-Row 'INFO' 'App window' 'not running -- opening it now' 'Yellow' }

    Start-Process $app
    Write-Host ""
    Write-Host "  $name opened. It may go straight to the system tray (bottom-right)." -ForegroundColor Green
    Write-Host ""
    Write-Host "  FIRST TIME:" -ForegroundColor White
    Write-Host "    1. Create account -> you get a 16-digit number, no email needed" -ForegroundColor Gray
    Write-Host "    2. SAVE THAT NUMBER. It is your account. No password reset exists." -ForegroundColor Yellow
    Write-Host "    3. Add time (card / PayPal / cash / crypto)" -ForegroundColor Gray
    Write-Host "    4. Connect -- pick Spain or France (matches your Morocco timezone)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  THEN ENABLE in Settings > VPN settings (all free):" -ForegroundColor White
    Write-Host "    Kill switch / Lockdown mode   no leak if the tunnel drops -- REQUIRED" -ForegroundColor Gray
    Write-Host "    Quantum-resistant tunnel      defeats harvest-now-decrypt-later" -ForegroundColor Gray
    Write-Host "    DAITA                         defeats AI traffic-analysis" -ForegroundColor Gray
    Write-Host "    Auto-connect                  never accidentally unprotected" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Then press R here to re-run preflight -- it should flip to VPN up." -ForegroundColor Cyan
}

# ---------- one-button automatic mode --------------------------------------
function Invoke-Auto {
    param($State)

    Write-Host ""
    Write-Host "  ================================================================" -ForegroundColor DarkCyan
    Write-Host "   AUTOMATIC RUN -- checking everything, then opening your browser" -ForegroundColor Cyan
    Write-Host "  ================================================================" -ForegroundColor DarkCyan

    # --- 1. local leak settings (LLMNR / mDNS / multi-homed DNS) ------------
    Write-Head "Local leak settings"
    $dnsPol = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient'
    $checks = @(
        @{ P=$dnsPol; N='EnableMulticast';            W=0; L='LLMNR disabled' }
        @{ P=$dnsPol; N='EnableMDNS';                 W=0; L='mDNS disabled' }
        @{ P=$dnsPol; N='DisableSmartNameResolution'; W=1; L='Multi-homed DNS off' }
    )
    $hardened = 0
    foreach ($c in $checks) {
        $v = $null
        if (Test-Path $c.P) { try { $v = (Get-ItemProperty $c.P -Name $c.N -EA Stop).($c.N) } catch {} }
        if ($v -eq $c.W) { Write-Row 'OK' $c.L "= $v" 'Green'; $hardened++ }
        else { Write-Row 'TODO' $c.L "not set -- run HARDEN.cmd" 'Yellow' }
    }

    # --- 1b. advanced layer (compact -- full detail in Test-Advanced.ps1) ---
    Write-Head "Advanced layer"

    $dohActive = $false
    try {
        foreach ($a in (Get-NetAdapter | Where-Object Status -eq 'Up')) {
            $k = "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters\$($a.InterfaceGuid)\DohInterfaceSettings"
            if (Test-Path $k) { $dohActive = $true }
        }
    } catch { }
    # Windows 10 has no DoH client, so the browser's own secure DNS is what
    # matters here -- and it is also what Chromium uses to fetch ECH keys.
    $braveDoh = $null
    $bls = Join-Path $Config.BraveDataDir 'Local State'
    if (Test-Path $bls) {
        try { $braveDoh = (Get-Content $bls -Raw | ConvertFrom-Json).dns_over_https.mode } catch { }
    }
    if ($braveDoh -in 'secure','automatic') { Write-Row 'OK' 'Encrypted DNS (browser)' "mode = $braveDoh" 'Green' }
    elseif ($dohActive) { Write-Row 'OK' 'Encrypted DNS (OS)' 'active' 'Green' }
    else { Write-Row 'TODO' 'Encrypted DNS' 'run scripts\Configure-Brave.ps1' 'Yellow' }

    # ECH is on by default in Brave (the flag was removed upstream in M122).
    # Whether it actually functions depends entirely on encrypted DNS.
    if ($braveDoh -in 'secure','automatic') { Write-Row 'OK' 'ECH (encrypted SNI)' 'on by default, DoH present' 'Green' }
    else { Write-Row 'TODO' 'ECH (encrypted SNI)' 'inactive -- needs browser DoH' 'Yellow' }

    Write-Host "          Full audit: option A, or scripts\Test-Advanced.ps1" -ForegroundColor DarkGray

    # --- 2. browsers --------------------------------------------------------
    Write-Head "Browsers"
    foreach ($k in 'Edge','Brave','Firefox','Mullvad','Tor') {
        if ($Browsers[$k]) { Write-Row 'OK' $k 'installed' 'Green' }
        else { Write-Row '--' $k 'not installed' 'DarkGray' }
    }

    # --- 3. Lane 2 profile --------------------------------------------------
    Write-Head "Lane 2 profile"
    $prefs = Join-Path $Config.BraveDataDir 'Default\Preferences'
    $configured = $false
    if (Test-Path $prefs) {
        try {
            $j = Get-Content $prefs -Raw | ConvertFrom-Json
            $configured = ($j.webrtc.ip_handling_policy -eq 'disable_non_proxied_udp')
        } catch { $configured = $false }
    }
    if ($configured) {
        Write-Row 'OK' 'Brave Lane 2' 'configured (WebRTC sealed)' 'Green'
    } else {
        Write-Row 'FIX' 'Brave Lane 2' 'not configured -- applying now' 'Yellow'
        $cfg = Join-Path $Root 'scripts\Configure-Brave.ps1'
        if (Test-Path $cfg) { & $cfg -DataDir $Config.BraveDataDir -SkipVerify | Out-Null; Write-Row 'OK' 'Brave Lane 2' 'configured' 'Green' }
        else { Write-Row 'ERR' 'Brave Lane 2' "missing $cfg" 'Red' }
    }

    # --- 4. verdict ---------------------------------------------------------
    Write-Head "Verdict"
    if ($State.VpnUp) {
        Write-Host "  Tunnel up. Launching Lane 2." -ForegroundColor Green
    } else {
        Write-Host ""
        Write-Host "  +--------------------------------------------------------------+" -ForegroundColor Red
        Write-Host "  |  NO VPN -- your real IP is visible to every site you open.    |" -ForegroundColor Red
        Write-Host "  |  Fingerprint protection is ON, but your address is not hidden.|" -ForegroundColor Red
        Write-Host "  +--------------------------------------------------------------+" -ForegroundColor Red
        Write-Host ""
        Write-Host "  Opening anyway: hardened Brave with no VPN is still better than" -ForegroundColor Yellow
        Write-Host "  your normal browser with no VPN. But the plan is not complete" -ForegroundColor Yellow
        Write-Host "  until a tunnel is up." -ForegroundColor Yellow
        Write-Host ""
        $vpnApp = ($VpnApps.Values | Where-Object { $_ } | Select-Object -First 1)
        if ($vpnApp) {
            Write-Host "  A VPN client IS installed but not connected:" -ForegroundColor Cyan
            Write-Host "    $vpnApp" -ForegroundColor DarkGray
            Write-Host "  Open it from the Start menu, or press V in the full menu." -ForegroundColor Cyan
        } else {
            Write-Host "  No VPN client installed. Press I in the full menu." -ForegroundColor Cyan
        }
        Write-Host ""
    }

    # --- 5. launch ----------------------------------------------------------
    # firstRun is true only when the profile was unconfigured at the top of this
    # function -- i.e. we just built it. Normal launches open no tabs at all.
    $firstRun = (-not $configured) -and $Config.OpenVerifyTabsOnFirstRun
    if ($Browsers.Brave) {

        # Resolve which profile directory to launch.
        if ($Config.IdentityMode -eq 'Fresh') {
            Write-Head "Identity"
            try {
                $tpl = Initialize-Template
                $profileDir = New-FreshIdentity -Template $tpl -SessionRoot $Config.BraveSessions
                Write-Row 'NEW' 'Fresh identity' (Split-Path $profileDir -Leaf) 'Magenta'
                Write-Host "          No cookies, no history, no logins carried over." -ForegroundColor DarkGray
                Write-Host "          Previous session deleted." -ForegroundColor DarkGray
                if (-not $State.VpnUp) {
                    Write-Host ""
                    Write-Host "          WARNING: your IP did NOT change -- there is no tunnel." -ForegroundColor Red
                    Write-Host "          A fresh profile behind the same IP is not a new identity." -ForegroundColor Red
                    Write-Host "          Connect the VPN (option V) for this mode to mean anything." -ForegroundColor Red
                }
                $firstRun = $false   # a fresh profile every launch must not spam verification tabs
            } catch {
                Write-Row 'ERR' 'Fresh identity' "$($_.Exception.Message) -- using persistent profile" 'Red'
                $profileDir = $Config.BraveDataDir
            }
        } else {
            $profileDir = $Config.BraveDataDir
        }

        New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
        # NB: not $args -- that is a PowerShell automatic variable.
        $braveArgs = @("--user-data-dir=$profileDir", '--no-default-browser-check')
        if ($firstRun) {
            # First run: open the verification pages so the setup proves itself.
            $braveArgs += @(
                'https://abrahamjuliot.github.io/creepjs/'
                'https://browserleaks.com/webrtc'
                'https://ipleak.net'
            )
        }
        Start-Process $Browsers.Brave -ArgumentList $braveArgs
        Write-Host "  Brave launched (Lane 2)." -ForegroundColor Green
        if ($firstRun) {
            Write-Host ""
            Write-Host "  First run -- three verification tabs opened:" -ForegroundColor Cyan
            Write-Host "    CreepJS      -> 'lies detected' must be 0" -ForegroundColor Gray
            Write-Host "    WebRTC       -> no 192.168.x / 10.x candidates" -ForegroundColor Gray
            Write-Host "    ipleak.net   -> confirms what sites actually see" -ForegroundColor Gray
        }
    }
    elseif ($Browsers.Edge) {
        Write-Host "  Brave not installed. Press I in the menu to install it." -ForegroundColor Yellow
        Write-Host "  Opening Edge (Lane 1) instead." -ForegroundColor Yellow
        Start-Lane1
    }
    else { Write-Host "  No usable browser found." -ForegroundColor Red }

    Write-Host ""
    Write-Host "  Done. Full menu: .\Start-Bulkhead.ps1" -ForegroundColor DarkGray
    Write-Host ""
}

# ---------- auto-install ----------------------------------------------------
function Install-Missing {
    Write-Head "Install missing browsers"

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Host "  winget not found. Install browsers manually:" -ForegroundColor Red
        foreach ($k in 'Firefox','Brave','Mullvad','Tor') { Write-Host "    $k  $($InstallLinks[$k])" -ForegroundColor Gray }
        return
    }

    $pkgs = [ordered]@{
        'Brave (Lane 2)'          = 'Brave.Brave'
        'Firefox (Lane 2 alt)'    = 'Mozilla.Firefox'
        'Mullvad Browser (Lane 3)'= 'MullvadVPN.MullvadBrowser'
        'Mullvad VPN (network)'   = 'MullvadVPN.MullvadVPN'
    }

    $i = 0; $map = @{}
    foreach ($name in $pkgs.Keys) {
        $i++
        $id = $pkgs[$name]
        $have = switch -Wildcard ($id) {
            'Brave.Brave'               { [bool]$Browsers.Brave }
            'Mozilla.Firefox'           { [bool]$Browsers.Firefox }
            'MullvadVPN.MullvadBrowser' { [bool]$Browsers.Mullvad }
            default                     { $null }
        }
        $tag = if ($have -eq $true) { 'installed' } elseif ($null -eq $have) { '?' } else { 'missing' }
        $col = if ($have -eq $true) { 'Green' } else { 'Yellow' }
        Write-Host ("   {0}  {1,-26} {2,-28} {3}" -f $i, $name, $id, $tag) -ForegroundColor $col
        $map["$i"] = @{ Name = $name; Id = $id }
    }

    Write-Host ""
    Write-Host "  Mullvad VPN is free to install but needs a paid account you create yourself." -ForegroundColor DarkGray
    Write-Host ""
    $sel = (Read-Host "  Numbers to install (e.g. 1,3) or Enter to cancel").Trim()
    if (-not $sel) { Write-Host "  Cancelled." -ForegroundColor Yellow; return }

    foreach ($n in ($sel -split '[,\s]+' | Where-Object { $_ })) {
        if (-not $map.ContainsKey($n)) { Write-Host "  Skipping '$n'." -ForegroundColor Red; continue }
        $pkg = $map[$n]
        Write-Host ""
        Write-Host "  Installing $($pkg.Name) [$($pkg.Id)]..." -ForegroundColor Cyan
        winget install --id $pkg.Id --exact --silent --accept-package-agreements --accept-source-agreements
        if ($LASTEXITCODE -eq 0) { Write-Host "  $($pkg.Name) installed." -ForegroundColor Green }
        else { Write-Host "  winget exited $LASTEXITCODE for $($pkg.Name)." -ForegroundColor Yellow }
    }

    Write-Host ""
    Write-Host "  Restart this script so it picks up the new installs." -ForegroundColor Yellow
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
    Write-Head "Bulkhead"
    $vpnTag = if ($State.VpnUp) { "VPN up" } else { "VPN DOWN" }
    $vpnCol = if ($State.VpnUp) { 'Green' } else { 'Red' }
    Write-Host "  Tunnel: " -NoNewline; Write-Host $vpnTag -ForegroundColor $vpnCol -NoNewline
    if ($State.Country) { Write-Host "   Exit: $($State.Country)   IP: $($State.Ip)" -ForegroundColor DarkGray }
    else { Write-Host "" }
    Write-Host ""
    Write-Host "   1   Lane 1  Identity    bank / gov / work      real fingerprint" -ForegroundColor Blue
    Write-Host "   2   Lane 2  Daily       shopping / social      hardened, coherent" -ForegroundColor Yellow
    Write-Host "   3   Lane 3  Anonymous   research / reading     uniform crowd" -ForegroundColor Magenta
    Write-Host "   4   Lane 4  Maximum     serious threat model   Tails / Whonix / Qubes" -ForegroundColor DarkMagenta
    Write-Host ""
    Write-Host "   V   Open the VPN app          (connect / settings)" -ForegroundColor Gray
    Write-Host "   I   Install missing browsers  (winget)" -ForegroundColor Gray
    Write-Host "   T   Run full leak test        (scripts\Test-Leaks.ps1)" -ForegroundColor Gray
    Write-Host "   A   Advanced audit            (FDE, DoH, ECH, tunnel features)" -ForegroundColor Gray
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
Clear-Screen
Write-Host ""
Write-Host "  B U L K H E A D" -ForegroundColor White
Write-Host "  $Root" -ForegroundColor DarkGray

$State = if ($SkipPreflight) {
    @{ VpnUp = $true; Ip = $null; Country = $null; Tz = (Get-TimeZone).Id }
} else { Invoke-Preflight }

if ($Auto) {
    Invoke-Auto -State $State
    # Keep the window open when double-clicked. Harmless if stdin is redirected
    # or PowerShell is in NonInteractive mode -- never let the pause fail the run.
    try { Read-Host "  Press Enter to close" | Out-Null } catch { }
    return
}

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
        '4' { Start-Lane4 }
        'V' { Start-Vpn }
        'I' { Install-Missing }
        'T' {
            $t = Join-Path $Root 'scripts\Test-Leaks.ps1'
            if (Test-Path $t) { & $t } else { Write-Host "  Not found: $t" -ForegroundColor Red }
        }
        'A' {
            $a = Join-Path $Root 'scripts\Test-Advanced.ps1'
            if (Test-Path $a) { & $a } else { Write-Host "  Not found: $a" -ForegroundColor Red }
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
    Clear-Screen
}
