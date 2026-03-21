#requires -Version 5.1

<#
.SYNOPSIS
Convenience wrapper -- imports Delphi.PowerShell.CI and calls Invoke-DelphiCi.

.DESCRIPTION
Lets callers use a single script path instead of managing module imports.
All parameters are forwarded to Invoke-DelphiCi unchanged.

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
.\tools\delphi-ci.ps1 -Steps Clean,Build,Test `
    -ProjectFile .\source\MyApp.dproj `
    -TestProjectFile .\tests\MyApp.Tests.dproj `
    -TestDefines CI

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
    [string]$ProjectFile,

    [Parameter(ParameterSetName = 'Run')]
    [string[]]$Steps,

    [Parameter(ParameterSetName = 'Run')]
    [string]$Platform,

    [Parameter(ParameterSetName = 'Run')]
    [string]$Configuration,

    [Parameter(ParameterSetName = 'Run')]
    [string]$Toolchain,

    [Parameter(ParameterSetName = 'Run')]
    [string]$BuildEngine,

    [Parameter(ParameterSetName = 'Run')]
    [string[]]$Defines,

    [Parameter(ParameterSetName = 'Run')]
    [string[]]$CleanIncludeFiles,

    [Parameter(ParameterSetName = 'Run')]
    [string[]]$CleanExcludeDirectories,

    [Parameter(ParameterSetName = 'Run')]
    [string]$TestProjectFile,

    [Parameter(ParameterSetName = 'Run')]
    [string]$TestExecutable,

    [Parameter(ParameterSetName = 'Run')]
    [string[]]$TestDefines,

    [Parameter(ParameterSetName = 'Run')]
    [string[]]$TestArguments,

    [Parameter(ParameterSetName = 'Run')]
    [int]$TestTimeoutSeconds,

    [Parameter(ParameterSetName = 'Run')]
    [bool]$TestBuild,

    [Parameter(ParameterSetName = 'Run')]
    [bool]$TestRun
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
