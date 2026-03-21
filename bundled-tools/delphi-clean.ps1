#requires -Version 5.1

<#
.SYNOPSIS
Cleans Delphi build artifacts from a repository tree using three cleanup levels.

.DESCRIPTION
Runs from the tools location and targets the parent directory by default.
Supports three cleanup levels:

  lite  - safe, low-risk cleanup of common transient files
  build - removes build outputs and common generated files
  full  - aggressive cleanup including user-local IDE state files

.EXAMPLE
powershell.exe -File .\delphi-clean.ps1

.EXAMPLE
powershell.exe -File .\delphi-clean.ps1 -Level build

.EXAMPLE
powershell.exe -File .\delphi-clean.ps1 -Level full -Verbose

.EXAMPLE
powershell.exe -File .\delphi-clean.ps1 -Level full -WhatIf

.EXAMPLE
powershell.exe -File .\delphi-clean.ps1 -Level build -PassThru

.EXAMPLE
powershell.exe -File .\delphi-clean.ps1 -Level build -Json

.EXAMPLE
powershell.exe -File .\delphi-clean.ps1 -Level lite -IncludeFilePattern '*.res'

.EXAMPLE
powershell.exe -File .\delphi-clean.ps1 -Level lite -IncludeFilePattern '*.res','*.mab' -ExcludeDirPattern 'assets','vendor*'

.EXAMPLE
powershell.exe -File .\delphi-clean.ps1 -Version

.EXAMPLE
powershell.exe -File .\delphi-clean.ps1 -Version -Format json
#>

[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Clean')]
param(
    [Parameter(ParameterSetName = 'Version', Mandatory)]
    [switch]$Version,

    [Parameter(ParameterSetName = 'Version')]
    [ValidateSet('text', 'json')]
    [string]$Format = 'text',

    [Parameter(ParameterSetName = 'Clean')]
    [ValidateSet('lite', 'build', 'full')]
    [string]$Level = 'lite',

    [Parameter(ParameterSetName = 'Clean')]
    [string]$RootPath,

    [Parameter(ParameterSetName = 'Clean')]
    [string[]]$ExcludeDirectories = @(
        '.git',
        '.vs',
        '.claude'
    ),

    [Parameter(ParameterSetName = 'Clean')]
    [string[]]$IncludeFilePattern = @(),

    [Parameter(ParameterSetName = 'Clean')]
    [string[]]$ExcludeDirPattern = @(),

    [Parameter(ParameterSetName = 'Clean')]
    [switch]$PassThru,

    [Parameter(ParameterSetName = 'Clean')]
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ToolVersion = '0.4.0'

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

function Write-Section {
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    if ($Json) {
        return
    }

    Write-Information '' -InformationAction Continue
    Write-Information ('=' * 70) -InformationAction Continue
    Write-Information $Message -InformationAction Continue
    Write-Information ('=' * 70) -InformationAction Continue
}

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
        $scriptDir = Split-Path -Parent $PSCommandPath
        $resolved = Resolve-Path (Join-Path $scriptDir '..')
        return $resolved.Path
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

    if ($fullRoot.TrimEnd([char[]]@('\','/')).Length -lt 4) {
        throw "Refusing to clean an unsafe root path: $fullRoot"
    }
}

function Test-PathUnderExcludedDirectory {
    param(
        [Parameter(Mandatory)]
        [string]$FullName,

        [Parameter(Mandatory)]
        [string]$Root,

        [Parameter(Mandatory)]
        [string[]]$ExcludedDirectoryNames,

        [string[]]$ExcludedDirPatterns = @()
    )

    $relative = Get-RelativePathCompat -BasePath $Root -TargetPath $FullName

    if ($relative -eq '.') {
        return $false
    }

    $parts = $relative -split '[\\/]'
    foreach ($part in $parts) {
        if ($ExcludedDirectoryNames -icontains $part) {
            return $true
        }
        foreach ($pattern in $ExcludedDirPatterns) {
            if ($part -ilike $pattern) {
                return $true
            }
        }
    }

    return $false
}

function Get-LevelDefinition {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('lite', 'build', 'full')]
        [string]$Name
    )

    # --- base (lite) ---
    $liteFiles = @(
        '*.dcu',
        '*.identcache',
        '*.bak',
        '*.tmp',
        '*.dsk',
        '*.tvsconfig',
        '*.stat'
    )

    $liteDirs = @(
        '__history'
    )

    # --- build additions ---
    $buildFilesExtra = @(
        '*.local',
        '*.dproj.local',
        '*.groupproj.local',
        '*.projdata',
        '*.drc',
        '*.map',
        '*.rsm',
        '*.tds',
        '*.bpl',
        '*.dcp',
        '*.bpi',
        '*.so',
        '*.dll',
        '*.exe',
        '*.obj',
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

    $buildDirsExtra = @(
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

    # --- full additions ---
    $fullFilesExtra = @(
        '*.~*',
        '*.lib',
        '*.fbpInf',
        '*.fbl8',
        '*.fbpbrk',
        '*.fb8lck',
        'TestInsightSettings.ini'
    )

    $fullDirsExtra = @(
        '__recovery'
    )

    # --- compose ---
    switch ($Name) {
        'lite' {
            $files = $liteFiles
            $dirs  = $liteDirs
        }

        'build' {
            $files = $liteFiles + $buildFilesExtra
            $dirs  = $liteDirs + $buildDirsExtra
        }

        'full' {
            $files = $liteFiles + $buildFilesExtra + $fullFilesExtra
            $dirs  = $liteDirs + $buildDirsExtra + $fullDirsExtra
        }
    }

    # --- dedupe ---
    $files = $files | Sort-Object -Unique
    $dirs  = $dirs  | Sort-Object -Unique

    return @{
        FilePatterns  = $files
        DirectoryNames = $dirs
    }
}

function Get-FilesToDelete {
    param(
        [Parameter(Mandatory)]
        [string]$Root,

        [Parameter(Mandatory)]
        [string[]]$Patterns,

        [Parameter(Mandatory)]
        [string[]]$ExcludedDirectoryNames,

        [string[]]$ExcludedDirPatterns = @()
    )

    Write-Verbose 'Scanning for matching files.'

    $allFiles = Get-ChildItem -Path $Root -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object {
            -not (Test-PathUnderExcludedDirectory -FullName $_.FullName -Root $Root -ExcludedDirectoryNames $ExcludedDirectoryNames -ExcludedDirPatterns $ExcludedDirPatterns)
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
        [string[]]$ExcludedDirectoryNames,

        [string[]]$ExcludedDirPatterns = @()
    )

    Write-Verbose 'Scanning for matching directories.'

    $nameSet = @{}
    foreach ($dirName in $DirectoryNames) {
        $nameSet[$dirName.ToUpperInvariant()] = $true
    }

    Get-ChildItem -Path $Root -Recurse -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object {
            $nameSet.ContainsKey($_.Name.ToUpperInvariant()) -and
            -not (Test-PathUnderExcludedDirectory -FullName $_.FullName -Root $Root -ExcludedDirectoryNames $ExcludedDirectoryNames -ExcludedDirPatterns $ExcludedDirPatterns)
        } |
        Sort-Object -Property FullName -Unique |
        Sort-Object -Property { $_.FullName.Length } -Descending
}

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

function Remove-FileList {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [System.IO.FileInfo[]]$Files = @(),
        [switch]$ReturnRecords
    )

    $result = [PSCustomObject]@{
        DeletedCount = 0
        Records      = New-Object System.Collections.Generic.List[object]
    }

    if (@($Files).Count -eq 0) {
        return $result
    }

    foreach ($file in $Files) {
        Write-Verbose "Evaluating file: $($file.FullName)"

        if ($PSCmdlet.ShouldProcess($file.FullName, 'Delete file')) {
            try {
                Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
                $result.DeletedCount++
                Write-Information "Deleted file: $($file.FullName)" -InformationAction Continue

                if ($ReturnRecords) {
                    $result.Records.Add((ConvertTo-DeletionRecord -Type File -Path $file.FullName -Deleted $true))
                }
            }
            catch {
                Write-Warning "Failed to delete file: $($file.FullName)"
                Write-Error -ErrorRecord $_
            }
        }
        elseif ($ReturnRecords -and $WhatIfPreference) {
            $result.Records.Add((ConvertTo-DeletionRecord -Type File -Path $file.FullName -Deleted $false))
        }
    }

    return $result
}

function Remove-DirectoryList {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [System.IO.DirectoryInfo[]]$Directories = @(),
        [switch]$ReturnRecords
    )

    $result = [PSCustomObject]@{
        DeletedCount = 0
        Records      = New-Object System.Collections.Generic.List[object]
    }

    if (@($Directories).Count -eq 0) {
        return $result
    }

    foreach ($dir in $Directories) {
        if (-not (Test-Path -LiteralPath $dir.FullName)) {
            continue
        }

        Write-Verbose "Evaluating directory: $($dir.FullName)"

        if ($PSCmdlet.ShouldProcess($dir.FullName, 'Delete directory')) {
            try {
                Remove-Item -LiteralPath $dir.FullName -Recurse -Force -ErrorAction Stop
                $result.DeletedCount++
                Write-Information "Deleted directory: $($dir.FullName)" -InformationAction Continue

                if ($ReturnRecords) {
                    $result.Records.Add((ConvertTo-DeletionRecord -Type Directory -Path $dir.FullName -Deleted $true))
                }
            }
            catch {
                Write-Warning "Failed to delete directory: $($dir.FullName)"
                Write-Error -ErrorRecord $_
            }
        }
        elseif ($ReturnRecords -and $WhatIfPreference) {
            $result.Records.Add((ConvertTo-DeletionRecord -Type Directory -Path $dir.FullName -Deleted $false))
        }
    }

    return $result
}

try {
    $cleanRoot = Resolve-CleanRoot -InputRoot $RootPath
    Test-SafeCleanRoot -Root $cleanRoot

    $definition = Get-LevelDefinition -Name $Level
    $mode = if ($WhatIfPreference) { 'WhatIf (no changes)' } else { 'Execute' }
    $returnRecords = ($PassThru -or $Json)

    $allFilePatterns = @($definition.FilePatterns) + @($IncludeFilePattern) | Sort-Object -Unique

    Write-Section 'Delphi Clean'

    if (-not $Json) {
        Write-Information ('Level           : {0}' -f $Level) -InformationAction Continue
        Write-Information ('Root            : {0}' -f $cleanRoot) -InformationAction Continue
        Write-Information ('Excluded dirs   : {0}' -f ($ExcludeDirectories -join ', ')) -InformationAction Continue
        if ($ExcludeDirPattern.Count -gt 0) {
            Write-Information ('Excl dir patterns: {0}' -f ($ExcludeDirPattern -join ', ')) -InformationAction Continue
        }
        if ($IncludeFilePattern.Count -gt 0) {
            Write-Information ('Extra patterns  : {0}' -f ($IncludeFilePattern -join ', ')) -InformationAction Continue
        }
        Write-Information ('Mode            : {0}' -f $mode) -InformationAction Continue
    }

    $filesToDelete = @(Get-FilesToDelete -Root $cleanRoot -Patterns $allFilePatterns -ExcludedDirectoryNames $ExcludeDirectories -ExcludedDirPatterns $ExcludeDirPattern)
    $dirsToDelete  = @(Get-DirectoriesToDelete -Root $cleanRoot -DirectoryNames $definition.DirectoryNames -ExcludedDirectoryNames $ExcludeDirectories -ExcludedDirPatterns $ExcludeDirPattern)

    if (-not $Json) {
        Write-Information '' -InformationAction Continue
        Write-Information ('Files found      : {0}' -f $filesToDelete.Count) -InformationAction Continue
        Write-Information ('Directories found: {0}' -f $dirsToDelete.Count) -InformationAction Continue
    }

    if (($filesToDelete.Count -eq 0) -and ($dirsToDelete.Count -eq 0)) {

        if ($Json) {
            [PSCustomObject]@{
                Level               = $Level
                Root                = $cleanRoot
                ExcludedDirectories = @($ExcludeDirectories)
                ExcludeDirPattern   = @($ExcludeDirPattern)
                IncludeFilePattern  = @($IncludeFilePattern)
                Mode                = $mode
                FilesFound          = 0
                DirectoriesFound    = 0
                FilesDeleted        = 0
                DirectoriesDeleted  = 0
                Items               = @()
            } | ConvertTo-Json -Depth 5
        }
        else {
            Write-Information '' -InformationAction Continue
            Write-Information 'Nothing to clean.' -InformationAction Continue
        }

        exit 0
    }

    Write-Section 'Cleaning'
    $fileRemovalResult = Remove-FileList -Files $filesToDelete -ReturnRecords:$returnRecords
    $dirRemovalResult  = Remove-DirectoryList -Directories $dirsToDelete -ReturnRecords:$returnRecords

    #$allRecords = @($fileRemovalResult.Records) + @($dirRemovalResult.Records)
    $allRecords = New-Object System.Collections.Generic.List[object]
    $allRecords.AddRange([object[]]$fileRemovalResult.Records)
    $allRecords.AddRange([object[]]$dirRemovalResult.Records)

    if ($Json) {
        [PSCustomObject]@{
            Level               = $Level
            Root                = $cleanRoot
            ExcludedDirectories = @($ExcludeDirectories)
            ExcludeDirPattern   = @($ExcludeDirPattern)
            IncludeFilePattern  = @($IncludeFilePattern)
            Mode                = $mode
            FilesFound          = $filesToDelete.Count
            DirectoriesFound    = $dirsToDelete.Count
            FilesDeleted        = $fileRemovalResult.DeletedCount
            DirectoriesDeleted  = $dirRemovalResult.DeletedCount
            Items               = $allRecords
        } | ConvertTo-Json -Depth 5
    }
    else {
        Write-Section 'Summary'
        Write-Information ('Files deleted      : {0}' -f $fileRemovalResult.DeletedCount) -InformationAction Continue
        Write-Information ('Directories deleted: {0}' -f $dirRemovalResult.DeletedCount) -InformationAction Continue
    }

    if ($PassThru -and -not $Json) {
        $allRecords
    }

    exit 0
}
catch {
    Write-Error -ErrorRecord $_
    exit 1
}
