#Requires -Version 5.1
<#
.SYNOPSIS
    Preflight check for pinyin-boost.

.DESCRIPTION
    Collects OS / PowerShell / toolchain / IME state and the current IME process
    footprint, prints a summary and writes a JSON report to artifacts\env\.

.PARAMETER NoSave
    Print the summary only, do not write the JSON report.

.PARAMETER SkipNetwork
    Skip the outbound reachability probe (github.com:443, aka.ms:443).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\Test-Environment.ps1
#>
[CmdletBinding()]
param(
    [switch]$NoSave,
    [switch]$SkipNetwork
)

Import-Module (Join-Path $PSScriptRoot 'lib\PinyinBoost.Common.psm1') -Force

Write-PBLog 'pinyin-boost :: environment check' Step

$os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
$imePath = Get-PinyinDataPath

$imeTips = @()
try {
    $imeTips = Get-WinUserLanguageList | ForEach-Object {
        '{0} :: {1}' -f $_.LanguageTag, (($_.InputMethodTips) -join ',')
    }
} catch {
    $imeTips = @('unavailable')
}

$tools = [ordered]@{}
foreach ($t in @('winget', 'git', 'dotnet', 'python', 'py', '7z')) {
    $cmd = Get-Command $t -ErrorAction SilentlyContinue
    $tools[$t] = $(if ($cmd) { $cmd.Source } else { 'MISSING' })
}
$weasel = Resolve-RimeServerPath
$tools['WeaselServer'] = $(if ($weasel) { $weasel } else { 'not installed' })

$disk = $null
try {
    $d = Get-PSDrive C -ErrorAction Stop
    $disk = [pscustomobject]@{
        Drive   = 'C:'
        Free_GB = [math]::Round($d.Free / 1GB, 1)
        Used_GB = [math]::Round($d.Used / 1GB, 1)
    }
} catch { }

$net = $null
if (-not $SkipNetwork) {
    $net = [pscustomobject]@{
        GitHub_443 = (Test-PBTcp -TargetHost 'github.com' -Port 443)
        Akamai_443 = (Test-PBTcp -TargetHost 'aka.ms' -Port 443)
    }
}

$report = [ordered]@{
    GeneratedAt       = (Get-Date).ToString('s')
    Computer          = $env:COMPUTERNAME
    User              = $env:USERNAME
    OS                = $(if ($os) { '{0} ({1})' -f $os.Caption, $os.Version } else { [Environment]::OSVersion.VersionString })
    PowerShell        = $PSVersionTable.PSVersion.ToString()
    IsAdmin           = (Test-PBAdmin)
    ImeDataPath       = $imePath
    ImeDataCandidates = (Get-PinyinDataCandidates)
    ConfiguredImeTips = $imeTips
    Tools             = $tools
    Disk              = $disk
    Network           = $net
    Footprint         = @(Get-ImeProcessFootprint)
}

$summary = @(
    [pscustomobject]@{ Item = 'OS';            Value = [string]$report.OS }
    [pscustomobject]@{ Item = 'PowerShell';    Value = $report.PowerShell }
    [pscustomobject]@{ Item = 'IsAdmin';       Value = $report.IsAdmin }
    [pscustomobject]@{ Item = 'IME data dir';  Value = $(if ($imePath) { $imePath } else { 'NOT FOUND' }) }
    [pscustomobject]@{ Item = 'winget';        Value = $tools['winget'] }
    [pscustomobject]@{ Item = 'git';           Value = $tools['git'] }
    [pscustomobject]@{ Item = 'dotnet';        Value = $tools['dotnet'] }
    [pscustomobject]@{ Item = 'python';        Value = $tools['python'] }
    [pscustomobject]@{ Item = 'Rime (Weasel)'; Value = $tools['WeaselServer'] }
)
Write-Host ''
$summary | Format-Table -AutoSize | Out-String | Write-Host

Write-Host 'IME footprint:'
$fp = @(Get-ImeProcessFootprint)
if ($fp.Count -gt 0) {
    $fp | Format-Table -AutoSize | Out-String | Write-Host
} else {
    Write-PBLog 'no IME processes found (nothing typed yet this session?)' Warn
}

if (-not $NoSave) {
    $file = Join-Path (Get-PBArtifactsRoot 'env') ("environment-{0}.json" -f (Get-PBTimestamp))
    $report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $file -Encoding UTF8
    Write-PBLog "saved: $file" Ok
}
