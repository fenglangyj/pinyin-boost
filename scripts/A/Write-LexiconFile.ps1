#Requires -Version 5.1
<#
.SYNOPSIS
    Write a ready-made Microsoft Pinyin lexicon file (win10mspyss) into the live IME.

.DESCRIPTION
    Takes a .dat produced by imewlconverter or by tools\build_lexicon_pack.py
    (artifacts\lexicon-pack\dat\*.mspinyin.dat), validates the native container magic
    (55 AA 88 81), stops ChsIME so the file is not locked, backs up the current lexicon
    and replaces it.

    IMPORTANT (measured on Windows 11 26300): a direct replace is NOT reliable. The IME
    keeps its own in-memory/store copy and rewrites ChsPinyinUDL.dat later, so an external
    replacement can be reverted within minutes (we observed a 19,900-entry write dropping
    to ~7% overlap). The reliable path is the official importer:
        Settings > Time & language > Language & region > Chinese > Language options >
        Microsoft Pinyin > Lexicon and self-learning > Import
    which updates the IME's own state (verified: a 20,000-entry import stayed at 100%).

    Note: this replaces the whole self-learning lexicon. The entries you learned on this
    machine are not merged automatically - the personal list extracted earlier is kept at
    artifacts\public\personal.txt if you want to re-merge it (see docs\LEXICON-PACK-zh.md).

.PARAMETER File
    Path to the source .dat (native self-learning lexicon container).

.PARAMETER IUnderstandTheRisk
    Required: this overwrites the live user lexicon.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\A\Write-LexiconFile.ps1 `
        -File .\artifacts\lexicon-pack\dat\combo-general-mid-it.mspinyin.dat -IUnderstandTheRisk
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][string]$File,
    [switch]$IUnderstandTheRisk
)

Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib\PinyinBoost.Common.psm1') -Force

if (-not $IUnderstandTheRisk) {
    Write-PBLog 'this overwrites the live self-learning lexicon; re-run with -IUnderstandTheRisk' Error
    return
}
if (-not (Test-Path -LiteralPath $File)) {
    Write-PBLog "file not found: $File" Error
    return
}
$src = (Get-Item -LiteralPath $File).FullName

$bytes = [IO.File]::ReadAllBytes($src)
if ($bytes.Length -lt 16) { Write-PBLog 'file is too small to be a lexicon container' Error; return }
$magic = ($bytes[0..3] | ForEach-Object { $_.ToString('x2') }) -join ' '
if ($magic -ne '55 aa 88 81') {
    Write-PBLog "unexpected container magic '$magic' (expected '55 aa 88 81'); refusing to write" Error
    return
}
$count = [BitConverter]::ToUInt32($bytes, 12)
Write-PBLog ("source : {0}" -f $src) Info
Write-PBLog ("entries: {0}  size: {1:N1} KB" -f $count, ($bytes.Length / 1KB)) Info

$ime = Get-PinyinDataPath
if (-not $ime) { Write-PBLog 'Microsoft Pinyin data directory not found' Error; return }

# never hardcode the file name: Windows renamed it across builds
$lexFiles = Resolve-PinyinLexiconFiles
if ($lexFiles.SelfLearning) {
    $target = $lexFiles.SelfLearning
} else {
    $target = $lexFiles.LegacyTarget
}
Write-PBLog ("target: {0}" -f $target) Info

if (-not $PSCmdlet.ShouldProcess($target, 'replace live self-learning lexicon')) { return }

Write-PBLog 'stopping ChsIME so the lexicon file is released (it restarts on demand)' Info
& taskkill.exe /f /im ChsIME.exe 2>$null | Out-Null
Start-Sleep -Milliseconds 1200

$backup = Backup-PBPath -Path $target -Label 'ChsPinyinUDL.dat'
if (-not $backup) { Write-PBLog 'refusing to overwrite without a backup' Error; return }

try {
    Copy-Item -LiteralPath $src -Destination $target -Force
} catch {
    Write-PBLog ('replace failed (file still locked?): ' + $_.Exception.Message) Error
    return
}

Write-PBLog ("written: {0} ({1} entries)" -f $target, $count) Ok
Write-PBLog 'the IME restarts automatically on the next keystroke' Info
Write-PBLog ("rollback: Copy-Item '{0}\*' '{1}' -Force  (or use Restore-PinyinData.ps1)" -f $backup, $ime) Info
