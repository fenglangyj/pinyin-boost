#Requires -Version 5.1
<#
.SYNOPSIS
    Restore a Microsoft Pinyin data backup produced by Backup-PinyinData.ps1.

.DESCRIPTION
    Copies the backed-up lexicon files back into the IME data directory (a fresh
    pre-restore backup is taken first) and imports the registry snapshot when present.

.PARAMETER BackupPath
    Folder created by Backup-PinyinData.ps1 (the one containing manifest.json).

.PARAMETER SkipRegistry
    Do not import the registry snapshot.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\A\Restore-PinyinData.ps1 -BackupPath .\artifacts\backups\ime-20261014-120000
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][string]$BackupPath,
    [switch]$SkipRegistry
)

Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib\PinyinBoost.Common.psm1') -Force

if (-not (Test-Path -LiteralPath $BackupPath)) {
    Write-PBLog "backup folder not found: $BackupPath" Error
    return
}
$backupDir = (Get-Item -LiteralPath $BackupPath).FullName

$ime = Get-PinyinDataPath
if (-not $ime) {
    Write-PBLog 'Microsoft Pinyin data directory not found on this machine.' Error
    return
}

if ($PSCmdlet.ShouldProcess($ime, "restore data from $backupDir")) {
    Backup-PBPath -Path $ime -Label 'pre-restore' | Out-Null
    Get-ChildItem -LiteralPath $backupDir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne 'manifest.json' -and $_.Extension -ne '.reg' } |
        ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination $ime -Force
            Write-PBLog ("restored: " + $_.Name) Ok
        }
}

$regFile = Join-Path $backupDir 'registry-CHS.reg'
if (-not $SkipRegistry -and (Test-Path -LiteralPath $regFile)) {
    if ($PSCmdlet.ShouldProcess($regFile, 'import registry snapshot')) {
        & reg.exe import $regFile | Out-Null
        Write-PBLog "registry restored from: $regFile" Ok
    }
}

Write-PBLog 'apply now:  taskkill /f /im ChsIME.exe   (or sign out and back in)' Info
