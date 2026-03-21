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

        [string[]]$Defines = @()
    )

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
        '-ShowOutput'
    )
    foreach ($d in $Defines) {
        $buildArgs.Add('-Define')
        $buildArgs.Add($d)
    }

    $toolResult = [PSCustomObject]@{ ExitCode = 0; Success = $true }

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
        StepName    = 'Build'
        Success     = $toolResult.Success
        Duration    = $stopwatch.Elapsed
        ExitCode    = $toolResult.ExitCode
        Tool        = $tool
        Message     = if ($toolResult.Success) { 'Build completed' } else { "Exit code $($toolResult.ExitCode)" }
        ProjectFile = $ProjectFile
    }
}
