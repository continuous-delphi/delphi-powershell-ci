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

For RC files, the two FileVersion locations are updated:
  FILEVERSION (comma-separated)
  VALUE "FileVersion" (dot-separated string)
ProductVersion is left unchanged.

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

$script:ToolVersion = '1.5.1'

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
        Updates FileVersion in VERSIONINFO block of RC file content (leaves ProductVersion unchanged).
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

    # Replace FILEVERSION (comma-separated) -- leave PRODUCTVERSION unchanged
    $Content = $Content -replace "(?m)^(\s*FILEVERSION\s+)${commaPattern}(\s*)$",    "`${1}${newCommaVer}`${2}"

    # Replace VALUE "FileVersion" (dot-separated string) -- leave VALUE "ProductVersion" unchanged
    $Content = $Content -replace "(VALUE\s+`"FileVersion`"\s*,\s*`")${dotPattern}",    "`${1}${newDotVer}"

    return @{
        Content    = $Content
        OldVersion = $oldDotVer
        NewVersion = $newDotVer
    }
}

function Update-TextContent {
    <#
    .SYNOPSIS
        Parses, increments, and replaces a version string in text file content
        using a regex pattern with a capture group.
        Returns a hashtable with Content (updated string) and OldVersion/NewVersion.
    #>
    param(
        [string]$Content,
        [string]$Pattern,
        [string]$Style,
        [string]$PartName
    )

    $regex = [regex]::new($Pattern)
    $match = $regex.Match($Content)
    if (-not $match.Success) {
        return $null
    }
    if ($match.Groups.Count -lt 2) {
        throw "Pattern must contain at least one capture group for the version string."
    }

    $group = $match.Groups[1]
    $oldVersionStr = $group.Value

    # Parse and increment based on style
    if ($Style -eq 'WinVer') {
        $parts = ConvertFrom-WinVer $oldVersionStr
        $newParts = Step-WinVer -Parts $parts -PartName $PartName
        $newVersionStr = ConvertTo-WinVer -Parts $newParts -Separator '.'
    }
    else {
        $parsed = ConvertFrom-SemVer $oldVersionStr
        $bumped = Step-SemVer -Parsed $parsed -PartName $PartName
        $newVersionStr = ConvertTo-SemVer $bumped
    }

    $before = $Content.Substring(0, $group.Index)
    $after  = $Content.Substring($group.Index + $group.Length)
    $updated = $before + $newVersionStr + $after

    return @{
        Content    = $updated
        OldVersion = $oldVersionStr
        NewVersion = $newVersionStr
    }
}

function Update-DProjContent {
    <#
    .SYNOPSIS
        Updates FileVersion in every VerInfo_Keys element and keeps the discrete
        VerInfo_MajorVer/MinorVer/Release/Build elements of the same PropertyGroup
        in sync (update where present, create where absent).

        The .dproj format stores the file version in two representations read by
        two different consumers: builds read the FileVersion key, while the RAD
        Studio Version Info options page reads the discrete elements and writes its
        state back into BOTH on Save. Bumping only the key therefore risks a
        silent reversion the next time a developer opens Project Options and saves.
        Keeping both in sync closes that gap (see issue #8).

        The baseline version is the MAXIMUM FileVersion across all VerInfo_Keys
        nodes (component-wise numeric, missing components treated as zero; ties
        resolved to the last in document order). This avoids reading the Base
        group's 1.0.0.0 placeholder and regressing the effective version that lives
        in a more-derived config group (see issue #9). The bumped value is written
        to every VerInfo_Keys node, so a bump never decreases any FileVersion entry.

        Edits are applied as targeted string replacements so the file is preserved
        byte-for-byte apart from the owned values and inserted elements -- the BOM,
        line endings, indentation, and all other content are left untouched. (A DOM
        round-trip would reindent and re-serialize the whole document.)

        Returns a hashtable with Content, OldVersion, NewVersion, and
        DiscreteVersion -- or $null if no VerInfo_Keys carrying a FileVersion is
        found.
    #>
    param(
        [string]$Content,
        [string]$FilePath,
        [string]$PartName
    )

    # Collect every FileVersion across all VerInfo_Keys nodes (document order).
    $keysMatches = [regex]::Matches($Content, '<VerInfo_Keys>(.*?)</VerInfo_Keys>', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    $versionStrings = @()
    foreach ($km in $keysMatches) {
        if ($km.Groups[1].Value -match 'FileVersion=([^;<]+)') {
            $versionStrings += $Matches[1]
        }
    }
    if ($versionStrings.Count -eq 0) {
        return $null
    }

    # Select the baseline as the MAXIMUM FileVersion. Comparison is component-wise
    # numeric with missing components treated as zero; on ties, the last value in
    # document order wins so the retained width matches the most-derived group.
    # This prevents the Base group's 1.0.0.0 placeholder from being chosen and
    # regressing the effective version (issue #9). Every FileVersion must parse --
    # a bad value fails here (before any write) rather than being skipped.
    $baselineStr = $null
    $baselinePad = $null
    foreach ($vs in $versionStrings) {
        try {
            $parts = ConvertFrom-WinVer $vs
        }
        catch {
            throw "Unparsable FileVersion '$vs' in '$FilePath'. $($_.Exception.Message)"
        }
        $pad = @(0, 0, 0, 0)
        for ($i = 0; $i -lt $parts.Count -and $i -lt 4; $i++) { $pad[$i] = $parts[$i] }

        if ($null -eq $baselinePad) {
            $baselineStr = $vs
            $baselinePad = $pad
            continue
        }
        # $atLeast is true when $pad >= $baselinePad, so an equal value (tie) also
        # replaces the baseline and the last in document order is retained.
        $atLeast = $true
        for ($i = 0; $i -lt 4; $i++) {
            if ($pad[$i] -gt $baselinePad[$i]) { $atLeast = $true; break }
            if ($pad[$i] -lt $baselinePad[$i]) { $atLeast = $false; break }
        }
        if ($atLeast) {
            $baselineStr = $vs
            $baselinePad = $pad
        }
    }
    $oldVersionStr = $baselineStr

    # When the keys disagree, surface which distinct values were seen and which was
    # chosen. Informational only (never fails); visible on the console by default.
    $distinctCount = ($versionStrings | Select-Object -Unique | Measure-Object).Count
    if ($distinctCount -gt 1) {
        $summary = ($versionStrings | Group-Object | Sort-Object Name | ForEach-Object { "$($_.Name) (x$($_.Count))" }) -join ', '
        Write-Host "Multiple FileVersion values found: $summary. Using baseline $baselineStr."
    }

    # Parse and increment (the FileVersion string keeps its original width)
    $oldParts = ConvertFrom-WinVer $oldVersionStr
    $newParts = Step-WinVer -Parts $oldParts -PartName $PartName
    $newVersionStr = ConvertTo-WinVer -Parts $newParts -Separator '.'

    # Discrete four-part form: zero-pad on the right (discrete elements are always
    # four values even when the FileVersion string is narrower).
    $discrete = [int[]]@(0, 0, 0, 0)
    for ($i = 0; $i -lt $newParts.Count -and $i -lt 4; $i++) {
        $discrete[$i] = $newParts[$i]
    }
    $discreteVersionStr = $discrete -join '.'

    # Map discrete element names to their component values, in component order.
    $script:DProjNewFileVersion = $newVersionStr
    $script:DProjElementValues  = [ordered]@{
        'VerInfo_MajorVer' = $discrete[0]
        'VerInfo_MinorVer' = $discrete[1]
        'VerInfo_Release'  = $discrete[2]
        'VerInfo_Build'    = $discrete[3]
    }

    # Pre-validate existing discrete elements in the keyed PropertyGroups. Failing
    # here (before any write) guarantees a clear message and an untouched file when
    # a discrete element holds a non-numeric value.
    foreach ($pg in [regex]::Matches($Content, '<PropertyGroup\b.*?</PropertyGroup>', [System.Text.RegularExpressions.RegexOptions]::Singleline)) {
        if ($pg.Value -notmatch '<VerInfo_Keys>[^<]*FileVersion=') { continue }
        foreach ($name in $script:DProjElementValues.Keys) {
            $ex = [regex]::Match($pg.Value, "<$name>(.*?)</$name>", [System.Text.RegularExpressions.RegexOptions]::Singleline)
            if ($ex.Success) {
                $cur = $ex.Groups[1].Value.Trim()
                if ($cur -ne '' -and $cur -notmatch '^\d+$') {
                    throw "Non-numeric <$name> value '$cur' in '$FilePath'. Cannot sync discrete version elements."
                }
            }
        }
    }

    # Transform each PropertyGroup that carries a FileVersion key. PropertyGroups
    # do not nest in a .dproj, so a non-greedy match is safe.
    $evaluator = {
        param([System.Text.RegularExpressions.Match]$m)
        $block = $m.Value

        # Scope: exactly the PropertyGroups whose VerInfo_Keys gets its FileVersion
        # updated. Groups without a keyed FileVersion are left entirely alone.
        if ($block -notmatch '<VerInfo_Keys>[^<]*FileVersion=') {
            return $block
        }

        # 1. Update FileVersion inside VerInfo_Keys.
        $block = [regex]::Replace($block, '(FileVersion=)[^;<]+', "`${1}$script:DProjNewFileVersion")

        # Detect line ending and child indentation from the block itself so
        # inserted elements match the surrounding file exactly.
        $eol = if ($block -match "`r`n") { "`r`n" } else { "`n" }
        $indent = '        '
        if ($block -match "(?m)^([ \t]+)<VerInfo_Keys>") {
            $indent = $Matches[1]
        }

        # 2. Sync discrete elements: update in place where present, insert in
        #    alphabetical position where absent.
        foreach ($name in $script:DProjElementValues.Keys) {
            $value = $script:DProjElementValues[$name]
            $existing = [regex]::Match($block, "<$name>(.*?)</$name>", [System.Text.RegularExpressions.RegexOptions]::Singleline)
            if ($existing.Success) {
                # Value already validated numeric (or empty) in the pre-scan above.
                $block = $block.Remove($existing.Groups[1].Index, $existing.Groups[1].Length).Insert($existing.Groups[1].Index, "$value")
            }
            else {
                # Insert before the first sibling element whose name sorts after
                # this one (ordinal), matching the RAD Studio IDE's alphabetical
                # serialization of the VerInfo_* block; otherwise before the
                # closing </PropertyGroup>.
                $lines = [System.Collections.Generic.List[string]]($block -split [regex]::Escape($eol))
                $insertAt = -1
                for ($li = 1; $li -lt $lines.Count; $li++) {
                    $lm = [regex]::Match($lines[$li], '^\s*<([A-Za-z0-9_]+)[ >/]')
                    if (-not $lm.Success) { continue }
                    $sibName = $lm.Groups[1].Value
                    if ($sibName -eq 'PropertyGroup') { continue }
                    if ([string]::CompareOrdinal($sibName, $name) -gt 0) {
                        $insertAt = $li
                        break
                    }
                }
                if ($insertAt -lt 0) {
                    $insertAt = $lines.Count - 1
                }
                $lines.Insert($insertAt, "$indent<$name>$value</$name>")
                $block = [string]::Join($eol, $lines)
            }
        }

        return $block
    }

    $newContent = [regex]::Replace($Content, '<PropertyGroup\b.*?</PropertyGroup>', $evaluator, [System.Text.RegularExpressions.RegexOptions]::Singleline)

    return @{
        Content         = $newContent
        OldVersion      = $oldVersionStr
        NewVersion      = $newVersionStr
        DiscreteVersion = $discreteVersionStr
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
        # DProj target -- update FileVersion in all VerInfo_Keys elements and sync
        # the discrete VerInfo_* elements in the same PropertyGroups.
        $updateResult = Update-DProjContent -Content $content -FilePath $File -PartName $Part
        if ($null -eq $updateResult) {
            Write-Error "No VerInfo_Keys with FileVersion found in $File" -ErrorAction Continue
            Write-Result @{ file = $File; error = "VerInfo_Keys not found" }
            exit $ExitPatternNotFound
        }

        # Write bytes directly to preserve the file exactly: a real IDE .dproj is
        # UTF-8 with a BOM, but honor whatever the input actually had. CRLF and
        # indentation are already carried in the edited content string.
        $dprojBytes  = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $File).Path)
        $dprojHasBom = $dprojBytes.Length -ge 3 -and $dprojBytes[0] -eq 0xEF -and $dprojBytes[1] -eq 0xBB -and $dprojBytes[2] -eq 0xBF
        $dprojEnc    = [System.Text.UTF8Encoding]::new($dprojHasBom)
        [System.IO.File]::WriteAllText((Resolve-Path -LiteralPath $File).Path, $updateResult.Content, $dprojEnc)
        Write-Host "$($updateResult.OldVersion) -> $($updateResult.NewVersion)"

        Write-Result @{
            file            = $File
            target          = $resolvedTarget
            style           = $resolvedStyle
            part            = if ([string]::IsNullOrEmpty($Part)) { 'last' } else { $Part }
            oldVersion      = $updateResult.OldVersion
            newVersion      = $updateResult.NewVersion
            discreteVersion = $updateResult.DiscreteVersion
        }
        exit $ExitSuccess
    }
    else {
        # Text target -- parse, increment, and replace version via pattern
        $updateResult = Update-TextContent -Content $content -Pattern $Pattern -Style $resolvedStyle -PartName $Part
        if ($null -eq $updateResult) {
            Write-Error "Pattern not found in $File" -ErrorAction Continue
            Write-Result @{ file = $File; error = "Pattern not found" }
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
