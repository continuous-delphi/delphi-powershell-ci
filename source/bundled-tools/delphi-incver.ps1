#requires -Version 5.1
# -----------------------------------------------------------------------------
# delphi-incver
#
# Increment version numbers in RC (VERSIONINFO), Delphi .dproj, or text
# source files. Supports WinVer (numeric N.N.N.N) and SemVer (semver.org)
# styles.
#
# Part of Continuous-Delphi: Strengthening Delphi's continued success
# https://github.com/continuous-delphi
#
# Project repository:
# https://github.com/continuous-delphi/delphi-incver
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
Increments a version number in an RC, DProj, or text file.

.DESCRIPTION
Parses a version string from the target file, increments the specified
component, and writes the updated version back to the file.

For RC files, all four VERSIONINFO locations are updated:
  FILEVERSION, PRODUCTVERSION (comma-separated)
  VALUE "FileVersion", VALUE "ProductVersion" (dot-separated strings)

For DProj files, the FileVersion value inside every VerInfo_Keys element
is updated across all PropertyGroups. ProductVersion is left unchanged.

For text files, a regex pattern with a capture group identifies the
version string to update.

Exit codes:
  0  success
  1  unexpected error
  2  invalid arguments
  3  file not found or unreadable
  4  version pattern not found in file
  5  version increment failed (e.g. part/width mismatch)

.EXAMPLE
pwsh -File delphi-incver.ps1 -File src/versioninfo.rc

.EXAMPLE
./delphi-incver.ps1 -File src/tool.ps1 -Target Text -Pattern '\$script:ToolVersion\s*=\s*''([^'']+)'''

.EXAMPLE
pwsh -File delphi-incver.ps1 -File src/MyApp.dproj

.EXAMPLE
pwsh -File delphi-incver.ps1 -File src/versioninfo.rc -Part minor
#>

[CmdletBinding()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
  Justification='Write-Host is intentional: standalone CLI tool streams status to the console host.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'OutputFile',
  Justification='OutputFile is consumed inside the Write-Result helper function.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
  Justification='Update-RcContent, Update-DProjContent, and Update-TextContent are pure transforms; file I/O is in the main block.')]
param(
    [Parameter(ParameterSetName = 'IncVer', Mandatory)]
    [string]$File,

    [Parameter(ParameterSetName = 'IncVer')]
    [ValidateSet('RC', 'DProj', 'Text')]
    [string]$Target,

    [Parameter(ParameterSetName = 'IncVer')]
    [ValidateSet('WinVer', 'SemVer')]
    [string]$Style,

    [Parameter(ParameterSetName = 'IncVer')]
    [ValidateSet('major', 'minor', 'patch', 'build', 'pre-release')]
    [string]$Part,

    [Parameter(ParameterSetName = 'IncVer')]
    [string]$Pattern,

    [Parameter(ParameterSetName = 'IncVer')]
    [string]$OutputFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExitSuccess          = 0
$ExitUnexpectedError  = 1
$ExitInvalidArguments = 2
$ExitFileNotFound     = 3
$ExitPatternNotFound  = 4
$ExitIncrementFailed  = 5

$script:ToolVersion = '0.2.0'

# -----------------------------------------------------------------------------
# Version parsing and formatting
# -----------------------------------------------------------------------------

function ConvertFrom-WinVer {
    <#
    .SYNOPSIS
        Parses a WinVer string (dot or comma separated) into an int array.
    #>
    param([string]$VersionString)

    $separator = if ($VersionString -match ',') { ',' } else { '.' }
    $parts = $VersionString -split "[${separator}\s]+" | Where-Object { $_ -ne '' }
    $ints = @()
    foreach ($p in $parts) {
        $val = 0
        if (-not [int]::TryParse($p.Trim(), [ref]$val)) {
            throw "Non-numeric version component '$p' in '$VersionString'"
        }
        $ints += $val
    }
    if ($ints.Count -lt 1 -or $ints.Count -gt 4) {
        throw "WinVer must have 1-4 numeric components, got $($ints.Count) in '$VersionString'"
    }
    return , $ints
}

function ConvertTo-WinVer {
    <#
    .SYNOPSIS
        Formats an int array back to a version string with the given separator.
    #>
    param(
        [int[]]$Parts,
        [string]$Separator = '.'
    )
    return ($Parts -join $Separator)
}

function ConvertFrom-SemVer {
    <#
    .SYNOPSIS
        Parses a SemVer string into a hashtable with Major, Minor, Patch,
        PreRelease, and BuildMetadata.
    #>
    param([string]$VersionString)

    # SemVer: MAJOR.MINOR.PATCH[-prerelease][+buildmetadata]
    $semverPattern = '^(\d+)(?:\.(\d+))?(?:\.(\d+))?(?:-([a-zA-Z0-9]+(?:\.[a-zA-Z0-9]+)*))?(?:\+([a-zA-Z0-9]+(?:\.[a-zA-Z0-9]+)*))?$'
    if ($VersionString -notmatch $semverPattern) {
        throw "Invalid SemVer string: '$VersionString'"
    }

    $result = @{
        Major         = [int]$Matches[1]
        Minor         = $null
        Patch         = $null
        PreRelease    = $null
        BuildMetadata = $null
        PartCount     = 1
    }
    if ($null -ne $Matches[2] -and $Matches[2] -ne '') {
        $result.Minor = [int]$Matches[2]
        $result.PartCount = 2
    }
    if ($null -ne $Matches[3] -and $Matches[3] -ne '') {
        $result.Patch = [int]$Matches[3]
        $result.PartCount = 3
    }
    if ($null -ne $Matches[4] -and $Matches[4] -ne '') {
        $result.PreRelease = $Matches[4]
    }
    if ($null -ne $Matches[5] -and $Matches[5] -ne '') {
        $result.BuildMetadata = $Matches[5]
    }
    return $result
}

function ConvertTo-SemVer {
    <#
    .SYNOPSIS
        Reconstructs a SemVer string from a parsed hashtable.
    #>
    param([hashtable]$Parsed)

    $ver = "$($Parsed.Major)"
    if ($null -ne $Parsed.Minor) {
        $ver += ".$($Parsed.Minor)"
    }
    if ($null -ne $Parsed.Patch) {
        $ver += ".$($Parsed.Patch)"
    }
    if (-not [string]::IsNullOrEmpty($Parsed.PreRelease)) {
        $ver += "-$($Parsed.PreRelease)"
    }
    if (-not [string]::IsNullOrEmpty($Parsed.BuildMetadata)) {
        $ver += "+$($Parsed.BuildMetadata)"
    }
    return $ver
}

# -----------------------------------------------------------------------------
# Version incrementing
# -----------------------------------------------------------------------------

function Step-WinVer {
    <#
    .SYNOPSIS
        Increments a WinVer component and zeros trailing parts.
    #>
    param(
        [int[]]$Parts,
        [string]$PartName
    )

    $partMap = @{ major = 0; minor = 1; patch = 2; build = 3 }

    if ([string]::IsNullOrEmpty($PartName)) {
        # Default: bump the last component
        $idx = $Parts.Count - 1
    }
    else {
        if (-not $partMap.ContainsKey($PartName)) {
            throw "Invalid part '$PartName' for WinVer style."
        }
        $idx = $partMap[$PartName]
        if ($idx -ge $Parts.Count) {
            throw "Cannot increment '$PartName' on a $($Parts.Count)-part version. The version does not have that component."
        }
    }

    $newParts = [int[]]::new($Parts.Count)
    for ($i = 0; $i -lt $Parts.Count; $i++) {
        if ($i -lt $idx) {
            $newParts[$i] = $Parts[$i]
        }
        elseif ($i -eq $idx) {
            $newParts[$i] = $Parts[$i] + 1
        }
        else {
            $newParts[$i] = 0
        }
    }
    return , $newParts
}

function Step-SemVer {
    <#
    .SYNOPSIS
        Increments a SemVer component according to semver.org rules.
    #>
    param(
        [hashtable]$Parsed,
        [string]$PartName
    )

    $result = @{
        Major         = $Parsed.Major
        Minor         = $Parsed.Minor
        Patch         = $Parsed.Patch
        PreRelease    = $Parsed.PreRelease
        BuildMetadata = $Parsed.BuildMetadata
        PartCount     = $Parsed.PartCount
    }

    if ([string]::IsNullOrEmpty($PartName)) {
        # Default: bump the last numeric component
        if (-not [string]::IsNullOrEmpty($Parsed.PreRelease)) {
            # Bump numeric suffix of pre-release
            return Step-SemVerPreRelease $result
        }
        elseif ($null -ne $Parsed.Patch) {
            $result.Patch = $Parsed.Patch + 1
        }
        elseif ($null -ne $Parsed.Minor) {
            $result.Minor = $Parsed.Minor + 1
        }
        else {
            $result.Major = $Parsed.Major + 1
        }
        return $result
    }

    switch ($PartName) {
        'major' {
            $result.Major = $Parsed.Major + 1
            if ($null -ne $result.Minor) { $result.Minor = 0 }
            if ($null -ne $result.Patch) { $result.Patch = 0 }
            $result.PreRelease = $null
        }
        'minor' {
            if ($null -eq $Parsed.Minor) {
                throw "Cannot increment 'minor' on a $($Parsed.PartCount)-part version."
            }
            $result.Minor = $Parsed.Minor + 1
            if ($null -ne $result.Patch) { $result.Patch = 0 }
            $result.PreRelease = $null
        }
        'patch' {
            if ($null -eq $Parsed.Patch) {
                throw "Cannot increment 'patch' on a $($Parsed.PartCount)-part version."
            }
            $result.Patch = $Parsed.Patch + 1
            $result.PreRelease = $null
        }
        'build' {
            throw "Cannot increment 'build' on a SemVer version. SemVer uses 3 components (major.minor.patch). Use 'patch' instead, or switch to WinVer style."
        }
        'pre-release' {
            if ([string]::IsNullOrEmpty($Parsed.PreRelease)) {
                throw "Cannot increment 'pre-release': version has no pre-release tag."
            }
            $result = Step-SemVerPreRelease $result
        }
    }

    return $result
}

function Step-SemVerPreRelease {
    <#
    .SYNOPSIS
        Increments the numeric suffix of a pre-release tag.
        alpha.1 -> alpha.2, beta -> beta.1
    #>
    param([hashtable]$Parsed)

    $pre = $Parsed.PreRelease
    if ($pre -match '^(.+?)\.(\d+)$') {
        $Parsed.PreRelease = "$($Matches[1]).$([int]$Matches[2] + 1)"
    }
    elseif ($pre -match '(\d+)$') {
        $num = [int]$Matches[1]
        $prefix = $pre.Substring(0, $pre.Length - $Matches[1].Length)
        $Parsed.PreRelease = "${prefix}$($num + 1)"
    }
    else {
        # No numeric component -- append .1
        $Parsed.PreRelease = "$pre.1"
    }
    return $Parsed
}

# -----------------------------------------------------------------------------
# File content updating
# -----------------------------------------------------------------------------

function Update-RcContent {
    <#
    .SYNOPSIS
        Updates all VERSIONINFO locations in RC file content.
        Returns a hashtable with Content (updated string) and OldVersion/NewVersion.
    #>
    param(
        [string]$Content,
        [string]$PartName
    )

    # Extract version from FILEVERSION (comma-separated, canonical source)
    $fileVerPattern = '(?m)^(\s*FILEVERSION\s+)(\d+(?:\s*,\s*\d+){0,3})\s*$'
    if ($Content -notmatch $fileVerPattern) {
        return $null
    }
    $oldCommaVer = $Matches[2]
    $oldParts = ConvertFrom-WinVer $oldCommaVer
    $newParts = Step-WinVer -Parts $oldParts -PartName $PartName

    $oldDotVer   = ConvertTo-WinVer -Parts $oldParts -Separator '.'
    $newDotVer   = ConvertTo-WinVer -Parts $newParts -Separator '.'
    $newCommaVer = ConvertTo-WinVer -Parts $newParts -Separator ','

    # Build regex patterns that match the exact old part count
    $commaCount = $oldParts.Count - 1
    $dotCount   = $oldParts.Count - 1

    $commaPattern = '\d+' + ('\s*,\s*\d+' * $commaCount)
    $dotPattern   = '\d+' + ('\.\d+' * $dotCount)

    # Replace FILEVERSION and PRODUCTVERSION (comma-separated)
    $Content = $Content -replace "(?m)^(\s*FILEVERSION\s+)${commaPattern}(\s*)$",    "`${1}${newCommaVer}`${2}"
    $Content = $Content -replace "(?m)^(\s*PRODUCTVERSION\s+)${commaPattern}(\s*)$", "`${1}${newCommaVer}`${2}"

    # Replace VALUE "FileVersion" and VALUE "ProductVersion" (dot-separated strings)
    $Content = $Content -replace "(VALUE\s+`"FileVersion`"\s*,\s*`")${dotPattern}",    "`${1}${newDotVer}"
    $Content = $Content -replace "(VALUE\s+`"ProductVersion`"\s*,\s*`")${dotPattern}",  "`${1}${newDotVer}"

    return @{
        Content    = $Content
        OldVersion = $oldDotVer
        NewVersion = $newDotVer
    }
}

function Update-TextContent {
    <#
    .SYNOPSIS
        Uses a regex pattern with a capture group to find and replace a
        version string in text file content.
    #>
    param(
        [string]$Content,
        [string]$Pattern,
        [string]$NewVersion
    )

    # The pattern must have exactly one capture group for the version
    $regex = [regex]::new($Pattern)
    $match = $regex.Match($Content)
    if (-not $match.Success) {
        return $null
    }
    if ($match.Groups.Count -lt 2) {
        throw "Pattern must contain at least one capture group for the version string."
    }

    $group = $match.Groups[1]
    $before = $Content.Substring(0, $group.Index)
    $after  = $Content.Substring($group.Index + $group.Length)
    $updated = $before + $NewVersion + $after

    return @{
        Content    = $updated
        OldVersion = $group.Value
        NewVersion = $NewVersion
    }
}

function Update-DProjContent {
    <#
    .SYNOPSIS
        Updates FileVersion in all VerInfo_Keys elements of a .dproj XML file.
        Returns a hashtable with XmlDocument, OldVersion, and NewVersion.
    #>
    param(
        [string]$FilePath,
        [string]$PartName
    )

    $xml = [xml](Get-Content -LiteralPath $FilePath -Raw -ErrorAction Stop)
    $nsMgr = [System.Xml.XmlNamespaceManager]::new($xml.NameTable)
    $nsMgr.AddNamespace('ms', 'http://schemas.microsoft.com/developer/msbuild/2003')

    $nodes = $xml.SelectNodes('//ms:VerInfo_Keys', $nsMgr)
    if ($null -eq $nodes -or $nodes.Count -eq 0) {
        return $null
    }

    # Read current FileVersion from the first VerInfo_Keys node
    $firstKeys = $nodes[0].InnerText
    $oldVersionStr = $null
    foreach ($pair in $firstKeys -split ';') {
        $kv = $pair -split '=', 2
        if ($kv[0] -eq 'FileVersion') {
            $oldVersionStr = $kv[1]
            break
        }
    }
    if ([string]::IsNullOrEmpty($oldVersionStr)) {
        return $null
    }

    # Parse and increment
    $oldParts = ConvertFrom-WinVer $oldVersionStr
    $newParts = Step-WinVer -Parts $oldParts -PartName $PartName
    $newVersionStr = ConvertTo-WinVer -Parts $newParts -Separator '.'

    # Update FileVersion in all VerInfo_Keys nodes
    foreach ($node in $nodes) {
        $keysStr = $node.InnerText
        $keys = $keysStr -split ';'
        for ($i = 0; $i -lt $keys.Count; $i++) {
            $kv = $keys[$i] -split '=', 2
            if ($kv[0] -eq 'FileVersion') {
                $keys[$i] = "FileVersion=$newVersionStr"
            }
        }
        $node.InnerText = $keys -join ';'
    }

    return @{
        XmlDocument = $xml
        OldVersion  = $oldVersionStr
        NewVersion  = $newVersionStr
    }
}

# -----------------------------------------------------------------------------
# Auto-detection helpers
# -----------------------------------------------------------------------------

function Resolve-Target {
    param([string]$FilePath, [string]$ExplicitTarget)
    if (-not [string]::IsNullOrEmpty($ExplicitTarget)) { return $ExplicitTarget }
    $ext = [System.IO.Path]::GetExtension($FilePath).ToLower()
    if ($ext -eq '.rc') { return 'RC' }
    if ($ext -eq '.dproj') { return 'DProj' }
    return 'Text'
}

function Resolve-Style {
    param([string]$Target, [string]$ExplicitStyle)
    if (-not [string]::IsNullOrEmpty($ExplicitStyle)) { return $ExplicitStyle }
    if ($Target -eq 'RC' -or $Target -eq 'DProj') { return 'WinVer' }
    return 'SemVer'
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
# Main
# -----------------------------------------------------------------------------

try {
    # Validate file exists
    if (-not (Test-Path -LiteralPath $File -PathType Leaf)) {
        Write-Error "File not found: $File" -ErrorAction Continue
        Write-Result @{ file = $File; error = "File not found" }
        exit $ExitFileNotFound
    }

    # Auto-detect target and style
    $resolvedTarget = Resolve-Target -FilePath $File -ExplicitTarget $Target
    $resolvedStyle  = Resolve-Style  -Target $resolvedTarget -ExplicitStyle $Style

    # Validate combinations
    if ($resolvedTarget -in @('RC', 'DProj') -and $resolvedStyle -eq 'SemVer') {
        Write-Error "$resolvedTarget target does not support SemVer style." -ErrorAction Continue
        exit $ExitInvalidArguments
    }
    if ($Part -eq 'pre-release' -and $resolvedStyle -ne 'SemVer') {
        Write-Error "Part 'pre-release' is only valid with SemVer style." -ErrorAction Continue
        exit $ExitInvalidArguments
    }
    if ($resolvedTarget -eq 'Text' -and [string]::IsNullOrEmpty($Pattern)) {
        Write-Error "Text target requires a -Pattern parameter with a capture group." -ErrorAction Continue
        exit $ExitInvalidArguments
    }

    # Read file content
    $content = Get-Content -LiteralPath $File -Raw -ErrorAction Stop

    if ($resolvedTarget -eq 'RC') {
        # RC target -- update all VERSIONINFO locations
        $updateResult = Update-RcContent -Content $content -PartName $Part
        if ($null -eq $updateResult) {
            Write-Error "No VERSIONINFO block found in $File" -ErrorAction Continue
            Write-Result @{ file = $File; error = "VERSIONINFO not found" }
            exit $ExitPatternNotFound
        }

        Set-Content -LiteralPath $File -Value $updateResult.Content -NoNewline -Encoding UTF8
        Write-Host "$($updateResult.OldVersion) -> $($updateResult.NewVersion)"

        Write-Result @{
            file       = $File
            target     = $resolvedTarget
            style      = $resolvedStyle
            part       = if ([string]::IsNullOrEmpty($Part)) { 'last' } else { $Part }
            oldVersion = $updateResult.OldVersion
            newVersion = $updateResult.NewVersion
        }
        exit $ExitSuccess
    }
    elseif ($resolvedTarget -eq 'DProj') {
        # DProj target -- update FileVersion in all VerInfo_Keys elements
        $updateResult = Update-DProjContent -FilePath $File -PartName $Part
        if ($null -eq $updateResult) {
            Write-Error "No VerInfo_Keys with FileVersion found in $File" -ErrorAction Continue
            Write-Result @{ file = $File; error = "VerInfo_Keys not found" }
            exit $ExitPatternNotFound
        }

        $updateResult.XmlDocument.Save($File)
        Write-Host "$($updateResult.OldVersion) -> $($updateResult.NewVersion)"

        Write-Result @{
            file       = $File
            target     = $resolvedTarget
            style      = $resolvedStyle
            part       = if ([string]::IsNullOrEmpty($Part)) { 'last' } else { $Part }
            oldVersion = $updateResult.OldVersion
            newVersion = $updateResult.NewVersion
        }
        exit $ExitSuccess
    }
    else {
        # Text target -- use pattern to find and update version
        # First extract the current version using the pattern
        $regex = [regex]::new($Pattern)
        $match = $regex.Match($content)
        if (-not $match.Success) {
            Write-Error "Pattern not found in $File" -ErrorAction Continue
            Write-Result @{ file = $File; error = "Pattern not found" }
            exit $ExitPatternNotFound
        }
        if ($match.Groups.Count -lt 2) {
            Write-Error "Pattern must contain at least one capture group for the version string." -ErrorAction Continue
            exit $ExitInvalidArguments
        }

        $oldVersionStr = $match.Groups[1].Value

        # Parse and increment based on style
        if ($resolvedStyle -eq 'WinVer') {
            $parts = ConvertFrom-WinVer $oldVersionStr
            $newParts = Step-WinVer -Parts $parts -PartName $Part
            $newVersionStr = ConvertTo-WinVer -Parts $newParts -Separator '.'
        }
        else {
            # SemVer
            $parsed = ConvertFrom-SemVer $oldVersionStr
            $bumped = Step-SemVer -Parsed $parsed -PartName $Part
            $newVersionStr = ConvertTo-SemVer $bumped
        }

        # Replace the version in the content using the capture group position
        $updateResult = Update-TextContent -Content $content -Pattern $Pattern -NewVersion $newVersionStr
        if ($null -eq $updateResult) {
            Write-Error "Failed to update version in $File" -ErrorAction Continue
            Write-Result @{ file = $File; error = "Update failed" }
            exit $ExitPatternNotFound
        }

        Set-Content -LiteralPath $File -Value $updateResult.Content -NoNewline -Encoding UTF8
        Write-Host "$oldVersionStr -> $newVersionStr"

        Write-Result @{
            file       = $File
            target     = $resolvedTarget
            style      = $resolvedStyle
            part       = if ([string]::IsNullOrEmpty($Part)) { 'last' } else { $Part }
            oldVersion = $oldVersionStr
            newVersion = $newVersionStr
        }
        exit $ExitSuccess
    }
}
catch {
    $exitCode = $ExitUnexpectedError
    if ($_.Exception.Message -match 'Cannot increment') {
        $exitCode = $ExitIncrementFailed
    }
    Write-Error $_.Exception.Message -ErrorAction Continue
    Write-Result @{ file = $File; error = $_.Exception.Message }
    exit $exitCode
}
