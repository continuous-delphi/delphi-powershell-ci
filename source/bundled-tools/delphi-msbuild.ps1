# -----------------------------------------------------------------------------
# delphi-msbuild
#
# Simple command-line consistent builds for Delphi projects.
#
# Project repository:
# https://github.com/continuous-delphi/delphi-msbuild
#
# Pair with delphi-inspect to discover the full list of installed Delphi toolchains
# (or pick the latest) and pass build settings into scripts or CI.
# https://github.com/continuous-delphi/delphi-inspect
#
# Also bundled as part of delphi-powershell-ci, providing a suite of pipeline
# actions including: Clean, IncVer, Build, Run, Coverage, CallGraph, Copy, and Compress.
# https://github.com/continuous-delphi/delphi-powershell-ci
#
# Part of Continuous-Delphi: Strengthening Delphi's continued success
# https://github.com/continuous-delphi
#
# Copyright (c) 2026 Darian Miller
# Licensed under the MIT License.
# https://opensource.org/licenses/MIT
# SPDX-License-Identifier: MIT
# -----------------------------------------------------------------------------

<#
delphi-msbuild.ps1

Build a Delphi project using MSBuild.

Sources the Delphi build environment from rsvars.bat found under <RootDir>\bin\.
Designed to be run stand-alone or to accept piped output from
delphi-inspect.ps1 -DetectLatest -BuildSystem MSBuild.

USAGE
  # Auto-discover latest Delphi and build
  delphi-inspect.ps1 -DetectLatest -Platform Win32 -BuildSystem MSBuild |
      delphi-msbuild.ps1 -ProjectFile MyApp.dproj

  # Explicit root dir
  delphi-msbuild.ps1 -ProjectFile MyApp.dproj -RootDir "C:\RAD\Studio\23.0"

  # Override platform / config
  delphi-inspect.ps1 -DetectLatest -Platform Win64 -BuildSystem MSBuild |
      delphi-msbuild.ps1 -ProjectFile MyApp.dproj -Platform Win64 -Config Release

  # Stream output and rebuild
  delphi-inspect.ps1 -DetectLatest -Platform Win32 -BuildSystem MSBuild |
      delphi-msbuild.ps1 -ProjectFile MyApp.dproj -Target Rebuild -ShowOutput

NOTES
  -RootDir is the Delphi installation root (e.g. C:\RAD\Studio\23.0).
  rsvars.bat is expected at <RootDir>\bin\rsvars.bat.

  When piped a delphi-inspect result object, RootDir is taken from the object's
  .rootDir property.  An explicit -RootDir parameter takes precedence.

  -Config is the RAD Studio MSBuild property name (/p:Config); common values
  are Debug and Release.

  -BuildAllUnits (switch) sets /p:DCC_BuildAllUnits=true, and -EnvLibraryPath
  sets /p:_EnvLibraryPath=... -- two properties the batch build path relies
  on.  Both are emitted before -Property, so a matching -Property entry still
  overrides them.  A trailing path separator on -EnvLibraryPath is trimmed.

  -Property accepts a hashtable of arbitrary MSBuild properties, each passed
  through as /p:Key=Value (e.g. -Property @{ DCC_BuildAllUnits = 'true' }).
  These are appended after the built-in properties, so an entry overrides a
  built-in property of the same name.  The whole /p: set is written to a
  temporary MSBuild response file and passed as @file, so a value may contain
  whitespace, semicolons, or a trailing backslash and reach MSBuild intact under
  both Windows PowerShell 5.1 and PowerShell 7 (see Get-MsbuildResponseLines and
  ConvertTo-MsbuildResponseValue).

  -SkipRsvars builds using the caller's current process environment instead of
  requiring and sourcing <RootDir>\bin\rsvars.bat.  With it, -RootDir is optional
  metadata and is not validated.  -MsbuildPath invokes a specific msbuild.exe
  instead of resolving one from PATH, for explicit per-era framework selection.

  MSBuild output is always captured and returned in the result object's
  .output property.  Use -ShowOutput to also stream output to the console in
  real time; .output is populated in both cases.

  Exit codes:
    0  success
    1  unexpected error
    2  invalid arguments (missing -ProjectFile, or -MsbuildPath does not exist
       or is not a file)
    3  rootDir missing/empty, directory not found, or rsvars.bat not found
       (not applicable when -SkipRsvars is set)
    4  project file not found
    5  MSBuild failed (non-zero exit code)
#>

[CmdletBinding()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'ExitInvalidArguments',
  Justification='Reserved exit code constant; not yet referenced in code paths')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseProcessBlockForPipelineCommand', '',
  Justification='Script accepts at most one piped installation object; end-block semantics are correct.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', 'Get-RsvarsEnvLines',
  Justification='Function returns multiple KEY=VALUE lines from cmd.exe set; plural noun is accurate.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', 'Get-MsbuildResponseLines',
  Justification='Function returns the full set of /p: response-file lines; plural noun is accurate.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
  Justification='Write-Host is intentional: -ShowOutput streams build text directly to the console host.')]
param(
  [Parameter(ValueFromPipeline=$true)]
  [psobject]$DelphiInstallation,

  [Parameter(Position=0)]
  [string]$ProjectFile,

  [string]$RootDir,

  # Skip the rsvars.bat requirement and sourcing; build using the caller's
  # current process environment (BDS / PATH / FrameworkDir set by the caller,
  # as _SetDelphiBuildPaths.bat does).  -RootDir becomes optional metadata and
  # is not validated.
  [switch]$SkipRsvars,

  # Invoke this specific msbuild.exe instead of resolving msbuild.exe from PATH.
  # Enables explicit per-era .NET Framework msbuild selection (v2.0.50727 / v3.5
  # / v4.0.30319).  The path must exist or the script exits with code 2.
  [string]$MsbuildPath,

  [ValidateSet('Win32','Win64','macOS32','macOS64','macOSARM64','Linux64',
               'iOS32','iOSSimulator32','iOS64','iOSSimulator64','Android32','Android64','WinARM64EC')]
  [string]$Platform = 'Win32',

  [string]$Config = 'Debug',

  [ValidateSet('Build','Clean','Rebuild')]
  [string]$Target = 'Build',

  [ValidateSet('quiet','minimal','normal','detailed','diagnostic')]
  [string]$Verbosity = 'normal',

  # Output directory for the compiled executable or DLL (/p:DCC_ExeOutput property).
  [string]$ExeOutputDir,

  # Output directory for compiled DCU files (/p:DCC_DcuOutput property).
  [string]$DcuOutputDir,

  # Additional unit search paths.  Passed via the DCC_UnitSearchPath environment
  # variable (not /p:) so the project's config PropertyGroup extends rather than is
  # overridden by them; multiple paths are joined with semicolons and each trailing
  # separator is trimmed.  See Get-DccAppendEnv / #26.
  [string[]]$UnitSearchPath = @(),

  # Additional compiler defines.  Passed via the DCC_Define environment variable (not
  # /p:) so the project's config defines (DEBUG/RELEASE) are preserved and these are
  # appended.  See Get-DccAppendEnv / #26.
  [string[]]$Define = @(),

  # Build every unit reachable from the project, not just those out of date
  # (/p:DCC_BuildAllUnits=true).  First-class shortcut for a property the batch
  # build path always sets; remains overridable via -Property.
  [switch]$BuildAllUnits,

  # Library path for the environment (/p:_EnvLibraryPath="...").  Used by the
  # batch build path's Win32-only sub-path.  First-class shortcut; remains
  # overridable via -Property.
  [string]$EnvLibraryPath,

  # Arbitrary MSBuild properties passed through as /p:Key=Value.  Provide a
  # hashtable, e.g. -Property @{ DCC_BuildAllUnits = 'true'; DCC_ResourcePath = 'C:\res' }.
  # Entries are appended AFTER the built-in properties (Config, Platform, and the
  # DCC_* outputs/paths), so an entry here overrides a built-in of the same name --
  # MSBuild uses the last /p: occurrence on the command line.  Values are passed
  # through verbatim as /p:Key=Value; argument quoting is handled by PowerShell's
  # native-command argument passing, never by hand-embedded quotes (see the
  # arg-assembly notes in Invoke-MsbuildProject).
  [hashtable]$Property = @{},

  [switch]$ShowOutput,

  # When set, the result object is written as compressed JSON to this file path.
  # Used by Invoke-BuildPipeline to capture structured results from the subprocess
  # while still streaming build output to the console via | Out-Host.
  [string]$OutputFile,

  # Output format for the result object.
  # object (default) -- emits a PSCustomObject to the pipeline.
  # json             -- emits a single compressed JSON line; used by Invoke-BuildPipeline
  #                     to capture structured results from the subprocess.
  [ValidateSet('object', 'json')]
  [string]$Format = 'object'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExitSuccess          = 0
$ExitUnexpectedError  = 1
$ExitInvalidArguments = 2
$ExitRootDirError     = 3
$ExitProjectNotFound  = 4
$ExitBuildFailed      = 5

$script:Version = '1.2.10'

# Resolve the Delphi root dir from the explicit -RootDir parameter or from a
# piped delphi-inspect result object (.rootDir property).
# Returns $null when neither source provides a value.
function Resolve-RootDir {
  param(
    [string]$ExplicitRootDir,
    [psobject]$Installation
  )

  if (-not [string]::IsNullOrWhiteSpace($ExplicitRootDir)) {
    return $ExplicitRootDir
  }

  if ($null -ne $Installation) {
    $prop = $Installation.PSObject.Properties['rootDir']
    if ($null -ne $prop -and -not [string]::IsNullOrWhiteSpace([string]$prop.Value)) {
      return [string]$prop.Value
    }
  }

  return $null
}

# Derive the expected rsvars.bat path from the Delphi root dir.
function Get-RsvarsPath {
  param([string]$RootDir)
  return Join-Path (Join-Path $RootDir 'bin') 'rsvars.bat'
}

# Remove a trailing path separator from a directory-valued MSBuild property.
# MSBuild directory properties do not require a trailing separator.  Trimming it
# also avoids a Windows PowerShell 5.1 native-argument-quoting defect: when PS 5.1
# wraps an argument that contains a space in double quotes, a trailing backslash
# escapes the closing quote and corrupts the argument boundary.
# A drive-root value (e.g. 'C:\') keeps its separator -- trimming it to 'C:' would
# change the meaning to the drive's current directory.  A value that is all
# separators (e.g. '\\') is returned unchanged.
function Get-PathWithoutTrailingSeparator {
  param([string]$Path)
  if ([string]::IsNullOrEmpty($Path)) { return $Path }
  $trimmed = $Path.TrimEnd('\')
  if ([string]::IsNullOrEmpty($trimmed)) { return $Path }
  if ($trimmed -match '^[A-Za-z]:$') { return $trimmed + '\' }
  return $trimmed
}

# Encode a single MSBuild /p: value for inclusion in a response file.
# A response file is read by MSBuild's own tokenizer, not by CommandLineToArgvW,
# so quoting applied here reaches MSBuild identically regardless of the PowerShell
# host (Windows PowerShell 5.1 vs PowerShell 7).  That is what makes whitespace,
# semicolons, and trailing backslashes safe -- the command-line-quoting hazards
# that motivated #24 do not apply to a response file (see #25).
#
# Quoting rules, verified against msbuild.exe:
#   * The value is wrapped in double quotes when it is empty or contains whitespace,
#     a semicolon (which MSBuild's /p: switch parser splits on -- even inside a
#     response file), or a double quote.  A value with none of these is emitted
#     verbatim; a trailing backslash is then harmless because there is no closing
#     quote for it to escape.
#   * When quoting, backslashes follow the Windows CommandLineToArgvW rules MSBuild's
#     tokenizer honours: a run of backslashes immediately before a double quote
#     (including the closing delimiter) is doubled, and an embedded double quote is
#     escaped with an extra backslash.  Without this, a trailing '\' would escape the
#     closing quote and corrupt the value.
function ConvertTo-MsbuildResponseValue {
  param([string]$Value)

  if ($null -eq $Value) { $Value = '' }
  if ($Value.Length -gt 0 -and $Value -notmatch '[\s;"]') {
    return $Value
  }

  $sb = [System.Text.StringBuilder]::new()
  [void]$sb.Append('"')
  $backslashes = 0
  foreach ($ch in $Value.ToCharArray()) {
    if ($ch -eq '\') {
      $backslashes++
    }
    elseif ($ch -eq '"') {
      [void]$sb.Append('\' * (($backslashes * 2) + 1))
      [void]$sb.Append('"')
      $backslashes = 0
    }
    else {
      if ($backslashes -gt 0) {
        [void]$sb.Append('\' * $backslashes)
        $backslashes = 0
      }
      [void]$sb.Append($ch)
    }
  }
  if ($backslashes -gt 0) {
    [void]$sb.Append('\' * ($backslashes * 2))
  }
  [void]$sb.Append('"')
  return $sb.ToString()
}

# Assemble the ordered set of /p:Key=Value response-file lines for a build.
# Config and Platform come first, then the DCC_* outputs, the two batch-path
# shortcuts (DCC_BuildAllUnits / _EnvLibraryPath), and finally the generic -Property
# pass-through in sorted key order.  -Property is emitted LAST so an explicit entry
# overrides a built-in of the same name -- MSBuild honours the last /p: occurrence,
# and a response file preserves line order.  Each value is encoded once, in one
# place, by ConvertTo-MsbuildResponseValue.
#
# NOTE: the two APPEND-style properties (DCC_Define, DCC_UnitSearchPath) are NOT here.
# They are passed as environment variables (see Invoke-MsbuildProject) because a /p:
# global property overrides -- rather than extends -- a project's config-scoped
# <DCC_Define>DEBUG;$(DCC_Define)</DCC_Define> assignment (see #26).
function Get-MsbuildResponseLines {
  param(
    [string]$Config,
    [string]$Platform,
    [string]$ExeOutputDir,
    [string]$DcuOutputDir,
    [switch]$BuildAllUnits,
    [string]$EnvLibraryPath,
    [hashtable]$Property      = @{}
  )

  $pairs = New-Object System.Collections.Generic.List[object]
  [void]$pairs.Add(@{ K = 'Config';   V = $Config })
  [void]$pairs.Add(@{ K = 'Platform'; V = $Platform })
  if (-not [string]::IsNullOrWhiteSpace($ExeOutputDir)) { [void]$pairs.Add(@{ K = 'DCC_ExeOutput'; V = $ExeOutputDir }) }
  if (-not [string]::IsNullOrWhiteSpace($DcuOutputDir)) { [void]$pairs.Add(@{ K = 'DCC_DcuOutput'; V = $DcuOutputDir }) }

  if ($BuildAllUnits) { [void]$pairs.Add(@{ K = 'DCC_BuildAllUnits'; V = 'true' }) }
  if (-not [string]::IsNullOrWhiteSpace($EnvLibraryPath)) {
    [void]$pairs.Add(@{ K = '_EnvLibraryPath'; V = (Get-PathWithoutTrailingSeparator $EnvLibraryPath) })
  }

  if ($Property.Count -gt 0) {
    foreach ($key in ($Property.Keys | Sort-Object)) {
      [void]$pairs.Add(@{ K = $key; V = [string]$Property[$key] })
    }
  }

  $lines = foreach ($p in $pairs) { '/p:' + $p.K + '=' + (ConvertTo-MsbuildResponseValue $p.V) }
  return @($lines)
}

# Invoke cmd.exe to source rsvars.bat and capture the resulting environment.
# Returns the raw KEY=VALUE lines from `set`.
# Separated into its own function so tests can mock it.
function Get-RsvarsEnvLines {
  param([string]$RsvarsPath)
  $lines = @(& cmd.exe /c "call `"$RsvarsPath`" > nul 2>&1 && set")
  if ($LASTEXITCODE -ne 0) {
    throw "rsvars.bat exited with code $LASTEXITCODE : $RsvarsPath"
  }
  return $lines
}

# Source rsvars.bat into the current process environment.
# Calls Get-RsvarsEnvLines (mockable) and applies each KEY=VALUE pair.
function Invoke-RsvarsEnvironment {
  param([string]$RsvarsPath)

  $lines = Get-RsvarsEnvLines -RsvarsPath $RsvarsPath
  $count = 0
  foreach ($line in $lines) {
    if ($line -match '^([^=]+)=(.*)$') {
      [Environment]::SetEnvironmentVariable($Matches[1], $Matches[2], 'Process')
      $count++
    }
  }

  if ($count -eq 0) {
    throw "rsvars.bat produced no environment variables -- check that rsvars.bat is valid: $RsvarsPath"
  }
}

# Invoke msbuild with the given arguments.
# Returns [pscustomobject]@{ ExitCode; Output } where Output is always the
# captured build text.  When -ShowOutput is set each output line is also
# written to the host as MSBuild emits it.
# When -MsbuildPath is supplied that exact binary is invoked; otherwise
# msbuild.exe is resolved from PATH (the environment sourced from rsvars.bat).
# Separated into its own function so tests can mock it.
function Invoke-MsbuildExe {
  param(
    [string[]]$Arguments,
    [string]$MsbuildPath,
    [switch]$ShowOutput
  )

  $exe = if (-not [string]::IsNullOrWhiteSpace($MsbuildPath)) { $MsbuildPath } else { 'msbuild.exe' }

  $outputLines = New-Object System.Collections.Generic.List[string]
  & $exe @Arguments 2>&1 | ForEach-Object {
    $line = [string]$_
    [void]$outputLines.Add($line)
    if ($ShowOutput) { Write-Host $line }
  }
  $exitCode = $LASTEXITCODE
  $output = $outputLines -join [Environment]::NewLine
  if ($outputLines.Count -gt 0) {
    $output += [Environment]::NewLine
  }
  return [pscustomobject]@{ ExitCode = $exitCode; Output = $output }
}

# Compute the environment variables that carry the APPEND-style DCC properties
# (DCC_Define, DCC_UnitSearchPath).  These are passed as environment variables rather
# than /p: global properties: an environment-derived property has the LOWEST MSBuild
# precedence, so the project's config-scoped PropertyGroup
# (e.g. <DCC_Define>DEBUG;$(DCC_Define)</DCC_Define>) still runs and its $(...)
# self-reference resolves against this value -- preserving the project's own defines
# and search paths and appending ours.  A /p: global property would OVERRIDE that
# assignment entirely, dropping the project's values and leaving the self-reference
# unresolved (see #26).  Only supplied (non-empty) values are returned; UnitSearchPath
# entries have their trailing separator trimmed first.
function Get-DccAppendEnv {
  param(
    [string[]]$Define         = @(),
    [string[]]$UnitSearchPath = @()
  )
  $envVars = [ordered]@{}
  if ($Define.Count -gt 0) {
    $envVars['DCC_Define'] = ($Define -join ';')
  }
  if ($UnitSearchPath.Count -gt 0) {
    $trimmed = @($UnitSearchPath | ForEach-Object { Get-PathWithoutTrailingSeparator $_ })
    $envVars['DCC_UnitSearchPath'] = ($trimmed -join ';')
  }
  return $envVars
}

# Assemble MSBuild arguments and invoke the build.
# Returns the result object from Invoke-MsbuildExe.
function Invoke-MsbuildProject {
  param(
    [string]$ProjectFile,
    [string]$Platform,
    [string]$Config,
    [string]$Target,
    [string]$Verbosity,
    [string]$ExeOutputDir,
    [string]$DcuOutputDir,
    [string[]]$UnitSearchPath = @(),
    [string[]]$Define         = @(),
    [switch]$BuildAllUnits,
    [string]$EnvLibraryPath,
    [hashtable]$Property      = @{},
    [string]$MsbuildPath,
    [switch]$ShowOutput
  )

  # Only the project file and the non-/p: switches travel as direct command-line
  # arguments.  The OVERRIDE-style /p: set goes through a temporary MSBuild response
  # file (assembled by Get-MsbuildResponseLines), which MSBuild reads with its own
  # tokenizer rather than via CommandLineToArgvW.  This delivers every property value
  # identically under Windows PowerShell 5.1 and PowerShell 7 -- whitespace, semicolons,
  # and trailing backslashes are all safe (see #24 / #25).
  #
  # The APPEND-style properties (DCC_Define, DCC_UnitSearchPath) are NOT in the response
  # file; they are set as environment variables so the project's config PropertyGroup can
  # extend rather than be overridden by them (see Get-DccAppendEnv / #26).
  $directArgs = @(
    $ProjectFile,
    "/t:$Target",
    "/nologo",
    "/v:$Verbosity"
  )

  $responseLines = Get-MsbuildResponseLines `
    -Config          $Config `
    -Platform        $Platform `
    -ExeOutputDir    $ExeOutputDir `
    -DcuOutputDir    $DcuOutputDir `
    -BuildAllUnits:$BuildAllUnits `
    -EnvLibraryPath  $EnvLibraryPath `
    -Property        $Property

  $appendEnv = Get-DccAppendEnv -Define $Define -UnitSearchPath $UnitSearchPath

  # Write the response file as UTF-8 without a BOM so it is read correctly by every
  # MSBuild version (a BOM confuses older .NET-Framework msbuild).  Set the append-style
  # env vars (saving any prior value) around the build.  Both the file and the env vars
  # are restored/removed in the finally regardless of build outcome.
  $responseFile = [System.IO.Path]::GetTempFileName()
  $savedEnv = @{}
  try {
    foreach ($name in $appendEnv.Keys) {
      $savedEnv[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
      [Environment]::SetEnvironmentVariable($name, $appendEnv[$name], 'Process')
    }

    $content = ($responseLines -join [Environment]::NewLine)
    if ($responseLines.Count -gt 0) { $content += [Environment]::NewLine }
    [System.IO.File]::WriteAllText($responseFile, $content, [System.Text.UTF8Encoding]::new($false))

    $msbuildArgs = $directArgs + @("@$responseFile")
    return Invoke-MsbuildExe -Arguments $msbuildArgs -MsbuildPath $MsbuildPath -ShowOutput:$ShowOutput
  }
  finally {
    Remove-Item -LiteralPath $responseFile -Force -ErrorAction SilentlyContinue
    foreach ($name in $savedEnv.Keys) {
      [Environment]::SetEnvironmentVariable($name, $savedEnv[$name], 'Process')
    }
  }
}

# Parse the dcc32.exe invocation line from captured msbuild output and extract
# the exe output dir (-E flag) and DCU output dir (-NO flag).
# Paths are resolved to absolute using the project file directory as base.
# Returns [pscustomobject]@{ ExeOutputDir; DcuOutputDir } -- either may be $null.
function Get-BuildOutputDir {
  param(
    [string]$Output,
    [string]$ProjectFileDir
  )

  $result = [pscustomobject]@{ ExeOutputDir = $null; DcuOutputDir = $null }
  if ([string]::IsNullOrWhiteSpace($Output)) { return $result }

  $dcc32Line = ($Output -split "`n") |
    Where-Object { $_ -match '[/\\]dcc32\.exe\s' } |
    Select-Object -First 1
  if (-not $dcc32Line) { return $result }

  if ($dcc32Line -match '\s-E(\S+)') {
    $result.ExeOutputDir = [System.IO.Path]::GetFullPath(
      [System.IO.Path]::Combine($ProjectFileDir, $Matches[1]))
  }

  if ($dcc32Line -match '\s-NO(\S+)') {
    $result.DcuOutputDir = [System.IO.Path]::GetFullPath(
      [System.IO.Path]::Combine($ProjectFileDir, $Matches[1]))
  }

  return $result
}

# Parse the MSBuild summary block from captured output and return warning and
# error counts as integers.
# Returns [pscustomobject]@{ Warnings; Errors }.
function Get-BuildCount {
  param([string]$Output)

  $warnings = 0
  $errors   = 0
  if (-not [string]::IsNullOrWhiteSpace($Output)) {
    $wMatch = [regex]::Match($Output, '^\s*(\d+)\s+Warning\(s\)',
      [System.Text.RegularExpressions.RegexOptions]::Multiline)
    $eMatch = [regex]::Match($Output, '^\s*(\d+)\s+Error\(s\)',
      [System.Text.RegularExpressions.RegexOptions]::Multiline)
    if ($wMatch.Success) { $warnings = [int]$wMatch.Groups[1].Value }
    if ($eMatch.Success) { $errors   = [int]$eMatch.Groups[1].Value }
  }
  return [pscustomobject]@{ Warnings = $warnings; Errors = $errors }
}

# Guard: skip top-level execution when the script is dot-sourced for testing.
if ($MyInvocation.InvocationName -eq '.') { return }

try {
  if ([string]::IsNullOrWhiteSpace($ProjectFile)) {
    Write-Error '-ProjectFile is required.' -ErrorAction Continue
    exit $ExitInvalidArguments
  }

  if (-not [string]::IsNullOrWhiteSpace($MsbuildPath) -and -not (Test-Path -LiteralPath $MsbuildPath -PathType Leaf)) {
    Write-Error "MSBuild executable not found: $MsbuildPath" -ErrorAction Continue
    exit $ExitInvalidArguments
  }

  $resolvedRootDir = Resolve-RootDir -ExplicitRootDir $RootDir -Installation $DelphiInstallation
  $rsvarsPath      = $null

  if ($SkipRsvars) {
    # Caller-managed environment: do not require or source rsvars.  -RootDir is
    # optional metadata only; when supplied, derive rsvarsPath for the result
    # object but neither validate nor source it.
    if (-not [string]::IsNullOrWhiteSpace($resolvedRootDir)) {
      $rsvarsPath = Get-RsvarsPath -RootDir $resolvedRootDir
    }
  } else {
    if ([string]::IsNullOrWhiteSpace($resolvedRootDir)) {
      $msg = 'No Delphi root dir supplied. Provide -RootDir, pipe a delphi-inspect result object, or use -SkipRsvars.'
      Write-Error $msg -ErrorAction Continue
      exit $ExitRootDirError
    }

    if (-not (Test-Path -LiteralPath $resolvedRootDir)) {
      $msg = "Delphi root dir not found on disk: $resolvedRootDir"
      Write-Error $msg -ErrorAction Continue
      exit $ExitRootDirError
    }

    $rsvarsPath = Get-RsvarsPath -RootDir $resolvedRootDir
    if (-not (Test-Path -LiteralPath $rsvarsPath)) {
      $msg = "rsvars.bat not found: $rsvarsPath"
      Write-Error $msg -ErrorAction Continue
      exit $ExitRootDirError
    }
  }

  $resolvedProjectFile = [System.IO.Path]::GetFullPath($ProjectFile)
  if (-not (Test-Path -LiteralPath $resolvedProjectFile)) {
    $msg = "Project file not found: $resolvedProjectFile"
    Write-Error $msg -ErrorAction Continue
    exit $ExitProjectNotFound
  }

  if (-not $SkipRsvars) {
    Invoke-RsvarsEnvironment -RsvarsPath $rsvarsPath
  }

  $buildResult = Invoke-MsbuildProject `
    -ProjectFile   $resolvedProjectFile `
    -Platform      $Platform `
    -Config        $Config `
    -Target        $Target `
    -Verbosity     $Verbosity `
    -ExeOutputDir  $ExeOutputDir `
    -DcuOutputDir  $DcuOutputDir `
    -UnitSearchPath $UnitSearchPath `
    -Define        $Define `
    -BuildAllUnits:$BuildAllUnits `
    -EnvLibraryPath $EnvLibraryPath `
    -Property      $Property `
    -MsbuildPath   $MsbuildPath `
    -ShowOutput:$ShowOutput

  $parsedDirs = Get-BuildOutputDir `
    -Output         $buildResult.Output `
    -ProjectFileDir (Split-Path $resolvedProjectFile -Parent)
  $counts = Get-BuildCount -Output $buildResult.Output

  $resultObj = [pscustomobject]@{
    output         = $buildResult.Output
    scriptVersion  = $script:Version
    projectFile    = $resolvedProjectFile
    platform       = $Platform
    config         = $Config
    target         = $Target
    define         = $Define
    buildAllUnits  = [bool]$BuildAllUnits
    envLibraryPath = if ([string]::IsNullOrWhiteSpace($EnvLibraryPath)) { $null } else { $EnvLibraryPath }
    property       = if ($Property.Count -eq 0) { $null } else { $Property }
    rootDir        = $resolvedRootDir
    rsvarsPath     = $rsvarsPath
    skipRsvars     = [bool]$SkipRsvars
    msbuildPath    = if ([string]::IsNullOrWhiteSpace($MsbuildPath)) { $null } else { $MsbuildPath }
    exeOutputDir   = if (-not [string]::IsNullOrWhiteSpace($ExeOutputDir)) { $ExeOutputDir } else { $parsedDirs.ExeOutputDir }
    dcuOutputDir   = if (-not [string]::IsNullOrWhiteSpace($DcuOutputDir)) { $DcuOutputDir } else { $parsedDirs.DcuOutputDir }
    unitSearchPath = if ($UnitSearchPath.Count -eq 0) { $null } else { $UnitSearchPath }
    exitCode       = $buildResult.ExitCode
    success        = ($buildResult.ExitCode -eq 0)
    warnings       = $counts.Warnings
    errors         = $counts.Errors
  }

  if (-not [string]::IsNullOrWhiteSpace($OutputFile)) {
    Set-Content -LiteralPath $OutputFile -Value ($resultObj | ConvertTo-Json -Depth 5 -Compress) -Encoding UTF8
  }

  if ($Format -eq 'json') {
    Write-Output ($resultObj | ConvertTo-Json -Depth 5 -Compress)
  } else {
    Write-Output $resultObj
  }

  if ($buildResult.ExitCode -ne 0) {
    if ($ShowOutput) {
      Write-Error "MSBuild failed with exit code $($buildResult.ExitCode)" -ErrorAction Continue
    }
    exit $ExitBuildFailed
  }

  exit $ExitSuccess

} catch {
  Write-Error $_.Exception.Message -ErrorAction Continue
  exit $ExitUnexpectedError
}
