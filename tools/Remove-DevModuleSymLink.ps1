#requires -Version 7.0
#requires -PSEdition Core

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host ""
Write-Host "delphi-powershell-ci  Remove-DevModuleSymLink.ps1"
Write-Host "==================================================="
Write-Host ""

# PowerShell user module directory
$moduleInstallRoot = Join-Path $HOME 'Documents/PowerShell/Modules'

# Link location
$linkPath = Join-Path $moduleInstallRoot 'Delphi.PowerShell.CI'

Write-Host "Module path : $linkPath"
Write-Host ""

if (-not (Test-Path -LiteralPath $linkPath)) {
    Write-Host "No module entry found. Nothing to remove."
    Write-Host ""
    exit 0
}

$item = Get-Item -LiteralPath $linkPath -Force

# Detect whether this is actually a symlink
if ($item.LinkType -ne 'SymbolicLink') {
    Write-Warning "The path exists but is not a symbolic link."
    Write-Warning "Refusing to delete to avoid removing a real module."
    Write-Host ""
    exit 1
}

Write-Host "Removing symbolic link..."

Remove-Item -LiteralPath $linkPath -Force

Write-Host ""
Write-Host "Symlink removed successfully."
Write-Host ""
