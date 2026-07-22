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
    <RootDir>\bin\<compiler>.exe   (Win32, macOS32, iOS32, iOSSimulator32, Android32)
    <RootDir>\bin64\<compiler>.exe (Win64, WinARM64EC, macOS64, macOSARM64, Linux64, etc.)

  When piped a delphi-inspect result object, RootDir is taken from the
  object's .rootDir property.  An explicit -RootDir parameter takes precedence.

  Both delphi-msbuild.ps1 and delphi-dccbuild.ps1 use -RootDir / .rootDir so
  they accept the same piped objects from delphi-inspect.

  -Config is passed to DCC as a conditional define (-D<CONFIG>).  Common
  values are Debug and Release; the define is uppercased automatically.
  Existing defines from the project's .cfg file are not affected.

  -NoConfig passes --no-config so DCC does not auto-load <RootDir>\bin\dcc32.cfg.
  Use it on portable/trimmed toolchains whose cfg carries stale library paths;
  units and includes then resolve only from the paths this script supplies.

  -ResourcePath adds resource compiler search paths (-R).  -BplOutputDir,
  -DcpOutputDir, and -BpiOutputDir set the package output directories (-LE,
  -LN, -NB).  -LinkPackage links runtime packages (-LU) and is strictly opt-in:
  it makes the output depend on rtlNNN.bpl / vclNNN.bpl at load time, so the
  default remains statically linked so standalone exes keep working.

  -ExtraArgs is an escape hatch: each element is appended verbatim after all
  modeled switches (no splitting or re-escaping) for dcc32 options this script
  does not model (e.g. -$D0, -$L-, -JL, -V*).

  -SkipRsvars bypasses the rsvars.bat requirement and sourcing.  The compiler
  then runs against the current process environment (pre-set by the caller and
  left untouched).  Use it for toolchains that predate rsvars.bat (Delphi
  2/7/2005) or when the caller manages BDS/PATH itself.  rsvarsPath is null in
  the result object when this switch is set.

  -WorkingDirectory sets the directory the compiler runs in.  It defaults to the
  resolved project file's folder so relative references the project author wrote
  -- a uses clause like SomeUnit in '..\..\shared\SomeUnit.pas', {$I ..\defs.inc}
  includes, and {$R ..\app.res} resources -- resolve as intended, matching the
  legacy DelphiBuild.bat which cd's into the .dpr folder.  Pass an explicit path
  to override, or pass your own current directory to reproduce the old
  no-change behavior.  Relative -ExeOutputDir / -DcuOutputDir / -UnitSearchPath /
  -IncludePath / -ResourcePath and the package output dirs are resolved to
  absolute against the caller's original CWD before the change, so they land
  where they did before.  The directory used is reported as workingDir in the
  result object.

  -Target Build   compiles only changed units.
  -Target Rebuild adds -B to force recompilation of all units.

  -Verbosity quiet adds -Q to suppress hints and warnings.
  -Verbosity normal (default) produces standard DCC output.

  DCC output is always captured and returned in the result object's .output
  property.  -ShowOutput additionally streams each line to the host in real
  time (a tee, matching delphi-msbuild.ps1); it does not suppress capture, so
  .output and the warning/error tally are populated either way.

  -OutputFile writes the full result object as compressed JSON to the given
  path.  -Format json emits the result object as a single compressed JSON line
  to the pipeline; -Format object (the default) emits the PSCustomObject
  unchanged.  Both match delphi-msbuild.ps1 so delphi-powershell-ci can marshal
  either engine's result uniformly.  Omitting both preserves the current
  default (object to the pipeline).

  The result object carries integer .warnings and .errors counts (matching
  delphi-msbuild.ps1).  dcc32 emits no MSBuild-style summary block, so these are
  counted from the compiler's diagnostic codes: .warnings from W#### lines and
  .errors from E#### plus F#### (fatal) lines; hints (H####) count as neither.
  Codes are counted rather than the localized severity words so the tally holds
  under non-English toolchains.  Because output is always captured (even under
  -ShowOutput, which tees rather than suppresses), the counts are populated on
  every code path.  Only -Verbosity quiet legitimately drives them toward 0, by
  telling dcc32 not to emit hints/warnings in the first place.

  Exit codes:
    0  success
    1  unexpected error
    2  reserved (invalid arguments)
    3  rootDir missing/empty, directory not found, rsvars.bat absent (unless -SkipRsvars), or compiler exe not found
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
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', 'Resolve-DccPaths',
  Justification='Function resolves an array of paths; plural noun is accurate.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
  Justification='Write-Host is intentional: -ShowOutput tees build text directly to the console host.')]
param(
  [Parameter(ValueFromPipeline=$true)]
  [psobject]$DelphiInstallation,

  [Parameter(Position=0)]
  [string]$ProjectFile,

  [string]$RootDir,

  [ValidateSet('Win32','Win64','WinARM64EC','macOS32','macOS64','macOSARM64','Linux64',
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

  # Additional resource search paths (-R flag).  Multiple paths are joined
  # with semicolons and passed as a single -R argument.
  [string[]]$ResourcePath = @(),

  # Output directory for compiled runtime packages, .bpl (-LE flag).
  [string]$BplOutputDir,

  # Output directory for package .dcp files (-LN flag).
  [string]$DcpOutputDir,

  # Output directory for package .bpi files (-NB flag).
  [string]$BpiOutputDir,

  # Runtime packages to link against (-LU flag).  Multiple entries are joined
  # with semicolons and passed as a single -LU argument.  STRICTLY OPT-IN:
  # linking runtime packages makes the output depend on rtlNNN.bpl / vclNNN.bpl
  # at load time.  Omit (the default) to statically link so standalone exes keep
  # working -- an exe built with -LUrtl fails to load (0xC0000135) when
  # rtlNNN.bpl is absent on the target.
  [string[]]$LinkPackage = @(),

  # Skip loading dcc32.cfg (--no-config).  By default DCC auto-loads
  # <RootDir>\bin\dcc32.cfg, which on portable/trimmed toolchains can carry
  # stale absolute or $(BDS)-relative library paths that silently inject wrong
  # or duplicate -U/-I entries.  With -NoConfig, unit and include paths resolve
  # only from what this script and its params supply.  Opt-in; omitting it
  # preserves the current default (cfg auto-loaded).
  [switch]$NoConfig,

  # Extra arguments appended verbatim to the dcc32 command line after all the
  # modeled switches.  Each array element is passed through as-is -- no
  # splitting, re-escaping, or reordering -- so array boundaries are preserved.
  # An escape hatch for switches this script does not model, e.g. the code-gen
  # switches -$D0 / -$L- / -$C- / -$Y-, map-file options, -JL, or -V*.
  # NOTE: this script places the project file first on the command line, so
  # "after the modeled switches" means at the end of the argument list.
  [string[]]$ExtraArgs = @(),

  # Skip the rsvars.bat requirement and sourcing.  By default the script
  # requires <RootDir>\bin\rsvars.bat and sources it to set BDS / PATH and
  # related variables.  With -SkipRsvars, rsvars is neither required nor
  # called: the compiler is run directly against the current process
  # environment, which the caller is expected to have pre-set.  Enables the
  # oldest toolchains (Delphi 2 / 7 / 2005) that predate rsvars.bat, and
  # caller-managed environments.  Combine with -NoConfig and explicit -U/-I
  # paths for a fully self-contained, reproducible build.
  [switch]$SkipRsvars,

  # Working directory the compiler runs in.  Defaults to the folder of the
  # resolved -ProjectFile so relative references the project author wrote --
  # a uses clause like SomeUnit in '..\..\shared\SomeUnit.pas', {$I ..\defs.inc}
  # includes, and {$R ..\app.res} resources -- resolve as intended (matching
  # the legacy DelphiBuild.bat, which cd's into the .dpr folder).  Pass an
  # explicit path to override; pass the caller's own CWD to reproduce the old
  # no-change behavior.  Relative output/search paths (-ExeOutputDir,
  # -DcuOutputDir, -UnitSearchPath, -IncludePath, -ResourcePath, and the
  # package output dirs) are resolved to absolute against the caller's original
  # CWD before the change, so existing callers see no change in where those
  # outputs land.
  [string]$WorkingDirectory,

  [switch]$ShowOutput,

  # When set, the result object is written as compressed JSON to this file path.
  # Used by delphi-powershell-ci's Invoke-BuildPipeline to capture structured
  # results from the subprocess while still streaming build output to the
  # console.  Matches delphi-msbuild.ps1's -OutputFile contract so the CI module
  # can read either engine's result uniformly.
  [string]$OutputFile,

  # Output format for the result object.
  # object (default) -- emits a PSCustomObject to the pipeline (current behavior).
  # json             -- emits a single compressed JSON line; used by
  #                     Invoke-BuildPipeline to capture structured results from
  #                     the subprocess.  Matches delphi-msbuild.ps1.
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

$script:Version = '0.4.11'

# Platform -> DCC compiler base-name map.
# Mirrors the CompilerMap in delphi-inspect.ps1; kept local so this script
# has no dependency on delphi-inspect.ps1 being present.
$script:CompilerMap = @{
  'Win32'          = 'dcc32'
  'Win64'          = 'dcc64'
  'WinARM64EC'     = 'dccarm64ec'
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
  if ($CompilerName.EndsWith('64') -or $CompilerName -eq 'dccarm64ec') { return 'bin64' }
  return 'bin'
}

# Build the full path to the DCC compiler executable.
function Get-CompilerPath {
  param([string]$RootDir, [string]$Platform)
  $name   = Get-CompilerName -Platform $Platform
  $folder = Get-CompilerBinFolder -CompilerName $name
  return Join-Path (Join-Path $RootDir $folder) "$name.exe"
}

# Resolve the working directory the compiler will run in.
# An explicit -WorkingDirectory (relative or absolute) is resolved to a full
# path against the current process CWD.  When omitted, defaults to the folder
# of the already-resolved (absolute) project file so relative in / {$I} / {$R}
# references resolve as the project author intended.
function Resolve-WorkingDirectory {
  param(
    [string]$WorkingDirectory,
    [string]$ProjectFile
  )
  if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
    return [System.IO.Path]::GetFullPath($WorkingDirectory)
  }
  return [System.IO.Path]::GetDirectoryName($ProjectFile)
}

# Resolve a single possibly-relative path to an absolute path against the
# current process CWD.  Null/empty/whitespace passes through unchanged so the
# corresponding switch is simply omitted downstream.  Must be called before the
# compiler's working directory is changed so relative paths anchor to the
# caller's original CWD (preserving pre-cd behavior).
function Resolve-DccPath {
  param([string]$Path)
  if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }
  return [System.IO.Path]::GetFullPath($Path)
}

# Resolve each entry of a path array to absolute (see Resolve-DccPath).
# Entries that are empty/whitespace pass through unchanged.  Always returns an
# array so the .Count checks in Invoke-DccProject behave.
function Resolve-DccPaths {
  param([string[]]$Paths)
  if ($null -eq $Paths -or $Paths.Count -eq 0) { return @() }
  return @($Paths | ForEach-Object { Resolve-DccPath -Path $_ })
}

# Invoke the DCC compiler with the given arguments.
# Returns [pscustomobject]@{ ExitCode; Output }.  Output is ALWAYS the captured
# compiler text (never null): each line is accumulated, and additionally written
# to the host when -ShowOutput is set.  This tee mirrors delphi-msbuild.ps1's
# Invoke-MsbuildExe so the warning/error tally (Get-DccBuildCount) works even
# when the caller streams -- notably delphi-powershell-ci's Invoke-BuildPipeline,
# which always passes -ShowOutput.  Separated into its own function so tests can
# mock it.
#
# When -WorkingDirectory is supplied the compiler runs with that directory as
# its current directory, restored afterward even on failure.  IMPORTANT: a
# native child process inherits [System.Environment]::CurrentDirectory (the
# .NET process CWD), which on Windows PowerShell 5.1 does NOT track
# Set-Location / $PWD.  Both are set here so the compiler's working directory
# is correct on every host, and both are restored in the finally block.
function Invoke-DccExe {
  param(
    [string]$CompilerPath,
    [string[]]$Arguments,
    [string]$WorkingDirectory,
    [switch]$ShowOutput
  )

  $changeDir      = -not [string]::IsNullOrWhiteSpace($WorkingDirectory)
  $originalEnvCwd = [System.Environment]::CurrentDirectory
  $pushed         = $false

  try {
    if ($changeDir) {
      # Push-Location first so a bad directory fails before we mutate the
      # process CWD; $pushed guards the matching Pop-Location in finally.
      Push-Location -LiteralPath $WorkingDirectory -ErrorAction Stop
      $pushed = $true
      [System.Environment]::CurrentDirectory = $WorkingDirectory
    }

    # Tee: always capture every line; also echo to the host under -ShowOutput.
    $outputLines = New-Object System.Collections.Generic.List[string]
    & $CompilerPath @Arguments 2>&1 | ForEach-Object {
      $line = [string]$_
      [void]$outputLines.Add($line)
      if ($ShowOutput) { Write-Host $line }
    }
    $exitCode = $LASTEXITCODE

    $output = $outputLines -join [Environment]::NewLine
    if ($outputLines.Count -gt 0) { $output += [Environment]::NewLine }

    return [pscustomobject]@{ ExitCode = $exitCode; Output = $output }
  }
  finally {
    if ($changeDir) {
      [System.Environment]::CurrentDirectory = $originalEnvCwd
      if ($pushed) { Pop-Location }
    }
  }
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
    [string[]]$ResourcePath   = @(),
    [string]$BplOutputDir,
    [string]$DcpOutputDir,
    [string]$BpiOutputDir,
    [string[]]$LinkPackage    = @(),
    [switch]$NoConfig,
    [string[]]$ExtraArgs      = @(),
    [string]$WorkingDirectory,
    [switch]$ShowOutput
  )

  # Resolve relative output/search paths to absolute against the CURRENT CWD
  # before Invoke-DccExe changes the compiler's working directory.  This keeps
  # these outputs anchored to the caller's CWD (pre-cd behavior) rather than
  # having them silently follow the compiler into the project folder.  The
  # project file, defines, namespaces, link packages, and -ExtraArgs are left
  # untouched (already absolute, or not paths, or a verbatim escape hatch).
  $ExeOutputDir   = Resolve-DccPath  -Path  $ExeOutputDir
  $DcuOutputDir   = Resolve-DccPath  -Path  $DcuOutputDir
  $BplOutputDir   = Resolve-DccPath  -Path  $BplOutputDir
  $DcpOutputDir   = Resolve-DccPath  -Path  $DcpOutputDir
  $BpiOutputDir   = Resolve-DccPath  -Path  $BpiOutputDir
  $UnitSearchPath = @(Resolve-DccPaths -Paths $UnitSearchPath)
  $IncludePath    = @(Resolve-DccPaths -Paths $IncludePath)
  $ResourcePath   = @(Resolve-DccPaths -Paths $ResourcePath)

  $dccArgs = @($ProjectFile)

  # Skip dcc32.cfg so only explicitly supplied paths are used (--no-config)
  if ($NoConfig) { $dccArgs += '--no-config' }

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

  # Package output directories: .bpl (-LE), .dcp (-LN), .bpi (-NB)
  if (-not [string]::IsNullOrWhiteSpace($BplOutputDir)) { $dccArgs += "-LE$BplOutputDir" }
  if (-not [string]::IsNullOrWhiteSpace($DcpOutputDir)) { $dccArgs += "-LN$DcpOutputDir" }
  if (-not [string]::IsNullOrWhiteSpace($BpiOutputDir)) { $dccArgs += "-NB$BpiOutputDir" }

  # Search paths: multiple entries joined with semicolons into a single flag
  if ($UnitSearchPath.Count -gt 0) { $dccArgs += "-U$($UnitSearchPath -join ';')" }
  if ($IncludePath.Count -gt 0)    { $dccArgs += "-I$($IncludePath -join ';')" }
  if ($ResourcePath.Count -gt 0)   { $dccArgs += "-R$($ResourcePath -join ';')" }

  # Unit scope names: multiple entries joined with semicolons into a single -NS flag
  if ($Namespace.Count -gt 0) { $dccArgs += "-NS$($Namespace -join ';')" }

  # Additional defines: multiple entries joined with semicolons into a single -D flag
  if ($Define.Count -gt 0) { $dccArgs += "-D$($Define -join ';')" }

  # Runtime packages to link (opt-in): joined with semicolons into a single -LU flag
  if ($LinkPackage.Count -gt 0) { $dccArgs += "-LU$($LinkPackage -join ';')" }

  # Extra pass-through args appended verbatim after all modeled switches.
  # Adding the array with += preserves each element as a distinct argument.
  if ($ExtraArgs.Count -gt 0) { $dccArgs += $ExtraArgs }

  return Invoke-DccExe -CompilerPath $CompilerPath -Arguments $dccArgs -WorkingDirectory $WorkingDirectory -ShowOutput:$ShowOutput
}

# Emit the build result object.
# When OutputFile is a non-empty path, the result is written there as a single
# compressed JSON line (UTF-8).  When Format is 'json' the result is emitted to
# the pipeline as compressed JSON; otherwise (the 'object' default) the
# PSCustomObject is emitted unchanged.  These mirror delphi-msbuild.ps1 so
# delphi-powershell-ci can marshal either engine's result uniformly.  Separated
# into its own function so tests can exercise the file/format contract without
# invoking a compiler.
# Count warnings and errors from captured dcc32 output.
# Returns [pscustomobject]@{ Warnings; Errors }.
#
# Unlike MSBuild, dcc32 emits no "N Warning(s) / N Error(s)" summary block; it
# emits per-diagnostic lines carrying stable message codes: H#### (hint),
# W#### (warning), E#### (error), F#### (fatal).  Counting the CODES is
# locale-robust -- the codes are invariant while the severity words
# ("Warning:", "Fatal:") are localized.  FATAL (F####) is folded into Errors
# for parity with MSBuild's error tally; hints (H####) count as neither.
#
# When output is null/empty (e.g. -ShowOutput streamed it and did not capture),
# both counts are 0 -- the same limitation delphi-msbuild's Get-BuildCount has.
function Get-DccBuildCount {
  param([string]$Output)

  $warnings = 0
  $errors   = 0
  if (-not [string]::IsNullOrWhiteSpace($Output)) {
    $warnings = [regex]::Matches($Output, '\bW\d{4}\b').Count
    $errors   = [regex]::Matches($Output, '\b[EF]\d{4}\b').Count
  }
  return [pscustomobject]@{ Warnings = $warnings; Errors = $errors }
}

function Write-DccResult {
  param(
    [psobject]$ResultObject,
    [string]$OutputFile,
    [string]$Format = 'object'
  )

  if (-not [string]::IsNullOrWhiteSpace($OutputFile)) {
    Set-Content -LiteralPath $OutputFile -Value ($ResultObject | ConvertTo-Json -Depth 5 -Compress) -Encoding UTF8
  }

  if ($Format -eq 'json') {
    Write-Output ($ResultObject | ConvertTo-Json -Depth 5 -Compress)
  } else {
    Write-Output $ResultObject
  }
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

  # rsvars.bat is required and sourced unless -SkipRsvars bypasses it.
  if ($SkipRsvars) {
    $rsvarsPath = $null
  }
  else {
    $rsvarsPath = Get-RsvarsPath -RootDir $resolvedRootDir
    if (-not (Test-Path -LiteralPath $rsvarsPath)) {
      Write-Error "rsvars.bat not found: $rsvarsPath" -ErrorAction Continue
      exit $ExitRootDirError
    }
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

  # Working directory the compiler runs in: explicit -WorkingDirectory, else the
  # resolved project file's folder.  Computed while CWD is still the caller's so
  # a relative -WorkingDirectory anchors there.
  $resolvedWorkingDir = Resolve-WorkingDirectory -WorkingDirectory $WorkingDirectory -ProjectFile $resolvedProjectFile

  # Source rsvars into the process environment unless the caller opted out.
  # With -SkipRsvars the current environment (pre-set by the caller) is used
  # as-is and left untouched.
  if (-not $SkipRsvars) {
    Invoke-RsvarsEnvironment -RsvarsPath $rsvarsPath
  }

  $buildResult = Invoke-DccProject `
    -CompilerPath      $compilerPath `
    -ProjectFile       $resolvedProjectFile `
    -Config            $Config `
    -Target            $Target `
    -Verbosity         $Verbosity `
    -ExeOutputDir      $ExeOutputDir `
    -DcuOutputDir      $DcuOutputDir `
    -UnitSearchPath    $UnitSearchPath `
    -IncludePath       $IncludePath `
    -Namespace         $Namespace `
    -Define            $Define `
    -ResourcePath      $ResourcePath `
    -BplOutputDir      $BplOutputDir `
    -DcpOutputDir      $DcpOutputDir `
    -BpiOutputDir      $BpiOutputDir `
    -LinkPackage       $LinkPackage `
    -NoConfig:$NoConfig `
    -ExtraArgs         $ExtraArgs `
    -WorkingDirectory  $resolvedWorkingDir `
    -ShowOutput:$ShowOutput

  # Warning/error tally parsed from the captured compiler output.  Matches
  # delphi-msbuild's warnings/errors fields so delphi-powershell-ci reads
  # either engine's result uniformly.
  $counts = Get-DccBuildCount -Output $buildResult.Output

  $resultObj = [pscustomobject]@{
    scriptVersion  = $script:Version
    projectFile    = $resolvedProjectFile
    platform       = $Platform
    config         = $Config
    target         = $Target
    define         = $Define
    rootDir        = $resolvedRootDir
    rsvarsPath     = $rsvarsPath
    compilerPath   = $compilerPath
    exeOutputDir   = if ([string]::IsNullOrWhiteSpace($ExeOutputDir))  { $null } else { $ExeOutputDir }
    dcuOutputDir   = if ([string]::IsNullOrWhiteSpace($DcuOutputDir))  { $null } else { $DcuOutputDir }
    unitSearchPath = if ($UnitSearchPath.Count -eq 0) { $null } else { $UnitSearchPath }
    includePath    = if ($IncludePath.Count    -eq 0) { $null } else { $IncludePath }
    namespace      = if ($Namespace.Count      -eq 0) { $null } else { $Namespace }
    resourcePath   = if ($ResourcePath.Count   -eq 0) { $null } else { $ResourcePath }
    bplOutputDir   = if ([string]::IsNullOrWhiteSpace($BplOutputDir)) { $null } else { $BplOutputDir }
    dcpOutputDir   = if ([string]::IsNullOrWhiteSpace($DcpOutputDir)) { $null } else { $DcpOutputDir }
    bpiOutputDir   = if ([string]::IsNullOrWhiteSpace($BpiOutputDir)) { $null } else { $BpiOutputDir }
    linkPackage    = if ($LinkPackage.Count    -eq 0) { $null } else { $LinkPackage }
    noConfig       = [bool]$NoConfig
    extraArgs      = if ($ExtraArgs.Count      -eq 0) { $null } else { $ExtraArgs }
    skipRsvars     = [bool]$SkipRsvars
    workingDir     = $resolvedWorkingDir
    exitCode       = $buildResult.ExitCode
    success        = ($buildResult.ExitCode -eq 0)
    warnings       = $counts.Warnings
    errors         = $counts.Errors
    output         = $buildResult.Output
  }

  Write-DccResult -ResultObject $resultObj -OutputFile $OutputFile -Format $Format

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
