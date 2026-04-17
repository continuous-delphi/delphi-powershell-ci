function Invoke-DelphiBuild {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectFile,

        [string]$Platform = 'Win32',

        [string]$Configuration = 'Debug',

        [string]$Toolchain = 'Latest',

        [ValidateSet('MSBuild', 'DCCBuild')]
        [string]$BuildEngine = 'MSBuild',

        [string[]]$Defines = @(),

        [string]$ExeOutputDir,

        [string]$DcuOutputDir,

        # Additional unit search paths (/p:DCC_UnitSearchPath for MSBuild,
        # -U for DCCBuild). Each entry is forwarded as -UnitSearchPath to the
        # bundled tool, which appends them to whatever the project already sets.
        [string[]]$UnitSearchPath = @(),

        # Additional include file search paths (DCC -I flag). DCCBuild-only --
        # MSBuild handles these via project PropertyGroups, not CLI flags.
        [string[]]$IncludePath = @(),

        # Unit scope (namespace) names searched when resolving unqualified
        # unit names (DCC -NS flag). Required for modern Delphi projects that
        # use namespaced RTL units (e.g. System.SysUtils) when building
        # outside the IDE without a project .cfg file. DCCBuild-only.
        [string[]]$Namespace = @(),

        [ValidateSet('quiet', 'minimal', 'normal', 'detailed', 'diagnostic')]
        [string]$BuildVerbosity = 'normal',

        # MSBuild target to run. 'Clean' is MSBuild-only -- the DCCBuild engine
        # accepts only 'Build' and 'Rebuild'. The CI 'Clean' step (delphi-clean)
        # is unrelated to MSBuild's clean target.
        [ValidateSet('Build', 'Clean', 'Rebuild')]
        [string]$BuildTarget = 'Build'
    )

    if ($BuildEngine -eq 'DCCBuild' -and $BuildTarget -eq 'Clean') {
        throw "BuildTarget 'Clean' is not supported by the DCCBuild engine. Use 'Build' or 'Rebuild', or run the CI 'Clean' step (delphi-clean) instead."
    }
    if ($BuildEngine -eq 'MSBuild' -and $IncludePath.Count -gt 0) {
        throw "IncludePath is supported only by the DCCBuild engine. With MSBuild, configure include paths via the project's PropertyGroups."
    }
    if ($BuildEngine -eq 'MSBuild' -and $Namespace.Count -gt 0) {
        throw "Namespace is supported only by the DCCBuild engine. With MSBuild, configure unit scope names via the project's PropertyGroups."
    }

    # Normalise project file extension to what the engine expects.
    $expectedExt = if ($BuildEngine -eq 'DCCBuild') { '.dpr' } else { '.dproj' }
    if ([System.IO.Path]::GetExtension($ProjectFile) -ne $expectedExt) {
        $ProjectFile = [System.IO.Path]::ChangeExtension($ProjectFile, $expectedExt)
    }

    $tool      = if ($BuildEngine -eq 'DCCBuild') { 'delphi-dccbuild.ps1' } else { 'delphi-msbuild.ps1' }
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    Write-DelphiCiMessage -Level 'STEP' -Message "Build ($Platform|$Configuration) -- $ProjectFile"

    # delphi-inspect uses 'DCC' for the DCC build system, not 'DCCBuild'
    $buildSystem = if ($BuildEngine -eq 'DCCBuild') { 'DCC' } else { 'MSBuild' }

    $inspectArgs = if ($Toolchain -eq 'Latest') {
        @('-DetectLatest', '-Platform', $Platform, '-BuildSystem', $buildSystem)
    }
    else {
        @('-Locate', '-Name', $Toolchain, '-Platform', $Platform, '-BuildSystem', $buildSystem)
    }

    $buildArgs = [System.Collections.Generic.List[string]]@(
        '-ProjectFile', $ProjectFile,
        '-Platform',    $Platform,
        '-Config',      $Configuration,
        '-Target',      $BuildTarget,
        '-Verbosity',   $BuildVerbosity,
        '-ShowOutput'
    )
    if (-not [string]::IsNullOrWhiteSpace($ExeOutputDir)) {
        $buildArgs.Add('-ExeOutputDir')
        $buildArgs.Add($ExeOutputDir)
    }
    if (-not [string]::IsNullOrWhiteSpace($DcuOutputDir)) {
        $buildArgs.Add('-DcuOutputDir')
        $buildArgs.Add($DcuOutputDir)
    }
    foreach ($p in $UnitSearchPath) {
        $buildArgs.Add('-UnitSearchPath')
        $buildArgs.Add($p)
    }
    foreach ($p in $IncludePath) {
        $buildArgs.Add('-IncludePath')
        $buildArgs.Add($p)
    }
    foreach ($n in $Namespace) {
        $buildArgs.Add('-Namespace')
        $buildArgs.Add($n)
    }
    foreach ($d in $Defines) {
        $buildArgs.Add('-Define')
        $buildArgs.Add($d)
    }

    $toolResult = [PSCustomObject]@{ ExitCode = 0; Success = $true; Warnings = 0; Errors = 0; ExeOutputDir = $null; Output = $null }

    if ($PSCmdlet.ShouldProcess($ProjectFile, "Build ($Platform|$Configuration)")) {
        $toolResult = Invoke-BuildPipeline -InspectArgs $inspectArgs -BuildArgs $buildArgs.ToArray() -Engine $BuildEngine
    }

    $stopwatch.Stop()

    if ($toolResult.Success) {
        Write-DelphiCiMessage -Level 'OK' -Message 'Build completed'
    }
    else {
        Write-DelphiCiMessage -Level 'ERROR' -Message "Build failed (exit code $($toolResult.ExitCode))"
    }

    return [PSCustomObject]@{
        StepName     = 'Build'
        Output       = $toolResult.Output
        Success      = $toolResult.Success
        Duration     = $stopwatch.Elapsed
        ExitCode     = $toolResult.ExitCode
        Tool         = $tool
        Message      = if ($toolResult.Success) { 'Build completed' } else { "Exit code $($toolResult.ExitCode)" }
        ProjectFile  = $ProjectFile
        Warnings     = $toolResult.Warnings
        Errors       = $toolResult.Errors
        ExeOutputDir = $toolResult.ExeOutputDir
    }
}
