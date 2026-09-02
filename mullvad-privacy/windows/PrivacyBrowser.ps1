param(
    [string]$ConfigPath = "$PSScriptRoot\..\config\privacy-browser.json",
    [switch]$DisableKillSwitch,
    [switch]$RemoveKillSwitch
)

$ErrorActionPreference = "Stop"
$RulePrefix = "PrivacyBrowser-KillSwitch"

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Remove-PrivacyFirewallRules {
    Get-NetFirewallRule -DisplayName "$RulePrefix*" -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue
}

function Enable-PrivacyFirewallRules([string]$BrowserExe) {
    if (-not (Test-Administrator)) {
        throw "Administrator privileges are required to modify Windows Defender Firewall rules."
    }
    Remove-PrivacyFirewallRules
    New-NetFirewallRule -DisplayName "$RulePrefix-IPv4-Low" -Direction Outbound -Action Block -Program $BrowserExe -RemoteAddress "0.0.0.0-126.255.255.255" -Profile Any | Out-Null
    New-NetFirewallRule -DisplayName "$RulePrefix-IPv4-High" -Direction Outbound -Action Block -Program $BrowserExe -RemoteAddress "128.0.0.0-255.255.255.255" -Profile Any | Out-Null
    New-NetFirewallRule -DisplayName "$RulePrefix-IPv6-All" -Direction Outbound -Action Block -Program $BrowserExe -RemoteAddress "::/0" -Profile Any | Out-Null
}

function Escape-JsString([string]$Value) {
    if ($null -eq $Value) { return "" }
    return $Value.Replace("\", "\\").Replace('"', '\"')
}

function Add-Pref([System.Collections.Generic.List[string]]$Lines, [string]$Name, $Value) {
    if ($Value -is [bool]) {
        $js = if ($Value) { "true" } else { "false" }
    } elseif ($Value -is [int] -or $Value -is [long]) {
        $js = [string]$Value
    } else {
        $js = '"' + (Escape-JsString ([string]$Value)) + '"'
    }
    $Lines.Add("user_pref(`"$Name`", $js);")
}

function Assert-StrictProxyHost([string]$HostName) {
    if ($HostName.Trim() -ne "127.0.0.1") {
        throw "Strict mode requires the SOCKS endpoint to be exactly 127.0.0.1."
    }
}

function Get-CoherentUserAgent([string]$Version, [string]$ExplicitUserAgent) {
    if (-not [string]::IsNullOrWhiteSpace($ExplicitUserAgent)) {
        return $ExplicitUserAgent.Trim()
    }
    if ([string]::IsNullOrWhiteSpace($Version)) {
        return ""
    }
    $trimmed = $Version.Trim()
    if ($trimmed -notmatch '^\d{2,3}(?:\.\d+){0,3}$') {
        throw "BrowserVersion must contain only a Firefox-style numeric version, for example 153 or 153.1.0."
    }
    $major = $trimmed.Split('.')[0]
    return "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:$major.0) Gecko/20100101 Firefox/$major.0"
}

if ($RemoveKillSwitch) {
    if (-not (Test-Administrator)) {
        throw "Administrator privileges are required to remove Windows Defender Firewall rules."
    }
    Remove-PrivacyFirewallRules
    Write-Host "Privacy Browser firewall rules removed."
    exit 0
}

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    throw "Config not found: $ConfigPath. Copy privacy-browser.example.json to privacy-browser.json and edit it."
}

$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$browserExe = [IO.Path]::GetFullPath([string]$config.BrowserExe)
$profileDir = [IO.Path]::GetFullPath([string]$config.ProfileDir)
Assert-StrictProxyHost ([string]$config.SocksHost)

if (-not (Test-Path -LiteralPath $browserExe)) {
    throw "Browser executable not found: $browserExe"
}
if ([int]$config.SocksPort -lt 1 -or [int]$config.SocksPort -gt 65535) {
    throw "SocksPort must be between 1 and 65535."
}
New-Item -ItemType Directory -Path $profileDir -Force | Out-Null

if ($config.SetSystemTimeZone) {
    if (-not (Test-Administrator)) {
        throw "Administrator privileges are required to change the Windows system timezone."
    }
    & tzutil.exe /s ([string]$config.SystemTimeZone)
    if ($LASTEXITCODE -ne 0) {
        throw "tzutil failed. Use 'tzutil /l' to list valid Windows timezone IDs."
    }
}

$userAgent = Get-CoherentUserAgent ([string]$config.BrowserVersion) ([string]$config.UserAgentOverride)

$prefs = New-Object 'System.Collections.Generic.List[string]'
Add-Pref $prefs "network.proxy.type" 1
Add-Pref $prefs "network.proxy.socks" "127.0.0.1"
Add-Pref $prefs "network.proxy.socks_port" ([int]$config.SocksPort)
Add-Pref $prefs "network.proxy.socks_version" 5
Add-Pref $prefs "network.proxy.socks5_remote_dns" $true
Add-Pref $prefs "network.proxy.no_proxies_on" ""
Add-Pref $prefs "network.proxy.failover_direct" $false
Add-Pref $prefs "network.proxy.allow_bypass" $false
Add-Pref $prefs "network.trr.mode" 5
Add-Pref $prefs "network.trr.uri" ""
Add-Pref $prefs "network.trr.default_provider_uri" ""
Add-Pref $prefs "network.trr.custom_uri" ""
Add-Pref $prefs "media.peerconnection.enabled" $false
Add-Pref $prefs "media.navigator.enabled" $false
Add-Pref $prefs "network.http.http3.enable" $false
Add-Pref $prefs "network.http.http3.enable_0rtt" $false
Add-Pref $prefs "network.webtransport.enabled" $false
Add-Pref $prefs "network.lna.enabled" $true
Add-Pref $prefs "network.lna.blocking" $true
Add-Pref $prefs "network.lna.allow_top_level_navigation" $false
Add-Pref $prefs "network.lna.websocket.enabled" $true
Add-Pref $prefs "network.lna.local-network-to-localhost.skip-checks" $false
Add-Pref $prefs "geo.enabled" $false
Add-Pref $prefs "dom.netinfo.enabled" $false
Add-Pref $prefs "device.sensors.enabled" $false
Add-Pref $prefs "dom.gamepad.enabled" $false
Add-Pref $prefs "dom.battery.enabled" $false
Add-Pref $prefs "privacy.identity.timezone_override" ([string]$config.BrowserTimeZone)
Add-Pref $prefs "privacy.identity.useragent_override" $userAgent
Add-Pref $prefs "privacy.identity.platform_override" ([string]$config.PlatformOverride)
Add-Pref $prefs "privacy.identity.oscpu_override" ([string]$config.OscpuOverride)
Add-Pref $prefs "privacy.identity.appversion_override" ([string]$config.AppVersionOverride)
Add-Pref $prefs "privacy.identity.buildid_override" ([string]$config.BuildIdOverride)

if ($config.NoReferrer) {
    Add-Pref $prefs "network.http.sendRefererHeader" 0
    Add-Pref $prefs "network.http.referer.defaultPolicy" 0
    Add-Pref $prefs "network.http.referer.defaultPolicy.pbmode" 0
} else {
    Add-Pref $prefs "network.http.referer.defaultPolicy" 2
    Add-Pref $prefs "network.http.referer.defaultPolicy.pbmode" 2
    Add-Pref $prefs "network.http.referer.XOriginTrimmingPolicy" 2
}

$userJs = Join-Path $profileDir "user.js"
$prefs | Set-Content -LiteralPath $userJs -Encoding UTF8

if ($config.KillSwitch -and -not $DisableKillSwitch) {
    Enable-PrivacyFirewallRules $browserExe
}

Write-Host "Profile written: $userJs"
Write-Host "SOCKS5 endpoint: 127.0.0.1:$($config.SocksPort)"
if ($config.KillSwitch -and -not $DisableKillSwitch) {
    Write-Host "Kill switch: ON (browser can only reach IPv4 loopback; IPv6 is blocked)"
} else {
    Write-Host "Kill switch: OFF"
}

Start-Process -FilePath $browserExe -ArgumentList @("-profile", $profileDir, "-no-remote")
