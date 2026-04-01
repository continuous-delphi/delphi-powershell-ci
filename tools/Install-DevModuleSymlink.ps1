#requires -Version 7.0
#requires -PSEdition Core

[CmdletBinding()]
param(
    [switch]$ElevatedRetry
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host "  $Message" -ForegroundColor Cyan
}

function Write-WarnText {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host "  warn  $Message" -ForegroundColor Yellow
}

function Fail {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host ''
    Write-Host "FAIL  $Message" -ForegroundColor Red
    Write-Host ''
    throw $Message
}

function Start-ElevatedSelf {
    $argumentList = @(
        '-NoProfile'
        '-ExecutionPolicy', 'Bypass'
        '-File', ('"{0}"' -f $PSCommandPath)
        '-ElevatedRetry'
    )

    Write-WarnText 'Administrator privilege required for this operation.'
    Write-Step 'Restarting script with elevation...'

    Start-Process -FilePath 'pwsh' -Verb RunAs -ArgumentList $argumentList | Out-Null
}

function New-ModuleSymlink {
    param(
        [Parameter(Mandatory = $true)][string]$LinkPath,
        [Parameter(Mandatory = $true)][string]$TargetPath
    )

    if (Test-Path -LiteralPath $LinkPath) {
        $existingItem = Get-Item -LiteralPath $LinkPath -Force

        if ($existingItem.LinkType -eq 'SymbolicLink') {
            Write-Step 'Removing existing symbolic link...'
            Remove-Item -LiteralPath $LinkPath -Force
        }
        else {
            Fail "Path already exists and is not a symbolic link: $LinkPath`n       Refusing to delete it automatically."
        }
    }

    Write-Step 'Creating symbolic link in PowerShell Modules directory...'
    New-Item -ItemType SymbolicLink -Path $LinkPath -Target $TargetPath | Out-Null
}

Write-Host ''
Write-Host 'Delphi.PowerShell.CI  Install-DevModuleSymlink' -ForegroundColor White
Write-Host '===============================================' -ForegroundColor White
Write-Host ''

$moduleName = 'Delphi.PowerShell.CI'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$moduleSource = Join-Path $repoRoot 'source'
$moduleManifest = Join-Path $moduleSource "$moduleName.psd1"
$moduleInstallRoot = Join-Path $HOME 'Documents\PowerShell\Modules'
$linkPath = Join-Path $moduleInstallRoot $moduleName

Write-Host "  Repo root : $repoRoot"
Write-Host "  Source    : $moduleSource"
Write-Host "  Manifest  : $moduleManifest"
Write-Host "  Link path : $linkPath"
Write-Host ''

if (-not (Test-Path -LiteralPath $moduleSource -PathType Container)) {
    Fail "Module source folder not found: $moduleSource"
}

if (-not (Test-Path -LiteralPath $moduleManifest -PathType Leaf)) {
    Fail "Module manifest not found: $moduleManifest"
}

New-Item -ItemType Directory -Path $moduleInstallRoot -Force | Out-Null

try {
    New-ModuleSymlink -LinkPath $linkPath -TargetPath $moduleSource

    Write-Host ''
    Write-Host 'Symlink created successfully.' -ForegroundColor Green
    Write-Host ''
    Write-Host 'You can now run commands like:' -ForegroundColor White
    Write-Host "  Import-Module $moduleName" -ForegroundColor White
    Write-Host '  Get-Command -Module Delphi.PowerShell.CI' -ForegroundColor White
    Write-Host ''

    if ($ElevatedRetry) {
        Write-Host 'Press Enter to close this elevated window...' -ForegroundColor Yellow
        [void](Read-Host)
    }
}
catch {
    $message = $_.Exception.Message

    $needsElevation = (
        $message -match 'Administrator privilege required' -or
        $message -match 'client does not possess a required privilege' -or
        $message -match 'A required privilege is not held by the client'
    )

    if ($needsElevation -and -not $ElevatedRetry) {
        Start-ElevatedSelf
        exit 0
    }

    if ($needsElevation -and $ElevatedRetry) {
        Fail 'Symlink creation still failed after elevation attempt.'
    }

    throw
}