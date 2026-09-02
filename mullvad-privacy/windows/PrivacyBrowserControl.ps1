Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = "Stop"
$configDir = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\config"))
$configPath = Join-Path $configDir "privacy-browser.json"
$examplePath = Join-Path $configDir "privacy-browser.example.json"
$launcherPath = Join-Path $PSScriptRoot "PrivacyBrowser.ps1"

New-Item -ItemType Directory -Path $configDir -Force | Out-Null
if (-not (Test-Path -LiteralPath $configPath)) {
    if (Test-Path -LiteralPath $examplePath) {
        Copy-Item -LiteralPath $examplePath -Destination $configPath
    } else {
        throw "Missing example configuration: $examplePath"
    }
}

$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json

$form = New-Object Windows.Forms.Form
$form.Text = "Privacy Browser Control"
$form.StartPosition = "CenterScreen"
$form.Size = New-Object Drawing.Size(820, 760)
$form.MinimumSize = New-Object Drawing.Size(820, 760)
$form.AutoScroll = $true

$font = New-Object Drawing.Font("Segoe UI", 9)
$form.Font = $font

$controls = @{}
$y = 20

function Add-TextField([string]$Key, [string]$Label, [string]$Value, [bool]$Password = $false) {
    $label = New-Object Windows.Forms.Label
    $label.Text = $Label
    $label.Location = New-Object Drawing.Point(20, $script:y)
    $label.Size = New-Object Drawing.Size(220, 24)
    $form.Controls.Add($label)

    $box = New-Object Windows.Forms.TextBox
    $box.Text = $Value
    $box.Location = New-Object Drawing.Point(250, $script:y)
    $box.Size = New-Object Drawing.Size(520, 24)
    $box.UseSystemPasswordChar = $Password
    $form.Controls.Add($box)
    $script:controls[$Key] = $box
    $script:y += 32
}

function Add-CheckBox([string]$Key, [string]$Label, [bool]$Value) {
    $box = New-Object Windows.Forms.CheckBox
    $box.Text = $Label
    $box.Checked = $Value
    $box.Location = New-Object Drawing.Point(250, $script:y)
    $box.Size = New-Object Drawing.Size(520, 24)
    $form.Controls.Add($box)
    $script:controls[$Key] = $box
    $script:y += 32
}

$title = New-Object Windows.Forms.Label
$title.Text = "Privacy Browser - strict privacy profile"
$title.Font = New-Object Drawing.Font("Segoe UI", 13, [Drawing.FontStyle]::Bold)
$title.Location = New-Object Drawing.Point(20, $y)
$title.Size = New-Object Drawing.Size(750, 30)
$form.Controls.Add($title)
$y += 42

Add-TextField "BrowserExe" "Browser executable" ([string]$config.BrowserExe)
Add-TextField "ProfileDir" "Profile directory" ([string]$config.ProfileDir)
Add-TextField "SocksHost" "SOCKS host (loopback only)" ([string]$config.SocksHost)
Add-TextField "SocksPort" "SOCKS port" ([string]$config.SocksPort)
Add-CheckBox "KillSwitch" "Enable Windows firewall kill switch" ([bool]$config.KillSwitch)

$separator1 = New-Object Windows.Forms.Label
$separator1.Text = "Location and time"
$separator1.Font = New-Object Drawing.Font("Segoe UI", 10, [Drawing.FontStyle]::Bold)
$separator1.Location = New-Object Drawing.Point(20, $y)
$separator1.Size = New-Object Drawing.Size(750, 26)
$form.Controls.Add($separator1)
$y += 30

Add-TextField "BrowserTimeZone" "Browser timezone (IANA; blank = Mullvad default)" ([string]$config.BrowserTimeZone)
Add-CheckBox "SetSystemTimeZone" "Change Windows system timezone before launch" ([bool]$config.SetSystemTimeZone)
Add-TextField "SystemTimeZone" "Windows timezone ID" ([string]$config.SystemTimeZone)

$separator2 = New-Object Windows.Forms.Label
$separator2.Text = "Browser identity overrides (blank = safest Mullvad default)"
$separator2.Font = New-Object Drawing.Font("Segoe UI", 10, [Drawing.FontStyle]::Bold)
$separator2.Location = New-Object Drawing.Point(20, $y)
$separator2.Size = New-Object Drawing.Size(750, 26)
$form.Controls.Add($separator2)
$y += 30

Add-TextField "BrowserVersion" "Browser version (example: 153)" ([string]$config.BrowserVersion)
Add-TextField "UserAgentOverride" "Full User-Agent override" ([string]$config.UserAgentOverride)
Add-TextField "PlatformOverride" "navigator.platform override" ([string]$config.PlatformOverride)
Add-TextField "OscpuOverride" "navigator.oscpu override" ([string]$config.OscpuOverride)
Add-TextField "AppVersionOverride" "navigator.appVersion override" ([string]$config.AppVersionOverride)
Add-TextField "BuildIdOverride" "navigator.buildID override" ([string]$config.BuildIdOverride)
Add-CheckBox "NoReferrer" "Send no HTTP Referer header" ([bool]$config.NoReferrer)

$warning = New-Object Windows.Forms.Label
$warning.Text = "Privacy note: custom identity values can make the browser more unique. Leave them blank unless you need a coherent, deliberate profile."
$warning.Location = New-Object Drawing.Point(20, $y)
$warning.Size = New-Object Drawing.Size(750, 40)
$form.Controls.Add($warning)
$y += 50

$status = New-Object Windows.Forms.Label
$status.Location = New-Object Drawing.Point(20, $y)
$status.Size = New-Object Drawing.Size(750, 36)
$form.Controls.Add($status)
$y += 42

$save = New-Object Windows.Forms.Button
$save.Text = "Save"
$save.Location = New-Object Drawing.Point(250, $y)
$save.Size = New-Object Drawing.Size(120, 34)
$form.Controls.Add($save)

$launch = New-Object Windows.Forms.Button
$launch.Text = "Save and Launch"
$launch.Location = New-Object Drawing.Point(380, $y)
$launch.Size = New-Object Drawing.Size(160, 34)
$form.Controls.Add($launch)

$remove = New-Object Windows.Forms.Button
$remove.Text = "Remove Kill Switch"
$remove.Location = New-Object Drawing.Point(550, $y)
$remove.Size = New-Object Drawing.Size(160, 34)
$form.Controls.Add($remove)

function Save-Config {
    $port = 0
    if (-not [int]::TryParse($controls.SocksPort.Text, [ref]$port) -or $port -lt 1 -or $port -gt 65535) {
        throw "SOCKS port must be between 1 and 65535."
    }
    $hostValue = $controls.SocksHost.Text.Trim().ToLowerInvariant()
    if ($hostValue -notin @("127.0.0.1", "localhost", "::1")) {
        throw "SOCKS host must be 127.0.0.1, localhost, or ::1."
    }

    $obj = [ordered]@{
        BrowserExe = $controls.BrowserExe.Text.Trim()
        ProfileDir = $controls.ProfileDir.Text.Trim()
        SocksHost = $hostValue
        SocksPort = $port
        KillSwitch = $controls.KillSwitch.Checked
        SetSystemTimeZone = $controls.SetSystemTimeZone.Checked
        SystemTimeZone = $controls.SystemTimeZone.Text.Trim()
        BrowserTimeZone = $controls.BrowserTimeZone.Text.Trim()
        BrowserVersion = $controls.BrowserVersion.Text.Trim()
        UserAgentOverride = $controls.UserAgentOverride.Text.Trim()
        PlatformOverride = $controls.PlatformOverride.Text.Trim()
        OscpuOverride = $controls.OscpuOverride.Text.Trim()
        AppVersionOverride = $controls.AppVersionOverride.Text.Trim()
        BuildIdOverride = $controls.BuildIdOverride.Text.Trim()
        NoReferrer = $controls.NoReferrer.Checked
    }
    $obj | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $configPath -Encoding UTF8
    $status.Text = "Configuration saved: $configPath"
}

$save.Add_Click({
    try {
        Save-Config
    } catch {
        [Windows.Forms.MessageBox]::Show($_.Exception.Message, "Privacy Browser", "OK", "Error") | Out-Null
    }
})

$launch.Add_Click({
    try {
        Save-Config
        $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$launcherPath`" -ConfigPath `"$configPath`""
        Start-Process powershell.exe -Verb RunAs -ArgumentList $arguments
        $status.Text = "Launch requested with administrative privileges."
    } catch {
        [Windows.Forms.MessageBox]::Show($_.Exception.Message, "Privacy Browser", "OK", "Error") | Out-Null
    }
})

$remove.Add_Click({
    try {
        $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$launcherPath`" -ConfigPath `"$configPath`" -RemoveKillSwitch"
        Start-Process powershell.exe -Verb RunAs -ArgumentList $arguments -Wait
        $status.Text = "Kill switch removal requested."
    } catch {
        [Windows.Forms.MessageBox]::Show($_.Exception.Message, "Privacy Browser", "OK", "Error") | Out-Null
    }
})

[void]$form.ShowDialog()
