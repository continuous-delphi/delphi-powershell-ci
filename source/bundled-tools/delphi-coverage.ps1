#requires -Version 5.1
# -----------------------------------------------------------------------------
# delphi-coverage
#
# Code coverage orchestrator for Delphi projects. Wraps coverage engines
# (DelphiCodeCoverage, radCodeCoverage) behind a unified interface with
# structured output, threshold enforcement, and badge generation.
#
# Part of Continuous-Delphi: Strengthening Delphi's continued success
# https://github.com/continuous-delphi
#
# Project repository:
# https://github.com/continuous-delphi/delphi-coverage
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
Runs Delphi code coverage analysis using a pluggable engine.

.DESCRIPTION
Orchestrates a coverage engine (DelphiCodeCoverage by default) to run a
Delphi test executable with code coverage instrumentation. Produces
coverage reports in multiple formats, enforces coverage thresholds, and
optionally generates coverage badges.

Exit codes:
  0  success (threshold met or no threshold set)
  1  unexpected error
  2  invalid arguments
  3  engine executable not found
  4  test executable or MAP file not found
  5  coverage run failed (engine exited non-zero)
  6  threshold not met

.EXAMPLE
./delphi-coverage.ps1 -Execute test\Win32\Debug\MyApp.Tests.exe -MapFile test\Win32\Debug\MyApp.Tests.map -SourceDir source\

.EXAMPLE
./delphi-coverage.ps1 -Execute test.exe -MapFile test.map -SourceDir source\ -Units 'MyApp.*' -Threshold 60

.EXAMPLE
./delphi-coverage.ps1 -Execute test.exe -MapFile test.map -SourceDir source\ -Badge docs/coverage-badge.svg

.EXAMPLE
./delphi-coverage.ps1 -Version -Format json
#>

[CmdletBinding()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
  Justification='Write-Host is intentional: standalone CLI tool streams status to the console host.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'OutputFile',
  Justification='OutputFile is consumed inside the Write-Result helper function.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
  Justification='New-CoverageBadge* are file-writing helpers; state change is intentional and controlled by the caller.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', 'Get-CoverageStats',
  Justification='Stats is a conventional abbreviation for statistics, not a plural noun.')]
param(
    [Parameter(ParameterSetName = 'Version', Mandatory)]
    [switch]$Version,

    [Parameter(ParameterSetName = 'Version')]
    [ValidateSet('text', 'json')]
    [string]$Format = 'text',

    [Parameter(ParameterSetName = 'Coverage', Mandatory)]
    [string]$Execute,

    [Parameter(ParameterSetName = 'Coverage', Mandatory)]
    [string]$MapFile,

    [Parameter(ParameterSetName = 'Dproj', Mandatory)]
    [string]$Dproj,

    [Parameter(ParameterSetName = 'Coverage')]
    [Parameter(ParameterSetName = 'Dproj')]
    [ValidateSet('DelphiCodeCoverage', 'radCodeCoverage')]
    [string]$Engine = 'DelphiCodeCoverage',

    [Parameter(ParameterSetName = 'Coverage')]
    [Parameter(ParameterSetName = 'Dproj')]
    [string]$EnginePath,

    [Parameter(ParameterSetName = 'Coverage')]
    [Parameter(ParameterSetName = 'Dproj')]
    [string]$SourceDir = '',

    [Parameter(ParameterSetName = 'Coverage')]
    [Parameter(ParameterSetName = 'Dproj')]
    [string]$Units = '',

    [Parameter(ParameterSetName = 'Coverage')]
    [Parameter(ParameterSetName = 'Dproj')]
    [string]$ExcludeUnits = '',

    [Parameter(ParameterSetName = 'Coverage')]
    [Parameter(ParameterSetName = 'Dproj')]
    [string]$OutputDir = 'coverage',

    [Parameter(ParameterSetName = 'Coverage')]
    [Parameter(ParameterSetName = 'Dproj')]
    [string]$Formats = 'html',

    [Parameter(ParameterSetName = 'Coverage')]
    [Parameter(ParameterSetName = 'Dproj')]
    [int]$Threshold = 0,

    # Test arguments can be passed via this parameter (comma-separated)
    # or via the DELPHI_COVERAGE_ARGS environment variable (used by the
    # CI module wrapper to avoid -File mode parsing issues with values
    # that start with '-').
    [Parameter(ParameterSetName = 'Coverage')]
    [Parameter(ParameterSetName = 'Dproj')]
    [string]$Arguments = '',

    [Parameter(ParameterSetName = 'Coverage')]
    [Parameter(ParameterSetName = 'Dproj')]
    [int]$TimeoutSeconds = 300,

    [Parameter(ParameterSetName = 'Coverage')]
    [Parameter(ParameterSetName = 'Dproj')]
    [string]$Badge,

    [Parameter(ParameterSetName = 'Coverage')]
    [Parameter(ParameterSetName = 'Dproj')]
    [string]$OutputFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExitSuccess          = 0
$ExitUnexpectedError  = 1
$ExitInvalidArguments = 2
$ExitEngineNotFound   = 3
$ExitFileNotFound     = 4
$ExitCoverageFailed   = 5
$ExitThresholdNotMet  = 6

$script:ToolVersion = '1.0.0'

# -----------------------------------------------------------------------------
# Version info
# -----------------------------------------------------------------------------

if ($Version) {
    $info = @{ tool = @{ name = 'delphi-coverage'; version = $script:ToolVersion } }
    if ($Format -eq 'json') {
        Write-Output ($info | ConvertTo-Json -Depth 5 -Compress)
    }
    else {
        Write-Host "delphi-coverage $($script:ToolVersion)"
    }
    exit $ExitSuccess
}

# -----------------------------------------------------------------------------
# Engine: DelphiCodeCoverage
# -----------------------------------------------------------------------------

function Find-DelphiCodeCoverage {
    <#
    .SYNOPSIS
        Locates the DelphiCodeCoverage executable.
    #>
    param([string]$ExplicitPath)

    if (-not [string]::IsNullOrEmpty($ExplicitPath)) {
        if (Test-Path -LiteralPath $ExplicitPath -PathType Leaf) {
            return $ExplicitPath
        }
        # ExplicitPath may be a bare filename -- try PATH lookup
        $found = Get-Command $ExplicitPath -ErrorAction SilentlyContinue
        if ($null -ne $found) {
            return $found.Source
        }
        return $null
    }

    # Search PATH for CodeCoverage.exe
    $found = Get-Command 'CodeCoverage.exe' -ErrorAction SilentlyContinue
    if ($null -ne $found) {
        return $found.Source
    }

    return $null
}

function Find-RadCodeCoverage {
    <#
    .SYNOPSIS
        Locates the radCodeCoverage executable.
    #>
    param([string]$ExplicitPath)

    if (-not [string]::IsNullOrEmpty($ExplicitPath)) {
        if (Test-Path -LiteralPath $ExplicitPath -PathType Leaf) {
            return $ExplicitPath
        }
        $found = Get-Command $ExplicitPath -ErrorAction SilentlyContinue
        if ($null -ne $found) {
            return $found.Source
        }
        return $null
    }

    # Search PATH for radCodeCoverage.exe
    $found = Get-Command 'radCodeCoverage.exe' -ErrorAction SilentlyContinue
    if ($null -ne $found) {
        return $found.Source
    }

    return $null
}

function Invoke-DelphiCodeCoverageEngine {
    <#
    .SYNOPSIS
        Builds and executes the DelphiCodeCoverage command line.
    #>
    param(
        [string]$EngineBinary,
        [string]$TestExecutable,
        [string]$TestMapFile,
        [string[]]$CoverageSourceDir = @(),
        [string[]]$CoverageUnits,
        [string[]]$CoverageExcludeUnits,
        [string]$CoverageOutputDir,
        [string[]]$CoverageFormats,
        [string[]]$TestArguments,
        [int]$CoverageTimeout
    )

    $engineArgs = [System.Collections.Generic.List[string]]::new()
    $engineArgs.Add('-e')
    $engineArgs.Add($TestExecutable)
    $engineArgs.Add('-m')
    $engineArgs.Add($TestMapFile)

    foreach ($sp in $CoverageSourceDir) {
        if (-not [string]::IsNullOrEmpty($sp)) {
            $engineArgs.Add('-sp')
            $engineArgs.Add($sp)
        }
    }

    foreach ($u in $CoverageUnits) {
        $engineArgs.Add('-u')
        $engineArgs.Add($u)
    }
    foreach ($eu in $CoverageExcludeUnits) {
        $engineArgs.Add('-uf')
        $engineArgs.Add($eu)
    }

    $engineArgs.Add('-od')
    $engineArgs.Add($CoverageOutputDir)

    # Always produce XML for internal stats parsing
    $xmlRequested = $false
    foreach ($fmt in $CoverageFormats) {
        switch ($fmt.ToLower()) {
            'html'      { $engineArgs.Add('-html') }
            'xml'       { $engineArgs.Add('-xml'); $xmlRequested = $true }
            'emma'      { $engineArgs.Add('-emma') }
            'lcov'      { $engineArgs.Add('-lcov') }
            'cobertura' { $engineArgs.Add('-xml'); $engineArgs.Add('-xmllines'); $xmlRequested = $true }
            'md'        { $engineArgs.Add('-md') }
            'covdb'     { $engineArgs.Add('-covdb') }
        }
    }
    if (-not $xmlRequested) {
        $engineArgs.Add('-xml')
    }

    if ($TestArguments.Count -gt 0) {
        ### Skip escaping as a test
        ### # CodeCoverage uses ^ as escape character for arguments.
        ### # Prefix - with ^ so -b becomes ^-b, --cm:off becomes ^-^-cm:off
        ### $escaped = $TestArguments | ForEach-Object { $_ -replace '-', '^-' }
        ### $engineArgs.Add("-a `"$($escaped -join ' ')`"")
        $engineArgs.Add("-a `"$($TestArguments -join ' ')`"")
    }

    # Ensure output directory exists
    if (-not (Test-Path -LiteralPath $CoverageOutputDir -PathType Container)) {
        New-Item -Path $CoverageOutputDir -ItemType Directory -Force | Out-Null
    }

    Write-Host "Engine: $EngineBinary"
    $argsString = $engineArgs -join ' '
    Write-Host "Args: $argsString"

    $workDir = [System.IO.Path]::GetDirectoryName($TestExecutable)
    $proc = Start-Process -FilePath $EngineBinary `
        -ArgumentList $argsString `
        -WorkingDirectory $workDir `
        -NoNewWindow -PassThru -Wait:$false
    $exited = $proc.WaitForExit($CoverageTimeout * 1000)
    if (-not $exited) {
        try { $proc.Kill() } catch { Write-Verbose "Process already exited: $_" }
        return @{
            Success  = $false
            ExitCode = -1
            Message  = "Coverage engine timed out after ${CoverageTimeout}s"
        }
    }

    return @{
        Success  = ($proc.ExitCode -eq 0)
        ExitCode = $proc.ExitCode
        Message  = if ($proc.ExitCode -eq 0) { 'Coverage engine completed' } else { "Engine exited with code $($proc.ExitCode)" }
    }
}

function Invoke-CoverageEngineDproj {
    <#
    .SYNOPSIS
        Invokes a coverage engine using -dproj mode (radCodeCoverage).
        The engine auto-discovers exe, map, units, and source paths.
    #>
    param(
        [string]$EngineBinary,
        [string]$DprojFile,
        [string[]]$CoverageSourceDir = @(),
        [string[]]$CoverageUnits,
        [string[]]$CoverageExcludeUnits,
        [string]$CoverageOutputDir,
        [string[]]$CoverageFormats,
        [string[]]$TestArguments,
        [int]$CoverageTimeout
    )

    $engineArgs = [System.Collections.Generic.List[string]]::new()
    $engineArgs.Add('-dproj')
    $engineArgs.Add($DprojFile)

    foreach ($sp in $CoverageSourceDir) {
        if (-not [string]::IsNullOrEmpty($sp)) {
            $engineArgs.Add('-sp')
            $engineArgs.Add($sp)
        }
    }

    foreach ($u in $CoverageUnits) {
        $engineArgs.Add('-u')
        $engineArgs.Add($u)
    }
    foreach ($eu in $CoverageExcludeUnits) {
        $engineArgs.Add('-uf')
        $engineArgs.Add($eu)
    }

    $engineArgs.Add('-od')
    $engineArgs.Add($CoverageOutputDir)

    # Always produce XML for internal stats parsing
    $xmlRequested = $false
    foreach ($fmt in $CoverageFormats) {
        switch ($fmt.ToLower()) {
            'html'      { $engineArgs.Add('-html') }
            'xml'       { $engineArgs.Add('-xml'); $xmlRequested = $true }
            'emma'      { $engineArgs.Add('-emma') }
            'lcov'      { $engineArgs.Add('-lcov') }
            'cobertura' { $engineArgs.Add('-xml'); $engineArgs.Add('-xmllines'); $xmlRequested = $true }
            'md'        { $engineArgs.Add('-md') }
            'covdb'     { $engineArgs.Add('-covdb') }
        }
    }
    if (-not $xmlRequested) {
        $engineArgs.Add('-xml')
    }

    if ($TestArguments.Count -gt 0) {
        $engineArgs.Add("-a `"$($TestArguments -join ' ')`"")
    }

    # Ensure output directory exists
    if (-not (Test-Path -LiteralPath $CoverageOutputDir -PathType Container)) {
        New-Item -Path $CoverageOutputDir -ItemType Directory -Force | Out-Null
    }

    Write-Host "Engine: $EngineBinary"
    $argsString = $engineArgs -join ' '
    Write-Host "Args: $argsString"

    $workDir = [System.IO.Path]::GetDirectoryName($DprojFile)
    $proc = Start-Process -FilePath $EngineBinary `
        -ArgumentList $argsString `
        -WorkingDirectory $workDir `
        -NoNewWindow -PassThru -Wait:$false
    $exited = $proc.WaitForExit($CoverageTimeout * 1000)
    if (-not $exited) {
        try { $proc.Kill() } catch { Write-Verbose "Process already exited: $_" }
        return @{
            Success  = $false
            ExitCode = -1
            Message  = "Coverage engine timed out after ${CoverageTimeout}s"
        }
    }

    return @{
        Success  = ($proc.ExitCode -eq 0)
        ExitCode = $proc.ExitCode
        Message  = if ($proc.ExitCode -eq 0) { 'Coverage engine completed' } else { "Engine exited with code $($proc.ExitCode)" }
    }
}

# -----------------------------------------------------------------------------
# Coverage report parsing
# -----------------------------------------------------------------------------

function Get-CoverageFromLcov {
    <#
    .SYNOPSIS
        Parses coverage statistics from an LCOV file.
        Counts DA: lines to determine covered vs total.
    #>
    param([string]$FilePath)

    $total   = 0
    $covered = 0
    foreach ($line in (Get-Content -LiteralPath $FilePath)) {
        if ($line -match '^DA:\d+,(\d+)') {
            $total++
            if ([int]$Matches[1] -gt 0) { $covered++ }
        }
    }

    if ($total -eq 0) { return $null }
    return @{
        CoveragePercent = [math]::Round(($covered / $total) * 100, 1)
        LinesCovered    = $covered
        LinesTotal      = $total
    }
}

function Get-CoverageStats {
    <#
    .SYNOPSIS
        Parses coverage statistics from report files in the output directory.
        Supports LCOV, Cobertura, and DelphiCodeCoverage XML formats.
    #>
    param([string]$CoverageOutputDir)

    # Try LCOV format (*.lcov or *.info)
    $lcovFiles = @(Get-ChildItem -Path $CoverageOutputDir -Include '*.lcov','*.info' -File -ErrorAction SilentlyContinue)
    foreach ($lf in $lcovFiles) {
        $result = Get-CoverageFromLcov -FilePath $lf.FullName
        if ($null -ne $result) { return $result }
    }

    # Try Cobertura format (coverage.xml with line-rate attribute)
    $coberturaFile = Join-Path $CoverageOutputDir 'coverage.xml'
    if (Test-Path -LiteralPath $coberturaFile -PathType Leaf) {
        $xml = [xml](Get-Content -LiteralPath $coberturaFile -Raw)
        if ($null -ne $xml.coverage) {
            $lineRate = [double]$xml.coverage.'line-rate'
            $linesValid = [int]$xml.coverage.'lines-valid'
            $linesCovered = [int]($lineRate * $linesValid)
            return @{
                CoveragePercent = [math]::Round($lineRate * 100, 1)
                LinesCovered    = $linesCovered
                LinesTotal      = $linesValid
            }
        }
    }

    # Try DelphiCodeCoverage XML format (CodeCoverage_Summary.xml)
    $dccXmlFile = Join-Path $CoverageOutputDir 'CodeCoverage_Summary.xml'
    if (Test-Path -LiteralPath $dccXmlFile -PathType Leaf) {
        $xml = [xml](Get-Content -LiteralPath $dccXmlFile -Raw)
        $stats = $xml.SelectSingleNode('//stats')
        if ($null -ne $stats) {
            $covered = [int]$stats.coveredlines.value
            $total   = [int]$stats.totallines.value
            $pct     = if ($total -gt 0) { [math]::Round(($covered / $total) * 100, 1) } else { 0 }
            return @{
                CoveragePercent = $pct
                LinesCovered    = $covered
                LinesTotal      = $total
            }
        }
    }

    # Fallback: scan for any XML with coverage data
    $xmlFiles = @(Get-ChildItem -Path $CoverageOutputDir -Filter '*.xml' -File -ErrorAction SilentlyContinue)
    foreach ($xf in $xmlFiles) {
        try {
            $xml = [xml](Get-Content -LiteralPath $xf.FullName -Raw)
            # Cobertura
            if ($null -ne $xml.coverage -and $null -ne $xml.coverage.'line-rate') {
                $lineRate = [double]$xml.coverage.'line-rate'
                $linesValid = [int]$xml.coverage.'lines-valid'
                $linesCovered = [int]($lineRate * $linesValid)
                return @{
                    CoveragePercent = [math]::Round($lineRate * 100, 1)
                    LinesCovered    = $linesCovered
                    LinesTotal      = $linesValid
                }
            }
        }
        catch { Write-Verbose "Failed to parse $($xf.Name): $_" }
    }

    return $null
}

# -----------------------------------------------------------------------------
# Badge generation
# -----------------------------------------------------------------------------

function Get-BadgeColor {
    param([double]$Percent)
    if ($Percent -ge 80) { return '#4c1' }       # green
    if ($Percent -ge 60) { return '#dfb317' }     # yellow
    return '#e05d44'                               # red
}

function New-CoverageBadgeSvg {
    <#
    .SYNOPSIS
        Generates a self-contained SVG coverage badge.
    #>
    param(
        [double]$Percent,
        [string]$OutputPath
    )

    $color = Get-BadgeColor $Percent
    $label = 'coverage'
    $message = "$([math]::Floor($Percent))%"
    $labelWidth = 62
    $messageWidth = 46
    $totalWidth = $labelWidth + $messageWidth

    $svg = @"
<svg xmlns="http://www.w3.org/2000/svg" width="$totalWidth" height="20">
  <linearGradient id="b" x2="0" y2="100%">
    <stop offset="0" stop-color="#bbb" stop-opacity=".1"/>
    <stop offset="1" stop-opacity=".1"/>
  </linearGradient>
  <clipPath id="a">
    <rect width="$totalWidth" height="20" rx="3" fill="#fff"/>
  </clipPath>
  <g clip-path="url(#a)">
    <rect width="$labelWidth" height="20" fill="#555"/>
    <rect x="$labelWidth" width="$messageWidth" height="20" fill="$color"/>
    <rect width="$totalWidth" height="20" fill="url(#b)"/>
  </g>
  <g fill="#fff" text-anchor="middle" font-family="DejaVu Sans,Verdana,Geneva,sans-serif" font-size="11">
    <text x="$($labelWidth / 2)" y="15" fill="#010101" fill-opacity=".3">$label</text>
    <text x="$($labelWidth / 2)" y="14">$label</text>
    <text x="$($labelWidth + $messageWidth / 2)" y="15" fill="#010101" fill-opacity=".3">$message</text>
    <text x="$($labelWidth + $messageWidth / 2)" y="14">$message</text>
  </g>
</svg>
"@

    $parentDir = [System.IO.Path]::GetDirectoryName($OutputPath)
    if (-not [string]::IsNullOrEmpty($parentDir) -and
        -not (Test-Path -LiteralPath $parentDir -PathType Container)) {
        New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
    }
    Set-Content -LiteralPath $OutputPath -Value $svg -NoNewline -Encoding UTF8
}

function New-CoverageBadgeJson {
    <#
    .SYNOPSIS
        Generates a Shields.io endpoint JSON file for dynamic badges.
    #>
    param(
        [double]$Percent,
        [string]$OutputPath
    )

    $colorName = if ($Percent -ge 80) { 'green' } elseif ($Percent -ge 60) { 'yellow' } else { 'red' }
    $badge = @{
        schemaVersion = 1
        label         = 'coverage'
        message       = "$([math]::Floor($Percent))%"
        color         = $colorName
    }

    $parentDir = [System.IO.Path]::GetDirectoryName($OutputPath)
    if (-not [string]::IsNullOrEmpty($parentDir) -and
        -not (Test-Path -LiteralPath $parentDir -PathType Container)) {
        New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
    }
    $json = $badge | ConvertTo-Json -Depth 5 -Compress
    Set-Content -LiteralPath $OutputPath -Value $json -NoNewline -Encoding UTF8
}

function New-CoverageBadge {
    <#
    .SYNOPSIS
        Generates a coverage badge file. Format determined by extension.
    #>
    param(
        [double]$Percent,
        [string]$OutputPath
    )

    $ext = [System.IO.Path]::GetExtension($OutputPath).ToLower()
    switch ($ext) {
        '.svg'  { New-CoverageBadgeSvg  -Percent $Percent -OutputPath $OutputPath }
        '.json' { New-CoverageBadgeJson -Percent $Percent -OutputPath $OutputPath }
        default { New-CoverageBadgeSvg  -Percent $Percent -OutputPath $OutputPath }
    }
}

# -----------------------------------------------------------------------------
# Result output
# -----------------------------------------------------------------------------

function Write-Result {
    param([hashtable]$Result)
    if (-not [string]::IsNullOrEmpty($OutputFile)) {
        $json = $Result | ConvertTo-Json -Depth 5 -Compress
        Set-Content -LiteralPath $OutputFile -Value $json -Encoding UTF8
    }
}

# -----------------------------------------------------------------------------
# MAP file validation
# -----------------------------------------------------------------------------

function Test-DetailedMapFile {
    <#
    .SYNOPSIS
        Validates that a MAP file contains detailed line number information.
    #>
    param([string]$Path)

    $content = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    return $content -match 'Line numbers for'
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$useDproj = $PSCmdlet.ParameterSetName -eq 'Dproj'
$displayTarget = if ($useDproj) { $Dproj } else { $Execute }

try {
    if ($useDproj) {
        # Validate .dproj file
        if (-not (Test-Path -LiteralPath $Dproj -PathType Leaf)) {
            Write-Error "Dproj file not found: $Dproj" -ErrorAction Continue
            Write-Result @{ dproj = $Dproj; error = "Dproj file not found" }
            exit $ExitFileNotFound
        }
    } else {
        # Validate test executable
        if (-not (Test-Path -LiteralPath $Execute -PathType Leaf)) {
            Write-Error "Test executable not found: $Execute" -ErrorAction Continue
            Write-Result @{ execute = $Execute; error = "Test executable not found" }
            exit $ExitFileNotFound
        }

        # Validate MAP file
        if (-not (Test-Path -LiteralPath $MapFile -PathType Leaf)) {
            Write-Error "MAP file not found: $MapFile" -ErrorAction Continue
            Write-Result @{ execute = $Execute; error = "MAP file not found" }
            exit $ExitFileNotFound
        }

        # Validate MAP file is detailed
        if (-not (Test-DetailedMapFile -Path $MapFile)) {
            Write-Error "MAP file does not contain line number information. Enable 'Detailed' map file in the project linker settings." -ErrorAction Continue
            Write-Result @{ execute = $Execute; error = "MAP file is not detailed" }
            exit $ExitInvalidArguments
        }
    }

    # Resolve comma-separated params into arrays early (needed for validation)
    $resolvedFormats = @(if (-not [string]::IsNullOrEmpty($Formats)) { $Formats -split ',' } else { @('html') })

    # Validate formats
    $validFormats = @('html', 'xml', 'emma', 'lcov', 'cobertura', 'md', 'covdb')
    foreach ($fmt in $resolvedFormats) {
        if ($fmt.ToLower() -notin $validFormats) {
            Write-Error "Invalid format '$fmt'. Valid values: $($validFormats -join ', ')" -ErrorAction Continue
            exit $ExitInvalidArguments
        }
    }

    # covdb format requires radCodeCoverage engine
    if ($resolvedFormats -contains 'covdb' -and $Engine -ne 'radCodeCoverage') {
        Write-Error "Format 'covdb' requires -Engine radCodeCoverage" -ErrorAction Continue
        exit $ExitInvalidArguments
    }

    # Find the coverage engine
    $engineBinary = $null
    switch ($Engine) {
        'DelphiCodeCoverage' {
            $engineBinary = Find-DelphiCodeCoverage -ExplicitPath $EnginePath
        }
        'radCodeCoverage' {
            $engineBinary = Find-RadCodeCoverage -ExplicitPath $EnginePath
        }
    }
    if ($null -eq $engineBinary) {
        Write-Error "Coverage engine '$Engine' not found. Provide -EnginePath or add it to PATH." -ErrorAction Continue
        Write-Result @{ execute = $displayTarget; engine = $Engine; error = "Engine not found" }
        exit $ExitEngineNotFound
    }

    Write-Host "Running coverage: $displayTarget"
    Write-Host "Engine: $Engine ($engineBinary)"

    # Resolve test arguments
    $resolvedTestArgs = @($(
        $resolvedArgs = if (-not [string]::IsNullOrEmpty($Arguments)) { $Arguments }
                        elseif (-not [string]::IsNullOrEmpty($env:DELPHI_COVERAGE_ARGS)) { $env:DELPHI_COVERAGE_ARGS }
                        else { '' }
        if (-not [string]::IsNullOrEmpty($resolvedArgs)) { $resolvedArgs -split ',' } else { @() }
    ))
    $resolvedSourceDirs  = @(if (-not [string]::IsNullOrEmpty($SourceDir))    { $SourceDir -split ',' }    else { @() })
    $resolvedUnits       = @(if (-not [string]::IsNullOrEmpty($Units))        { $Units -split ',' }        else { @() })
    $resolvedExclude     = @(if (-not [string]::IsNullOrEmpty($ExcludeUnits)) { $ExcludeUnits -split ',' } else { @() })

    # Run the coverage engine
    $engineResult = $null
    if ($useDproj) {
        $engineResult = Invoke-CoverageEngineDproj `
            -EngineBinary       $engineBinary `
            -DprojFile          $Dproj `
            -CoverageSourceDir  $resolvedSourceDirs `
            -CoverageUnits      $resolvedUnits `
            -CoverageExcludeUnits $resolvedExclude `
            -CoverageOutputDir  $OutputDir `
            -CoverageFormats    $resolvedFormats `
            -TestArguments      $resolvedTestArgs `
            -CoverageTimeout    $TimeoutSeconds
    } else {
        $engineResult = Invoke-DelphiCodeCoverageEngine `
            -EngineBinary       $engineBinary `
            -TestExecutable     $Execute `
            -TestMapFile        $MapFile `
            -CoverageSourceDir  $resolvedSourceDirs `
            -CoverageUnits      $resolvedUnits `
            -CoverageExcludeUnits $resolvedExclude `
            -CoverageOutputDir  $OutputDir `
            -CoverageFormats    $resolvedFormats `
            -TestArguments      $resolvedTestArgs `
            -CoverageTimeout    $TimeoutSeconds
    }

    if (-not $engineResult.Success) {
        Write-Error "Coverage engine failed: $($engineResult.Message)" -ErrorAction Continue
        Write-Result @{
            engine   = $Engine
            execute  = $displayTarget
            exitCode = $engineResult.ExitCode
            success  = $false
            error    = $engineResult.Message
        }
        exit $ExitCoverageFailed
    }

    # Parse coverage results
    $coverageData = Get-CoverageStats -CoverageOutputDir $OutputDir
    $coveragePercent = 0.0
    $linesCovered    = 0
    $linesTotal      = 0
    if ($null -ne $coverageData) {
        $coveragePercent = $coverageData.CoveragePercent
        $linesCovered    = $coverageData.LinesCovered
        $linesTotal      = $coverageData.LinesTotal
    }

    $stopwatch.Stop()
    $duration = $stopwatch.Elapsed.TotalSeconds

    Write-Host "Coverage: $coveragePercent% ($linesCovered/$linesTotal lines)"

    # Check threshold
    $thresholdMet = $true
    if ($Threshold -gt 0) {
        $thresholdMet = $coveragePercent -ge $Threshold
        if ($thresholdMet) {
            Write-Host "Threshold $Threshold% met"
        }
        else {
            Write-Host "Threshold $Threshold% NOT met"
        }
    }

    # Generate badge
    if (-not [string]::IsNullOrEmpty($Badge)) {
        New-CoverageBadge -Percent $coveragePercent -OutputPath $Badge
        Write-Host "Badge written: $Badge"
    }

    # Write result
    $result = @{
        engine          = $Engine
        execute         = $displayTarget
        exitCode        = 0
        success         = $thresholdMet
        coveragePercent = $coveragePercent
        linesCovered    = $linesCovered
        linesTotal      = $linesTotal
        threshold       = $Threshold
        thresholdMet    = $thresholdMet
        outputDir       = $OutputDir
        formats         = $resolvedFormats
        badge           = if ([string]::IsNullOrEmpty($Badge)) { $null } else { $Badge }
        duration        = [math]::Round($duration, 1)
    }
    Write-Result $result

    if (-not $thresholdMet) {
        Write-Error "Coverage $coveragePercent% is below threshold $Threshold%" -ErrorAction Continue
        exit $ExitThresholdNotMet
    }

    exit $ExitSuccess
}
catch {
    $stopwatch.Stop()
    Write-Error $_.Exception.Message -ErrorAction Continue
    Write-Result @{ execute = $displayTarget; error = $_.Exception.Message }
    exit $ExitUnexpectedError
}
