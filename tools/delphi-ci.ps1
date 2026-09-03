#requires -Version 5.1

<#
.SYNOPSIS
Convenience wrapper -- imports Delphi.PowerShell.CI and calls Invoke-DelphiCi.

.DESCRIPTION
Lets callers use a single script path instead of managing module imports.
All parameters are forwarded to Invoke-DelphiCi unchanged.

Parameter surface (by design): this wrapper exposes shorthand parameters only for
the common steps -- Clean, Build (including -ToolchainRootDir and -NoConfig), Run,
and Format. The data-heavy actions -- IncVer, Copy, Compress, Coverage, CallGraph,
and Codesign -- are intentionally NOT exposed as CLI shorthands here; drive them
through a pipeline config with -ConfigFile .\delphi-ci.json. This keeps the
wrapper from duplicating (and drifting behind) the full Invoke-DelphiCi surface.

Run from any directory; the module path is resolved relative to this script.

Run mode: progress is written to the host (console). Exits 0 on success,
1 on failure. No object is written to the pipeline -- the exit code is the
result.

VersionInfo mode: the structured version object is written to the pipeline
(so callers can capture and inspect it) and the script exits 0.

.EXAMPLE
.\tools\delphi-ci.ps1

.EXAMPLE
.\tools\delphi-ci.ps1 -ProjectFile .\source\MyApp.dproj

.EXAMPLE
.\tools\delphi-ci.ps1 -Steps Build -ProjectFile .\source\MyApp.dproj -Configuration Release

.EXAMPLE
.\tools\delphi-ci.ps1 -ConfigFile .\delphi-ci.json

.EXAMPLE
.\tools\delphi-ci.ps1 -Steps Format -FormatCheck $true -Root C:\MyRepo

.EXAMPLE
.\tools\delphi-ci.ps1 -VersionInfo
#>

[CmdletBinding(DefaultParameterSetName = 'Run')]
param(
    [Parameter(ParameterSetName = 'VersionInfo', Mandatory)]
    [switch]$VersionInfo,

    [Parameter(ParameterSetName = 'Run')]
    [string]$ConfigFile,

    [Parameter(ParameterSetName = 'Run')]
    [string]$Root,

    [Parameter(ParameterSetName = 'Run')]
    [string[]]$Steps,

    [Parameter(ParameterSetName = 'Run')]
    [string]$ProjectFile,

    [Parameter(ParameterSetName = 'Run')]
    [string]$Platform,

    [Parameter(ParameterSetName = 'Run')]
    [string]$Configuration,

    [Parameter(ParameterSetName = 'Run')]
    [string]$Toolchain,

    [Parameter(ParameterSetName = 'Run')]
    [string]$ToolchainRootDir,

    [Parameter(ParameterSetName = 'Run')]
    [string]$BuildEngine,

    [Parameter(ParameterSetName = 'Run')]
    [string[]]$Defines,

    [Parameter(ParameterSetName = 'Run')]
    [ValidateSet('quiet', 'minimal', 'normal', 'detailed', 'diagnostic')]
    [string]$BuildVerbosity,

    [Parameter(ParameterSetName = 'Run')]
    [ValidateSet('Build', 'Clean', 'Rebuild')]
    [string]$BuildTarget,

    [Parameter(ParameterSetName = 'Run')]
    [string]$ExeOutputDir,

    [Parameter(ParameterSetName = 'Run')]
    [string]$DcuOutputDir,

    [Parameter(ParameterSetName = 'Run')]
    [string[]]$UnitSearchPath,

    [Parameter(ParameterSetName = 'Run')]
    [string[]]$IncludePath,

    [Parameter(ParameterSetName = 'Run')]
    [string[]]$Namespace,

    [Parameter(ParameterSetName = 'Run')]
    [switch]$NoConfig,

    [Parameter(ParameterSetName = 'Run')]
    [ValidateSet('basic', 'standard', 'deep')]
    [string]$CleanLevel,

    [Parameter(ParameterSetName = 'Run')]
    [ValidateSet('detailed', 'summary', 'quiet')]
    [string]$CleanOutputLevel,

    [Parameter(ParameterSetName = 'Run')]
    [string[]]$CleanIncludeFilePattern,

    [Parameter(ParameterSetName = 'Run')]
    [string[]]$CleanExcludeDirectoryPattern,

    [Parameter(ParameterSetName = 'Run')]
    [string]$CleanConfigFile,

    [Parameter(ParameterSetName = 'Run')]
    [bool]$CleanRecycleBin,

    [Parameter(ParameterSetName = 'Run')]
    [bool]$CleanCheck,

    [Parameter(ParameterSetName = 'Run')]
    [string]$Execute,

    [Parameter(ParameterSetName = 'Run')]
    [string[]]$RunArguments,

    [Parameter(ParameterSetName = 'Run')]
    [int]$RunTimeoutSeconds,

    [Parameter(ParameterSetName = 'Run')]
    [ValidateSet('formatter', 'radFormatter')]
    [string]$FormatEngine,

    [Parameter(ParameterSetName = 'Run')]
    [string]$FormatEnginePath,

    [Parameter(ParameterSetName = 'Run')]
    [string]$FormatEngineConfigFile,

    [Parameter(ParameterSetName = 'Run')]
    [string[]]$FormatPath,

    [Parameter(ParameterSetName = 'Run')]
    [string[]]$FormatIncludeFilePattern,

    [Parameter(ParameterSetName = 'Run')]
    [string[]]$FormatExcludeDirectoryPattern,

    [Parameter(ParameterSetName = 'Run')]
    [string]$FormatEncoding,

    [Parameter(ParameterSetName = 'Run')]
    [bool]$FormatCreateBackups,

    [Parameter(ParameterSetName = 'Run')]
    [ValidateSet('detailed', 'summary', 'quiet')]
    [string]$FormatOutputLevel,

    [Parameter(ParameterSetName = 'Run')]
    [string]$FormatConfigFile,

    [Parameter(ParameterSetName = 'Run')]
    [bool]$FormatCheck
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$manifest = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\source\Delphi.PowerShell.CI.psd1'))
Import-Module $manifest -Force

$result = Invoke-DelphiCi @PSBoundParameters

if ($VersionInfo) {
    $result  # structured version data is the intended output in this mode
    exit 0
}

if (-not $result.Success) {
    exit 1
}

exit 0
