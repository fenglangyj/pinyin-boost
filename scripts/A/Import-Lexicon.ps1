#Requires -Version 5.1
<#
.SYNOPSIS
    Convert third-party dictionaries into a Microsoft Pinyin lexicon and hand it to the IME.

.DESCRIPTION
    Wraps imewlconverter (studyzy/imewlconverter).

    Modes:
      Prepare  (default) - convert sources into artifacts\lexicon-out, then open the
                           Windows language settings page and print the import steps.
                           You complete the import through the UI.
      Direct   (experimental) - additionally replace ChsPinyinUDL.dat in the live IME
                           data directory after a backup. Guarded by -IUnderstandTheRisk
                           and by a native-format sanity check (magic bytes 55 AA).

    The IME import accepts roughly 20000 entries per batch, so plain-text sources
    larger than -SplitLines are split automatically before conversion.

.PARAMETER LexiconDir
    Folder holding source dictionaries (.scel/.bin/.txt/.csv/.dat). Default: data\lexicons

.PARAMETER OutputFormat
    imewlconverter output format id. Verified good values:
      win10mspyss - Microsoft Pinyin self-learning lexicon (matches the native
                    ChsPinyinUDL.dat container, magic 55 AA 88 81)
      win10mspy   - Microsoft Pinyin user-defined phrases (container magic "mschxudp")
    Full list: <tool> --list-formats

.PARAMETER InputFormat
    Override the auto-detected input format id. Auto map by extension:
    .scel->scel, .qcel->qcel, .qpyd->qpyd, .bdict->bdict, .bcd->bcd,
    .qqsj->qqsj, .bin->sgpybin, .txt/.csv/.dat->word (plain word list)

.PARAMETER SplitLines
    Max entries per converted batch for plain-text sources (0 disables splitting).

.PARAMETER DownloadTool
    Download the latest imewlconverter release into tools\imewlconverter when missing.

.PARAMETER ShowToolHelp
    Print the tool's own help (lists supported format ids). May open a GUI window
    depending on the tool build.

.PARAMETER SkipOpenSettings
    Do not open the Windows language settings page (useful for automation).

.PARAMETER IUnderstandTheRisk
    Required by -Mode Direct.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\A\Import-Lexicon.ps1 -DownloadTool -ShowToolHelp

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\A\Import-Lexicon.ps1 -Mode Prepare
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$LexiconDir,
    [string]$OutDir,
    [string]$ToolDir,
    [string]$OutputFormat = 'win10mspyss',
    [string]$InputFormat,
    [string]$Proxy,
    [int]$SplitLines = 20000,
    [ValidateSet('Prepare', 'Direct')][string]$Mode = 'Prepare',
    [switch]$DownloadTool,
    [switch]$ShowToolHelp,
    [switch]$SkipOpenSettings,
    [switch]$IUnderstandTheRisk
)

Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib\PinyinBoost.Common.psm1') -Force

$script:Proxy = Get-PBProxy -Explicit $Proxy
if ($script:Proxy) { Write-PBLog "proxy: $script:Proxy" Info }

if ($Mode -eq 'Direct' -and $SplitLines -gt 0) {
    Write-PBLog 'Direct mode writes one native container; splitting disabled' Info
    $SplitLines = 0
}

$projectRoot = Get-PBProjectRoot
if (-not $LexiconDir) { $LexiconDir = Join-Path $projectRoot 'data\lexicons' }
if (-not $OutDir) { $OutDir = Get-PBArtifactsRoot 'lexicon-out' }
if (-not $ToolDir) { $ToolDir = Join-Path $projectRoot 'tools\imewlconverter' }

$script:ToolPath = $null

function Find-Imewlconverter {
    param([string]$Dir)
    if (-not (Test-Path -LiteralPath $Dir)) { return $null }
    # console entry point first, then the GUI exe, then dll builds
    foreach ($name in @('ImeWlConverterCmd.exe', 'ImeWlConverterCmd.dll',
                        'ImeWlConverter.exe', 'ImeWlConverter.dll')) {
        $hit = Get-ChildItem -LiteralPath $Dir -Recurse -File -Filter $name -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    return $null
}

function Get-Imewlconverter {
    param([string]$Dir, [switch]$Download)
    $found = Find-Imewlconverter -Dir $Dir
    if ($found) { return $found }
    if (-not $Download) { return $null }
    if ($WhatIfPreference) {
        Write-PBLog 'download skipped (WhatIf / dry run)' Info
        return $null
    }

    Write-PBLog 'querying latest imewlconverter release...' Info
    try {
        $apiArgs = @{ Uri = 'https://api.github.com/repos/studyzy/imewlconverter/releases/latest'
                      Headers = @{ 'User-Agent' = 'pinyin-boost' }; TimeoutSec = 60 }
        if ($script:Proxy) { $apiArgs['Proxy'] = $script:Proxy }
        $release = Invoke-RestMethod @apiArgs
    } catch {
        Write-PBLog ('release query failed: ' + $_.Exception.Message) Error
        return $null
    }
    # Releases ship one zip per platform; pick the Windows build, never a mac/linux one.
    $zips = @($release.assets | Where-Object { $_.name -match '\.zip$' })
    $asset = $zips |
        Where-Object { $_.name -match '(?i)(win|windows)' -and $_.name -notmatch '(?i)(macos|osx|linux|arm64|aarch64)' } |
        Select-Object -First 1
    if (-not $asset) {
        $asset = $zips | Where-Object { $_.name -notmatch '(?i)(macos|osx|linux|arm64|aarch64)' } | Select-Object -First 1
    }
    if (-not $asset) { $asset = $zips | Select-Object -First 1 }
    if (-not $asset) {
        Write-PBLog 'no platform zip asset in the latest release; download it manually into tools\imewlconverter' Warn
        return $null
    }
    Write-PBLog ('asset: ' + $asset.name) Info
    New-Item -ItemType Directory -Path $Dir -Force | Out-Null
    $zip = Join-Path $Dir $asset.name
    try {
        $curl = Get-PBCurlPath
        if ($curl) {
            # curl handles big files far better than the PS 5.1 single-connection downloader
            $curlArgs = @('-L', '--fail', '--retry', '3', '--retry-delay', '2', '--connect-timeout', '30', '-o', $zip)
            if ($script:Proxy) { $curlArgs += @('-x', $script:Proxy) }
            $curlArgs += $asset.browser_download_url
            & $curl @curlArgs
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $zip)) { throw "curl exited with $LASTEXITCODE" }
        } else {
            $iwrArgs = @{ Uri = $asset.browser_download_url; OutFile = $zip; UseBasicParsing = $true; TimeoutSec = 600 }
            if ($script:Proxy) { $iwrArgs['Proxy'] = $script:Proxy }
            Invoke-WebRequest @iwrArgs
        }
        Write-PBLog "downloaded: $zip" Ok
        Expand-Archive -LiteralPath $zip -DestinationPath $Dir -Force
        Write-PBLog "extracted into: $Dir" Ok
    } catch {
        Write-PBLog ('download/extract failed: ' + $_.Exception.Message) Error
        return $null
    }
    return (Find-Imewlconverter -Dir $Dir)
}

function Invoke-Tool {
    param([string[]]$Arguments)
    if ($script:ToolPath -like '*.dll') {
        & dotnet $script:ToolPath @Arguments
    } else {
        & $script:ToolPath @Arguments
    }
}

$script:ToolPath = Get-Imewlconverter -Dir $ToolDir -Download:$DownloadTool
if (-not $script:ToolPath) {
    Write-PBLog 'imewlconverter not found.' Warn
    Write-PBLog 'Re-run with -DownloadTool, or place a release under tools\imewlconverter.' Info
    return
}
Write-PBLog "tool: $script:ToolPath" Ok

if ($script:ToolPath -like '*.dll' -and -not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    Write-PBLog 'dotnet runtime missing for the CLI exe. Try: winget install Microsoft.DotNet.Runtime.10' Warn
}

if ($ShowToolHelp) {
    Write-PBLog 'tool help:' Info
    try {
        Invoke-Tool @('-h') 2>&1 | Select-Object -First 60 | ForEach-Object { Write-Host ('    ' + $_) }
    } catch {
        Write-PBLog ('help invocation failed: ' + $_.Exception.Message) Warn
    }
}

if (-not (Test-Path -LiteralPath $LexiconDir)) {
    New-Item -ItemType Directory -Path $LexiconDir -Force | Out-Null
    Write-PBLog "created source folder: $LexiconDir" Warn
    Write-PBLog 'put .scel/.bin/.txt dictionaries there and re-run' Info
    return
}
if (-not (Test-Path -LiteralPath $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }

$sources = @(Get-ChildItem -LiteralPath $LexiconDir -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -match '^\.(scel|bin|txt|csv|dat)$' })
if ($sources.Count -eq 0) {
    Write-PBLog "no source dictionaries found in $LexiconDir" Warn
    return
}
Write-PBLog ('sources: ' + (($sources | ForEach-Object { $_.Name }) -join ', ')) Info

$produced = @()
foreach ($src in $sources) {
    $inputs = @($src)

    if ($src.Extension -eq '.txt' -and $SplitLines -gt 0) {
        $lines = @(Get-Content -LiteralPath $src.FullName -Encoding UTF8)
        if ($lines.Count -gt $SplitLines) {
            $inputs = @()
            $partNo = 0
            for ($i = 0; $i -lt $lines.Count; $i += $SplitLines) {
                $partNo++
                $end = [math]::Min($i + $SplitLines - 1, $lines.Count - 1)
                $part = Join-Path $OutDir ('{0}.part{1:d2}.txt' -f $src.BaseName, $partNo)
                $lines[$i..$end] | Set-Content -LiteralPath $part -Encoding UTF8
                $inputs += (Get-Item -LiteralPath $part)
            }
            Write-PBLog ('split {0} -> {1} parts of {2} lines' -f $src.Name, $partNo, $SplitLines) Info
        }
    }

    foreach ($inp in $inputs) {
        $inFormat = $InputFormat
        if (-not $inFormat) {
            $extMap = @{
                '.scel' = 'scel'; '.qcel' = 'qcel'; '.qpyd' = 'qpyd'; '.bdict' = 'bdict'
                '.bcd' = 'bcd'; '.qqsj' = 'qqsj'; '.bin' = 'sgpybin'
                '.txt' = 'word'; '.csv' = 'word'; '.dat' = 'word'
            }
            $ext = $inp.Extension.ToLower()
            $inFormat = $(if ($extMap.ContainsKey($ext)) { $extMap[$ext] } else { 'word' })
        }
        $outFile = Join-Path $OutDir ($inp.BaseName + '.mspinyin.dat')
        if (-not $PSCmdlet.ShouldProcess($outFile, ('convert {0} ({1}) -> {2}' -f $inp.Name, $inFormat, $OutputFormat))) { continue }

        Write-PBLog ('convert: {0} -> {1}' -f $inp.Name, $outFile) Info
        try {
            Invoke-Tool @('-i', $inFormat, '-o', $OutputFormat, '-O', $outFile, $inp.FullName) 2>&1 |
                ForEach-Object { Write-Host ('    ' + $_) }
        } catch {
            Write-PBLog ('conversion failed: ' + $_.Exception.Message) Error
            continue
        }

        if (Test-Path -LiteralPath $outFile) {
            Write-PBLog ('produced: {0} ({1} bytes)' -f $outFile, (Get-Item -LiteralPath $outFile).Length) Ok
            $produced += $outFile
        } else {
            Write-PBLog ('no output for {0} - check the format id with -ShowToolHelp' -f $inp.Name) Warn
        }
    }
}

if ($produced.Count -eq 0) {
    Write-PBLog 'nothing converted; verify the output format id and the source dictionaries' Warn
    return
}

if ($Mode -eq 'Prepare') {
    Write-Host ''
    Write-PBLog 'manual import (Prepare mode):' Step
    Write-PBLog '1) Settings > Time & language > Language & region > Chinese > Language options' Info
    Write-PBLog '2) Microsoft Pinyin > Lexicon and self-learning > Import (~20000 entries per batch)' Info
    Write-PBLog ('3) pick the file(s) in: ' + $OutDir) Info
    if (-not $SkipOpenSettings) {
        if ($PSCmdlet.ShouldProcess('ms-settings:regionlanguage', 'open language settings')) {
            Start-Process 'ms-settings:regionlanguage'
        }
    }
    return
}

# --- Direct (experimental) --------------------------------------------------
if (-not $IUnderstandTheRisk) {
    Write-PBLog 'Direct mode rewrites the live IME lexicon file; re-run with -IUnderstandTheRisk' Error
    return
}
if ($OutputFormat -ne 'win10mspyss') {
    Write-PBLog "Direct mode expects the win10mspyss (self-learning lexicon) output; current: $OutputFormat" Error
    return
}
$ime = Get-PinyinDataPath
if (-not $ime) { Write-PBLog 'IME data directory not found on this machine.' Error; return }

if ($produced.Count -gt 1) {
    Write-PBLog ("Direct mode expects a single produced file but got {0}; re-run with -SplitLines 0" -f $produced.Count) Error
    return
}
$candidate = $produced | Select-Object -First 1
$bytes = [IO.File]::ReadAllBytes($candidate)
if ($bytes.Length -lt 2 -or -not ($bytes[0] -eq 0x55 -and $bytes[1] -eq 0xAA)) {
    Write-PBLog 'produced file does not start with the native lexicon magic (55 AA); Direct mode aborted, use Prepare.' Error
    return
}

# never hardcode the file name: Windows renamed ChsPinyinUDL.dat over builds
$lexFiles = Resolve-PinyinLexiconFiles
if ($lexFiles.SelfLearning) { $target = $lexFiles.SelfLearning } else { $target = $lexFiles.LegacyTarget }
Write-PBLog ("target: {0}" -f $target) Info
if (-not $PSCmdlet.ShouldProcess($target, 'replace live IME lexicon file')) { return }

# The running IME keeps this file open, which blocks both reading and replacing it.
Write-PBLog 'stopping ChsIME so the lexicon file is released (it restarts on demand)' Info
& taskkill.exe /f /im ChsIME.exe 2>$null | Out-Null
Start-Sleep -Milliseconds 1200

$backup = Backup-PBPath -Path $target -Label 'ChsPinyinUDL.dat'
if (-not $backup) { Write-PBLog 'refusing to overwrite without a backup' Error; return }

try {
    Copy-Item -LiteralPath $candidate -Destination $target -Force
} catch {
    Write-PBLog ('replace failed (file still locked?): ' + $_.Exception.Message) Error
    return
}
Write-PBLog "replaced: $target" Ok
Write-PBLog 'the IME restarts automatically on the next keystroke' Info
Write-PBLog ('rollback: copy ' + $backup + ' back over ' + $target) Info
