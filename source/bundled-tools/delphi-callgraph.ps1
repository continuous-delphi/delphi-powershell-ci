#requires -Version 5.1
# -----------------------------------------------------------------------------
# delphi-callgraph
#
# Call graph and dependency graph orchestrator for Delphi source code. Wraps
# radCallGraph, PasDoc GraphViz output, and Delphi compiler GraphViz output
# behind a unified PowerShell interface.
#
# Part of Continuous-Delphi: Strengthening Delphi's continued success
# https://github.com/continuous-delphi
#
# Project repository:
# https://github.com/continuous-delphi/delphi-callgraph
#
# Also intended for inclusion in the Continuous-Delphi PowerShell CI module:
# https://github.com/continuous-delphi/delphi-powershell-ci
#
# Copyright (c) 2026 Darian Miller
# Licensed under the MIT License.
# https://opensource.org/licenses/MIT
# SPDX-License-Identifier: MIT
# -----------------------------------------------------------------------------

<#
.SYNOPSIS
Runs Delphi call graph or dependency graph analysis.

.DESCRIPTION
Orchestrates a graph engine to produce JSON, DOT, or text output. The default
engine is radCallGraph.exe. PasDoc and the Delphi compiler GraphViz option are
supported for dependency/class DOT output.

Exit codes:
  0  success
  1  unexpected error
  2  invalid arguments
  3  engine executable not found
  4  input file or directory not found
  5  graph engine failed

.EXAMPLE
./delphi-callgraph.ps1 -Path source -Formats json,dot,txt

.EXAMPLE
./delphi-callgraph.ps1 -Path source -EnginePath C:\tools\radCallGraph.exe -Class TMyService -Formats json,dot

.EXAMPLE
./delphi-callgraph.ps1 -Path source -Engine PasDoc -GraphKind all -Formats dot

.EXAMPLE
./delphi-callgraph.ps1 -ProjectFile source\MyApp.dpr -Engine DCC -GraphVizExclude System.*,Vcl.* -Formats dot

.EXAMPLE
./delphi-callgraph.ps1 -Version -Format json
#>

[CmdletBinding(DefaultParameterSetName = 'Graph')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
  Justification='Write-Host is intentional: standalone CLI tool streams status to the console host.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '',
  Justification='Several parameters are consumed inside helper functions in script scope.')]
param(
    [Parameter(ParameterSetName = 'Version', Mandatory)]
    [switch]$Version,

    [Parameter(ParameterSetName = 'Version')]
    [ValidateSet('text', 'json')]
    [string]$Format = 'text',

    [Parameter(ParameterSetName = 'Graph', Position = 0)]
    [Alias('InputPath', 'Source')]
    [string[]]$Path = @(),

    [Parameter(ParameterSetName = 'Graph')]
    [ValidateSet('radCallGraph', 'PasDoc', 'DCC')]
    [string]$Engine = 'radCallGraph',

    [Parameter(ParameterSetName = 'Graph')]
    [string]$EnginePath,

    [Parameter(ParameterSetName = 'Graph')]
    [string]$OutputDir = 'callgraph',

    [Parameter(ParameterSetName = 'Graph')]
    [string]$Formats = '',

    [Parameter(ParameterSetName = 'Graph')]
    [string]$JsonFile,

    [Parameter(ParameterSetName = 'Graph')]
    [string]$DotFile,

    [Parameter(ParameterSetName = 'Graph')]
    [string]$SummaryFile,

    [Parameter(ParameterSetName = 'Graph')]
    [string]$Class,

    [Parameter(ParameterSetName = 'Graph')]
    [bool]$Annotations = $true,

    [Parameter(ParameterSetName = 'Graph')]
    [ValidateSet('', 'call', 'uses', 'classes', 'dependency', 'all')]
    [string]$GraphKind = '',

    [Parameter(ParameterSetName = 'Graph')]
    [switch]$GraphVizUses,

    [Parameter(ParameterSetName = 'Graph')]
    [switch]$GraphVizClasses,

    [Parameter(ParameterSetName = 'Graph')]
    [string[]]$PasDocOptions = @(),

    [Parameter(ParameterSetName = 'Graph')]
    [string]$ProjectFile,

    [Parameter(ParameterSetName = 'Graph')]
    [string[]]$GraphVizExclude = @(),

    [Parameter(ParameterSetName = 'Graph')]
    [string[]]$EngineArguments = @(),

    [Parameter(ParameterSetName = 'Graph')]
    [int]$TimeoutSeconds = 300,

    [Parameter(ParameterSetName = 'Graph')]
    [string]$OutputFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExitSuccess          = 0
$ExitUnexpectedError  = 1
$ExitInvalidArguments = 2
$ExitEngineNotFound   = 3
$ExitInputNotFound    = 4
$ExitEngineFailed     = 5

$script:ToolVersion = '0.1.0'

# -----------------------------------------------------------------------------
# Version info
# -----------------------------------------------------------------------------

if ($Version) {
    $info = @{ tool = @{ name = 'delphi-callgraph'; version = $script:ToolVersion } }
    if ($Format -eq 'json') {
        Write-Output ($info | ConvertTo-Json -Depth 5 -Compress)
    }
    else {
        Write-Host "delphi-callgraph $($script:ToolVersion)"
    }
    exit $ExitSuccess
}

# -----------------------------------------------------------------------------
# Shared helpers
# -----------------------------------------------------------------------------

function Split-CommaList {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return @() }

    return @($Value -split '[,\s]+' |
        ForEach-Object { $_.Trim() } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function ConvertTo-FullPath {
    param([Parameter(Mandatory)][string]$Value)

    if ([System.IO.Path]::IsPathRooted($Value)) {
        return [System.IO.Path]::GetFullPath($Value)
    }
    return [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $Value))
}

function Initialize-Directory {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
      Justification='This helper intentionally creates output directories requested by the caller.')]
    param([Parameter(Mandatory)][string]$Directory)

    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
        New-Item -Path $Directory -ItemType Directory -Force | Out-Null
    }
}

function Initialize-ParentDirectory {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
      Justification='This helper intentionally creates parent directories for requested output files.')]
    param([Parameter(Mandatory)][string]$FilePath)

    $parentDir = [System.IO.Path]::GetDirectoryName($FilePath)
    if (-not [string]::IsNullOrWhiteSpace($parentDir)) {
        Initialize-Directory -Directory $parentDir
    }
}

function Write-Result {
    param([hashtable]$Result)

    if (-not [string]::IsNullOrWhiteSpace($OutputFile)) {
        $resolvedOutputFile = ConvertTo-FullPath -Value $OutputFile
        Initialize-ParentDirectory -FilePath $resolvedOutputFile
        $json = $Result | ConvertTo-Json -Depth 8 -Compress
        Set-Content -LiteralPath $resolvedOutputFile -Value $json -Encoding UTF8
    }
}

function Exit-WithError {
    param(
        [Parameter(Mandatory)][string]$Message,
        [Parameter(Mandatory)][int]$ExitCode,
        [hashtable]$Extra = @{}
    )

    Write-Error $Message -ErrorAction Continue
    $result = @{
        success  = $false
        exitCode = $ExitCode
        engine   = $Engine
        error    = $Message
    }
    foreach ($key in $Extra.Keys) {
        $result[$key] = $Extra[$key]
    }
    Write-Result -Result $result
    exit $ExitCode
}

function Resolve-InputPathList {
    param([string[]]$InputPaths)

    $resolved = [System.Collections.Generic.List[string]]::new()
    foreach ($inputPath in $InputPaths) {
        if ([string]::IsNullOrWhiteSpace($inputPath)) { continue }

        $fullPath = ConvertTo-FullPath -Value $inputPath
        if (-not (Test-Path -LiteralPath $fullPath)) {
            Exit-WithError -Message "Input path not found: $inputPath" -ExitCode $ExitInputNotFound -Extra @{ input = $inputPath }
        }
        $resolved.Add($fullPath)
    }

    return $resolved.ToArray()
}

function Resolve-GraphFormatList {
    param(
        [string]$RequestedFormats,
        [string]$SelectedEngine
    )

    $resolvedFormats = @(Split-CommaList -Value $RequestedFormats)
    if ($resolvedFormats.Count -eq 0) {
        $resolvedFormats = if ($SelectedEngine -eq 'radCallGraph') { @('json') } else { @('dot') }
    }

    $validFormats = @('json', 'dot', 'txt')
    foreach ($fmt in $resolvedFormats) {
        if ($fmt.ToLower() -notin $validFormats) {
            Exit-WithError -Message "Invalid format '$fmt'. Valid values: $($validFormats -join ', ')" -ExitCode $ExitInvalidArguments
        }
    }

    if ($SelectedEngine -in @('PasDoc', 'DCC')) {
        foreach ($fmt in $resolvedFormats) {
            if ($fmt.ToLower() -ne 'dot') {
                Exit-WithError -Message "$SelectedEngine supports dot output only in this wrapper." -ExitCode $ExitInvalidArguments
            }
        }
    }

    return @($resolvedFormats | ForEach-Object { $_.ToLower() })
}

function Find-GraphEngine {
    param(
        [string]$SelectedEngine,
        [string]$ExplicitPath
    )

    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
        if (Test-Path -LiteralPath $ExplicitPath -PathType Leaf) {
            return (ConvertTo-FullPath -Value $ExplicitPath)
        }

        $explicitCommand = Get-Command $ExplicitPath -ErrorAction SilentlyContinue
        if ($null -ne $explicitCommand) {
            return $explicitCommand.Source
        }
        return $null
    }

    $candidates = switch ($SelectedEngine) {
        'radCallGraph' { @('radCallGraph.exe', 'radCallGraph') }
        'PasDoc'       { @('pasdoc.exe', 'pasdoc') }
        'DCC'          { @('dcc32.exe', 'dcc32') }
        default        { @() }
    }

    foreach ($candidate in $candidates) {
        $found = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($null -ne $found) {
            return $found.Source
        }
    }

    return $null
}

function Get-PowerShellExe {
    $pwsh = Get-Command 'pwsh' -ErrorAction SilentlyContinue
    if ($null -ne $pwsh) { return $pwsh.Source }

    $powershell = Get-Command 'powershell' -ErrorAction SilentlyContinue
    if ($null -ne $powershell) { return $powershell.Source }

    return $null
}

function ConvertTo-ArgumentString {
    param([string[]]$Arguments)

    $escaped = @()
    foreach ($argument in $Arguments) {
        if ($null -eq $argument) { continue }

        $argText = [string]$argument
        if ($argText -match '[\s"]') {
            $escaped += '"' + ($argText -replace '"', '\"') + '"'
        }
        else {
            $escaped += $argText
        }
    }

    return ($escaped -join ' ')
}

function Invoke-GraphEngineProcess {
    param(
        [Parameter(Mandatory)][string]$EngineBinary,
        [string[]]$Arguments,
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [int]$Timeout
    )

    $processFile = $EngineBinary
    $processArgs = $Arguments

    if ([System.IO.Path]::GetExtension($EngineBinary).ToLower() -eq '.ps1') {
        $powerShellExe = Get-PowerShellExe
        if ([string]::IsNullOrWhiteSpace($powerShellExe)) {
            return @{
                Success  = $false
                ExitCode = -1
                Message  = 'PowerShell executable not found for .ps1 engine path'
            }
        }

        $processFile = $powerShellExe
        $processArgs = @('-NoProfile', '-NonInteractive', '-File', $EngineBinary) + $Arguments
    }

    $argumentString = ConvertTo-ArgumentString -Arguments $processArgs

    Write-Host "Engine: $EngineBinary"
    Write-Host "Args: $argumentString"

    $proc = Start-Process -FilePath $processFile `
        -ArgumentList $argumentString `
        -WorkingDirectory $WorkingDirectory `
        -NoNewWindow -PassThru -Wait:$false

    $exited = $proc.WaitForExit($Timeout * 1000)
    if (-not $exited) {
        try { $proc.Kill() } catch { Write-Verbose "Process already exited: $_" }
        return @{
            Success  = $false
            ExitCode = -1
            Message  = "Graph engine timed out after ${Timeout}s"
        }
    }

    return @{
        Success  = ($proc.ExitCode -eq 0)
        ExitCode = $proc.ExitCode
        Message  = if ($proc.ExitCode -eq 0) { 'Graph engine completed' } else { "Engine exited with code $($proc.ExitCode)" }
    }
}

function Get-PasDocGraphSelection {
    $wantsUses = $GraphVizUses.IsPresent -or $GraphKind -in @('uses', 'dependency', 'all')
    $wantsClasses = $GraphVizClasses.IsPresent -or $GraphKind -in @('classes', 'all')
    if (-not $wantsUses -and -not $wantsClasses) {
        $wantsUses = $true
    }

    return @{
        Uses    = $wantsUses
        Classes = $wantsClasses
    }
}

function Get-OutputFileMap {
    param(
        [string[]]$ResolvedFormats,
        [string]$ResolvedOutputDir,
        [string]$SelectedEngine,
        [AllowNull()]
        [string]$ResolvedProjectFile
    )

    $files = @{}

    if ('json' -in $ResolvedFormats) {
        $files['json'] = if ([string]::IsNullOrWhiteSpace($JsonFile)) {
            Join-Path $ResolvedOutputDir 'callgraph.json'
        }
        else {
            ConvertTo-FullPath -Value $JsonFile
        }
    }

    if ('dot' -in $ResolvedFormats) {
        $files['dot'] = if ([string]::IsNullOrWhiteSpace($DotFile)) {
            switch ($SelectedEngine) {
                'PasDoc' {
                    $pasDocSelection = Get-PasDocGraphSelection
                    if ($pasDocSelection.Uses -and $pasDocSelection.Classes) {
                        @(
                            (Join-Path $ResolvedOutputDir 'GVUses.dot'),
                            (Join-Path $ResolvedOutputDir 'GVClasses.dot')
                        )
                    }
                    elseif ($pasDocSelection.Classes) {
                        Join-Path $ResolvedOutputDir 'GVClasses.dot'
                    }
                    else {
                        Join-Path $ResolvedOutputDir 'GVUses.dot'
                    }
                }
                'DCC' {
                    $baseName = if ([string]::IsNullOrWhiteSpace($ResolvedProjectFile)) {
                        'callgraph'
                    }
                    else {
                        [System.IO.Path]::GetFileNameWithoutExtension($ResolvedProjectFile)
                    }
                    Join-Path $ResolvedOutputDir "$baseName.gv"
                }
                default {
                    Join-Path $ResolvedOutputDir 'callgraph.dot'
                }
            }
        }
        else {
            ConvertTo-FullPath -Value $DotFile
        }
    }

    if ('txt' -in $ResolvedFormats) {
        $files['txt'] = if ([string]::IsNullOrWhiteSpace($SummaryFile)) {
            Join-Path $ResolvedOutputDir 'callgraph.txt'
        }
        else {
            ConvertTo-FullPath -Value $SummaryFile
        }
    }

    foreach ($value in $files.Values) {
        foreach ($fileValue in @($value)) {
            Initialize-ParentDirectory -FilePath $fileValue
        }
    }

    return $files
}

function Get-RadCallGraphArgumentList {
    param(
        [string[]]$InputPaths,
        [string[]]$ResolvedFormats,
        [hashtable]$Files
    )

    $argumentList = [System.Collections.Generic.List[string]]::new()

    if ('json' -in $ResolvedFormats) {
        $argumentList.Add('--json')
        $argumentList.Add($Files['json'])
    }
    if ('dot' -in $ResolvedFormats) {
        $argumentList.Add('--dot')
        $argumentList.Add($Files['dot'])
    }
    if ('txt' -in $ResolvedFormats) {
        $argumentList.Add('--summary')
        $argumentList.Add($Files['txt'])
    }
    if (-not [string]::IsNullOrWhiteSpace($Class)) {
        $argumentList.Add('--class')
        $argumentList.Add($Class)
    }
    if ($Annotations) {
        $argumentList.Add('--annotations')
    }
    else {
        $argumentList.Add('--no-annotations')
    }

    foreach ($extraArgument in $script:ResolvedEngineArguments) {
        if (-not [string]::IsNullOrWhiteSpace($extraArgument)) {
            $argumentList.Add($extraArgument)
        }
    }
    foreach ($inputPath in $InputPaths) {
        $argumentList.Add($inputPath)
    }

    return $argumentList.ToArray()
}

function Get-PasDocArgumentList {
    param([string[]]$InputPaths)

    $argumentList = [System.Collections.Generic.List[string]]::new()
    foreach ($option in $script:ResolvedPasDocOptions) {
        if (-not [string]::IsNullOrWhiteSpace($option)) {
            $argumentList.Add($option)
        }
    }

    $argumentList.Add('--output')
    $argumentList.Add($script:ResolvedOutputDir)

    $pasDocSelection = Get-PasDocGraphSelection

    if ($pasDocSelection.Uses) { $argumentList.Add('--graphviz-uses') }
    if ($pasDocSelection.Classes) { $argumentList.Add('--graphviz-classes') }

    foreach ($extraArgument in $script:ResolvedEngineArguments) {
        if (-not [string]::IsNullOrWhiteSpace($extraArgument)) {
            $argumentList.Add($extraArgument)
        }
    }
    foreach ($inputPath in $InputPaths) {
        $argumentList.Add($inputPath)
    }

    return $argumentList.ToArray()
}

function Resolve-DccProjectFile {
    param([string[]]$InputPaths)

    if (-not [string]::IsNullOrWhiteSpace($ProjectFile)) {
        $resolvedProject = ConvertTo-FullPath -Value $ProjectFile
        if (-not (Test-Path -LiteralPath $resolvedProject -PathType Leaf)) {
            Exit-WithError -Message "Project file not found: $ProjectFile" -ExitCode $ExitInputNotFound -Extra @{ projectFile = $ProjectFile }
        }
        return $resolvedProject
    }

    if ($InputPaths.Count -eq 1 -and (Test-Path -LiteralPath $InputPaths[0] -PathType Leaf)) {
        return $InputPaths[0]
    }

    Exit-WithError -Message 'DCC engine requires -ProjectFile or exactly one file path.' -ExitCode $ExitInvalidArguments
}

function Get-DccArgumentList {
    param([string]$ResolvedProjectFile)

    $argumentList = [System.Collections.Generic.List[string]]::new()
    $argumentList.Add('--graphviz')

    $resolvedGraphVizExclude = @(Split-CommaList -Value ($GraphVizExclude -join ','))
    if ($resolvedGraphVizExclude.Count -gt 0) {
        $argumentList.Add("--graphviz-exclude=$($resolvedGraphVizExclude -join ';')")
    }

    foreach ($extraArgument in $script:ResolvedEngineArguments) {
        if (-not [string]::IsNullOrWhiteSpace($extraArgument)) {
            $argumentList.Add($extraArgument)
        }
    }

    $argumentList.Add($ResolvedProjectFile)
    return $argumentList.ToArray()
}

function Find-DotLikeOutput {
    param(
        [string]$Directory,
        [datetime]$Since
    )

    $files = @(Get-ChildItem -Path $Directory -Include '*.dot', '*.gv' -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -ge $Since } |
        Sort-Object LastWriteTime -Descending)

    return $files
}

function Move-GraphOutputIfRequested {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
      Justification='This helper normalizes engine output into caller-requested output paths.')]
    param(
        [hashtable]$Files,
        [datetime]$Since
    )

    if (-not $Files.ContainsKey('dot')) { return }
    if ([string]::IsNullOrWhiteSpace($DotFile)) { return }

    $candidate = @(Find-DotLikeOutput -Directory $script:ResolvedOutputDir -Since $Since | Select-Object -First 1)
    if ($candidate.Count -eq 0) { return }

    Move-Item -LiteralPath $candidate[0].FullName -Destination $Files['dot'] -Force
}

# -----------------------------------------------------------------------------
# Argument environment fallback
# -----------------------------------------------------------------------------

function Resolve-ArgumentList {
    param(
        [string[]]$Values,
        [string]$EnvironmentValue
    )

    if ($Values.Count -gt 0) {
        return @($Values)
    }

    if (-not [string]::IsNullOrWhiteSpace($EnvironmentValue)) {
        return @(Split-CommaList -Value $EnvironmentValue)
    }

    return @()
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$engineStartTime = Get-Date

try {
    if ($Path.Count -eq 0 -and [string]::IsNullOrWhiteSpace($ProjectFile)) {
        Exit-WithError -Message 'At least one -Path value or -ProjectFile must be provided.' -ExitCode $ExitInvalidArguments
    }

    if ($TimeoutSeconds -le 0) {
        Exit-WithError -Message '-TimeoutSeconds must be greater than 0.' -ExitCode $ExitInvalidArguments
    }

    $script:ResolvedOutputDir = ConvertTo-FullPath -Value $OutputDir
    Initialize-Directory -Directory $script:ResolvedOutputDir

    $resolvedFormats = @(Resolve-GraphFormatList -RequestedFormats $Formats -SelectedEngine $Engine)
    $resolvedInputs = @(Resolve-InputPathList -InputPaths $Path)
    $script:ResolvedEngineArguments = @(Resolve-ArgumentList -Values $EngineArguments -EnvironmentValue $env:DELPHI_CALLGRAPH_ENGINE_ARGS)
    $script:ResolvedPasDocOptions = @(Resolve-ArgumentList -Values $PasDocOptions -EnvironmentValue $env:DELPHI_CALLGRAPH_PASDOC_OPTIONS)

    $resolvedProjectFile = $null
    if ($Engine -eq 'DCC') {
        $resolvedProjectFile = Resolve-DccProjectFile -InputPaths $resolvedInputs
        if ($resolvedInputs.Count -eq 0) {
            $resolvedInputs = @($resolvedProjectFile)
        }
    }

    $files = Get-OutputFileMap `
        -ResolvedFormats    $resolvedFormats `
        -ResolvedOutputDir  $script:ResolvedOutputDir `
        -SelectedEngine     $Engine `
        -ResolvedProjectFile $resolvedProjectFile

    $engineBinary = Find-GraphEngine -SelectedEngine $Engine -ExplicitPath $EnginePath
    if ($null -eq $engineBinary) {
        Exit-WithError -Message "Graph engine '$Engine' not found. Provide -EnginePath or add it to PATH." -ExitCode $ExitEngineNotFound
    }

    Write-Host "Running call graph analysis: $($resolvedInputs -join ', ')"
    Write-Host "Engine: $Engine ($engineBinary)"

    $engineArgs = switch ($Engine) {
        'radCallGraph' {
            Get-RadCallGraphArgumentList -InputPaths $resolvedInputs -ResolvedFormats $resolvedFormats -Files $files
        }
        'PasDoc' {
            Get-PasDocArgumentList -InputPaths $resolvedInputs
        }
        'DCC' {
            Get-DccArgumentList -ResolvedProjectFile $resolvedProjectFile
        }
    }

    $engineResult = Invoke-GraphEngineProcess `
        -EngineBinary     $engineBinary `
        -Arguments        $engineArgs `
        -WorkingDirectory $script:ResolvedOutputDir `
        -Timeout          $TimeoutSeconds

    if (-not $engineResult.Success) {
        Write-Result @{
            engine    = $Engine
            inputs    = $resolvedInputs
            exitCode  = $engineResult.ExitCode
            success   = $false
            outputDir = $script:ResolvedOutputDir
            formats   = $resolvedFormats
            files     = $files
            error     = $engineResult.Message
        }
        Write-Error "Graph engine failed: $($engineResult.Message)" -ErrorAction Continue
        exit $ExitEngineFailed
    }

    if ($Engine -in @('PasDoc', 'DCC')) {
        Move-GraphOutputIfRequested -Files $files -Since $engineStartTime
    }

    $stopwatch.Stop()
    $duration = [math]::Round($stopwatch.Elapsed.TotalSeconds, 1)

    $result = @{
        engine    = $Engine
        inputs    = $resolvedInputs
        exitCode  = 0
        success   = $true
        outputDir = $script:ResolvedOutputDir
        formats   = $resolvedFormats
        files     = $files
        duration  = $duration
    }

    Write-Result -Result $result
    Write-Host "Call graph analysis completed in ${duration}s"
    exit $ExitSuccess
}
catch {
    $stopwatch.Stop()
    Write-Error $_.Exception.Message -ErrorAction Continue
    Write-Result @{
        engine   = $Engine
        exitCode = $ExitUnexpectedError
        success  = $false
        error    = $_.Exception.Message
    }
    exit $ExitUnexpectedError
}
