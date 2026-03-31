#requires -Version 5.1

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
    [string[]]$ExcludeDirectoryPattern = @(
        '.git',
        '.vs',
        '.claude'
    ),

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

$script:ToolVersion = '0.9.0'

$script:OutputLevel = $OutputLevel

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
        'Linux64',
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

    $allFiles = Get-ChildItem -Path $Root -Recurse -File -Force -ErrorAction SilentlyContinue |
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
        [bool]$Deleted
    )

    [PSCustomObject]@{
        Type    = $Type
        Path    = $Path
        Deleted = $Deleted
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
                    $result.Records.Add((ConvertTo-DeletionRecord -Type File -Path $file.FullName -Deleted $true))
                }
            }
            catch {
                $result.FailedCount++
                Write-Warning "Failed to $($action.ToLower()): $($file.FullName) - $($_.Exception.Message)"

                if ($ReturnRecords) {
                    $result.Records.Add((ConvertTo-DeletionRecord -Type File -Path $file.FullName -Deleted $false))
                }
            }
        }
        elseif ($WhatIfPreference) {
            Write-Detail "Would $($action.ToLower()): $($file.FullName)"
            if ($ReturnRecords) {
                $result.Records.Add((ConvertTo-DeletionRecord -Type File -Path $file.FullName -Deleted $false))
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
                    $result.Records.Add((ConvertTo-DeletionRecord -Type Directory -Path $dir.FullName -Deleted $true))
                }
            }
            catch {
                $result.FailedCount++
                Write-Warning "Failed to $($action.ToLower()): $($dir.FullName) - $($_.Exception.Message)"

                if ($ReturnRecords) {
                    $result.Records.Add((ConvertTo-DeletionRecord -Type Directory -Path $dir.FullName -Deleted $false))
                }
            }
        }
        elseif ($WhatIfPreference) {
            Write-Detail "Would $($action.ToLower()): $($dir.FullName)"
            if ($ReturnRecords) {
                $result.Records.Add((ConvertTo-DeletionRecord -Type Directory -Path $dir.FullName -Deleted $false))
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

    $cleanRoot = Resolve-CleanRoot -InputRoot $RootPath
    Test-SafeCleanRoot -Root $cleanRoot

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

    $filesToDelete = @(Get-FilesToDelete    -Root $cleanRoot -Patterns $allFilePatterns            -ExcludedDirPatterns $ExcludeDirectoryPattern)
    $dirsToDelete  = @(Get-DirectoriesToDelete -Root $cleanRoot -DirectoryNames $definition.DirectoryNames -ExcludedDirPatterns $ExcludeDirectoryPattern)

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
                Items                   = @(
                                              @($filesToDelete | ForEach-Object { ConvertTo-DeletionRecord -Type File      -Path $_.FullName -Deleted $false }) +
                                              @($dirsToDelete  | ForEach-Object { ConvertTo-DeletionRecord -Type Directory -Path $_.FullName -Deleted $false })
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
        }

        Write-Verbose 'Exit code = 1'
        exit 1
    }

    # Normal clean path
    Write-Section 'Cleaning'
    $fileRemovalResult = Remove-FileList      -Files $filesToDelete       -ReturnRecords:$returnRecords -RecycleBin:$RecycleBin
    $dirRemovalResult  = Remove-DirectoryList -Directories $dirsToDelete  -ReturnRecords:$returnRecords -RecycleBin:$RecycleBin

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
            Items                   = $allRecords
        } | ConvertTo-Json -Depth 5
    }
    else {
        $removedLabel = if ($RecycleBin) { 'recycled' } else { 'deleted' }
        Write-SummarySection 'Summary'

        if ($WhatIfPreference) {
            Write-Summary ('Files would be {0}     : {1}' -f $removedLabel, $filesToDelete.Count)
            Write-Summary ('Directories would be {0}: {1}' -f $removedLabel, $dirsToDelete.Count)
        }
        else {
            Write-Summary ('Files {0}               : {1}' -f $removedLabel, $fileRemovalResult.DeletedCount)
            Write-Summary ('Directories {0}         : {1}' -f $removedLabel, $dirRemovalResult.DeletedCount)

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
