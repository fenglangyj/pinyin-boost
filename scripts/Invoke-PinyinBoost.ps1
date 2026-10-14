#Requires -Version 5.1
<#
.SYNOPSIS
    pinyin-boost 编排器：微软拼音隐私加固 + 词库工具链。

.DESCRIPTION
    按固定顺序执行：环境体检 → 备份 → 隐私开关 → 词表转容器（可选）。
    个性化词表的"选词"部分由 skill 与 tools/ 完成，见 skill/SKILL.md。

.PARAMETER Proxy
    HTTP 代理，例如 http://127.0.0.1:7890；留空自动探测。

.PARAMETER SkipLexicon
    跳过词表转换步骤。

.PARAMETER DryRun
    只打印计划，所有修改步骤以 -WhatIf 运行。

.PARAMETER Yes
    不询问确认。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-PinyinBoost.ps1 -DryRun
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-PinyinBoost.ps1 -Yes
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$Config,
    [string]$Proxy,
    [switch]$SkipLexicon,
    [switch]$DryRun,
    [switch]$Yes
)

Import-Module (Join-Path $PSScriptRoot 'lib\PinyinBoost.Common.psm1') -Force

$root = Get-PBProjectRoot
$dirA = Join-Path $PSScriptRoot 'A'

Write-PBLog 'pinyin-boost' Step

# --- config ---------------------------------------------------------------
$cfgPath = $Config
if (-not $cfgPath) {
    $local = Join-Path $root 'config\config.psd1'
    $example = Join-Path $root 'config\config.example.psd1'
    if (Test-Path -LiteralPath $local) { $cfgPath = $local }
    elseif (Test-Path -LiteralPath $example) { $cfgPath = $example }
}
$cfg = $null
if ($cfgPath -and (Test-Path -LiteralPath $cfgPath)) {
    try {
        $cfg = Import-PowerShellDataFile -LiteralPath $cfgPath
        Write-PBLog "config: $cfgPath" Info
    } catch {
        Write-PBLog ('config load failed: ' + $_.Exception.Message) Warn
    }
}

$disableCloud = $true
$lexFormat = 'win10mspyss'
$lexDownload = $false
if ($cfg) {
    if ($cfg.Pinyin -and $cfg.Pinyin.ContainsKey('DisableCloudCandidate')) {
        $disableCloud = [bool]$cfg.Pinyin.DisableCloudCandidate
    }
    if ($cfg.Lexicon) {
        if ($cfg.Lexicon.OutputFormat) { $lexFormat = $cfg.Lexicon.OutputFormat }
        if ($cfg.Lexicon.DownloadTool) { $lexDownload = [bool]$cfg.Lexicon.DownloadTool }
    }
    if (-not $Proxy -and $cfg.Network -and $cfg.Network.Proxy) { $Proxy = $cfg.Network.Proxy }
}

$whatIf = @{}
if ($DryRun) { $whatIf['WhatIf'] = $true }

$results = @()
function Invoke-Step {
    param([string]$Name, [string]$Path, [hashtable]$Arguments)
    Write-PBLog ('--- ' + $Name) Step
    try {
        & $Path @Arguments
        $script:results += [pscustomobject]@{ Step = $Name; Status = 'ok' }
    } catch {
        Write-PBLog ($Name + ' failed: ' + $_.Exception.Message) Error
        $script:results += [pscustomobject]@{ Step = $Name; Status = 'failed' }
    }
}

if (-not $Yes -and -not $DryRun) {
    $ans = Read-Host 'Proceed with these changes? [y/N]'
    if ($ans -notmatch '^[Yy]') { Write-PBLog 'aborted by user' Warn; return }
}

# --- steps ----------------------------------------------------------------
Invoke-Step -Name 'preflight' -Path (Join-Path $PSScriptRoot 'Test-Environment.ps1') -Arguments @{}
Invoke-Step -Name 'A1 backup lexicon + registry' -Path (Join-Path $dirA 'Backup-PinyinData.ps1') -Arguments $whatIf

$privacyArgs = @{}
if ($DryRun) { $privacyArgs['WhatIf'] = $true }
if (-not $disableCloud) { $privacyArgs['KeepCloudCandidate'] = $true }
Invoke-Step -Name 'A2 privacy switches' -Path (Join-Path $dirA 'Set-PinyinPrivacy.ps1') -Arguments $privacyArgs

if (-not $SkipLexicon) {
    $lexArgs = @{ Mode = 'Prepare'; OutputFormat = $lexFormat }
    if ($Proxy) { $lexArgs['Proxy'] = $Proxy }
    if ($lexDownload) { $lexArgs['DownloadTool'] = $true }
    if ($DryRun) { $lexArgs['WhatIf'] = $true }
    Invoke-Step -Name 'A3 lexicon -> container' -Path (Join-Path $dirA 'Import-Lexicon.ps1') -Arguments $lexArgs
}

Write-Host ''
Write-PBLog 'summary' Step
$results | Format-Table -AutoSize | Out-String | Write-Host
Write-PBLog 'next: extract builtin words -> fetch sources -> build profile lexicon -> official import' Info
Write-PBLog 'see docs/runbook.md' Info
