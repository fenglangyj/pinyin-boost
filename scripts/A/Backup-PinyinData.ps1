#Requires -Version 5.1
<#
.SYNOPSIS
    Back up Microsoft Pinyin data: lexicon files plus registry settings.

.DESCRIPTION
    Copies the IME data directory (lexicon, input history, pinned/deleted candidates)
    and exports HKCU\SOFTWARE\Microsoft\InputMethod\Settings\CHS into a timestamped
    folder under artifacts\backups together with a SHA-256 manifest.

.PARAMETER Destination
    Target folder. Default: artifacts\backups\ime-<timestamp>

.PARAMETER SkipRegistry
    Do not export the registry snapshot.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\A\Backup-PinyinData.ps1
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$Destination,
    [switch]$SkipRegistry
)

Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib\PinyinBoost.Common.psm1') -Force

$imePath = Get-PinyinDataPath
if (-not $imePath) {
    Write-PBLog 'Microsoft Pinyin data directory not found. Is the IME installed and used on this machine?' Warn
    return
}
Write-PBLog "source: $imePath" Info

if (-not $Destination) {
    $Destination = Join-Path (Get-PBArtifactsRoot 'backups') ('ime-{0}' -f (Get-PBTimestamp))
}

if (-not $PSCmdlet.ShouldProcess($Destination, "back up MS Pinyin data from $imePath")) { return }

New-Item -ItemType Directory -Path $Destination -Force | Out-Null
Copy-Item -Path (Join-Path $imePath '*') -Destination $Destination -Recurse -Force
Write-PBLog "files copied -> $Destination" Ok

$manifest = @()
Get-ChildItem -LiteralPath $imePath -File -ErrorAction SilentlyContinue | ForEach-Object {
    $manifest += [pscustomobject]@{
        Name      = $_.Name
        Size      = $_.Length
        SHA256    = (Get-FileSha256 -Path $_.FullName)
        LastWrite = $_.LastWriteTime.ToString('s')
    }
}

if (-not $SkipRegistry) {
    $regFile = Join-Path $Destination 'registry-CHS.reg'
    Export-PBRegistryKey -KeyPath 'HKCU\SOFTWARE\Microsoft\InputMethod\Settings\CHS' -DestFile $regFile | Out-Null
}

$report = [ordered]@{
    GeneratedAt = (Get-Date).ToString('s')
    Source      = $imePath
    Computer    = $env:COMPUTERNAME
    User        = $env:USERNAME
    Files       = $manifest
}
$manifestPath = Join-Path $Destination 'manifest.json'
$report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
Write-PBLog "manifest: $manifestPath" Ok
Write-PBLog "backup complete: $Destination" Ok
Write-PBLog ("restore later with: Restore-PinyinData.ps1 -BackupPath `"$Destination`"") Info
