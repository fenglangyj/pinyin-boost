<#
.SYNOPSIS
    Shared helpers for the pinyin-boost toolkit.

.DESCRIPTION
    Path detection, logging, backup, registry and process-footprint helpers.
    Targets Windows PowerShell 5.1 (no PS7-only syntax) and stays ASCII-only so it
    parses correctly under any console code page.
#>

function Write-PBLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('Info', 'Ok', 'Warn', 'Error', 'Step')][string]$Level = 'Info'
    )
    $prefix = '[i] '
    $color = 'Gray'
    switch ($Level) {
        'Step'  { $prefix = '[>>] '; $color = 'Cyan' }
        'Ok'    { $prefix = '[ok] '; $color = 'Green' }
        'Warn'  { $prefix = '[!!] '; $color = 'Yellow' }
        'Error' { $prefix = '[xx] '; $color = 'Red' }
    }
    Write-Host ($prefix + $Message) -ForegroundColor $color
}

function Get-PBProjectRoot {
    # module lives in <root>\scripts\lib
    return (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
}

function Get-PBTimestamp {
    return (Get-Date -Format 'yyyyMMdd-HHmmss')
}

function Get-PBArtifactsRoot {
    [CmdletBinding()]
    param([string]$Sub = '')
    $root = Join-Path (Get-PBProjectRoot) 'artifacts'
    if ($Sub) { $root = Join-Path $root $Sub }
    if (-not (Test-Path -LiteralPath $root)) {
        New-Item -ItemType Directory -Path $root -Force | Out-Null
    }
    return $root
}

function Get-PinyinDataCandidates {
    # Windows moved this folder between builds; check both well-known locations.
    $list = @()
    if ($env:APPDATA) { $list += (Join-Path $env:APPDATA 'Microsoft\InputMethod\Chs') }
    if ($env:LOCALAPPDATA) { $list += (Join-Path $env:LOCALAPPDATA 'Microsoft\InputMethod\Chs') }
    return $list
}

function Get-PinyinDataPath {
    foreach ($p in (Get-PinyinDataCandidates)) {
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return $null
}

function Get-RimeUserDir {
    if ($env:APPDATA) { return (Join-Path $env:APPDATA 'Rime') }
    return $null
}

function Resolve-PinyinLexiconFiles {
    <#
        Resolve the live Microsoft Pinyin lexicon containers.

        Windows renamed these over builds, so never hardcode a file name:
          self-learning lexicon : ChsPinyinUDL.dat  ->  ChsPinyinUDL_Setting.dat
          custom phrases        : (new) ChsPinyinEUDPv1.lex / ChsPinyinEUDPv2.lex  ("mschxudp")
        The newest ChsPinyinUDL*.dat wins; when nothing exists yet the legacy name is
        returned as the creation target.
    #>
    $dir = Get-PinyinDataPath
    $result = [pscustomobject]@{
        DataDir       = $dir
        SelfLearning  = $null
        LegacyTarget  = $null
        CustomPhrases = @()
    }
    if (-not $dir) { return $result }

    # prefer the canonical name; the IME also creates variants such as
    # ChsPinyinUDL_Setting.dat / ChsPinyinUDL_Setting_Beta.dat, so never just take the newest
    $exact = Join-Path $dir 'ChsPinyinUDL.dat'
    if (Test-Path -LiteralPath $exact) {
        $result.SelfLearning = $exact
    } else {
        $udl = @(Get-ChildItem -LiteralPath $dir -File -Filter 'ChsPinyinUDL*.dat' -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notmatch 'Beta' } |
            Sort-Object LastWriteTime -Descending)
        if ($udl.Count -gt 0) {
            $result.SelfLearning = $udl[0].FullName
        } else {
            $result.LegacyTarget = $exact
        }
    }

    $result.CustomPhrases = @(Get-ChildItem -LiteralPath $dir -File -Filter 'ChsPinyinEUDPv*.lex' -ErrorAction SilentlyContinue |
        Sort-Object Name | ForEach-Object { $_.FullName })

    return $result
}

function Resolve-RimeServerPath {
    # Weasel installs into <ProgramFiles>\Rime\<version>\WeaselServer.exe
    $roots = @()
    if ($env:ProgramFiles) { $roots += $env:ProgramFiles }
    if (${env:ProgramFiles(x86)}) { $roots += ${env:ProgramFiles(x86)} }
    foreach ($r in $roots) {
        $base = Join-Path $r 'Rime'
        if (-not (Test-Path -LiteralPath $base)) { continue }
        $hit = Get-ChildItem -LiteralPath $base -Recurse -Depth 3 -File -Filter 'WeaselServer.exe' -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    return $null
}

function Test-PBAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($id)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-PBTcp {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$TargetHost,
        [Parameter(Mandatory = $true)][int]$Port,
        [int]$TimeoutMs = 3000
    )
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $iar = $client.BeginConnect($TargetHost, $Port, $null, $null)
        $ok = $iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)
        if ($ok) { $client.EndConnect($iar) }
        $client.Close()
        return $ok
    } catch {
        return $false
    }
}

function Get-PBProxy {
    <#
        Resolve the HTTP proxy used for downloads and clones:
        explicit value > HTTPS_PROXY/HTTP_PROXY env > a listening local proxy port.
    #>
    [CmdletBinding()]
    param([string]$Explicit)
    if ($Explicit) { return $Explicit }
    foreach ($name in @('HTTPS_PROXY', 'HTTP_PROXY', 'https_proxy', 'http_proxy')) {
        $v = [Environment]::GetEnvironmentVariable($name)
        if ($v) { return $v }
    }
    foreach ($port in @(7890, 10809, 1080)) {
        if (Test-PBTcp -TargetHost '127.0.0.1' -Port $port -TimeoutMs 400) {
            return ('http://127.0.0.1:{0}' -f $port)
        }
    }
    return $null
}

function Get-PBCurlPath {
    foreach ($name in @('curl.exe', 'curl')) {
        $c = Get-Command $name -ErrorAction SilentlyContinue
        if ($c) { return $c.Source }
    }
    return $null
}

function Get-ImeProcessFootprint {
    $names = @('ChsIME', 'ctfmon', 'TextInputHost', 'TabTip', 'InputApp',
               'WeaselServer', 'WeaselDeployer', 'WeaselSetup')
    $procs = Get-Process -ErrorAction SilentlyContinue | Where-Object { $names -contains $_.ProcessName }
    foreach ($p in $procs) {
        $cpu = 0.0
        try { if ($null -ne $p.CPU) { $cpu = [math]::Round([double]$p.CPU, 1) } } catch { $cpu = 0.0 }
        [pscustomobject]@{
            Name   = $p.ProcessName
            PID    = $p.Id
            RAM_MB = [math]::Round($p.WorkingSet64 / 1MB, 1)
            CPU_s  = $cpu
        }
    }
}

function Get-FileSha256 {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Backup-PBPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$BackupRoot,
        [string]$Label
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-PBLog "backup source not found: $Path" Warn
        return $null
    }
    if (-not $BackupRoot) { $BackupRoot = Get-PBArtifactsRoot 'backups' }
    if (-not $Label) { $Label = (Split-Path -Leaf $Path) }
    $dest = Join-Path $BackupRoot ("{0}-{1}" -f $Label, (Get-PBTimestamp))
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    $item = Get-Item -LiteralPath $Path
    if ($item.PSIsContainer) {
        Copy-Item -Path (Join-Path $Path '*') -Destination $dest -Recurse -Force
    } else {
        Copy-Item -LiteralPath $Path -Destination $dest -Force
    }
    Write-PBLog "backup: $Path -> $dest" Ok
    return $dest
}

function Export-PBRegistryKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$KeyPath,
        [Parameter(Mandatory = $true)][string]$DestFile
    )
    $dir = Split-Path -Parent $DestFile
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    & reg.exe export $KeyPath $DestFile /y | Out-Null
    if (Test-Path -LiteralPath $DestFile) {
        Write-PBLog "registry exported: $DestFile" Ok
        return $DestFile
    }
    Write-PBLog "registry export failed: $KeyPath" Warn
    return $null
}

function Set-PBRegistryValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$KeyPath,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)]$Value,
        [ValidateSet('DWord', 'String', 'QWord')][string]$Type = 'DWord'
    )
    $prev = '<not set>'
    try {
        $prev = (Get-ItemProperty -LiteralPath $KeyPath -Name $Name -ErrorAction Stop).$Name
    } catch {
        $prev = '<not set>'
    }
    Set-ItemProperty -LiteralPath $KeyPath -Name $Name -Value $Value -Type $Type
    Write-PBLog ("registry: {0} :: {1} = {2} (was {3})" -f $KeyPath, $Name, $Value, $prev) Ok
}

Export-ModuleMember -Function *
