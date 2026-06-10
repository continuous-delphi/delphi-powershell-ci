#requires -Version 5.1
# -----------------------------------------------------------------------------
# delphi-codesign-azure
#
# Authenticode code signing and verification via Azure Trusted Signing.
#
# Part of Continuous-Delphi: Focused on strengthening Delphi's continued success
# https://github.com/continuous-delphi
#
# Project repository:
# https://github.com/continuous-delphi/delphi-codesign-azure
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
Authenticode code signing and verification using Azure Trusted Signing.

.DESCRIPTION
Signs and verifies Authenticode signatures on executables and libraries
using signtool.exe and Azure Trusted Signing.

Exit codes:
  0  success
  1  signature invalid or file not signed (verify)
  2  partial failure (some files failed to sign)
  3  fatal error (prerequisites missing, file not found, etc.)

.EXAMPLE
pwsh -File source/delphi-codesign-azure.ps1 -Sign -Files app.exe

.EXAMPLE
pwsh -File source/delphi-codesign-azure.ps1 -Sign -Files app.exe,lib.bpl -Format text

.EXAMPLE
pwsh -File source/delphi-codesign-azure.ps1 -Verify -FilePath app.exe -Format text

.EXAMPLE
pwsh -File source/delphi-codesign-azure.ps1 -Version -Format json
#>

[CmdletBinding(DefaultParameterSetName = 'Version')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
  Justification='Write-Host is intentional: standalone CLI tool streams status to the console host.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'OutputFile',
  Justification='Consumed by Write-OutputFile helper function.')]
param(
    [Parameter(ParameterSetName = 'Version', Mandatory)]
    [switch]$Version,

    [Parameter(ParameterSetName = 'Version')]
    [Parameter(ParameterSetName = 'Verify')]
    [Parameter(ParameterSetName = 'Sign')]
    [ValidateSet('object', 'text', 'json')]
    [string]$Format = 'object',

    [Parameter(ParameterSetName = 'Verify', Mandatory)]
    [switch]$Verify,

    [Parameter(ParameterSetName = 'Verify', Mandatory)]
    [string]$FilePath,

    [Parameter(ParameterSetName = 'Verify')]
    [Parameter(ParameterSetName = 'Sign')]
    [string]$SignToolPath,

    [Parameter(ParameterSetName = 'Sign', Mandatory)]
    [switch]$Sign,

    [Parameter(ParameterSetName = 'Sign', Mandatory)]
    [string[]]$Files,

    [Parameter(ParameterSetName = 'Sign')]
    [string]$DlibPath,

    [Parameter(ParameterSetName = 'Sign')]
    [string]$MetadataPath,

    [Parameter(ParameterSetName = 'Sign')]
    [string]$EnvFile,

    [Parameter(ParameterSetName = 'Verify')]
    [Parameter(ParameterSetName = 'Sign')]
    [string]$OutputFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Exit code constants
$ExitSuccess        = 0
$ExitDirty          = 1   # signature invalid or file not signed
$ExitPartialFailure = 2   # some files failed to sign
$ExitFatal          = 3   # prerequisites missing, file not found, etc.

$script:ToolVersion = '0.5.15'

# =============================================================================
# Version info
# =============================================================================

if ($Version) {
    $info = @{
        ok      = $true
        command = 'version'
        tool    = @{
            name    = 'delphi-codesign-azure'
            version = $script:ToolVersion
        }
    }
    switch ($Format) {
        'json'   { Write-Output ($info | ConvertTo-Json -Depth 5 -Compress) }
        'text'   { Write-Output "delphi-codesign-azure $($script:ToolVersion)" }
        default  { Write-Output ([PSCustomObject]$info) }
    }
    exit $ExitSuccess
}

# =============================================================================
# Signtool discovery
# =============================================================================

function Find-SignTool([string]$ExplicitPath) {
    if (-not [string]::IsNullOrEmpty($ExplicitPath)) {
        if (Test-Path -LiteralPath $ExplicitPath -PathType Leaf) {
            return $ExplicitPath
        }
        $found = Get-Command $ExplicitPath -ErrorAction SilentlyContinue
        if ($null -ne $found) { return $found.Source }
        return $null
    }
    $sdkRoot = 'C:\Program Files (x86)\Windows Kits\10\bin'
    if (-not (Test-Path -LiteralPath $sdkRoot)) { return $null }
    $found = Get-ChildItem -Path $sdkRoot -Filter 'signtool.exe' -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.DirectoryName -like '*\x64' } |
        Sort-Object { $_.DirectoryName } -Descending |
        Select-Object -First 1 -ExpandProperty FullName
    return $found
}

# =============================================================================
# Verify command
# =============================================================================

function Invoke-SignToolVerify([string]$SignToolExe, [string]$TargetFile) {
    $output = cmd.exe /c "`"$SignToolExe`" verify /pa /v `"$TargetFile`"" 2>&1
    return @{
        ExitCode = $LASTEXITCODE
        Output   = ($output | Out-String).TrimEnd()
    }
}

# =============================================================================
# Sign command
# =============================================================================

function Import-EnvFile([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
        $line = $line.Trim()
        if ($line -eq '' -or $line.StartsWith('#')) { continue }
        $eq = $line.IndexOf('=')
        if ($eq -gt 0) {
            $key = $line.Substring(0, $eq)
            $val = $line.Substring($eq + 1)
            if (-not [Environment]::GetEnvironmentVariable($key)) {
                [Environment]::SetEnvironmentVariable($key, $val, 'Process')
            }
        }
    }
}

function Find-Dlib([string]$ExplicitPath) {
    if (-not [string]::IsNullOrEmpty($ExplicitPath)) {
        if (Test-Path -LiteralPath $ExplicitPath -PathType Leaf) { return $ExplicitPath }
        return $null
    }
    $default = Join-Path $env:LOCALAPPDATA 'Microsoft\MicrosoftTrustedSigningClientTools\Azure.CodeSigning.Dlib.dll'
    if (Test-Path -LiteralPath $default -PathType Leaf) { return $default }
    return $null
}

function Invoke-SignToolSign([string]$SignToolExe, [string]$DlibDll, [string]$MetadataJson, [string]$TargetFile) {
    $output = cmd.exe /c "`"$SignToolExe`" sign /v /fd SHA256 /tr `"http://timestamp.acs.microsoft.com`" /td SHA256 /dlib `"$DlibDll`" /dmdf `"$MetadataJson`" `"$TargetFile`"" 2>&1
    return @{
        ExitCode = $LASTEXITCODE
        Output   = ($output | Out-String).TrimEnd()
    }
}

# =============================================================================
# Output helpers
# =============================================================================

function Write-ResultOutput([string]$Command, [hashtable]$Envelope) {
    switch ($Format) {
        'json'   { Write-Output ($Envelope | ConvertTo-Json -Depth 5 -Compress) }
        'object' {
            $obj = [PSCustomObject]@{ ok = $Envelope.ok; command = $Command; tool = [PSCustomObject]$Envelope.tool }
            if ($Envelope.ContainsKey('result')) {
                $resultObj = if ($Envelope.result -is [System.Collections.IDictionary]) { [PSCustomObject]$Envelope.result } else { $Envelope.result }
                $obj | Add-Member -MemberType NoteProperty -Name 'result' -Value $resultObj
            }
            if ($Envelope.ContainsKey('error')) {
                $obj | Add-Member -MemberType NoteProperty -Name 'error' -Value ([PSCustomObject]$Envelope.error)
            }
            Write-Output $obj
        }
    }
}

function Write-OutputFile([hashtable]$Envelope) {
    if (-not [string]::IsNullOrEmpty($OutputFile)) {
        $Envelope | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $OutputFile -Encoding UTF8
    }
}

function Write-ErrorResult([string]$Command, [int]$Code, [string]$Message) {
    $envelope = @{
        ok      = $false
        command = $Command
        tool    = @{ name = 'delphi-codesign-azure'; version = $script:ToolVersion }
        error   = @{ code = $Code; message = $Message }
    }
    switch ($Format) {
        'json'   { Write-Output ($envelope | ConvertTo-Json -Depth 5 -Compress) }
        'object' { Write-ResultOutput $Command $envelope }
        default  { Write-Error $Message -ErrorAction Continue }
    }
}

# =============================================================================
# Main execution
# =============================================================================

# Dot-source guard: when the script is dot-sourced (. ./script.ps1), load
# functions into the caller's scope but skip the main execution block.
# This allows Pester tests to unit-test individual functions directly.
if ($MyInvocation.InvocationName -eq '.') { return }

# --- Verify command ---

if ($Verify) {
    try {
        $resolvedFile = $null
        if (-not [string]::IsNullOrEmpty($FilePath)) {
            $resolvedFile = Resolve-Path -LiteralPath $FilePath -ErrorAction SilentlyContinue
        }
        if ($null -eq $resolvedFile) {
            Write-ErrorResult 'verify' $ExitFatal "File not found: $FilePath"
            exit $ExitFatal
        }
        $resolvedFilePath = $resolvedFile.ProviderPath

        $signtool = Find-SignTool $SignToolPath
        if ($null -eq $signtool) {
            Write-ErrorResult 'verify' $ExitFatal 'signtool.exe not found. Install the Windows SDK or pass -SignToolPath.'
            exit $ExitFatal
        }

        $result = Invoke-SignToolVerify -SignToolExe $signtool -TargetFile $resolvedFilePath
        $signed = ($result.ExitCode -eq 0)
        $outputLines = @($result.Output -split '\r?\n')

        $envelope = @{
            ok      = $signed
            command = 'verify'
            tool    = @{ name = 'delphi-codesign-azure'; version = $script:ToolVersion }
            result  = @{
                filePath         = $resolvedFilePath
                signed           = $signed
                signtoolExitCode = $result.ExitCode
                signtoolOutput   = $outputLines
            }
        }

        Write-OutputFile $envelope

        switch ($Format) {
            'text'   { Write-Host $result.Output }
            default  { Write-ResultOutput 'verify' $envelope }
        }

        if ($signed) { exit $ExitSuccess }
        else { exit $ExitDirty }
    }
    catch {
        Write-ErrorResult 'verify' $ExitFatal "$_"
        exit $ExitFatal
    }
}

# --- Sign command ---

if ($Sign) {
    try {
        # Load .env file for Azure credentials
        if (-not [string]::IsNullOrEmpty($EnvFile)) {
            Import-EnvFile $EnvFile
        }

        # Find signtool.exe
        $signtool = Find-SignTool $SignToolPath
        if ($null -eq $signtool) {
            Write-ErrorResult 'sign' $ExitFatal 'signtool.exe not found. Install the Windows SDK or pass -SignToolPath.'
            exit $ExitFatal
        }

        # Find Azure.CodeSigning.Dlib.dll
        $dlib = Find-Dlib $DlibPath
        if ($null -eq $dlib) {
            $msg = if (-not [string]::IsNullOrEmpty($DlibPath)) { "Azure.CodeSigning.Dlib.dll not found at: $DlibPath" }
                   else { 'Azure.CodeSigning.Dlib.dll not found. Install via: winget install -e --id Microsoft.Azure.TrustedSigningClientTools' }
            Write-ErrorResult 'sign' $ExitFatal $msg
            exit $ExitFatal
        }

        # Find metadata.json
        $metadata = $MetadataPath
        if ([string]::IsNullOrEmpty($metadata)) {
            $metadata = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Definition) 'metadata.json'
        }
        if (-not (Test-Path -LiteralPath $metadata -PathType Leaf)) {
            Write-ErrorResult 'sign' $ExitFatal "Metadata JSON not found at: $metadata"
            exit $ExitFatal
        }

        # Validate Azure credentials
        foreach ($var in @('AZURE_TENANT_ID', 'AZURE_CLIENT_ID', 'AZURE_CLIENT_SECRET')) {
            if (-not [Environment]::GetEnvironmentVariable($var)) {
                Write-ErrorResult 'sign' $ExitFatal "Environment variable $var is not set. Pass -EnvFile or set it in the environment."
                exit $ExitFatal
            }
        }

        # Sign each file
        $signed = 0
        $failed = 0
        $items = [System.Collections.Generic.List[object]]::new()

        foreach ($file in $Files) {
            if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
                if ($Format -eq 'text') { Write-Host "  SKIP  $file (not found)" -ForegroundColor Yellow }
                $items.Add(@{ file = $file; success = $false; message = 'File not found' })
                $failed++
                continue
            }

            $resolvedFile = (Resolve-Path -LiteralPath $file).ProviderPath
            if ($Format -eq 'text') { Write-Host "  SIGN  $resolvedFile" -ForegroundColor Cyan }

            $result = Invoke-SignToolSign -SignToolExe $signtool -DlibDll $dlib -MetadataJson $metadata -TargetFile $resolvedFile

            if ($result.ExitCode -ne 0) {
                if ($Format -eq 'text') {
                    Write-Host $result.Output -ForegroundColor Red
                    Write-Host "  FAIL  $resolvedFile (exit code $($result.ExitCode))" -ForegroundColor Red
                }
                $items.Add(@{ file = $resolvedFile; success = $false; exitCode = $result.ExitCode; message = $result.Output })
                $failed++
            }
            else {
                if ($Format -eq 'text') { Write-Host "  OK    $resolvedFile" -ForegroundColor Green }
                $items.Add(@{ file = $resolvedFile; success = $true; exitCode = 0 })
                $signed++
            }
        }

        # Output results
        $allOk = ($failed -eq 0)
        $total = $Files.Count

        $envelope = @{
            ok      = $allOk
            command = 'sign'
            tool    = @{ name = 'delphi-codesign-azure'; version = $script:ToolVersion }
            result  = @{
                signed = $signed
                failed = $failed
                total  = $total
                items  = @($items)
            }
        }

        Write-OutputFile $envelope

        switch ($Format) {
            'text' {
                Write-Host ''
                Write-Host "Signed: $signed  Failed: $failed  Total: $total"
            }
            default { Write-ResultOutput 'sign' $envelope }
        }

        if ($allOk) { exit $ExitSuccess }
        elseif ($signed -gt 0) { exit $ExitPartialFailure }
        else { exit $ExitFatal }
    }
    catch {
        Write-ErrorResult 'sign' $ExitFatal "$_"
        exit $ExitFatal
    }
}
