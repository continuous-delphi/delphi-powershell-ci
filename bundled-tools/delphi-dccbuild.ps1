<#
delphi-dccbuild.ps1

Build a Delphi project using the standalone DCC compiler.

Sources the Delphi build environment from rsvars.bat (found under <RootDir>\bin\)
then invokes the appropriate DCC compiler (dcc32.exe, dcc64.exe, etc.) directly.
Sourcing rsvars.bat ensures that $(BDS), $(BDSCOMMONDIR), and related environment
variables are set, which is required for projects that reference those variables in
search paths and for cross-platform targets that rely on SDK paths set by the installer.

Designed to accept piped output from delphi-inspect.ps1 -DetectLatest -BuildSystem DCC.

ASCII-only.

USAGE
  # Auto-discover latest Delphi and build
  delphi-inspect.ps1 -DetectLatest -Platform Win32 -BuildSystem DCC |
      delphi-dccbuild.ps1 -ProjectFile MyApp.dpr

  # Explicit root dir
  delphi-dccbuild.ps1 -ProjectFile MyApp.dpr -RootDir "C:\RAD\Studio\23.0"

  # Override platform / config
  delphi-inspect.ps1 -DetectLatest -Platform Win64 -BuildSystem DCC |
      delphi-dccbuild.ps1 -ProjectFile MyApp.dpr -Platform Win64 -Config Release

  # Stream output and rebuild all units
  delphi-inspect.ps1 -DetectLatest -Platform Win32 -BuildSystem DCC |
      delphi-dccbuild.ps1 -ProjectFile MyApp.dpr -Target Rebuild -ShowOutput

NOTES
  -RootDir is the Delphi installation root (e.g. C:\RAD\Studio\23.0).
  rsvars.bat is expected at <RootDir>\bin\rsvars.bat.
  The compiler executable is located at:
    <RootDir>\bin\dcc32.exe      (Win32, macOS32, iOS32, iOSSimulator32, Android32)
    <RootDir>\bin64\dcc64.exe    (Win64, macOS64, macOSARM64, Linux64, etc.)

  When piped a delphi-inspect result object, RootDir is taken from the
  object's .rootDir property.  An explicit -RootDir parameter takes precedence.

  Both delphi-msbuild.ps1 and delphi-dccbuild.ps1 use -RootDir / .rootDir so
  they accept the same piped objects from delphi-inspect.

  -Config is passed to DCC as a conditional define (-D<CONFIG>).  Common
  values are Debug and Release; the define is uppercased automatically.
  Existing defines from the project's .cfg file are not affected.

  -Target Build   compiles only changed units.
  -Target Rebuild adds -B to force recompilation of all units.

  -Verbosity quiet adds -Q to suppress hints and warnings.
  -Verbosity normal (default) produces standard DCC output.

  By default DCC output is captured and returned in the result object's
  .output property.  Use -ShowOutput to stream output to stdout in real time;
  in that case .output is null and errors are written via Write-Error.

  Exit codes:
    0  success
    1  unexpected error
    2  reserved (invalid arguments)
    3  rootDir missing/empty, directory not found, rsvars.bat absent, or compiler exe not found
    4  project file not found
    5  DCC compiler failed (non-zero exit code)
#>

[CmdletBinding()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'ExitInvalidArguments',
  Justification='Reserved exit code constant; not yet referenced in code paths')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseProcessBlockForPipelineCommand', '',
  Justification='Script accepts at most one piped installation object; end-block semantics are correct.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', 'Get-RsvarsEnvLines',
  Justification='Function returns multiple KEY=VALUE lines from cmd.exe set; plural noun is accurate.')]
param(
  [Parameter(ValueFromPipeline=$true)]
  [psobject]$DelphiInstallation,

  [Parameter(Position=0)]
  [string]$ProjectFile,

  [string]$RootDir,

  [ValidateSet('Win32','Win64','macOS32','macOS64','macOSARM64','Linux64',
               'iOS32','iOSSimulator32','iOS64','iOSSimulator64','Android32','Android64')]
  [string]$Platform = 'Win32',

  [string]$Config = 'Debug',

  [ValidateSet('Build','Rebuild')]
  [string]$Target = 'Build',

  [ValidateSet('quiet','normal')]
  [string]$Verbosity = 'normal',

  # Output directory for the compiled executable or DLL (-E flag).
  [string]$ExeOutputDir,

  # Output directory for compiled DCU files (-N0 flag).
  [string]$DcuOutputDir,

  # Additional unit search paths (-U flag).  Multiple paths are joined with
  # semicolons and passed as a single -U argument, appending to the paths
  # already set in the project .cfg file.
  [string[]]$UnitSearchPath = @(),

  # Additional include file search paths (-I flag).  Multiple paths are
  # joined with semicolons.
  [string[]]$IncludePath = @(),

  # Unit scope names searched when resolving unqualified unit names (-NS flag).
  # Multiple names are joined with semicolons and passed as a single -NS argument.
  # Required for modern Delphi projects that use namespaced RTL units (e.g. System.SysUtils)
  # when building outside the IDE without a project .cfg file.
  [string[]]$Namespace = @(),

  # Additional conditional defines (-D flag).  Multiple defines are joined
  # with semicolons and passed as a single -D argument.
  [string[]]$Define = @(),

  [switch]$ShowOutput
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExitSuccess          = 0
$ExitUnexpectedError  = 1
$ExitInvalidArguments = 2
$ExitRootDirError     = 3
$ExitProjectNotFound  = 4
$ExitBuildFailed      = 5

$script:Version = '0.3.0'

# Platform -> DCC compiler base-name map.
# Mirrors the CompilerMap in delphi-inspect.ps1; kept local so this script
# has no dependency on delphi-inspect.ps1 being present.
$script:CompilerMap = @{
  'Win32'          = 'dcc32'
  'Win64'          = 'dcc64'
  'macOS32'        = 'dccosx'
  'macOS64'        = 'dccosx64'
  'macOSARM64'     = 'dccosxarm64'
  'Linux64'        = 'dcclinux64'
  'iOS32'          = 'dcciosarm'
  'iOSSimulator32' = 'dccios32'
  'iOS64'          = 'dcciosarm64'
  'iOSSimulator64' = 'dcciossimarm64'
  'Android32'      = 'dccaarm'
  'Android64'      = 'dccaarm64'
}

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
# Sets BDS, BDSBIN, BDSCOMMONDIR, FrameworkDir, FrameworkVersion, and PATH,
# which DCC and project .cfg files may reference via $(BDS) and related variables.
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

# Return the DCC compiler base name (without .exe) for the given platform.
function Get-CompilerName {
  param([string]$Platform)
  return $script:CompilerMap[$Platform]
}

# Return the bin subdirectory name for the given compiler base name.
# 64-bit compilers live in bin64; all others live in bin.
function Get-CompilerBinFolder {
  param([string]$CompilerName)
  if ($CompilerName.EndsWith('64')) { return 'bin64' }
  return 'bin'
}

# Build the full path to the DCC compiler executable.
function Get-CompilerPath {
  param([string]$RootDir, [string]$Platform)
  $name   = Get-CompilerName -Platform $Platform
  $folder = Get-CompilerBinFolder -CompilerName $name
  return Join-Path (Join-Path $RootDir $folder) "$name.exe"
}

# Invoke the DCC compiler with the given arguments.
# Returns [pscustomobject]@{ ExitCode; Output } where Output is $null when
# -ShowOutput is set (output streams to stdout instead of being captured).
# Separated into its own function so tests can mock it.
function Invoke-DccExe {
  param(
    [string]$CompilerPath,
    [string[]]$Arguments,
    [switch]$ShowOutput
  )

  if ($ShowOutput) {
    & $CompilerPath @Arguments | Out-Host
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $null }
  }

  $output = & $CompilerPath @Arguments 2>&1 | Out-String
  return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
}

# Assemble DCC arguments and invoke the compiler.
# Returns the result object from Invoke-DccExe.
function Invoke-DccProject {
  param(
    [string]$CompilerPath,
    [string]$ProjectFile,
    [string]$Config,
    [string]$Target,
    [string]$Verbosity,
    [string]$ExeOutputDir,
    [string]$DcuOutputDir,
    [string[]]$UnitSearchPath = @(),
    [string[]]$IncludePath    = @(),
    [string[]]$Namespace      = @(),
    [string[]]$Define         = @(),
    [switch]$ShowOutput
  )

  $dccArgs = @($ProjectFile)

  # Rebuild: force recompilation of all units
  if ($Target -eq 'Rebuild') { $dccArgs += '-B' }

  # Config as a conditional define (uppercased); adds to any existing defines
  # in the project .cfg -- does not replace them
  $dccArgs += "-D$($Config.ToUpper())"

  # Quiet: suppress hints and warnings
  if ($Verbosity -eq 'quiet') { $dccArgs += '-Q' }

  # Output directories
  if (-not [string]::IsNullOrWhiteSpace($ExeOutputDir)) { $dccArgs += "-E$ExeOutputDir" }
  if (-not [string]::IsNullOrWhiteSpace($DcuOutputDir)) { $dccArgs += "-N0$DcuOutputDir" }

  # Search paths: multiple entries joined with semicolons into a single flag
  if ($UnitSearchPath.Count -gt 0) { $dccArgs += "-U$($UnitSearchPath -join ';')" }
  if ($IncludePath.Count -gt 0)    { $dccArgs += "-I$($IncludePath -join ';')" }

  # Unit scope names: multiple entries joined with semicolons into a single -NS flag
  if ($Namespace.Count -gt 0) { $dccArgs += "-NS$($Namespace -join ';')" }

  # Additional defines: multiple entries joined with semicolons into a single -D flag
  if ($Define.Count -gt 0) { $dccArgs += "-D$($Define -join ';')" }

  return Invoke-DccExe -CompilerPath $CompilerPath -Arguments $dccArgs -ShowOutput:$ShowOutput
}

# Guard: skip top-level execution when the script is dot-sourced for testing.
if ($MyInvocation.InvocationName -eq '.') { return }

try {
  if ([string]::IsNullOrWhiteSpace($ProjectFile)) {
    Write-Error '-ProjectFile is required.' -ErrorAction Continue
    exit $ExitInvalidArguments
  }

  $resolvedRootDir = Resolve-RootDir -ExplicitRootDir $RootDir -Installation $DelphiInstallation

  if ([string]::IsNullOrWhiteSpace($resolvedRootDir)) {
    Write-Error 'No Delphi root dir supplied. Provide -RootDir or pipe a delphi-inspect result object.' -ErrorAction Continue
    exit $ExitRootDirError
  }

  if (-not (Test-Path -LiteralPath $resolvedRootDir)) {
    Write-Error "Delphi root dir not found on disk: $resolvedRootDir" -ErrorAction Continue
    exit $ExitRootDirError
  }

  $rsvarsPath = Get-RsvarsPath -RootDir $resolvedRootDir
  if (-not (Test-Path -LiteralPath $rsvarsPath)) {
    Write-Error "rsvars.bat not found: $rsvarsPath" -ErrorAction Continue
    exit $ExitRootDirError
  }

  $compilerPath = Get-CompilerPath -RootDir $resolvedRootDir -Platform $Platform
  if (-not (Test-Path -LiteralPath $compilerPath)) {
    Write-Error "DCC compiler not found: $compilerPath" -ErrorAction Continue
    exit $ExitRootDirError
  }

  $resolvedProjectFile = [System.IO.Path]::GetFullPath($ProjectFile)
  if (-not (Test-Path -LiteralPath $resolvedProjectFile)) {
    Write-Error "Project file not found: $resolvedProjectFile" -ErrorAction Continue
    exit $ExitProjectNotFound
  }

  Invoke-RsvarsEnvironment -RsvarsPath $rsvarsPath

  $buildResult = Invoke-DccProject `
    -CompilerPath    $compilerPath `
    -ProjectFile     $resolvedProjectFile `
    -Config          $Config `
    -Target          $Target `
    -Verbosity       $Verbosity `
    -ExeOutputDir    $ExeOutputDir `
    -DcuOutputDir    $DcuOutputDir `
    -UnitSearchPath  $UnitSearchPath `
    -IncludePath     $IncludePath `
    -Namespace       $Namespace `
    -Define          $Define `
    -ShowOutput:$ShowOutput

  $resultObj = [pscustomobject]@{
    scriptVersion  = $script:Version
    projectFile    = $resolvedProjectFile
    platform       = $Platform
    config         = $Config
    target         = $Target
    rootDir        = $resolvedRootDir
    rsvarsPath     = $rsvarsPath
    compilerPath   = $compilerPath
    exeOutputDir   = if ([string]::IsNullOrWhiteSpace($ExeOutputDir))  { $null } else { $ExeOutputDir }
    dcuOutputDir   = if ([string]::IsNullOrWhiteSpace($DcuOutputDir))  { $null } else { $DcuOutputDir }
    unitSearchPath = if ($UnitSearchPath.Count -eq 0) { $null } else { $UnitSearchPath }
    includePath    = if ($IncludePath.Count    -eq 0) { $null } else { $IncludePath }
    namespace      = if ($Namespace.Count      -eq 0) { $null } else { $Namespace }
    exitCode       = $buildResult.ExitCode
    success        = ($buildResult.ExitCode -eq 0)
    output         = $buildResult.Output
  }

  Write-Output $resultObj

  if ($buildResult.ExitCode -ne 0) {
    if ($ShowOutput) {
      Write-Error "DCC compiler failed with exit code $($buildResult.ExitCode)" -ErrorAction Continue
    }
    exit $ExitBuildFailed
  }

  exit $ExitSuccess

} catch {
  Write-Error $_.Exception.Message -ErrorAction Continue
  exit $ExitUnexpectedError
}
