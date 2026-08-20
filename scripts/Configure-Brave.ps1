<#
.SYNOPSIS
    Configure a Brave profile for Lane 2 (Daily).

.DESCRIPTION
    Writes Lane 2 settings directly into Brave's Preferences and Local State
    JSON for a dedicated user-data-dir. Brave must be CLOSED when this runs.

    WHAT IT SETS
      - WebRTC IP handling  -> disable_non_proxied_udp   (stops the VPN leak)
      - Brave P3A / metrics -> off
      - Brave News, Wallet prompts, Rewards surface -> off
      - Search suggestions / autofill -> off

    WHAT IT DELIBERATELY LEAVES ALONE
      - Fingerprinting protection stays on Brave's DEFAULT (Standard).
        Standard = farbling on: per-session, per-origin deterministic noise on
        canvas, WebGL, WebGPU, audio, fonts, speech synthesis and more.
        "Strict" is NOT set on purpose -- it raises breakage for marginal gain,
        and this plan optimizes for coherence over maximal spoofing.
        See ..\docs\coherence-matrix.md.

    Every change is verified by relaunching Brave and re-reading the files,
    because Brave silently discards prefs it does not recognize.

.PARAMETER DataDir
    Brave user-data-dir to configure.
    Default: %LOCALAPPDATA%\PrivacyPlan\brave-lane2

.PARAMETER SkipVerify
    Don't relaunch Brave to confirm the settings stuck. Faster, less certain.

.EXAMPLE
    .\Configure-Brave.ps1
#>

[CmdletBinding()]
param(
    [string]$DataDir = (Join-Path $env:LOCALAPPDATA 'PrivacyPlan\brave-lane2'),
    [switch]$SkipVerify
)

$ErrorActionPreference = 'Stop'

function Find-Brave {
    @(
        '%ProgramFiles%\BraveSoftware\Brave-Browser\Application\brave.exe'
        '%ProgramFiles(x86)%\BraveSoftware\Brave-Browser\Application\brave.exe'
        '%LOCALAPPDATA%\BraveSoftware\Brave-Browser\Application\brave.exe'
    ) | ForEach-Object { [Environment]::ExpandEnvironmentVariables($_) } |
        Where-Object { Test-Path $_ } | Select-Object -First 1
}

$Brave = Find-Brave
if (-not $Brave) { throw "brave.exe not found. Install with: winget install --id Brave.Brave --exact" }

Write-Host ""
Write-Host "  Configuring Brave for Lane 2" -ForegroundColor White
Write-Host "  exe:     $Brave" -ForegroundColor DarkGray
Write-Host "  profile: $DataDir" -ForegroundColor DarkGray
Write-Host ""

# --- Brave must be closed -----------------------------------------------
$running = Get-Process brave -ErrorAction SilentlyContinue
if ($running) {
    Write-Host "  Brave is running. Closing it so prefs aren't overwritten on exit..." -ForegroundColor Yellow
    $running | Stop-Process -Force
    Start-Sleep -Seconds 3
}

# --- Create the profile if it doesn't exist ------------------------------
$PrefsPath = Join-Path $DataDir 'Default\Preferences'
if (-not (Test-Path $PrefsPath)) {
    Write-Host "  No profile yet -- initializing..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $DataDir -Force | Out-Null
    $p = Start-Process $Brave -ArgumentList @(
        "--user-data-dir=$DataDir", '--no-first-run', '--no-default-browser-check', 'about:blank'
    ) -PassThru
    $waited = 0
    while (-not (Test-Path $PrefsPath) -and $waited -lt 40) { Start-Sleep -Seconds 2; $waited += 2 }
    Get-Process brave -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 3
    if (-not (Test-Path $PrefsPath)) { throw "Brave did not create a profile at $PrefsPath" }
    Write-Host "  Profile initialized." -ForegroundColor Green
}

# --- helper: set a dotted path in a PSCustomObject ------------------------
function Set-JsonPath {
    param([object]$Obj, [string]$Path, $Value)
    $parts = $Path -split '\.'
    $cur = $Obj
    for ($i = 0; $i -lt $parts.Count - 1; $i++) {
        $seg = $parts[$i]
        if (-not $cur.PSObject.Properties[$seg] -or $null -eq $cur.$seg) {
            $cur | Add-Member -NotePropertyName $seg -NotePropertyValue ([pscustomobject]@{}) -Force
        }
        $cur = $cur.$seg
    }
    $leaf = $parts[-1]
    $cur | Add-Member -NotePropertyName $leaf -NotePropertyValue $Value -Force
}

function Get-JsonPath {
    param([object]$Obj, [string]$Path)
    $cur = $Obj
    foreach ($seg in ($Path -split '\.')) {
        if ($null -eq $cur -or -not $cur.PSObject.Properties[$seg]) { return '<absent>' }
        $cur = $cur.$seg
    }
    return $cur
}

# ===========================================================================
#  The settings
# ===========================================================================
$PrefSettings = [ordered]@{
    # WebRTC -- the leak that walks straight past a VPN.
    # These three are standard Chromium prefs; Brave's own UI writes them.
    'webrtc.ip_handling_policy'      = 'disable_non_proxied_udp'
    'webrtc.multiple_routes_enabled' = $false
    'webrtc.nonproxied_udp_enabled'  = $false

    # Brave News off -- it phones home for feeds and is pure attack surface.
    'brave.today.opted_in'           = $false
    'brave.new_tab_page.show_brave_news' = $false

    # Don't stream keystrokes to a search provider.
    'search.suggest_enabled'         = $false

    # Autofill off -- use a real password manager instead.
    'autofill.credit_card_enabled'   = $false
    'autofill.profile_enabled'       = $false
    'credentials_enable_service'     = $false

    # Don't let the profile advertise a stable sign-in identity.
    'signin.allowed'                 = $false
}

$LocalStateSettings = [ordered]@{
    'p3a.enabled'                        = $false   # Brave's privacy-preserving analytics
    'brave.stats.reporting_enabled'      = $false   # usage ping
    'user_experience_metrics.reporting_enabled' = $false
}

# --- apply: Preferences ---------------------------------------------------
Write-Host "  Preferences" -ForegroundColor Cyan
$prefs = Get-Content $PrefsPath -Raw | ConvertFrom-Json
foreach ($k in $PrefSettings.Keys) {
    $before = Get-JsonPath $prefs $k
    Set-JsonPath $prefs $k $PrefSettings[$k]
    Write-Host ("    {0,-40} {1}  ->  {2}" -f $k, $before, $PrefSettings[$k]) -ForegroundColor DarkGray
}
$prefs | ConvertTo-Json -Depth 100 -Compress | Set-Content $PrefsPath -Encoding UTF8 -NoNewline
Write-Host "    written" -ForegroundColor Green

# --- apply: Local State ---------------------------------------------------
$LsPath = Join-Path $DataDir 'Local State'
if (Test-Path $LsPath) {
    Write-Host ""
    Write-Host "  Local State" -ForegroundColor Cyan
    $ls = Get-Content $LsPath -Raw | ConvertFrom-Json
    foreach ($k in $LocalStateSettings.Keys) {
        $before = Get-JsonPath $ls $k
        Set-JsonPath $ls $k $LocalStateSettings[$k]
        Write-Host ("    {0,-40} {1}  ->  {2}" -f $k, $before, $LocalStateSettings[$k]) -ForegroundColor DarkGray
    }
    $ls | ConvertTo-Json -Depth 100 -Compress | Set-Content $LsPath -Encoding UTF8 -NoNewline
    Write-Host "    written" -ForegroundColor Green
}

# ===========================================================================
#  Verify -- Brave discards prefs it doesn't recognize, so check they survive
# ===========================================================================
if (-not $SkipVerify) {
    Write-Host ""
    Write-Host "  Verifying (relaunching Brave)..." -ForegroundColor Cyan
    $p = Start-Process $Brave -ArgumentList @(
        "--user-data-dir=$DataDir", '--no-first-run', '--no-default-browser-check', 'about:blank'
    ) -PassThru
    Start-Sleep -Seconds 12
    Get-Process brave -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 3

    $after = Get-Content $PrefsPath -Raw | ConvertFrom-Json
    $kept = 0; $lost = 0
    Write-Host ""
    foreach ($k in $PrefSettings.Keys) {
        $v = Get-JsonPath $after $k
        $want = $PrefSettings[$k]
        if ("$v" -eq "$want") { Write-Host ("    [KEPT] {0,-40} {1}" -f $k, $v) -ForegroundColor Green; $kept++ }
        else { Write-Host ("    [LOST] {0,-40} {1} (wanted {2})" -f $k, $v, $want) -ForegroundColor Red; $lost++ }
    }
    Write-Host ""
    Write-Host "    $kept kept, $lost discarded by Brave" -ForegroundColor $(if ($lost) { 'Yellow' } else { 'Green' })
    if ($lost) {
        Write-Host "    Discarded prefs must be set in Brave's UI instead." -ForegroundColor Yellow
    }
}

# ===========================================================================
Write-Host ""
Write-Host "  Done. Remaining steps are UI-only (Brave has no pref for them):" -ForegroundColor White
Write-Host ""
Write-Host "    1. Shields (lion icon) > Advanced > Trackers & ads blocking = Aggressive" -ForegroundColor Yellow
Write-Host "       Default is Standard, which is already good. Aggressive also blocks" -ForegroundColor DarkGray
Write-Host "       first-party trackers. Slightly more breakage." -ForegroundColor DarkGray
Write-Host ""
Write-Host "    2. Fingerprinting: LEAVE ON STANDARD." -ForegroundColor Yellow
Write-Host "       Standard already farbles canvas, WebGL, WebGPU, audio, fonts and" -ForegroundColor DarkGray
Write-Host "       speech synthesis per session and per site. Strict adds breakage" -ForegroundColor DarkGray
Write-Host "       for marginal gain -- see docs\antipatterns.md." -ForegroundColor DarkGray
Write-Host ""
Write-Host "    3. Verify at https://abrahamjuliot.github.io/creepjs/  -> lies must be 0" -ForegroundColor Yellow
Write-Host ""
