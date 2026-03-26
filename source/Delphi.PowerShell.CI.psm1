#Requires -Version 5.1

Set-StrictMode -Version Latest

$_psd1Raw             = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Delphi.PowerShell.CI.psd1') -Raw
$script:ModuleVersion = if ($_psd1Raw -match "ModuleVersion\s*=\s*'([^']+)'") { $Matches[1] } else { '0.0.0' }
Remove-Variable _psd1Raw
$script:BundledToolsDir = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'bundled-tools'))

# Prefer pwsh (PS 7+); fall back to powershell (Windows PowerShell 5.1).
$script:PowerShellExe   = if (Get-Command -Name 'pwsh' -ErrorAction SilentlyContinue) { 'pwsh' } else { 'powershell' }

$private = @(Get-ChildItem -Path "$PSScriptRoot\Private\*.ps1" -ErrorAction SilentlyContinue)
$public  = @(Get-ChildItem -Path "$PSScriptRoot\Public\*.ps1"  -ErrorAction SilentlyContinue)

foreach ($script in $private) { . $script.FullName }
foreach ($script in $public)  { . $script.FullName }

if ($public.Count -gt 0) {
    Export-ModuleMember -Function $public.BaseName
}
