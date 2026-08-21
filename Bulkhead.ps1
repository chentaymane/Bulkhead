<#
.SYNOPSIS
    BULKHEAD -- the whole privacy stack in one script.

.DESCRIPTION
    Everything that used to live in six separate files: preflight leak checks,
    browser configuration, OS hardening, the advanced audit, fresh-identity
    profiles, lane launching, VPN control and the revert path.

    Run it with no arguments for the menu. Double-click BULKHEAD.cmd for the
    automatic path: check everything, fix what can be fixed without admin,
    open the browser.

    ELEVATION: this script does NOT run elevated, on purpose -- browsers must
    never launch as administrator. The one part that needs admin (OS hardening)
    spawns its own elevated child process and nothing else does.

.PARAMETER Auto
    One-button mode. Check everything, fix what it can, open the browser.
    No menu, no prompts. This is what BULKHEAD.cmd calls.

.PARAMETER Lane
    Launch a lane directly: 1 (identity), 2 (daily), 3 (anonymous).

.PARAMETER Harden
    Run the OS hardening. Requires admin; self-elevates if needed.
    Dry run unless -Apply is also passed.

.PARAMETER Revert
    Undo the OS hardening. Requires admin. Dry run unless -Apply.

.PARAMETER Apply
    Actually make changes. Only meaningful with -Harden or -Revert.

.PARAMETER Audit
    Full read-only audit: network leaks + advanced layer. Changes nothing.

.PARAMETER Configure
    Rebuild the Lane 2 browser configuration and the identity template.

.PARAMETER Force
    Launch Lanes 2/3 even with no tunnel.

.EXAMPLE
    .\Bulkhead.ps1
.EXAMPLE
    .\Bulkhead.ps1 -Auto
.EXAMPLE
    .\Bulkhead.ps1 -Harden -Apply
#>

[CmdletBinding(DefaultParameterSetName = 'Menu')]
param(
    [Parameter(ParameterSetName='Auto')]     [switch]$Auto,
    [Parameter(ParameterSetName='Lane')]     [ValidateSet('1','2','3','4')][string]$Lane,
    [Parameter(ParameterSetName='Harden')]   [switch]$Harden,
    [Parameter(ParameterSetName='Revert')]   [switch]$Revert,
    [Parameter(ParameterSetName='Harden')]
    [Parameter(ParameterSetName='Revert')]   [switch]$Apply,
    [Parameter(ParameterSetName='Harden')]   [string]$NewHostname,
    [Parameter(ParameterSetName='Audit')]    [switch]$Audit,
    [Parameter(ParameterSetName='Configure')][switch]$Configure,
    [switch]$Force,
    [switch]$SkipPreflight
)

$ErrorActionPreference = 'Stop'
$Root = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }

# ============================================================================
#  CONFIG -- edit once
# ============================================================================
$Config = @{
    # Exit country your IP should appear in (ISO code) for the coherence check.
    # Must agree with your system timezone. '' disables the check.
    ExpectedCountry = ''

    # ---- IDENTITY MODE, PER LANE -----------------------------------------
    # These are deliberately different, because the lanes have opposite jobs.
    #
    # LANE 2 = 'Persistent'.  This is where you are LOGGED IN. Anti-bot
    #   systems expect a returning user: aged cookies, accumulated history, a
    #   stable fingerprint. A brand-new profile on every launch is the
    #   signature of automation -- and paired with a datacenter VPN exit it is
    #   close to a textbook bot profile. THIS is what gets you challenged and
    #   banned. Vendors say it plainly: keep the cookie jar and the
    #   fingerprint stable so you present as the same returning user.
    #
    # LANE 3 = 'Fresh'.  Nothing is logged in here, so discarding the identity
    #   every launch costs nothing and is exactly right. CAPTCHAs in this lane
    #   are the accepted price. (Mullvad Browser is already amnesic; this
    #   setting covers the Brave fallback.)
    #
    # You get "new identity every launch" AND "not banned" -- by putting them
    # in different lanes instead of fighting over one.
    Lane2IdentityMode = 'Fresh'
    Lane3IdentityMode = 'Fresh'

    # ---- DEFAULT LANE ------------------------------------------------------
    # Which lane BULKHEAD.cmd opens.
    #
    # 3 = Mullvad Browser. This is the real "new identity every launch, like
    #     Tor" answer: it IS the Tor Browser engine, it is amnesic by design,
    #     and -- the part that matters -- every user shares one fingerprint.
    #     Fresh AND uniform. A throwaway profile is what sites expect here, so
    #     it does not read as automation the way a throwaway Brave profile does.
    #
    # 2 = Brave, fresh profile each launch. Also a new identity, but a RARE
    #     one: no history, no cookies, randomized fingerprint. That combination
    #     is the automation signature and draws challenges.
    #
    # If you want Tor-like behaviour, 3 is the lane that gives it to you
    # without the ban cost.
    DefaultLane = 3

    DataRoot        = Join-Path $env:LOCALAPPDATA 'Bulkhead'
    DohTemplate     = 'https://dns.quad9.net/dns-query'
    DohMode         = 'secure'      # 'secure' = no plaintext fallback (ECH needs this)
    KeepSessions    = 1             # how many past identities to retain
}
$Config.BraveDataDir  = Join-Path $Config.DataRoot 'brave-lane2'
$Config.BraveTemplate = Join-Path $Config.DataRoot 'brave-template'
$Config.BraveSessions = Join-Path $Config.DataRoot 'sessions'
$Config.RevertLog     = Join-Path $Root 'revert-state.json'

# ============================================================================
#  CONSOLE
# ============================================================================
$script:Unicode = $false
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $script:Unicode = $true
} catch { }

function Clear-Screen { try { Clear-Host } catch { Write-Host "" } }

function Show-Banner {
    Clear-Screen
    Write-Host ""
    if ($script:Unicode) {
        $art = @(
            '  ██████╗ ██╗   ██╗██╗     ██╗  ██╗██╗  ██╗███████╗ █████╗ ██████╗ '
            '  ██╔══██╗██║   ██║██║     ██║ ██╔╝██║  ██║██╔════╝██╔══██╗██╔══██╗'
            '  ██████╔╝██║   ██║██║     █████╔╝ ███████║█████╗  ███████║██║  ██║'
            '  ██╔══██╗██║   ██║██║     ██╔═██╗ ██╔══██║██╔══╝  ██╔══██║██║  ██║'
            '  ██████╔╝╚██████╔╝███████╗██║  ██╗██║  ██║███████╗██║  ██║██████╔╝'
            '  ╚═════╝  ╚═════╝ ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═════╝ '
        )
    } else {
        $art = @(
            '  ####    ##   ##  ##      ##  ##   ##  ##  ######   ####   #####  '
            '  ##  ##  ##   ##  ##      ## ##    ##  ##  ##      ##  ##  ##  ## '
            '  #####   ##   ##  ##      ####     ######  #####   ######  ##  ## '
            '  ##  ##  ##   ##  ##      ## ##    ##  ##  ##      ##  ##  ##  ## '
            '  #####    #####   ######  ##  ##   ##  ##  ######  ##  ##  #####  '
        )
    }
    foreach ($l in $art) { Write-Host $l -ForegroundColor Cyan }
    Write-Host ""
    Write-Host "   Compartmentalized browsing  ·  four lanes  ·  one coherent story" -ForegroundColor DarkGray
    Write-Host "   $Root" -ForegroundColor DarkGray
    Write-Host ""
}

function Write-Head { param([string]$T)
    Write-Host ""
    Write-Host "  $T" -ForegroundColor White
    Write-Host "  $('-' * 68)" -ForegroundColor DarkGray
}
function Write-Row { param([string]$S,[string]$L,[string]$D,[string]$C='Gray')
    Write-Host ("  {0,-7} {1,-28} {2}" -f "[$S]", $L, $D) -ForegroundColor $C
}
function Write-Note { param([string]$T) Write-Host "          $T" -ForegroundColor DarkGray }

$script:IsAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# ============================================================================
#  DISCOVERY  (cached -- these were being re-enumerated on every call before)
# ============================================================================
function Find-Exe {
    param([string[]]$Candidates)
    foreach ($c in $Candidates) {
        $p = [Environment]::ExpandEnvironmentVariables($c)
        if (Test-Path $p) { return $p }
    }
    return $null
}

$script:Browsers = $null
function Get-Browsers {
    if ($script:Browsers) { return $script:Browsers }
    $script:Browsers = @{
        Brave = Find-Exe @(
            '%ProgramFiles%\BraveSoftware\Brave-Browser\Application\brave.exe'
            '%ProgramFiles(x86)%\BraveSoftware\Brave-Browser\Application\brave.exe'
            '%LOCALAPPDATA%\BraveSoftware\Brave-Browser\Application\brave.exe'
        )
        Edge = Find-Exe @(
            '%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe'
            '%ProgramFiles%\Microsoft\Edge\Application\msedge.exe'
        )
        Firefox = Find-Exe @(
            '%ProgramFiles%\Mozilla Firefox\firefox.exe'
            '%ProgramFiles(x86)%\Mozilla Firefox\firefox.exe'
        )
        # Real path is Mullvad\MullvadBrowser\Release\mullvadbrowser.exe --
        # no hyphen, different folder. The rest are legacy fallbacks.
        Mullvad = Find-Exe @(
            '%LOCALAPPDATA%\Mullvad\MullvadBrowser\Release\mullvadbrowser.exe'
            '%ProgramFiles%\Mullvad\MullvadBrowser\Release\mullvadbrowser.exe'
            '%ProgramFiles%\Mullvad Browser\mullvadbrowser.exe'
            '%LOCALAPPDATA%\Mullvad Browser\mullvad-browser.exe'
        )
        Tor = Find-Exe @(
            "$env:USERPROFILE\Desktop\Tor Browser\Browser\firefox.exe"
            '%LOCALAPPDATA%\Tor Browser\Browser\firefox.exe'
            "$env:USERPROFILE\Downloads\Tor Browser\Browser\firefox.exe"
        )
    }
    return $script:Browsers
}

$script:VpnApps = $null
function Get-VpnApps {
    if ($script:VpnApps) { return $script:VpnApps }
    $script:VpnApps = @{
        Mullvad = Find-Exe @('%ProgramFiles%\Mullvad VPN\Mullvad VPN.exe','%ProgramFiles(x86)%\Mullvad VPN\Mullvad VPN.exe')
        Proton  = Find-Exe @('%ProgramFiles%\Proton\VPN\ProtonVPN.exe','%LOCALAPPDATA%\Programs\Proton\VPN\ProtonVPN.exe')
    }
    return $script:VpnApps
}

$script:Adapters = $null
function Get-UpAdapters {
    if ($null -eq $script:Adapters) {
        $script:Adapters = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up')
    }
    return $script:Adapters
}
function Get-VpnAdapter {
    Get-UpAdapters | Where-Object {
        $_.InterfaceDescription -match 'WireGuard|OpenVPN|TAP|Wintun|Mullvad|Proton|IVPN|NordLynx' -or
        $_.Name -match 'WireGuard|VPN|Mullvad|Proton'
    } | Select-Object -First 1
}

# Browser DoH state -- on Windows 10 this is the only encrypted DNS available,
# and it is what Chromium uses to fetch ECH keys.
function Get-BrowserDoh {
    $ls = Join-Path $Config.BraveDataDir 'Local State'
    if (-not (Test-Path $ls)) { return $null }
    try { return (Get-Content $ls -Raw | ConvertFrom-Json).dns_over_https.mode } catch { return $null }
}

$script:OsDohSupported = [bool](Get-Command Get-DnsClientDohServerAddress -ErrorAction SilentlyContinue)

function Get-DnsPolicyState {
    $p = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient'
    $out = @{}
    foreach ($n in 'EnableMulticast','EnableMDNS','DisableSmartNameResolution') {
        $v = $null
        if (Test-Path $p) { try { $v = (Get-ItemProperty $p -Name $n -EA Stop).$n } catch { } }
        $out[$n] = $v
    }
    return $out
}

# ============================================================================
#  PREFLIGHT
# ============================================================================
function Invoke-Preflight {
    Write-Head "Preflight"
    $s = [ordered]@{ VpnUp=$false; Ip=$null; Country=$null; Tz=(Get-TimeZone).Id }

    $vpn = Get-VpnAdapter
    if ($vpn) { $s.VpnUp = $true; Write-Row 'OK' 'VPN interface' $vpn.Name 'Green' }
    else      { Write-Row 'DOWN' 'VPN interface' 'no tunnel detected' 'Red' }

    $def = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -EA SilentlyContinue | Sort-Object RouteMetric | Select-Object -First 1
    if ($def) {
        $n = (Get-NetAdapter -InterfaceIndex $def.ifIndex -EA SilentlyContinue).Name
        if ($vpn -and $n -eq $vpn.Name) { Write-Row 'OK' 'Default route' "via $n" 'Green' }
        else { Write-Row 'WARN' 'Default route' "via $n (not the VPN)" 'Yellow' }
    }

    $def6 = Get-NetRoute -DestinationPrefix '::/0' -EA SilentlyContinue | Sort-Object RouteMetric | Select-Object -First 1
    if (-not $def6) { Write-Row 'OK' 'IPv6' 'no route (cannot leak)' 'Green' }
    else {
        $n6 = (Get-NetAdapter -InterfaceIndex $def6.ifIndex -EA SilentlyContinue).Name
        if ($vpn -and $n6 -eq $vpn.Name) { Write-Row 'OK' 'IPv6' "via $n6" 'Green' }
        else { Write-Row 'LEAK' 'IPv6' "via $n6 -- bypasses the tunnel" 'Red' }
    }

    # One request gives both IP and country. (Two separate lookups before.)
    try {
        $t = Invoke-RestMethod -Uri 'https://www.cloudflare.com/cdn-cgi/trace' -TimeoutSec 8
        $s.Ip      = (($t -split "`n" | Where-Object { $_ -like 'ip=*'  }) -replace 'ip=','').Trim()
        $s.Country = (($t -split "`n" | Where-Object { $_ -like 'loc=*' }) -replace 'loc=','').Trim()
        Write-Row 'INFO' 'Public IP' $s.Ip
        Write-Row 'INFO' 'Apparent country' $s.Country
    } catch { Write-Row 'WARN' 'Public IP' 'could not reach Cloudflare trace' 'Yellow' }

    Write-Row 'INFO' 'System timezone' $s.Tz
    if ($Config.ExpectedCountry -and $s.Country) {
        if ($s.Country -eq $Config.ExpectedCountry) { Write-Row 'OK' 'Coherence' "exit = $($s.Country) as expected" 'Green' }
        else { Write-Row 'FAIL' 'Coherence' "exit=$($s.Country) expected=$($Config.ExpectedCountry)" 'Red' }
    } else {
        Write-Note "Set ExpectedCountry in the config block to check this automatically."
    }
    return $s
}

# ============================================================================
#  AUDIT  (was Test-Leaks.ps1 + Test-Advanced.ps1)
# ============================================================================
function Invoke-Audit {
    param([switch]$Brief)
    $todo = New-Object System.Collections.ArrayList

    function A { param($S,$L,$D,$F,$C='Gray')
        Write-Row $S $L $D $C
        if ($F -and $S -in 'MISS','PART') { [void]$todo.Add($F) }
    }

    Write-Head "Hardware and disk"
    if ($script:IsAdmin) {
        try {
            $sys = Get-BitLockerVolume -EA Stop | Where-Object VolumeType -eq 'OperatingSystem' | Select-Object -First 1
            if ($sys -and $sys.ProtectionStatus -eq 'On') { A 'OK' 'Full-disk encryption' "BitLocker on ($($sys.MountPoint))" $null 'Green' }
            else { A 'MISS' 'Full-disk encryption' 'BitLocker OFF' 'Enable BitLocker (or VeraCrypt). Without it, every other layer is theatre if the laptop is taken.' 'Red' }
        } catch { A 'PART' 'Full-disk encryption' 'BitLocker unavailable' 'Windows Home has no BitLocker -- use VeraCrypt (https://veracrypt.io).' 'Yellow' }
        try { if (Confirm-SecureBootUEFI -EA Stop) { A 'OK' 'Secure Boot' 'enabled' $null 'Green' } else { A 'PART' 'Secure Boot' 'disabled' 'Enable Secure Boot in UEFI.' 'Yellow' } }
        catch { A 'INFO' 'Secure Boot' 'legacy BIOS / unsupported' }
        try {
            $tpm = Get-Tpm -EA Stop
            if ($tpm.TpmPresent -and $tpm.TpmReady) { A 'OK' 'TPM' 'present and ready' $null 'Green' }
            elseif ($tpm.TpmPresent) { A 'PART' 'TPM' 'present, not ready' 'Initialize the TPM (tpm.msc) to back BitLocker in hardware.' 'Yellow' }
            else { A 'INFO' 'TPM' 'not present' }
        } catch { A 'INFO' 'TPM' 'unavailable' }
    } else {
        Write-Row 'ADMIN' 'Disk / firmware checks' 'need admin -- use menu option H or -Audit elevated' 'DarkGray'
    }

    Write-Head "DNS"
    $doh = Get-BrowserDoh
    if (-not $script:OsDohSupported) {
        Write-Row 'INFO' 'OS encrypted DNS' 'not supported on this Windows build'
        Write-Note "Windows 10 has no DoH client -- that is a Windows 11 feature."
    }
    if ($doh -in 'secure','automatic') { A 'OK' 'Browser encrypted DNS' "Brave DoH = $doh" $null 'Green' }
    else { A 'MISS' 'Browser encrypted DNS' 'off' 'Run option C (Configure) -- sets dns_over_https.mode = secure. This is what enables ECH.' 'Red' }

    $dns = Get-DnsPolicyState
    foreach ($c in @(
        @{K='EnableMulticast';            W=0; L='LLMNR disabled'}
        @{K='EnableMDNS';                 W=0; L='mDNS disabled'}
        @{K='DisableSmartNameResolution'; W=1; L='Multi-homed DNS off'}
    )) {
        if ($dns[$c.K] -eq $c.W) { A 'OK' $c.L "= $($dns[$c.K])" $null 'Green' }
        else { A 'MISS' $c.L 'not set' 'Run option H (Harden) -- closes the LAN broadcast and VPN DNS leak paths.' 'Red' }
    }

    Write-Head "ECH -- encrypted SNI"
    # The encrypted-client-hello flag expired in Chromium M122 and was removed;
    # ECH is on by default. Encrypted DNS is the only real prerequisite.
    Write-Row 'OK' 'ECH support' 'on by default (flag removed upstream)' 'Green'
    if ($doh -in 'secure','automatic') { A 'OK' 'ECH prerequisite (DoH)' "browser DoH = $doh" $null 'Green' }
    else { A 'MISS' 'ECH prerequisite (DoH)' 'plaintext DNS -> ECH silently inactive' 'Run option C. ECH keys arrive over DNS; without DoH your SNI stays in the clear.' 'Red' }
    Write-Note "Live proof: https://crypto.cloudflare.com/cdn-cgi/trace -> want sni=encrypted"

    # ---- Ban-risk: why sites challenge you --------------------------------
    # Static leak checks say what you look like. This says how you are SCORED.
    Write-Head "Ban risk"

    # 1. Identity mode on a logged-in lane. The single biggest self-inflicted
    #    cause of challenges: a new profile every launch has no cookie age and
    #    no history, which is the automation signature.
    if ($Config.Lane2IdentityMode -eq 'Fresh') {
        A 'MISS' 'Lane 2 identity' 'Fresh -- no cookie age, no history' `
          "Set Lane2IdentityMode = 'Persistent' in Bulkhead.ps1. A brand-new profile every launch is the automation signature; on a lane where you log in it raises challenges sharply." 'Red'
    } else {
        $h = Join-Path $Config.BraveDataDir 'Default\History'
        $age = if (Test-Path $h) { [int]((Get-Date) - (Get-Item $h).CreationTime).TotalDays } else { 0 }
        if ($age -ge 7) { A 'OK' 'Lane 2 identity' "persistent, $age days aged" $null 'Green' }
        else { A 'PART' 'Lane 2 identity' "persistent but only $age day(s) old" 'Young profiles still draw challenges. It improves on its own -- just keep using it instead of resetting it.' 'Yellow' }
    }

    # 2. Exit reputation. Datacenter/VPN ranges sit on every vendor's list.
    $vpnUp = [bool](Get-VpnAdapter)
    if ($vpnUp) {
        A 'PART' 'Exit IP reputation' 'VPN / datacenter range' `
          'Expected: VPN exits carry a higher baseline challenge rate than a home connection. Trade-off, not a bug. If one site is unusable, open it in Lane 1 on your home connection.' 'Yellow'
    } else {
        A 'OK' 'Exit IP reputation' 'residential ISP -- good reputation' $null 'Green'
    }

    # 3. Geographic coherence: exit country vs system clock.
    $tzOff = [int][Math]::Round([TimeZoneInfo]::Local.GetUtcOffset((Get-Date)).TotalHours)
    $offsets = @{ MA=1; PT=1; GB=1; ES=2; FR=2; DE=2; NL=2; BE=2; IT=2; CH=2; SE=2; NO=2; PL=2
                  US=-5; CA=-5; JP=9; SG=8; AU=10; AE=4; RO=3; FI=3; TR=3 }
    try {
        $t = Invoke-RestMethod 'https://www.cloudflare.com/cdn-cgi/trace' -TimeoutSec 8
        $loc = (($t -split "`n" | Where-Object { $_ -like 'loc=*' }) -replace 'loc=','').Trim()
        if ($offsets.ContainsKey($loc)) {
            $gap = [Math]::Abs($offsets[$loc] - $tzOff)
            if ($gap -le 1) { A 'OK' 'Geo coherence' "exit $loc vs clock UTC+$tzOff (${gap}h)" $null 'Green' }
            elseif ($gap -le 3) { A 'PART' 'Geo coherence' "exit $loc vs clock UTC+$tzOff (${gap}h gap)" "A ${gap}-hour gap between exit country and system clock is a mild flag. Pick an exit nearer your timezone, or accept it." 'Yellow' }
            else { A 'MISS' 'Geo coherence' "exit $loc vs clock UTC+$tzOff (${gap}h gap)" "A ${gap}-hour gap is the classic VPN tell. Choose an exit close to your real timezone." 'Red' }
        } else {
            Write-Row 'INFO' 'Geo coherence' "exit $loc vs clock UTC+$tzOff -- check manually"
        }
    } catch { }

    # 4. Cookie state. Blocking or clearing everything defeats verification.
    $ck = Join-Path $Config.BraveDataDir 'Default\Network\Cookies'
    if (Test-Path $ck) { A 'OK' 'Cookie state' 'persistent jar present' $null 'Green' }
    else { A 'PART' 'Cookie state' 'no cookie jar yet' 'Sites that cannot set a cookie will re-challenge forever. Normal for a new profile.' 'Yellow' }

    if (-not $Brief) {
        Write-Head "Network"
        $vpn = Get-VpnAdapter
        if ($vpn) {
            A 'OK' 'VPN interface' $vpn.Name $null 'Green'
            Write-Note "Enable in the client (all free): kill switch, quantum-resistant"
            Write-Note "tunnel, DAITA. Multihop optional."
        } else {
            A 'MISS' 'VPN interface' 'no tunnel' 'Open the VPN app (option V). Post-quantum, DAITA and multihop all need it.' 'Red'
        }
        foreach ($a in (Get-UpAdapters)) {
            $srv = (Get-DnsClientServerAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -EA SilentlyContinue).ServerAddresses -join ', '
            if ($srv) { Write-Row 'INFO' "DNS on $($a.Name)" $srv }
        }
        Write-Note "Verify externally: dnsleaktest.com (extended), ipleak.net,"
        Write-Note "browserleaks.com/webrtc"

        Write-Head "Identity layer -- audit yourself"
        Write-Host "    [ ] Email aliasing (SimpleLogin / addy.io)" -ForegroundColor Gray
        Write-Note "Your address is a stronger cross-site key than any fingerprint."
        Write-Host "    [ ] Separate email per lane" -ForegroundColor Gray
        Write-Host "    [ ] Password manager, unique passwords" -ForegroundColor Gray
        Write-Host "    [ ] Virtual / single-use payment cards" -ForegroundColor Gray
    }

    Write-Host ""
    Write-Host "  $('=' * 68)" -ForegroundColor DarkCyan
    if ($todo.Count) {
        Write-Host "  DO THESE, in order:" -ForegroundColor White
        Write-Host ""
        $i = 0
        foreach ($t in ($todo | Select-Object -Unique)) { $i++; Write-Host "   $i. $t" -ForegroundColor Yellow }
    } else {
        Write-Host "  Everything checkable is in place." -ForegroundColor Green
    }
    Write-Host ""
    return $todo.Count
}

# ============================================================================
#  CONFIGURE BROWSER  (was Configure-Brave.ps1)
# ============================================================================
$PrefSettings = [ordered]@{
    'webrtc.ip_handling_policy'          = 'disable_non_proxied_udp'
    'webrtc.multiple_routes_enabled'     = $false
    'webrtc.nonproxied_udp_enabled'      = $false
    'brave.today.opted_in'               = $false
    'brave.new_tab_page.show_brave_news' = $false
    'search.suggest_enabled'             = $false
    'autofill.credit_card_enabled'       = $false
    'autofill.profile_enabled'           = $false
    'credentials_enable_service'         = $false
    'signin.allowed'                     = $false
}

function Get-JsonPath { param($Obj,[string]$Path)
    $cur = $Obj
    foreach ($p in $Path.Split('.')) {
        if ($null -eq $cur) { return $null }
        $cur = $cur.PSObject.Properties[$p]
        if (-not $cur) { return $null }
        $cur = $cur.Value
    }
    return $cur
}
function Set-JsonPath { param($Obj,[string]$Path,$Value)
    $parts = $Path.Split('.'); $cur = $Obj
    for ($i=0; $i -lt $parts.Count-1; $i++) {
        $n = $parts[$i]
        if (-not $cur.PSObject.Properties[$n] -or $null -eq $cur.$n) {
            $cur | Add-Member -NotePropertyName $n -NotePropertyValue ([pscustomobject]@{}) -Force
        }
        $cur = $cur.$n
    }
    $cur | Add-Member -NotePropertyName $parts[-1] -NotePropertyValue $Value -Force
}

function Invoke-ConfigureBrowser {
    param([string]$DataDir = $Config.BraveDataDir, [switch]$Quiet)

    $b = (Get-Browsers).Brave
    if (-not $b) { Write-Host "  Brave not installed." -ForegroundColor Red; return $false }

    if (-not $Quiet) { Write-Head "Configuring Lane 2" }
    New-Item -ItemType Directory -Path $DataDir -Force | Out-Null

    $prefs = Join-Path $DataDir 'Default\Preferences'
    $lsp   = Join-Path $DataDir 'Local State'

    # Brave must have run once for the files to exist.
    if (-not (Test-Path $prefs)) {
        if (-not $Quiet) { Write-Host "  Initializing profile..." -ForegroundColor Yellow }
        $p = Start-Process $b -ArgumentList @("--user-data-dir=$DataDir",'--no-first-run','--no-default-browser-check','about:blank') -PassThru
        $t = 0
        while (-not (Test-Path $prefs) -and $t -lt 30) { Start-Sleep -Milliseconds 500; $t++ }
        Start-Sleep 2
        Get-Process -Id $p.Id -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
        Start-Sleep 2
    }
    if (-not (Test-Path $prefs)) { Write-Host "  Could not initialize profile." -ForegroundColor Red; return $false }

    # Brave must be closed or it overwrites on exit.
    Get-Process brave -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
    Start-Sleep 2

    $j = Get-Content $prefs -Raw | ConvertFrom-Json
    foreach ($k in $PrefSettings.Keys) { Set-JsonPath $j $k $PrefSettings[$k] }
    $j | ConvertTo-Json -Depth 100 -Compress | Set-Content $prefs -Encoding UTF8 -NoNewline

    $ls = if (Test-Path $lsp) { Get-Content $lsp -Raw | ConvertFrom-Json } else { [pscustomobject]@{} }
    Set-JsonPath $ls 'p3a.enabled' $false
    Set-JsonPath $ls 'brave.stats.reporting_enabled' $false
    Set-JsonPath $ls 'user_experience_metrics.reporting_enabled' $false
    # Encrypted DNS in the browser -- Windows 10 has no OS DoH, and Chromium
    # fetches ECH keys through its own resolver, so this is what enables ECH.
    Set-JsonPath $ls 'dns_over_https.mode' $Config.DohMode
    Set-JsonPath $ls 'dns_over_https.templates' $Config.DohTemplate
    $ls | ConvertTo-Json -Depth 100 -Compress | Set-Content $lsp -Encoding UTF8 -NoNewline

    # Verify: Brave silently discards settings it does not recognise, so
    # writing them is not proof. Relaunch and read them back.
    if (-not $Quiet) { Write-Host "  Verifying (relaunching)..." -ForegroundColor DarkGray }
    $p2 = Start-Process $b -ArgumentList @("--user-data-dir=$DataDir",'--no-first-run','--no-default-browser-check','about:blank') -PassThru
    Start-Sleep 6
    Get-Process -Id $p2.Id -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
    Start-Sleep 2

    $kept = 0; $lost = 0
    $after   = Get-Content $prefs -Raw | ConvertFrom-Json
    $lsAfter = Get-Content $lsp   -Raw | ConvertFrom-Json
    foreach ($k in $PrefSettings.Keys) {
        if ("$(Get-JsonPath $after $k)" -eq "$($PrefSettings[$k])") { $kept++ } else { $lost++
            if (-not $Quiet) { Write-Host "    [LOST] $k" -ForegroundColor Red } }
    }
    foreach ($k in @('dns_over_https.mode','dns_over_https.templates')) {
        $want = if ($k -like '*mode') { $Config.DohMode } else { $Config.DohTemplate }
        if ("$(Get-JsonPath $lsAfter $k)" -eq "$want") { $kept++ } else { $lost++
            if (-not $Quiet) { Write-Host "    [LOST] $k" -ForegroundColor Red } }
    }

    if (-not $Quiet) {
        Write-Row $(if($lost -eq 0){'OK'}else{'WARN'}) 'Settings retained' "$kept kept, $lost discarded" $(if($lost -eq 0){'Green'}else{'Yellow'})
        Write-Note "Fingerprinting stays on Brave's Standard setting deliberately --"
        Write-Note "Standard already farbles canvas/WebGL/WebGPU/audio/fonts per"
        Write-Note "session and per origin. Strict adds breakage for little gain."
    }

    # Rebuild the identity template so fresh sessions inherit all of this.
    Remove-Item $Config.BraveTemplate -Recurse -Force -EA SilentlyContinue
    New-FreshTemplate | Out-Null
    return ($lost -eq 0)
}

# ============================================================================
#  FRESH IDENTITY
# ============================================================================
function New-FreshTemplate {
    $tpl = $Config.BraveTemplate
    if (Test-Path (Join-Path $tpl 'Default\Preferences')) { return $tpl }
    New-Item -ItemType Directory -Path (Join-Path $tpl 'Default') -Force | Out-Null
    $src = Join-Path $Config.BraveDataDir 'Default\Preferences'
    if (-not (Test-Path $src)) { throw "No configured profile to build a template from" }
    Set-Content -Path (Join-Path $tpl 'First Run') -Value '' -NoNewline
    Copy-Item $src (Join-Path $tpl 'Default\Preferences') -Force
    $ls = Join-Path $Config.BraveDataDir 'Local State'
    if (Test-Path $ls) { Copy-Item $ls (Join-Path $tpl 'Local State') -Force }
    return $tpl
}

function New-FreshIdentity {
    $tpl = New-FreshTemplate
    $root = $Config.BraveSessions
    New-Item -ItemType Directory -Path $root -Force | Out-Null

    # Retire old identities. This is the point of the mode, and it also leaves
    # no forensic residue behind.
    #
    # A Brave still running from a previous launch holds locks on its session
    # directory, so deletion fails. Retry briefly, and REPORT anything that
    # survives -- silently swallowing this lets stale identities pile up while
    # the tool claims the previous session was deleted.
    $stale = @()
    $old = @(Get-ChildItem $root -Directory -EA SilentlyContinue | Sort-Object CreationTime -Descending)
    foreach ($d in $old | Select-Object -Skip ([Math]::Max(0,$Config.KeepSessions-1))) {
        $gone = $false
        for ($try = 0; $try -lt 3 -and -not $gone; $try++) {
            try { Remove-Item $d.FullName -Recurse -Force -EA Stop; $gone = $true }
            catch { Start-Sleep -Milliseconds 700 }
        }
        if (-not $gone) { $stale += $d.Name }
    }
    if ($stale.Count) {
        Write-Row 'WARN' 'Old identity not deleted' ($stale -join ', ') 'Yellow'
        Write-Note "Locked by a running Brave. Close all Brave windows and relaunch,"
        Write-Note "or delete manually: $root"
    }
    $script:LastCleanupClean = ($stale.Count -eq 0)

    $s = Join-Path $root ("s{0}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    New-Item -ItemType Directory -Path (Join-Path $s 'Default') -Force | Out-Null
    Set-Content -Path (Join-Path $s 'First Run') -Value '' -NoNewline
    Copy-Item (Join-Path $tpl 'Default\Preferences') (Join-Path $s 'Default\Preferences') -Force
    $tls = Join-Path $tpl 'Local State'
    if (Test-Path $tls) { Copy-Item $tls (Join-Path $s 'Local State') -Force }
    return $s
}

function Resolve-Lane2Profile {
    param([bool]$VpnUp)
    if ($Config.Lane2IdentityMode -ne 'Fresh') {
        # Age is an asset here: accumulated history and cookies are what make
        # you read as a returning human rather than a fresh automation profile.
        $h = Join-Path $Config.BraveDataDir 'Default\History'
        if (Test-Path $h) {
            $age = [int]((Get-Date) - (Get-Item $h).CreationTime).TotalDays
            Write-Row 'OK' 'Identity' "persistent, $age day(s) of history" 'Green'
        } else {
            Write-Row 'OK' 'Identity' 'persistent (new profile, will age in)' 'Green'
        }
        return $Config.BraveDataDir
    }
    Write-Row 'WARN' 'Identity' 'Fresh on a logged-in lane -- raises ban risk' 'Yellow'
    Write-Note "Set Lane2IdentityMode = 'Persistent' unless you know why you want this."
    try {
        $p = New-FreshIdentity
        Write-Row 'NEW' 'Fresh identity' (Split-Path $p -Leaf) 'Magenta'
        if ($script:LastCleanupClean) {
            Write-Note "No cookies, history or logins carried over. Previous session deleted."
        } else {
            Write-Note "No cookies, history or logins carried over."
        }
        if (-not $VpnUp) {
            Write-Host ""
            Write-Host "          Your IP did NOT change -- there is no tunnel." -ForegroundColor Red
            Write-Host "          A fresh profile behind the same IP is not a new identity." -ForegroundColor Red
        }
        return $p
    } catch {
        Write-Row 'ERR' 'Fresh identity' "$($_.Exception.Message) -- using persistent" 'Red'
        return $Config.BraveDataDir
    }
}

# ============================================================================
#  LANES
# ============================================================================
function Confirm-NoTunnel {
    param([string]$LaneName,[bool]$VpnUp)
    if ($VpnUp -or $Force) { return $true }
    Write-Host ""
    Write-Host "  No VPN. $LaneName over your real IP defeats the point." -ForegroundColor Red
    return ((Read-Host "  Launch anyway? (y/N)") -eq 'y')
}

function Start-Lane1 {
    Write-Head "Lane 1 -- Identity"
    $br = Get-Browsers
    $exe = $br.Edge; $kind = 'Edge'
    if (-not $exe) { $exe = $br.Firefox; $kind = 'Firefox' }
    if (-not $exe) { Write-Host "  No Edge or Firefox found." -ForegroundColor Red; return }
    Write-Note "Real fingerprint, no spoofing. Bank / government / work only."
    if ($kind -eq 'Edge') {
        Start-Process $exe -ArgumentList @("--user-data-dir=$(Join-Path $Config.DataRoot 'edge-lane1')")
    } else { Start-Process $exe -ArgumentList @('-P','lane1-identity') }
    Write-Host "  Launched $kind (Lane 1)." -ForegroundColor Green
}

function Start-Lane2 {
    param([bool]$VpnUp)
    Write-Head "Lane 2 -- Daily"
    if (-not (Confirm-NoTunnel 'Lane 2' $VpnUp)) { Write-Host "  Cancelled." -ForegroundColor Yellow; return }
    $b = (Get-Browsers).Brave
    if (-not $b) { Write-Host "  Brave not installed -- use option I." -ForegroundColor Red; return }
    if (-not (Test-Path (Join-Path $Config.BraveDataDir 'Default\Preferences'))) {
        Write-Host "  Profile not configured yet -- configuring now." -ForegroundColor Yellow
        Invoke-ConfigureBrowser -Quiet | Out-Null
    }
    $dir = Resolve-Lane2Profile -VpnUp $VpnUp
    Start-Process $b -ArgumentList @("--user-data-dir=$dir",'--no-default-browser-check')
    Write-Host "  Launched Brave (Lane 2). WebRTC sealed, DoH on, ECH active." -ForegroundColor Green
}

function Start-Lane3 {
    param([bool]$VpnUp)
    Write-Head "Lane 3 -- Anonymous"
    if (-not (Confirm-NoTunnel 'Lane 3' $VpnUp)) { Write-Host "  Cancelled." -ForegroundColor Yellow; return }
    $br = Get-Browsers
    if ($br.Mullvad)  { Start-Process $br.Mullvad; Write-Host "  Launched Mullvad Browser." -ForegroundColor Green }
    elseif ($br.Tor)  { Start-Process $br.Tor;     Write-Host "  Launched Tor Browser." -ForegroundColor Green }
    else { Write-Host "  Install Mullvad Browser (option I)." -ForegroundColor Red; return }
    Write-Host ""
    Write-Host "  RULES:" -ForegroundColor Magenta
    Write-Host "    Change NOTHING -- no extensions, no theme, no resize, no about:config." -ForegroundColor Magenta
    Write-Host "    Uniformity IS the protection. Customizing makes you unique." -ForegroundColor Magenta
    Write-Host "    Log into NOTHING from Lane 1 or 2." -ForegroundColor Magenta
}

function Start-Lane4 {
    Write-Head "Lane 4 -- Maximum"
    Write-Host "  Tor, plus the isolation Tor Browser alone does not have." -ForegroundColor Magenta
    Write-Host ""
    Write-Host "  Plain Tor Browser is one process on your normal PC, so a browser" -ForegroundColor White
    Write-Host "  exploit reaches your real IP and real disk. Lane 4 removes that." -ForegroundColor White
    Write-Host ""
    Write-Host "    Tails         amnesic live USB      https://tails.net" -ForegroundColor Gray
    Write-Host "    Whonix        two-VM Tor gateway    https://www.whonix.org" -ForegroundColor Gray
    Write-Host "    Qubes-Whonix  the ceiling           https://www.qubes-os.org" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Guide: lanes\lane4-maximum.md  ·  Honest comparison: docs\beyond-tor.md" -ForegroundColor Yellow
}

# ============================================================================
#  VPN
# ============================================================================
function Start-Vpn {
    Write-Head "VPN"
    $apps = Get-VpnApps
    $app = $null; $name = $null
    foreach ($k in 'Mullvad','Proton') { if ($apps[$k]) { $app = $apps[$k]; $name = $k; break } }
    if (-not $app) {
        Write-Host "  No VPN client installed." -ForegroundColor Red
        Write-Host "    winget install --id MullvadVPN.MullvadVPN --exact" -ForegroundColor Cyan
        Write-Host "    winget install --id Proton.ProtonVPN --exact      (free tier)" -ForegroundColor Cyan
        return
    }
    Write-Row 'OK' "$name client" $app 'Green'
    $svc = Get-Service -Name 'MullvadVPN' -EA SilentlyContinue
    if ($svc) { Write-Row 'OK' 'Background service' $svc.Status 'Green' }
    Start-Process $app
    Write-Host ""
    Write-Host "  Opened. It may go to the SYSTEM TRAY (bottom-right), not a window." -ForegroundColor Green
    Write-Host ""
    Write-Host "  FIRST TIME: create account -> 16-digit number, no email." -ForegroundColor White
    Write-Host "              SAVE IT. There is no password reset." -ForegroundColor Yellow
    Write-Host "              Add time, then connect to Spain or France." -ForegroundColor Gray
    Write-Host ""
    Write-Host "  THEN ENABLE (Settings > VPN settings, all free):" -ForegroundColor White
    Write-Host "    Kill switch / Lockdown mode    REQUIRED" -ForegroundColor Gray
    Write-Host "    Quantum-resistant tunnel       harvest-now-decrypt-later" -ForegroundColor Gray
    Write-Host "    DAITA                          AI traffic-analysis defense" -ForegroundColor Gray
    Write-Host "    Auto-connect" -ForegroundColor Gray
}

function Install-Missing {
    Write-Head "Install"
    if (-not (Get-Command winget -EA SilentlyContinue)) { Write-Host "  winget not available." -ForegroundColor Red; return }
    $br = Get-Browsers; $vp = Get-VpnApps
    $want = @()
    if (-not $br.Brave)   { $want += @{ Id='Brave.Brave';               N='Brave (Lane 2)' } }
    if (-not $br.Mullvad) { $want += @{ Id='MullvadVPN.MullvadBrowser'; N='Mullvad Browser (Lane 3)' } }
    if (-not $vp.Mullvad) { $want += @{ Id='MullvadVPN.MullvadVPN';     N='Mullvad VPN' } }
    if (-not $want) { Write-Host "  Everything is installed." -ForegroundColor Green; return }
    foreach ($w in $want) { Write-Host "    $($w.N)   [$($w.Id)]" -ForegroundColor Gray }
    Write-Host ""
    if ((Read-Host "  Install these? (y/N)") -ne 'y') { Write-Host "  Cancelled." -ForegroundColor Yellow; return }
    foreach ($w in $want) {
        Write-Host "`n  Installing $($w.N)..." -ForegroundColor Cyan
        winget install --id $w.Id --exact --accept-package-agreements --accept-source-agreements | Out-Null
    }
    $script:Browsers = $null; $script:VpnApps = $null   # bust the cache
    Write-Host "`n  Done." -ForegroundColor Green
}

# ============================================================================
#  HARDEN / REVERT  (was Harden-Windows.ps1 + Revert-Hardening.ps1)
# ============================================================================
function Invoke-Harden {
    param([switch]$DoApply,[string]$Hostname)

    if (-not $script:IsAdmin) { throw "Hardening needs administrator." }
    $changes = New-Object System.Collections.ArrayList
    $mode = if ($DoApply) { 'APPLY' } else { 'DRY-RUN' }

    Write-Head "OS hardening -- $mode"
    if (-not $DoApply) { Write-Host "  Nothing will be changed. Review, then confirm." -ForegroundColor Yellow }

    function Reg { param($Path,$Name,$Value,$Why)
        $old = $null
        if (Test-Path $Path) { try { $old = (Get-ItemProperty $Path -Name $Name -EA Stop).$Name } catch { } }
        if ($old -eq $Value) { Write-Row 'SKIP' $Name "already $Value" 'DarkGray'; return }
        Write-Row $(if($DoApply){'SET'}else{'WOULD'}) $Name "$(if($null -eq $old){'<unset>'}else{$old}) -> $Value" $(if($DoApply){'Green'}else{'Yellow'})
        if ($Why) { Write-Note $Why }
        [void]$changes.Add([pscustomobject]@{ Kind='Registry'; Path=$Path; Name=$Name; OldValue=$old; Type='DWord' })
        if ($DoApply) {
            if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
            New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType DWord -Force | Out-Null
        }
    }

    $dnsPol = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient'
    Reg $dnsPol 'EnableMulticast' 0 'LLMNR broadcasts your DNS queries to the whole LAN.'
    Reg $dnsPol 'EnableMDNS' 0 'mDNS advertises this device to the whole LAN.'
    Reg $dnsPol 'DisableSmartNameResolution' 1 'Stops DNS going out every interface -- the classic VPN DNS leak.'
    Reg 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters' 'DisableParallelAandAAAA' 1 'Stops parallel A/AAAA races escaping the tunnel.'

    $nb = 'HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces'
    if (Test-Path $nb) { foreach ($i in Get-ChildItem $nb) { Reg $i.PSPath 'NetbiosOptions' 2 $null } }

    Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 0 'Minimize diagnostic upload.'
    Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0 'Disable the cross-app advertising ID.'
    Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 0 $null
    Reg 'HKCU:\Software\Microsoft\Input\TIPC' 'Enabled' 0 'Disable inking/typing telemetry.'

    Write-Head "Hostname"
    Write-Row 'INFO' 'Current' $env:COMPUTERNAME
    Write-Note "Broadcast via DHCP opt-12, mDNS and NetBIOS on every network you join."
    if ($Hostname) {
        Write-Row $(if($DoApply){'SET'}else{'WOULD'}) 'Rename' "$env:COMPUTERNAME -> $Hostname (reboot)" 'Yellow'
        [void]$changes.Add([pscustomobject]@{ Kind='Hostname'; OldValue=$env:COMPUTERNAME; NewValue=$Hostname })
        if ($DoApply) { Rename-Computer -NewName $Hostname -Force }
    } else { Write-Note "Pass -NewHostname DESKTOP-XXXXXXX to change it." }

    Write-Head "MAC randomization -- manual"
    Write-Note "MAC never reaches a website (layer 2, stripped at the first router)."
    Write-Note "It matters to Wi-Fi access points and captive portals."
    Write-Host "    Settings > Network & Internet > Wi-Fi" -ForegroundColor Magenta
    Write-Host "      -> Random hardware addresses = On" -ForegroundColor Magenta

    Write-Host ""
    if ($DoApply -and $changes.Count) {
        $changes | ConvertTo-Json -Depth 5 | Set-Content $Config.RevertLog -Encoding UTF8
        Write-Host "  Applied $($changes.Count) change(s). Revert data: $($Config.RevertLog)" -ForegroundColor Green
        Write-Host "  REBOOT for NetBIOS changes to take effect." -ForegroundColor Yellow
    } elseif (-not $DoApply) {
        Write-Host "  $($changes.Count) change(s) proposed. Nothing was modified." -ForegroundColor Yellow
    } else {
        Write-Host "  Nothing to change -- already hardened." -ForegroundColor Green
    }
    return $changes.Count
}

function Invoke-Revert {
    param([switch]$DoApply)
    if (-not $script:IsAdmin) { throw "Revert needs administrator." }
    if (-not (Test-Path $Config.RevertLog)) {
        Write-Host "`n  Nothing to revert -- no revert-state.json.`n" -ForegroundColor Yellow; return
    }
    $changes = @(Get-Content $Config.RevertLog -Raw | ConvertFrom-Json)
    Write-Head "Revert -- $(if($DoApply){'APPLY'}else{'DRY-RUN'})"
    foreach ($c in $changes) {
        switch ($c.Kind) {
            'Registry' {
                $shown = if ($null -eq $c.OldValue) { '<delete>' } else { $c.OldValue }
                Write-Row 'UNDO' $c.Name "-> $shown" 'Yellow'
                if ($DoApply) {
                    if ($null -eq $c.OldValue) { Remove-ItemProperty -Path $c.Path -Name $c.Name -EA SilentlyContinue }
                    else {
                        if (-not (Test-Path $c.Path)) { New-Item -Path $c.Path -Force | Out-Null }
                        New-ItemProperty -Path $c.Path -Name $c.Name -Value $c.OldValue -PropertyType $c.Type -Force | Out-Null
                    }
                }
            }
            'Hostname' {
                Write-Row 'MANUAL' 'Hostname' "was $($c.OldValue)" 'Magenta'
                Write-Note "Restore with: Rename-Computer -NewName '$($c.OldValue)' -Force"
            }
        }
    }
    Write-Host ""
    if ($DoApply) { Remove-Item $Config.RevertLog -Force; Write-Host "  Reverted. Reboot to finish.`n" -ForegroundColor Green }
    else { Write-Host "  Dry run. Re-run with -Apply to revert.`n" -ForegroundColor Yellow }
}

# Spawn an elevated copy of THIS script for the admin-only parts. The browser
# must never run elevated, so only this path asks for it.
function Invoke-Elevated {
    param([string[]]$ScriptArgs)
    $exe = if (Get-Command pwsh -EA SilentlyContinue) { 'pwsh' } else { 'powershell' }
    $a = @('-NoProfile','-ExecutionPolicy','Bypass','-NoExit','-File',"`"$PSCommandPath`"") + $ScriptArgs
    try { Start-Process $exe -ArgumentList $a -Verb RunAs }
    catch { Write-Host "  Elevation cancelled." -ForegroundColor Yellow }
}

# ============================================================================
#  AUTO
# ============================================================================
function Invoke-Auto {
    param($State)
    Write-Head "Automatic run"

    $dns = Get-DnsPolicyState
    $hardened = ($dns['EnableMulticast'] -eq 0) -and ($dns['EnableMDNS'] -eq 0) -and ($dns['DisableSmartNameResolution'] -eq 1)
    Write-Row $(if($hardened){'OK'}else{'TODO'}) 'OS hardening' $(if($hardened){'complete'}else{'incomplete -- run option H'}) $(if($hardened){'Green'}else{'Yellow'})

    $doh = Get-BrowserDoh
    Write-Row $(if($doh -in 'secure','automatic'){'OK'}else{'TODO'}) 'Encrypted DNS + ECH' $(if($doh){"browser DoH = $doh"}else{'off -- run option C'}) $(if($doh){'Green'}else{'Yellow'})

    $br = Get-Browsers
    Write-Row 'INFO' 'Browsers' (($br.GetEnumerator() | Where-Object { $_.Value } | ForEach-Object { $_.Key }) -join ', ')

    if (-not $br.Brave) {
        Write-Host "`n  Brave is not installed. Use option I from the menu.`n" -ForegroundColor Red
        return
    }
    if (-not (Test-Path (Join-Path $Config.BraveDataDir 'Default\Preferences'))) {
        Write-Row 'FIX' 'Lane 2 profile' 'not configured -- configuring now' 'Yellow'
        Invoke-ConfigureBrowser -Quiet | Out-Null
    } else {
        Write-Row 'OK' 'Lane 2 profile' 'configured' 'Green'
    }

    # ---- Lane 3 default: amnesic + uniform, the real Tor-like path ---------
    if ($Config.DefaultLane -eq 3) {
        Write-Head "Launch -- Lane 3 (new identity every launch)"
        $l3 = if ($br.Mullvad) { $br.Mullvad } elseif ($br.Tor) { $br.Tor } else { $null }
        if ($l3) {
            $which = if ($br.Mullvad) { 'Mullvad Browser' } else { 'Tor Browser' }
            Write-Row 'NEW' 'Identity' 'fresh -- nothing is saved, ever' 'Magenta'
            Write-Note "$which is amnesic by design: no history, no cookies, no"
            Write-Note "logins survive closing it. Every launch is the first launch."
            Write-Note "And your fingerprint matches every other user of it, so"
            Write-Note "'brand new' looks normal here instead of looking automated."
            if (-not $State.VpnUp) {
                Write-Host ""
                Write-Host "          No tunnel -- your real IP is still visible." -ForegroundColor Red
                Write-Host "          Connect the VPN (menu option V) for a new IP too." -ForegroundColor Red
            }
            Start-Process $l3
            Write-Host ""
            Write-Host "  $which launched." -ForegroundColor Green
            Write-Host "  Change NOTHING in it. No extensions, no resize, no settings --" -ForegroundColor Magenta
            Write-Host "  uniformity IS the protection. Log into nothing from Lane 1 or 2." -ForegroundColor Magenta
            Write-Host ""
            return
        }
        Write-Row 'MISS' 'Lane 3 browser' 'not installed -- falling back to Lane 2' 'Yellow'
        Write-Note "Install Mullvad Browser with menu option I for true Tor-like behaviour."
    }

    Write-Head "Launch"
    if (-not $State.VpnUp) {
        Write-Host "  +--------------------------------------------------------------+" -ForegroundColor Red
        Write-Host "  |  NO VPN -- your real IP is visible to every site you open.    |" -ForegroundColor Red
        Write-Host "  |  Fingerprinting is handled. Your address is not.              |" -ForegroundColor Red
        Write-Host "  +--------------------------------------------------------------+" -ForegroundColor Red
        $app = (Get-VpnApps).Values | Where-Object { $_ } | Select-Object -First 1
        if ($app) { Write-Host "`n  VPN client is installed -- press V in the menu to connect." -ForegroundColor Cyan }
        Write-Host ""
    }

    $dir = Resolve-Lane2Profile -VpnUp $State.VpnUp
    Start-Process $br.Brave -ArgumentList @("--user-data-dir=$dir",'--no-default-browser-check')
    Write-Host "  Brave launched." -ForegroundColor Green
    Write-Host ""
}

# ============================================================================
#  MENU
# ============================================================================
function Show-Menu {
    param($State)
    $tag = if ($State.VpnUp) { 'VPN UP' } else { 'VPN DOWN' }
    $col = if ($State.VpnUp) { 'Green' } else { 'Red' }
    Write-Host "  Tunnel: " -NoNewline; Write-Host $tag -ForegroundColor $col -NoNewline
    if ($State.Country) { Write-Host "   Exit: $($State.Country)   IP: $($State.Ip)" -ForegroundColor DarkGray } else { Write-Host "" }
    Write-Host "  Identity: Lane 2 $($Config.Lane2IdentityMode) · Lane 3 $($Config.Lane3IdentityMode)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "   1   Lane 1  Identity    bank / gov / work     real fingerprint" -ForegroundColor Blue
    Write-Host "   2   Lane 2  Daily       shopping / social     hardened, coherent" -ForegroundColor Yellow
    Write-Host "   3   Lane 3  Anonymous   research / reading    uniform crowd" -ForegroundColor Magenta
    Write-Host "   4   Lane 4  Maximum     serious threat        Tails / Whonix" -ForegroundColor DarkMagenta
    Write-Host ""
    Write-Host "   V   Open the VPN app            connect, settings" -ForegroundColor Gray
    Write-Host "   A   Full audit                  leaks, disk, DNS, ECH" -ForegroundColor Gray
    Write-Host "   H   Harden Windows              needs admin (UAC)" -ForegroundColor Gray
    Write-Host "   C   Reconfigure the browser     rebuild Lane 2 + template" -ForegroundColor Gray
    Write-Host "   I   Install missing software    winget" -ForegroundColor Gray
    Write-Host "   U   Undo hardening              needs admin" -ForegroundColor Gray
    Write-Host "   R   Re-run preflight" -ForegroundColor Gray
    Write-Host "   Q   Quit" -ForegroundColor Gray
    Write-Host ""
}

# ============================================================================
#  MAIN
# ============================================================================

# Admin-only entry points run and exit; they never touch the browser.
if ($Harden) { Show-Banner; try { Invoke-Harden -DoApply:$Apply -Hostname $NewHostname } catch { Write-Host "  $($_.Exception.Message)" -ForegroundColor Red }; try { Read-Host "`n  Press Enter to close" | Out-Null } catch { }; return }
if ($Revert) { Show-Banner; try { Invoke-Revert -DoApply:$Apply } catch { Write-Host "  $($_.Exception.Message)" -ForegroundColor Red }; try { Read-Host "`n  Press Enter to close" | Out-Null } catch { }; return }

Show-Banner

if ($Configure) { Invoke-ConfigureBrowser | Out-Null; try { Read-Host "`n  Press Enter to close" | Out-Null } catch { }; return }
if ($Audit)     { Invoke-Preflight | Out-Null; Invoke-Audit | Out-Null; try { Read-Host "  Press Enter to close" | Out-Null } catch { }; return }

$State = if ($SkipPreflight) { @{ VpnUp=$true; Ip=$null; Country=$null } } else { Invoke-Preflight }

if ($Auto) {
    Invoke-Auto -State $State
    try { Read-Host "  Press Enter to close" | Out-Null } catch { }
    return
}

if ($Lane) {
    switch ($Lane) {
        '1' { Start-Lane1 }
        '2' { Start-Lane2 -VpnUp $State.VpnUp }
        '3' { Start-Lane3 -VpnUp $State.VpnUp }
        '4' { Start-Lane4 }
    }
    Write-Host ""
    return
}

while ($true) {
    Show-Menu -State $State
    $c = (Read-Host "  Select").Trim().ToUpper()
    switch ($c) {
        '1' { Start-Lane1 }
        '2' { Start-Lane2 -VpnUp $State.VpnUp }
        '3' { Start-Lane3 -VpnUp $State.VpnUp }
        '4' { Start-Lane4 }
        'V' { Start-Vpn }
        'A' { Invoke-Audit | Out-Null }
        'H' { Write-Host "`n  Opening an elevated window for hardening..." -ForegroundColor Cyan; Invoke-Elevated @('-Harden') }
        'U' { Write-Host "`n  Opening an elevated window to revert..." -ForegroundColor Cyan; Invoke-Elevated @('-Revert') }
        'C' { Invoke-ConfigureBrowser | Out-Null }
        'I' { Install-Missing }
        'R' { $script:Adapters = $null; $State = Invoke-Preflight }
        'Q' { Write-Host ""; return }
        default { Write-Host "  Unknown option." -ForegroundColor Red }
    }
    Write-Host ""
    try { Read-Host "  Press Enter for the menu" | Out-Null } catch { }
    Show-Banner
}
