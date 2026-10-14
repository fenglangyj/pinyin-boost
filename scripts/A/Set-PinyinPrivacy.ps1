#Requires -Version 5.1
<#
.SYNOPSIS
    Tune Microsoft Pinyin privacy-related switches (pure-local mode).

.DESCRIPTION
    Disables the cloud candidate feed so typed text is no longer sent out for cloud
    suggestions, while keeping on-device self-learning and dynamic ranking (both of
    which are local and still improve suggestions).

    A .reg snapshot is written first, so the change can be reverted with a single
    command (-Restore).

.PARAMETER KeepCloudCandidate
    Leave the cloud candidate feed enabled (only normalize the other switches).

.PARAMETER Restore
    Import the newest registry snapshot from artifacts\backups and exit.

.PARAMETER RegSnapshotPath
    Explicit .reg file to import when using -Restore.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\A\Set-PinyinPrivacy.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\A\Set-PinyinPrivacy.ps1 -Restore
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$Restore,
    [switch]$KeepCloudCandidate,
    [string]$RegSnapshotPath
)

Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib\PinyinBoost.Common.psm1') -Force

$key = 'HKCU:\SOFTWARE\Microsoft\InputMethod\Settings\CHS'

if ($Restore) {
    if (-not $RegSnapshotPath) {
        $found = Get-ChildItem -Path (Join-Path (Get-PBArtifactsRoot 'backups') '*\registry-CHS.reg') -ErrorAction SilentlyContinue |
                 Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($found) { $RegSnapshotPath = $found.FullName }
    }
    if (-not $RegSnapshotPath -or -not (Test-Path -LiteralPath $RegSnapshotPath)) {
        Write-PBLog 'no registry snapshot found; nothing to restore' Warn
        return
    }
    if ($PSCmdlet.ShouldProcess($key, "import registry snapshot $RegSnapshotPath")) {
        & reg.exe import $RegSnapshotPath | Out-Null
        Write-PBLog "restored from: $RegSnapshotPath" Ok
    }
    return
}

if (-not (Test-Path -LiteralPath $key)) {
    Write-PBLog "registry key not found: $key (Microsoft Pinyin never configured on this account?)" Error
    return
}

$snapshot = Join-Path (Get-PBArtifactsRoot 'backups\registry') ('CHS-{0}.reg' -f (Get-PBTimestamp))
if (-not $WhatIfPreference) {
    Export-PBRegistryKey -KeyPath 'HKCU\SOFTWARE\Microsoft\InputMethod\Settings\CHS' -DestFile $snapshot | Out-Null
}

$plan = @()
if (-not $KeepCloudCandidate) { $plan += @{ Name = 'Enable Cloud Candidate'; Value = 0 } }
$plan += @{ Name = 'Enable self-learning'; Value = 1 }
$plan += @{ Name = 'EnableSmartSelfLearning'; Value = 1 }
$plan += @{ Name = 'Enable Dynamic Candidate Ranking'; Value = 1 }

foreach ($item in $plan) {
    if ($PSCmdlet.ShouldProcess("$key :: $($item.Name)", "set to $($item.Value)")) {
        Set-PBRegistryValue -KeyPath $key -Name $item.Name -Value $item.Value -Type DWord
    }
}

Write-Host ''
Write-PBLog 'current values:' Info
$final = Get-ItemProperty -LiteralPath $key
foreach ($item in $plan) {
    $v = (Get-ItemProperty -LiteralPath $key -Name $item.Name -ErrorAction SilentlyContinue).$($item.Name)
    Write-Host ("       {0} = {1}" -f $item.Name, $v)
}

Write-Host ''
Write-PBLog 'apply now:  taskkill /f /im ChsIME.exe   (the IME restarts on its own)' Info
Write-PBLog ("rollback:  reg import `"" + $snapshot + "`"") Info
