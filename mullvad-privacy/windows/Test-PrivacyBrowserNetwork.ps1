param(
    [string]$ConfigPath = "$PSScriptRoot\..\config\privacy-browser.json",
    [int]$ObserveSeconds = 15
)

$ErrorActionPreference = "Stop"
$RulePrefix = "PrivacyBrowser-KillSwitch"
$failures = New-Object 'System.Collections.Generic.List[string]'

function Fail([string]$Message) {
    $script:failures.Add($Message)
    Write-Host "FAIL: $Message" -ForegroundColor Red
}

function Pass([string]$Message) {
    Write-Host "PASS: $Message" -ForegroundColor Green
}

function Is-LoopbackAddress([string]$Address) {
    if ([string]::IsNullOrWhiteSpace($Address)) { return $false }
    if ($Address -eq "::1") { return $true }
    $ip = $null
    if (-not [Net.IPAddress]::TryParse($Address, [ref]$ip)) { return $false }
    if ($ip.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork) {
        return $ip.GetAddressBytes()[0] -eq 127
    }
    return [Net.IPAddress]::IsLoopback($ip)
}

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    throw "Config not found: $ConfigPath"
}
$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$browserExe = [IO.Path]::GetFullPath([string]$config.BrowserExe)
$profileDir = [IO.Path]::GetFullPath([string]$config.ProfileDir)
$userJs = Join-Path $profileDir "user.js"
$processName = [IO.Path]::GetFileNameWithoutExtension($browserExe)

if ($config.SocksHost -notin @("127.0.0.1", "localhost", "::1")) {
    Fail "SOCKS host is not loopback: $($config.SocksHost)"
} else {
    Pass "SOCKS host is loopback-only"
}

if (Test-NetConnection -ComputerName $config.SocksHost -Port ([int]$config.SocksPort) -InformationLevel Quiet) {
    Pass "local SOCKS endpoint is reachable at $($config.SocksHost):$($config.SocksPort)"
} else {
    Fail "local SOCKS endpoint is not reachable at $($config.SocksHost):$($config.SocksPort)"
}

if (-not (Test-Path -LiteralPath $userJs)) {
    Fail "profile user.js does not exist: $userJs"
} else {
    $prefs = Get-Content -LiteralPath $userJs -Raw
    $required = @(
        'user_pref("network.proxy.type", 1);',
        'user_pref("network.proxy.socks5_remote_dns", true);',
        'user_pref("network.proxy.failover_direct", false);',
        'user_pref("network.proxy.allow_bypass", false);',
        'user_pref("network.trr.mode", 5);',
        'user_pref("media.peerconnection.enabled", false);',
        'user_pref("media.navigator.enabled", false);',
        'user_pref("network.http.http3.enable", false);',
        'user_pref("network.webtransport.enabled", false);',
        'user_pref("network.lna.blocking", true);',
        'user_pref("geo.enabled", false);',
        'user_pref("dom.netinfo.enabled", false);'
    )
    foreach ($needle in $required) {
        if ($prefs.Contains($needle)) { Pass "profile contains $needle" } else { Fail "profile missing $needle" }
    }
}

if ($config.KillSwitch) {
    $rules = @(Get-NetFirewallRule -DisplayName "$RulePrefix*" -ErrorAction SilentlyContinue)
    if ($rules.Count -lt 3) {
        Fail "expected at least three kill-switch firewall rules, found $($rules.Count)"
    } else {
        Pass "kill-switch firewall rules exist"
        foreach ($rule in $rules) {
            if ($rule.Enabled -ne "True") { Fail "firewall rule disabled: $($rule.DisplayName)" }
            if ($rule.Direction -ne "Outbound") { Fail "firewall rule is not outbound: $($rule.DisplayName)" }
            if ($rule.Action -ne "Block") { Fail "firewall rule is not block: $($rule.DisplayName)" }
            $app = Get-NetFirewallApplicationFilter -AssociatedNetFirewallRule $rule
            if ($app.Program -and ([IO.Path]::GetFullPath($app.Program) -ne $browserExe)) {
                Fail "firewall rule targets unexpected executable: $($app.Program)"
            }
        }
    }
} else {
    Write-Host "WARN: KillSwitch is disabled in configuration" -ForegroundColor Yellow
}

$processes = @(Get-Process -Name $processName -ErrorAction SilentlyContinue)
if ($processes.Count -eq 0) {
    Fail "browser process is not running; launch it and browse several HTTPS pages before this test"
} else {
    Pass "browser process is running"
    $pids = @($processes.Id)
    $deadline = (Get-Date).AddSeconds([Math]::Max(1, $ObserveSeconds))
    $seenTcp = 0
    $seenUdp = 0
    do {
        foreach ($connection in @(Get-NetTCPConnection -ErrorAction SilentlyContinue | Where-Object { $_.OwningProcess -in $pids })) {
            if ($connection.State -notin @("Listen", "Bound", "Closed") -and $connection.RemoteAddress) {
                $seenTcp++
                if (-not (Is-LoopbackAddress $connection.RemoteAddress)) {
                    Fail "direct TCP endpoint detected from browser PID $($connection.OwningProcess): $($connection.RemoteAddress):$($connection.RemotePort) state=$($connection.State)"
                }
            }
        }
        foreach ($endpoint in @(Get-NetUDPEndpoint -ErrorAction SilentlyContinue | Where-Object { $_.OwningProcess -in $pids })) {
            $seenUdp++
            if ($endpoint.LocalAddress -notin @("0.0.0.0", "::") -and -not (Is-LoopbackAddress $endpoint.LocalAddress)) {
                Fail "non-loopback UDP bind detected from browser PID $($endpoint.OwningProcess): $($endpoint.LocalAddress):$($endpoint.LocalPort)"
            }
        }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)

    if ($failures.Count -eq 0) {
        Pass "no direct non-loopback TCP connection was observed during $ObserveSeconds seconds"
        Write-Host "Observed TCP samples: $seenTcp; UDP endpoint samples: $seenUdp"
    }
}

if ($failures.Count -gt 0) {
    Write-Host ""
    Write-Host "Privacy Browser runtime network test FAILED with $($failures.Count) finding(s)." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Privacy Browser runtime network test PASSED." -ForegroundColor Green
exit 0
