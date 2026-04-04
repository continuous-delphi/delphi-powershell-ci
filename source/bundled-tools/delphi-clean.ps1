#requires -Version 5.1
# -----------------------------------------------------------------------------
# delphi-clean
#
# A PowerShell utility to remove Delphi build artifacts, intermediate files,
# and IDE-generated clutter, with support for preview, validation, and CI workflows.
#
# Part of Continuous-Delphi: Strengthening Delphi's continued success
# https://github.com/continuous-delphi
#
# Project repository:
# https://github.com/continuous-delphi/delphi-clean
#
# Also included in the Continuous-Delphi PowerShell CI module:
# https://github.com/continuous-delphi/delphi-powershell-ci
#
# Copyright (c) 2026 Darian Miller
# Licensed under the MIT License.
# https://opensource.org/licenses/MIT
# SPDX-License-Identifier: MIT
# -----------------------------------------------------------------------------

<#
.SYNOPSIS
Cleans Delphi build artifacts from a repository tree using three cleanup levels.

.DESCRIPTION
Targets the current working directory by default.
Supports three cleanup levels:

  basic    - safe, low-risk cleanup of common transient files
  standard - removes build outputs and common generated files
  deep     - aggressive cleanup including user-local IDE state files

Use -Check to audit without deleting. Use -OutputLevel to control verbosity.

.EXAMPLE
powershell.exe -File .\delphi-clean.ps1

.EXAMPLE
powershell.exe -File .\delphi-clean.ps1 -Level standard

.EXAMPLE
powershell.exe -File .\delphi-clean.ps1 -Level deep -Verbose

.EXAMPLE
powershell.exe -File .\delphi-clean.ps1 -Level deep -WhatIf

.EXAMPLE
powershell.exe -File .\delphi-clean.ps1 -Level standard -PassThru

.EXAMPLE
powershell.exe -File .\delphi-clean.ps1 -Level standard -Json

.EXAMPLE
powershell.exe -File .\delphi-clean.ps1 -Level basic -IncludeFilePattern '*.res'

.EXAMPLE
powershell.exe -File .\delphi-clean.ps1 -Level basic -IncludeFilePattern '*.res','*.mab' -ExcludeDirectoryPattern 'assets','vendor*'

.EXAMPLE
powershell.exe -File .\delphi-clean.ps1 -Version

.EXAMPLE
powershell.exe -File .\delphi-clean.ps1 -Version -Format json

.EXAMPLE
powershell.exe -File .\delphi-clean.ps1 -Level standard -RecycleBin

.EXAMPLE
powershell.exe -File .\delphi-clean.ps1 -Level standard -Check

.EXAMPLE
powershell.exe -File .\delphi-clean.ps1 -Level standard -Check -OutputLevel quiet

.EXAMPLE
powershell.exe -File .\delphi-clean.ps1 -Level standard -OutputLevel summary

.EXAMPLE
powershell.exe -File .\delphi-clean.ps1 -ShowConfig

.EXAMPLE
powershell.exe -File .\delphi-clean.ps1 -ShowConfig -Json

.EXAMPLE
powershell.exe -File .\delphi-clean.ps1 -ConfigFile C:/ci/delphi-clean-ci.json -Level standard

.PARAMETER Level
Cleanup level to apply. One of: basic, standard, deep. Levels are cumulative --
standard includes everything basic removes, and deep includes everything standard
removes. Defaults to basic.

.PARAMETER RootPath
Root directory to scan. Defaults to the current working directory when omitted.
All scans and deletions are confined to this directory tree.

.PARAMETER ExcludeDirectoryPattern
One or more directory-name glob patterns to skip during scanning. Directories
whose names match any pattern (case-insensitive) are not entered and nothing
inside them is deleted. The built-in exclusions (.git, .vs, .claude) are always
applied in addition to any patterns supplied here.

.PARAMETER IncludeFilePattern
One or more additional file-name glob patterns to delete beyond the patterns
implied by -Level. Useful for project-specific artifacts such as *.res or *.mab.

.PARAMETER PassThru
Return a structured object to the pipeline containing the list of found items
and deletion results. Intended for scripting scenarios that consume the output
programmatically. May be combined with -WhatIf.

.PARAMETER Json
Emit a single JSON object to standard output instead of plain-text messages.
Suppresses all other output (Write-Information, Write-Progress). Suitable for
CI pipelines and tooling integrations.

.PARAMETER RecycleBin
Send items to the platform recycle bin / trash instead of deleting them
permanently. On Windows, uses Microsoft.VisualBasic.FileIO.FileSystem. On
macOS, uses the 'trash' shell command. Not supported on Linux.

.PARAMETER Check
Audit-only mode. Scans for artifacts but does not delete anything. Exits with
code 0 when nothing is found, or 1 when artifacts are present. Cannot be
combined with -WhatIf.

.PARAMETER ShowConfig
Display the effective merged configuration (from all config files and CLI
flags) and exit without scanning or cleaning. Add -Json for machine-readable
output.

.PARAMETER ConfigFile
Path to an explicit JSON configuration file. Loaded at the highest priority
below command-line parameters, above project-level and local config files.
Useful in CI pipelines where the config lives outside the repository tree.

.PARAMETER OutputLevel
Controls the amount of plain-text output produced during a run.
  detailed - header, per-item lines, and summary (default)
  summary  - header and summary only; per-item lines are suppressed
  quiet    - no output at all; use the exit code or -Json as the signal
Has no effect when -Json is active.

.PARAMETER Version
Display the tool version and exit. Cannot be combined with Clean parameters.

.PARAMETER Format
Output format when -Version is specified. One of: text (default), json.
#>

[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Clean')]
param(
    [Parameter(ParameterSetName = 'Version', Mandatory)]
    [switch]$Version,

    [Parameter(ParameterSetName = 'Version')]
    [ValidateSet('text', 'json')]
    [string]$Format = 'text',

    [Parameter(ParameterSetName = 'Clean')]
    [ValidateSet('basic', 'standard', 'deep')]
    [string]$Level = 'basic',

    [Parameter(ParameterSetName = 'Clean')]
    [string]$RootPath,

    [Parameter(ParameterSetName = 'Clean')]
    [string[]]$ExcludeDirectoryPattern = @(),

    [Parameter(ParameterSetName = 'Clean')]
    [string[]]$IncludeFilePattern = @(),

    [Parameter(ParameterSetName = 'Clean')]
    [switch]$PassThru,

    [Parameter(ParameterSetName = 'Clean')]
    [switch]$Json,

    [Parameter(ParameterSetName = 'Clean')]
    [switch]$RecycleBin,

    # Audit mode: scan only, never deletes. Exit 0 = nothing found, 2 = artifacts found.
    # Cannot be combined with -WhatIf.
    [Parameter(ParameterSetName = 'Clean')]
    [switch]$Check,

    # Show the effective merged configuration and exit. No scan or cleanup is performed.
    [Parameter(ParameterSetName = 'Clean')]
    [switch]$ShowConfig,

    # Path to an explicit JSON config file. Loaded at highest config priority (above
    # project and local files, below command-line parameters).
    [Parameter(ParameterSetName = 'Clean')]
    [string]$ConfigFile,

    # Controls how much output is produced during a clean or check run.
    #   detailed - header, per-item lines, and summary (default)
    #   summary  - header and summary only; per-item lines are suppressed
    #   quiet    - no output at all; use the exit code as the signal
    [Parameter(ParameterSetName = 'Clean')]
    [ValidateSet('detailed', 'summary', 'quiet')]
    [string]$OutputLevel = 'detailed'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ToolVersion        = '0.10.0'

$script:OutputLevel        = $OutputLevel
$script:BuiltInExcludeDirs = @('.git', '.vs', '.claude')

if ($Version) {
    if ($Format -eq 'json') {
        [PSCustomObject]@{
            ok      = $true
            command = 'version'
            tool    = [PSCustomObject]@{
                name    = 'delphi-clean'
                version = $script:ToolVersion
            }
        } | ConvertTo-Json -Depth 3 -Compress
    }
    else {
        Write-Output "delphi-clean $script:ToolVersion"
    }
    exit 0
}

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------

# Write-Detail       : visible at 'detailed' only
# Write-Summary      : visible at 'detailed' and 'summary'
# Write-Section      : section banner, visible at 'detailed' only
# Write-SummarySection: section banner, visible at 'detailed' and 'summary'
# Warnings and errors are never suppressed by -OutputLevel.

function Write-Detail {
    param([AllowEmptyString()][Parameter(Mandatory)][string]$Message)
    if ($script:OutputLevel -eq 'detailed' -and -not $Json) {
        Write-Information $Message -InformationAction Continue
    }
}

function Write-Summary {
    param([AllowEmptyString()][Parameter(Mandatory)][string]$Message)
    if ($script:OutputLevel -ne 'quiet' -and -not $Json) {
        Write-Information $Message -InformationAction Continue
    }
}

function Write-Section {
    param([AllowEmptyString()][Parameter(Mandatory)][string]$Message)
    if ($script:OutputLevel -eq 'detailed' -and -not $Json) {
        Write-Information '' -InformationAction Continue
        Write-Information ('=' * 70) -InformationAction Continue
        Write-Information $Message -InformationAction Continue
        Write-Information ('=' * 70) -InformationAction Continue
    }
}

function Write-SummarySection {
    param([AllowEmptyString()][Parameter(Mandatory)][string]$Message)
    if ($script:OutputLevel -ne 'quiet' -and -not $Json) {
        Write-Information '' -InformationAction Continue
        Write-Information ('=' * 70) -InformationAction Continue
        Write-Information $Message -InformationAction Continue
        Write-Information ('=' * 70) -InformationAction Continue
    }
}

# ---------------------------------------------------------------------------
# Size helpers
# ---------------------------------------------------------------------------

function Format-Duration {
    param([long]$Milliseconds)
    if ($Milliseconds -lt 1000) { return "$Milliseconds ms" }
    return ('{0:N3} s' -f ($Milliseconds / 1000))
}

function Format-ByteSize {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return ('{0:N1} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N1} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N1} KB' -f ($Bytes / 1KB)) }
    return "$Bytes B"
}

function Get-TreeSize {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )
    if (-not (Test-Path -LiteralPath $Path)) { return [long]0 }
    $total = [long]0
    foreach ($f in (Get-ChildItem -Path $Path -Recurse -File -Force -ErrorAction SilentlyContinue)) {
        $total += $f.Length
    }
    return $total
}

# ---------------------------------------------------------------------------
# Trash / recycle helpers
# ---------------------------------------------------------------------------

function Get-TrashDestination {
    param(
        [Parameter(Mandatory)]
        [string]$TrashFilesDir,

        [Parameter(Mandatory)]
        [string]$Name
    )

    $dest = Join-Path $TrashFilesDir $Name
    if (-not (Test-Path -LiteralPath $dest)) {
        return $dest
    }

    $base    = [System.IO.Path]::GetFileNameWithoutExtension($Name)
    $ext     = [System.IO.Path]::GetExtension($Name)
    $counter = 2
    do {
        $uniqueName = if ($ext) { "$base $counter$ext" } else { "$Name $counter" }
        $dest = Join-Path $TrashFilesDir $uniqueName
        $counter++
    } while (Test-Path -LiteralPath $dest)

    return $dest
}

function Send-ToMacTrash {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $trashDir = Join-Path $HOME '.Trash'
    if (-not (Test-Path -LiteralPath $trashDir)) {
        New-Item -ItemType Directory -Path $trashDir | Out-Null
    }

    $name = Split-Path -Path $Path -Leaf
    $dest = Get-TrashDestination -TrashFilesDir $trashDir -Name $name
    Move-Item -LiteralPath $Path -Destination $dest
}

function Send-ToLinuxTrash {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $trashRoot = Join-Path $HOME '.local/share/Trash'
    $filesDir  = Join-Path $trashRoot 'files'
    $infoDir   = Join-Path $trashRoot 'info'

    foreach ($dir in @($filesDir, $infoDir)) {
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir | Out-Null
        }
    }

    $name      = Split-Path -Path $Path -Leaf
    $destPath  = Get-TrashDestination -TrashFilesDir $filesDir -Name $name
    $destName  = Split-Path -Path $destPath -Leaf
    $infoFile  = Join-Path $infoDir "$destName.trashinfo"
    $absPath   = [System.IO.Path]::GetFullPath($Path)
    $timestamp = [datetime]::Now.ToString('yyyy-MM-ddTHH:mm:ss')

    $trashInfoContent = "[Trash Info]`nPath=$absPath`nDeletionDate=$timestamp`n"
    [System.IO.File]::WriteAllText($infoFile, $trashInfoContent)

    try {
        Move-Item -LiteralPath $Path -Destination $destPath
    }
    catch {
        Remove-Item -LiteralPath $infoFile -Force -ErrorAction SilentlyContinue
        throw
    }
}

function Send-ToRecycleBin {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [ValidateSet('File', 'Directory')]
        [string]$Type
    )

    if ($IsWindows) {
        Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction Stop
        if ($Type -eq 'File') {
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
                $Path,
                [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
                [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
            )
        }
        else {
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory(
                $Path,
                [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
                [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
            )
        }
    }
    elseif ($IsMacOS) {
        Send-ToMacTrash -Path $Path
    }
    elseif ($IsLinux) {
        Send-ToLinuxTrash -Path $Path
    }
    else {
        throw 'Unsupported platform for -RecycleBin.'
    }
}

# ---------------------------------------------------------------------------
# Path helpers
# ---------------------------------------------------------------------------

function Get-RelativePathCompat {
    param(
        [Parameter(Mandatory)]
        [string]$BasePath,

        [Parameter(Mandatory)]
        [string]$TargetPath
    )

    $baseFull = [System.IO.Path]::GetFullPath($BasePath)
    $targetFull = [System.IO.Path]::GetFullPath($TargetPath)

    if (-not $baseFull.EndsWith([string][System.IO.Path]::DirectorySeparatorChar)) {
        $baseFull += [string][System.IO.Path]::DirectorySeparatorChar
    }

    $baseUri = New-Object System.Uri($baseFull)
    $targetUri = New-Object System.Uri($targetFull)
    $relativeUri = $baseUri.MakeRelativeUri($targetUri)
    $relativePath = [System.Uri]::UnescapeDataString($relativeUri.ToString()) -replace '/', [System.IO.Path]::DirectorySeparatorChar

    if ([string]::IsNullOrWhiteSpace($relativePath)) {
        return '.'
    }

    return $relativePath
}

function Resolve-CleanRoot {
    param(
        [string]$InputRoot
    )

    if ([string]::IsNullOrWhiteSpace($InputRoot)) {
        return (Get-Location).Path
    }

    $resolvedInput = Resolve-Path $InputRoot
    return $resolvedInput.Path
}

function Test-SafeCleanRoot {
    param(
        [Parameter(Mandatory)]
        [string]$Root
    )

    $fullRoot = [System.IO.Path]::GetFullPath($Root)
    $rootOfRoot = [System.IO.Path]::GetPathRoot($fullRoot)

    if ($fullRoot -eq $rootOfRoot) {
        throw "Refusing to clean an unsafe root path: $fullRoot"
    }

    $resolved = Resolve-Path -LiteralPath $fullRoot
    if (-not $resolved) {
        throw "Invalid root path: $fullRoot"
    }
}

function Test-PathUnderExcludedDirectory {
    param(
        [Parameter(Mandatory)]
        [string]$FullName,

        [Parameter(Mandatory)]
        [string]$Root,

        [Parameter(Mandatory)]
        [string[]]$ExcludedDirPatterns
    )

    $relative = Get-RelativePathCompat -BasePath $Root -TargetPath $FullName

    if ($relative -eq '.') {
        return $false
    }

    $parts = $relative -split '[\\\/]'
    foreach ($part in $parts) {
        foreach ($pattern in $ExcludedDirPatterns) {
            if ($part -ilike $pattern) {
                return $true
            }
        }
    }

    return $false
}

# ---------------------------------------------------------------------------
# Configuration file helpers
# ---------------------------------------------------------------------------

function Get-ConfigValue {
    param(
        [object]$Config,
        [Parameter(Mandatory)]
        [string]$Key,
        $Default = $null
    )
    if ($null -eq $Config) { return $Default }
    $prop = $Config.PSObject.Properties[$Key]
    if ($null -eq $prop) { return $Default }
    return $prop.Value
}

function Read-ConfigFile {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    try {
        $content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        return $content | ConvertFrom-Json
    }
    catch {
        Write-Warning "[config] Failed to parse '$Path': $($_.Exception.Message)"
        return $null
    }
}

function Merge-CleanConfig {
    param(
        [object[]]$Configs = @()
    )

    $resultLevel        = $null
    $resultOutputLevel  = $null
    $resultRecycleBin   = $null
    $resultSearchParent = $null

    $seenInclude   = New-Object 'System.Collections.Generic.HashSet[string]' -ArgumentList ([System.StringComparer]::OrdinalIgnoreCase)
    $seenExclude   = New-Object 'System.Collections.Generic.HashSet[string]' -ArgumentList ([System.StringComparer]::OrdinalIgnoreCase)
    $resultInclude = New-Object 'System.Collections.Generic.List[string]'
    $resultExclude = New-Object 'System.Collections.Generic.List[string]'

    foreach ($config in $Configs) {
        if ($null -eq $config) { continue }

        $val = Get-ConfigValue -Config $config -Key 'level'
        if ($null -ne $val) { $resultLevel = $val }

        $val = Get-ConfigValue -Config $config -Key 'outputLevel'
        if ($null -ne $val) { $resultOutputLevel = $val }

        $val = Get-ConfigValue -Config $config -Key 'recycleBin'
        if ($null -ne $val) { $resultRecycleBin = $val }

        $val = Get-ConfigValue -Config $config -Key 'searchParentFolders'
        if ($null -ne $val) { $resultSearchParent = $val }

        foreach ($item in @(Get-ConfigValue -Config $config -Key 'includeFilePattern' -Default @())) {
            if (-not [string]::IsNullOrEmpty($item) -and $seenInclude.Add($item)) {
                $resultInclude.Add($item)
            }
        }

        foreach ($item in @(Get-ConfigValue -Config $config -Key 'excludeDirectoryPattern' -Default @())) {
            if (-not [string]::IsNullOrEmpty($item) -and $seenExclude.Add($item)) {
                $resultExclude.Add($item)
            }
        }
    }

    return [PSCustomObject]@{
        level                   = $resultLevel
        outputLevel             = $resultOutputLevel
        recycleBin              = $resultRecycleBin
        searchParentFolders     = $resultSearchParent
        includeFilePattern      = @($resultInclude)
        excludeDirectoryPattern = @($resultExclude)
    }
}

function Resolve-EffectiveConfig {
    param(
        [Parameter(Mandatory)]
        [string]$RootPath,

        [string]$ConfigFile = ''
    )

    $log            = New-Object 'System.Collections.Generic.List[string]'
    $anyConfigFound = $false

    # Allow test suites to redirect the home directory lookup.
    # Guard against $HOME being null/empty (e.g. minimal CI environments).
    $homeDir = if (-not [string]::IsNullOrEmpty($env:DELPHI_CLEAN_HOME_OVERRIDE)) {
        $env:DELPHI_CLEAN_HOME_OVERRIDE
    } elseif (-not [string]::IsNullOrEmpty($HOME)) {
        [string]$HOME
    } else {
        ''
    }

    $projectConfigPath = Join-Path $RootPath 'delphi-clean.json'
    $localConfigPath   = Join-Path $RootPath 'delphi-clean.local.json'

    $homeConfig = $null
    if (-not [string]::IsNullOrEmpty($homeDir)) {
        $homeConfigPath = Join-Path $homeDir 'delphi-clean.json'
        $homeConfig     = Read-ConfigFile -Path $homeConfigPath
        Write-Verbose ("[config] user-level:     {0}" -f $(if ($null -ne $homeConfig) { $homeConfigPath } else { "$homeConfigPath (not found)" }))
        if ($null -ne $homeConfig) { $anyConfigFound = $true; $log.Add("[config] user-level:     $homeConfigPath") }
    } else {
        Write-Verbose '[config] user-level:     skipped ($HOME not set)'
    }

    $projectConfig = Read-ConfigFile -Path $projectConfigPath
    $localConfig   = Read-ConfigFile -Path $localConfigPath

    # Write-Verbose always shows all paths; log only tracks found files
    Write-Verbose ("[config] project-level:  {0}" -f $(if ($null -ne $projectConfig) { $projectConfigPath } else { "$projectConfigPath (not found)" }))
    Write-Verbose ("[config] local override: {0}" -f $(if ($null -ne $localConfig)   { $localConfigPath   } else { "$localConfigPath (not found)" }))

    if ($null -ne $projectConfig) { $anyConfigFound = $true; $log.Add("[config] project-level:  $projectConfigPath") }
    if ($null -ne $localConfig)   { $anyConfigFound = $true; $log.Add("[config] local override: $localConfigPath") }

    # Traversal is triggered only by the project-level or local config.
    # searchParentFolders in the $HOME config is intentionally ignored.
    $traversalRequested = ((Get-ConfigValue -Config $projectConfig -Key 'searchParentFolders') -eq $true) -or
                          ((Get-ConfigValue -Config $localConfig   -Key 'searchParentFolders') -eq $true)

    $traversedConfigs = @()

    if ($traversalRequested) {
        $current = Split-Path -Parent $RootPath

        while (-not [string]::IsNullOrEmpty($current)) {
            $parentConfigPath = Join-Path $current 'delphi-clean.json'
            $parentConfig     = Read-ConfigFile -Path $parentConfigPath

            if ($null -ne $parentConfig) {
                # Prepend so farthest ancestor ends up first (lowest priority among traversed)
                $traversedConfigs = @($parentConfig) + $traversedConfigs
                $anyConfigFound   = $true
                Write-Verbose "[config] traversed:      $parentConfigPath"
                $log.Add("[config] traversed:      $parentConfigPath")

                if ((Get-ConfigValue -Config $parentConfig -Key 'searchParentFolders') -eq $false) {
                    Write-Verbose '[config]   (stop marker -- traversal ends here)'
                    $log.Add('[config]   (stop marker -- traversal ends here)')
                    break
                }
            }

            $parent = Split-Path -Parent $current
            if ($parent -eq $current) { break }  # filesystem root reached
            $current = $parent
        }
    }

    # Explicit config file (highest config priority, below CLI)
    $explicitConfig = $null
    if (-not [string]::IsNullOrEmpty($ConfigFile)) {
        if (-not (Test-Path -LiteralPath $ConfigFile)) {
            Write-Warning "[config] Explicit config file not found: $ConfigFile"
        }
        else {
            $explicitConfig = Read-ConfigFile -Path $ConfigFile
            if ($null -ne $explicitConfig) {
                $anyConfigFound = $true
                Write-Verbose "[config] explicit file:  $ConfigFile"
                $log.Add("[config] explicit file:  $ConfigFile")
            }
        }
    }

    # Merge: lowest priority first
    $allConfigs = @($homeConfig) + $traversedConfigs + @($projectConfig) + @($localConfig) + @($explicitConfig)
    $merged = Merge-CleanConfig -Configs $allConfigs

    $finalLogLines = @(
        '[config] final merged values:'
        ("[config]   level                   = {0}" -f $(if ($null -ne $merged.level)               { $merged.level }               else { '(not set)' }))
        ("[config]   outputLevel             = {0}" -f $(if ($null -ne $merged.outputLevel)         { $merged.outputLevel }         else { '(not set)' }))
        ("[config]   recycleBin              = {0}" -f $(if ($null -ne $merged.recycleBin)          { "$($merged.recycleBin)" }     else { '(not set)' }))
        ("[config]   searchParentFolders     = {0}" -f $(if ($null -ne $merged.searchParentFolders) { "$($merged.searchParentFolders)" } else { '(not set)' }))
        ("[config]   includeFilePattern      = [{0}]" -f ($merged.includeFilePattern -join ', '))
        ("[config]   excludeDirectoryPattern = [{0}]" -f ($merged.excludeDirectoryPattern -join ', '))
    )
    foreach ($line in $finalLogLines) { Write-Verbose $line }

    return [PSCustomObject]@{
        Merged       = $merged
        Log          = $log.ToArray()
        ConfigsFound = $anyConfigFound
    }
}

# ---------------------------------------------------------------------------
# Level definitions
# ---------------------------------------------------------------------------

function Get-LevelDefinition {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('basic', 'standard', 'deep')]
        [string]$Name
    )

    # --- base (basic) ---
    $basicFiles = @(
        '*.dcu',
        '*.identcache',
        '*.bak',
        '*.tmp',
        '*.dsk',
        '*.tvsconfig',
        '*.stat'
    )

    $basicDirs = @(
        '__history'
    )

    # --- standard additions ---
    $standardFilesExtra = @(
        '*.drc',
        '*.map',
        '*.rsm',
        '*.tds',
        '*.bpl',
        '*.dcp',
        '*.bpi',
        '*.so',
        '*.o',
        '*.a',
        '*.dylib',
        '*.exe',
        '*.hpp',
        '*.dres',
        '*.ilc',
        '*.ild',
        '*.ilf',
        '*.ipu',
        '*.ddp',
        '*.prjmgc',
        '*.vlb',
        'dunitx-results.xml'
    )

    $standardDirsExtra = @(
        'Win32',
        'Win64',
        'Debug',
        'Release',
        'OSX64',
        'OSXARM64',
        'Android',
        'Android64',
        'iOSDevice64',
        'iOSSimulatorArm64',
        'Linux64',
        'LinuxARM64',
        'TMSWeb'
    )

    # --- deep additions ---
    $deepFilesExtra = @(
        '*.local',
        '*.dproj.local',
        '*.groupproj.local',
        '*.projdata',
        '*.~*',
        '*.lib',
        '*.fbpInf',
        '*.fbl8',
        '*.fbpbrk',
        '*.fb8lck',
        '*.mab',
        'TestInsightSettings.ini'
    )

    $deepDirsExtra = @(
        '__recovery'
    )

    # --- compose ---
    switch ($Name) {
        'basic' {
            $files = $basicFiles
            $dirs  = $basicDirs
        }

        'standard' {
            $files = $basicFiles + $standardFilesExtra
            $dirs  = $basicDirs + $standardDirsExtra
        }

        'deep' {
            $files = $basicFiles + $standardFilesExtra + $deepFilesExtra
            $dirs  = $basicDirs + $standardDirsExtra + $deepDirsExtra
        }
    }

    # --- dedupe ---
    $files = $files | Sort-Object -Unique
    $dirs  = $dirs  | Sort-Object -Unique

    return @{
        FilePatterns   = $files
        DirectoryNames = $dirs
    }
}

# ---------------------------------------------------------------------------
# Scan functions
# ---------------------------------------------------------------------------

function Get-FilesToDelete {
    param(
        [Parameter(Mandatory)]
        [string]$Root,

        [Parameter(Mandatory)]
        [string[]]$Patterns,

        [Parameter(Mandatory)]
        [string[]]$ExcludedDirPatterns
    )

    Write-Verbose 'Scanning for matching files.'

    $examined = 0
    $allFiles = Get-ChildItem -Path $Root -Recurse -File -Force -ErrorAction SilentlyContinue |
        ForEach-Object {
            $examined++
            if (-not $Json -and $examined % 500 -eq 0) {
                Write-Progress -Activity 'delphi-clean' -Status "Scanning: $examined files examined..."
            }
            $_
        } |
        Where-Object {
            -not (Test-PathUnderExcludedDirectory -FullName $_.FullName -Root $Root -ExcludedDirPatterns $ExcludedDirPatterns)
        }

    $allFiles |
        Where-Object {
            $file = $_
            foreach ($pattern in $Patterns) {
                if ($file.Name -like $pattern) {
                    return $true
                }
            }
            return $false
        } |
        Sort-Object -Property FullName -Unique
}

function Get-DirectoriesToDelete {
    param(
        [Parameter(Mandatory)]
        [string]$Root,

        [Parameter(Mandatory)]
        [string[]]$DirectoryNames,

        [Parameter(Mandatory)]
        [string[]]$ExcludedDirPatterns
    )

    Write-Verbose 'Scanning for matching directories.'

    $nameSet = @{}
    foreach ($dirName in $DirectoryNames) {
        $nameSet[$dirName.ToUpperInvariant()] = $true
    }

    Get-ChildItem -Path $Root -Recurse -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object {
            $nameSet.ContainsKey($_.Name.ToUpperInvariant()) -and
            -not (Test-PathUnderExcludedDirectory -FullName $_.FullName -Root $Root -ExcludedDirPatterns $ExcludedDirPatterns)
        } |
        Sort-Object -Property FullName -Unique |
        Sort-Object -Property { $_.FullName.Length } -Descending
}

# ---------------------------------------------------------------------------
# Deletion record
# ---------------------------------------------------------------------------

function ConvertTo-DeletionRecord {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('File', 'Directory')]
        [string]$Type,

        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [bool]$Deleted,

        [long]$Size = 0
    )

    [PSCustomObject]@{
        Type    = $Type
        Path    = $Path
        Deleted = $Deleted
        Size    = $Size
    }
}

# ---------------------------------------------------------------------------
# Removal functions
# ---------------------------------------------------------------------------

function Remove-FileList {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [System.IO.FileInfo[]]$Files = @(),
        [switch]$ReturnRecords,
        [switch]$RecycleBin
    )

    $result = [PSCustomObject]@{
        DeletedCount = 0
        FailedCount  = 0
        Records      = New-Object System.Collections.Generic.List[object]
    }

    if (@($Files).Count -eq 0) {
        return $result
    }

    $action = if ($RecycleBin) { 'Recycle file' } else { 'Delete file' }
    $verb   = if ($RecycleBin) { 'Recycled' } else { 'Deleted' }

    foreach ($file in $Files) {
        Write-Verbose "Evaluating file: $($file.FullName)"

        if ($PSCmdlet.ShouldProcess($file.FullName, $action)) {
            try {
                if ($RecycleBin) {
                    Send-ToRecycleBin -Path $file.FullName -Type 'File'
                }
                else {
                    Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
                }
                $result.DeletedCount++
                Write-Detail "$verb file: $($file.FullName)"

                if ($ReturnRecords) {
                    $result.Records.Add((ConvertTo-DeletionRecord -Type File -Path $file.FullName -Deleted $true -Size $file.Length))
                }
            }
            catch {
                $result.FailedCount++
                Write-Warning "Failed to $($action.ToLower()): $($file.FullName) - $($_.Exception.Message)"

                if ($ReturnRecords) {
                    $result.Records.Add((ConvertTo-DeletionRecord -Type File -Path $file.FullName -Deleted $false -Size $file.Length))
                }
            }
        }
        elseif ($WhatIfPreference) {
            Write-Detail "Would $($action.ToLower()): $($file.FullName)"
            if ($ReturnRecords) {
                $result.Records.Add((ConvertTo-DeletionRecord -Type File -Path $file.FullName -Deleted $false -Size $file.Length))
            }
        }
    }

    return $result
}

function Remove-DirectoryList {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [System.IO.DirectoryInfo[]]$Directories = @(),
        [switch]$ReturnRecords,
        [switch]$RecycleBin
    )

    $result = [PSCustomObject]@{
        DeletedCount = 0
        FailedCount  = 0
        Records      = New-Object System.Collections.Generic.List[object]
    }

    if (@($Directories).Count -eq 0) {
        return $result
    }

    $action = if ($RecycleBin) { 'Recycle directory' } else { 'Delete directory' }
    $verb   = if ($RecycleBin) { 'Recycled' } else { 'Deleted' }

    foreach ($dir in $Directories) {
        if (-not (Test-Path -LiteralPath $dir.FullName)) {
            continue
        }

        Write-Verbose "Evaluating directory: $($dir.FullName)"

        # Compute size before any deletion so it is available for the record regardless of outcome
        $dirSize = Get-TreeSize -Path $dir.FullName

        if ($PSCmdlet.ShouldProcess($dir.FullName, $action)) {
            try {
                if ($RecycleBin) {
                    Send-ToRecycleBin -Path $dir.FullName -Type 'Directory'
                }
                else {
                    Remove-Item -LiteralPath $dir.FullName -Recurse -Force -ErrorAction Stop
                }

                # Verify the directory is actually gone. On some PowerShell versions
                # Remove-Item -Recurse can silently partial-succeed when a handle is open
                # (e.g. an open shell session in the directory), deleting children but
                # leaving the directory itself without throwing.
                if (Test-Path -LiteralPath $dir.FullName) {
                    throw "Directory still exists after removal attempt (a process may have an open handle): $($dir.FullName)"
                }

                $result.DeletedCount++
                Write-Detail "$verb directory: $($dir.FullName)"

                if ($ReturnRecords) {
                    $result.Records.Add((ConvertTo-DeletionRecord -Type Directory -Path $dir.FullName -Deleted $true -Size $dirSize))
                }
            }
            catch {
                $result.FailedCount++
                Write-Warning "Failed to $($action.ToLower()): $($dir.FullName) - $($_.Exception.Message)"

                if ($ReturnRecords) {
                    $result.Records.Add((ConvertTo-DeletionRecord -Type Directory -Path $dir.FullName -Deleted $false -Size $dirSize))
                }
            }
        }
        elseif ($WhatIfPreference) {
            Write-Detail "Would $($action.ToLower()): $($dir.FullName)"
            if ($ReturnRecords) {
                $result.Records.Add((ConvertTo-DeletionRecord -Type Directory -Path $dir.FullName -Deleted $false -Size $dirSize))
            }
        }
    }

    return $result
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

try {
    # -Check cannot be combined with -WhatIf: they are both no-op scan modes
    # but have different exit code semantics that cannot be meaningfully reconciled.
    if ($Check -and $WhatIfPreference) {
        Write-Error '-Check cannot be combined with -WhatIf. Use -Check with -OutputLevel instead.'
        Write-Verbose 'Exit code = 3'
        exit 3
    }

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    $cleanRoot = Resolve-CleanRoot -InputRoot $RootPath
    Test-SafeCleanRoot -Root $cleanRoot

    # --- Load and apply configuration files ---
    $configResult    = Resolve-EffectiveConfig -RootPath $cleanRoot -ConfigFile $ConfigFile
    $effectiveConfig = $configResult.Merged

    # Scalars: config value applies only when the CLI did not explicitly supply the parameter
    if ('Level' -notin $PSBoundParameters.Keys) {
        $cfgVal = Get-ConfigValue -Config $effectiveConfig -Key 'level'
        if ($null -ne $cfgVal) { $Level = $cfgVal }
    }
    if ('OutputLevel' -notin $PSBoundParameters.Keys) {
        $cfgVal = Get-ConfigValue -Config $effectiveConfig -Key 'outputLevel'
        if ($null -ne $cfgVal) {
            $OutputLevel = $cfgVal
            $script:OutputLevel = $OutputLevel
        }
    }
    if ('RecycleBin' -notin $PSBoundParameters.Keys) {
        if ((Get-ConfigValue -Config $effectiveConfig -Key 'recycleBin') -eq $true) {
            $RecycleBin = [System.Management.Automation.SwitchParameter]::new($true)
        }
    }

    # Arrays: built-ins + config + CLI, deduplicated (first-seen position preserved)
    $seenExcludes   = New-Object 'System.Collections.Generic.HashSet[string]' -ArgumentList ([System.StringComparer]::OrdinalIgnoreCase)
    $mergedExcludes = New-Object 'System.Collections.Generic.List[string]'
    foreach ($d in $script:BuiltInExcludeDirs) {
        if ($seenExcludes.Add($d)) { $mergedExcludes.Add($d) }
    }
    foreach ($d in @($effectiveConfig.excludeDirectoryPattern)) {
        if (-not [string]::IsNullOrEmpty($d) -and $seenExcludes.Add($d)) { $mergedExcludes.Add($d) }
    }
    foreach ($d in @($ExcludeDirectoryPattern)) {
        if (-not [string]::IsNullOrEmpty($d) -and $seenExcludes.Add($d)) { $mergedExcludes.Add($d) }
    }
    $ExcludeDirectoryPattern = $mergedExcludes.ToArray()

    $seenIncludes   = New-Object 'System.Collections.Generic.HashSet[string]' -ArgumentList ([System.StringComparer]::OrdinalIgnoreCase)
    $mergedIncludes = New-Object 'System.Collections.Generic.List[string]'
    foreach ($p in @($effectiveConfig.includeFilePattern)) {
        if (-not [string]::IsNullOrEmpty($p) -and $seenIncludes.Add($p)) { $mergedIncludes.Add($p) }
    }
    foreach ($p in @($IncludeFilePattern)) {
        if (-not [string]::IsNullOrEmpty($p) -and $seenIncludes.Add($p)) { $mergedIncludes.Add($p) }
    }
    $IncludeFilePattern = $mergedIncludes.ToArray()

    # Show config log now that OutputLevel is finalised (it may itself have come from config).
    # Skipped when -Verbose is active because Write-Verbose already emitted the same lines.
    if ($configResult.ConfigsFound -and $VerbosePreference -ne 'Continue') {
        foreach ($line in $configResult.Log) { Write-Detail $line }
    }

    # -ShowConfig: display effective configuration and exit without scanning.
    if ($ShowConfig) {
        if ($Json) {
            [PSCustomObject]@{
                Root                    = $cleanRoot
                ConfigSources           = @($configResult.Log)
                Level                   = $Level
                OutputLevel             = $script:OutputLevel
                RecycleBin              = $RecycleBin.IsPresent
                IncludeFilePattern      = @($IncludeFilePattern)
                ExcludeDirectoryPattern = @($ExcludeDirectoryPattern)
            } | ConvertTo-Json -Depth 5
        }
        else {
            $nl = [System.Environment]::NewLine
            Write-Information "$nl$('=' * 70)" -InformationAction Continue
            Write-Information 'Delphi Clean -- Effective Configuration' -InformationAction Continue
            Write-Information ('=' * 70) -InformationAction Continue
            Write-Information "Root: $cleanRoot" -InformationAction Continue
            Write-Information '' -InformationAction Continue
            if ($configResult.Log.Count -gt 0) {
                Write-Information 'Config sources:' -InformationAction Continue
                foreach ($line in $configResult.Log) {
                    Write-Information "  $line" -InformationAction Continue
                }
                Write-Information '' -InformationAction Continue
            }
            else {
                Write-Information 'No config files found (using defaults and CLI parameters).' -InformationAction Continue
                Write-Information '' -InformationAction Continue
            }
            $includeDisplay = if ($IncludeFilePattern.Count -gt 0) { $IncludeFilePattern -join ', ' } else { '(none)' }
            Write-Information 'Effective values:' -InformationAction Continue
            Write-Information ('  Level                   : {0}' -f $Level) -InformationAction Continue
            Write-Information ('  OutputLevel             : {0}' -f $script:OutputLevel) -InformationAction Continue
            Write-Information ('  RecycleBin              : {0}' -f $RecycleBin.IsPresent) -InformationAction Continue
            Write-Information ('  IncludeFilePattern      : {0}' -f $includeDisplay) -InformationAction Continue
            Write-Information ('  ExcludeDirectoryPattern : {0}' -f ($ExcludeDirectoryPattern -join ', ')) -InformationAction Continue
        }
        Write-Verbose 'Exit code = 0'
        exit 0
    }

    $definition    = Get-LevelDefinition -Name $Level
    $mode          = if ($Check) { 'Check (no changes)' } elseif ($WhatIfPreference) { 'WhatIf (no changes)' } else { 'Execute' }
    $disposition   = if ($RecycleBin) { 'Recycle Bin' } else { 'Permanent' }
    $returnRecords = ($PassThru -or $Json)

    $allFilePatterns = @($definition.FilePatterns) + @($IncludeFilePattern) | Sort-Object -Unique

    Write-Section 'Delphi Clean'
    Write-Detail ('Level           : {0}' -f $Level)
    Write-Detail ('Root            : {0}' -f $cleanRoot)
    Write-Detail ('Excluded dirs   : {0}' -f ($ExcludeDirectoryPattern -join ', '))
    if ($IncludeFilePattern.Count -gt 0) {
        Write-Detail ('Extra patterns  : {0}' -f ($IncludeFilePattern -join ', '))
    }
    Write-Detail ('Mode            : {0}' -f $mode)
    if (-not $Check) {
        Write-Detail ('Disposition     : {0}' -f $disposition)
    }

    if (-not $Json) { Write-Progress -Activity 'delphi-clean' -Status 'Scanning for files...' }
    $filesToDelete = @(Get-FilesToDelete    -Root $cleanRoot -Patterns $allFilePatterns            -ExcludedDirPatterns $ExcludeDirectoryPattern)
    if (-not $Json) { Write-Progress -Activity 'delphi-clean' -Status 'Scanning for directories...' }
    $dirsToDelete  = @(Get-DirectoriesToDelete -Root $cleanRoot -DirectoryNames $definition.DirectoryNames -ExcludedDirPatterns $ExcludeDirectoryPattern)
    if (-not $Json) { Write-Progress -Activity 'delphi-clean' -Completed }

    if (-not $Check) {
      Write-Detail ''
      Write-Detail ('Files found      : {0}' -f $filesToDelete.Count)
      Write-Detail ('Directories found: {0}' -f $dirsToDelete.Count)
    }

    $nothingFound = ($filesToDelete.Count -eq 0) -and ($dirsToDelete.Count -eq 0)

    if ($nothingFound) {
        if ($Json) {
            [PSCustomObject]@{
                Level                   = $Level
                Root                    = $cleanRoot
                ExcludeDirectoryPattern = @($ExcludeDirectoryPattern)
                IncludeFilePattern      = @($IncludeFilePattern)
                Mode                    = $mode
                Disposition             = $disposition
                RecycleBin              = $RecycleBin.IsPresent
                Check                   = $Check.IsPresent
                FilesFound              = 0
                DirectoriesFound        = 0
                FilesDeleted            = 0
                DirectoriesDeleted      = 0
                FilesFailed             = 0
                DirectoriesFailed       = 0
                BytesFreed              = 0
                DurationMs              = $stopwatch.ElapsedMilliseconds
                Items                   = @()
            } | ConvertTo-Json -Depth 5
        }
        else {
            Write-Summary ''
            Write-Summary 'Nothing to clean.'
        }

        Write-Verbose 'Exit code = 0'
        exit 0
    }

    # Compute total bytes and per-directory sizes (used by both -Check items and normal path)
    $totalBytes  = [long]0
    $dirSizeMap  = @{}
    foreach ($f   in $filesToDelete) { $totalBytes += $f.Length }
    foreach ($dir in $dirsToDelete)  {
        $s = Get-TreeSize -Path $dir.FullName
        $dirSizeMap[$dir.FullName] = $s
        $totalBytes += $s
    }

    # -Check: report what was found and exit without deleting.
    if ($Check) {
        if ($Json) {
            [PSCustomObject]@{
                Level                   = $Level
                Root                    = $cleanRoot
                ExcludeDirectoryPattern = @($ExcludeDirectoryPattern)
                IncludeFilePattern      = @($IncludeFilePattern)
                Mode                    = $mode
                Disposition             = $disposition
                RecycleBin              = $RecycleBin.IsPresent
                Check                   = $true
                FilesFound              = $filesToDelete.Count
                DirectoriesFound        = $dirsToDelete.Count
                FilesDeleted            = 0
                DirectoriesDeleted      = 0
                FilesFailed             = 0
                DirectoriesFailed       = 0
                BytesFreed              = $totalBytes
                DurationMs              = $stopwatch.ElapsedMilliseconds
                Items                   = @(
                                              @($filesToDelete | ForEach-Object { ConvertTo-DeletionRecord -Type File      -Path $_.FullName -Deleted $false -Size $_.Length }) +
                                              @($dirsToDelete  | ForEach-Object { ConvertTo-DeletionRecord -Type Directory -Path $_.FullName -Deleted $false -Size $dirSizeMap[$_.FullName] })
                                          )
            } | ConvertTo-Json -Depth 5
        }
        else {
            Write-Section 'Artifacts found'
            foreach ($file in $filesToDelete) {
                Write-Detail "  File      : $($file.FullName)"
            }
            foreach ($dir in $dirsToDelete) {
                Write-Detail "  Directory : $($dir.FullName)"
            }

            Write-SummarySection 'Check summary'
            Write-Summary ('Files found      : {0}' -f $filesToDelete.Count)
            Write-Summary ('Directories found: {0}' -f $dirsToDelete.Count)
            Write-Summary ('Space to free    : {0}' -f (Format-ByteSize $totalBytes))
            Write-Summary ('Duration         : {0}' -f (Format-Duration $stopwatch.ElapsedMilliseconds))
        }

        Write-Verbose 'Exit code = 1'
        exit 1
    }

    # Normal clean path
    Write-Section 'Cleaning'
    if (-not $Json) { Write-Progress -Activity 'delphi-clean' -Status "Removing $($filesToDelete.Count) files..." }
    $fileRemovalResult = Remove-FileList      -Files $filesToDelete       -ReturnRecords:$returnRecords -RecycleBin:$RecycleBin
    if (-not $Json) { Write-Progress -Activity 'delphi-clean' -Status "Removing $($dirsToDelete.Count) directories..." }
    $dirRemovalResult  = Remove-DirectoryList -Directories $dirsToDelete  -ReturnRecords:$returnRecords -RecycleBin:$RecycleBin
    if (-not $Json) { Write-Progress -Activity 'delphi-clean' -Completed }

    $allRecords = New-Object System.Collections.Generic.List[object]
    $allRecords.AddRange([object[]]$fileRemovalResult.Records)
    $allRecords.AddRange([object[]]$dirRemovalResult.Records)

    $totalFailed = $fileRemovalResult.FailedCount + $dirRemovalResult.FailedCount

    if ($Json) {
        [PSCustomObject]@{
            Level                   = $Level
            Root                    = $cleanRoot
            ExcludeDirectoryPattern = @($ExcludeDirectoryPattern)
            IncludeFilePattern      = @($IncludeFilePattern)
            Mode                    = $mode
            Disposition             = $disposition
            RecycleBin              = $RecycleBin.IsPresent
            Check                   = $false
            FilesFound              = $filesToDelete.Count
            DirectoriesFound        = $dirsToDelete.Count
            FilesDeleted            = $fileRemovalResult.DeletedCount
            DirectoriesDeleted      = $dirRemovalResult.DeletedCount
            FilesFailed             = $fileRemovalResult.FailedCount
            DirectoriesFailed       = $dirRemovalResult.FailedCount
            BytesFreed              = $totalBytes
            DurationMs              = $stopwatch.ElapsedMilliseconds
            Items                   = $allRecords
        } | ConvertTo-Json -Depth 5
    }
    else {
        $removedLabel = if ($RecycleBin) { 'recycled' } else { 'deleted' }
        Write-SummarySection 'Summary'

        if ($WhatIfPreference) {
            Write-Summary ('{0}: {1}' -f ('Files would be {0}'       -f $removedLabel).PadRight(29), $filesToDelete.Count)
            Write-Summary ('{0}: {1}' -f ('Directories would be {0}' -f $removedLabel).PadRight(29), $dirsToDelete.Count)
            Write-Summary ('{0}: {1}' -f 'Space would free'.PadRight(29), (Format-ByteSize $totalBytes))
            Write-Summary ('{0}: {1}' -f 'Duration'.PadRight(29), (Format-Duration $stopwatch.ElapsedMilliseconds))
        }
        else {
            Write-Summary ('{0}: {1}' -f ('Files {0}'       -f $removedLabel).PadRight(20), $fileRemovalResult.DeletedCount)
            Write-Summary ('{0}: {1}' -f ('Directories {0}' -f $removedLabel).PadRight(20), $dirRemovalResult.DeletedCount)
            Write-Summary ('{0}: {1}' -f 'Space freed'.PadRight(20), (Format-ByteSize $totalBytes))
            Write-Summary ('{0}: {1}' -f 'Duration'.PadRight(20), (Format-Duration $stopwatch.ElapsedMilliseconds))

            if ($totalFailed -gt 0) {
                Write-Warning ('Items failed to {0}: {1}' -f $removedLabel, $totalFailed)
            }
        }
    }

    if ($PassThru -and -not $Json) {
        $allRecords
    }

    # Exit code contract:
    #   0 = success:
    #         normal mode - every matched item was removed
    #         -WhatIf     - dry run completed (nothing removed by design)
    #         -Check      - scan completed, no artifacts found
    #         any mode    - nothing to clean found during scan
    #   1 = dirty (check mode.)  [Validation failures]
    #   2 = Error deleting a file or directory.  [Cleanup failures]
    #   3 = Fatal.  Invalid usage / exceptions (root path, invalid platform)
    if ($totalFailed -gt 0) {
        Write-Verbose 'Exit code = 2'
        exit 2
    }

    Write-Verbose 'Exit code = 0'
    exit 0
}
catch {
    Write-Error -ErrorRecord $_
    Write-Verbose 'Exit code = 3'
    exit 3
}
