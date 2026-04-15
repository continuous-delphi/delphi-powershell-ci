function Invoke-TestBuild {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TestProjectFile,

        [string]$Platform = 'Win32',

        [string]$Configuration = 'Debug',

        [string]$Toolchain = 'Latest',

        [ValidateSet('MSBuild', 'DCCBuild')]
        [string]$BuildEngine = 'MSBuild',

        [string[]]$Defines = @()
    )

    # Normalise extension to match the engine.
    $expectedExt = if ($BuildEngine -eq 'DCCBuild') { '.dpr' } else { '.dproj' }
    if ([System.IO.Path]::GetExtension($TestProjectFile) -ne $expectedExt) {
        $TestProjectFile = [System.IO.Path]::ChangeExtension($TestProjectFile, $expectedExt)
    }

    $buildSystem = if ($BuildEngine -eq 'DCCBuild') { 'DCC' } else { 'MSBuild' }

    $inspectArgs = if ($Toolchain -eq 'Latest') {
        @('-DetectLatest', '-Platform', $Platform, '-BuildSystem', $buildSystem)
    }
    else {
        @('-Locate', '-Name', $Toolchain, '-Platform', $Platform, '-BuildSystem', $buildSystem)
    }

    $buildArgs = [System.Collections.Generic.List[string]]@(
        '-ProjectFile', $TestProjectFile,
        '-Platform',    $Platform,
        '-Config',      $Configuration,
        '-Verbosity',   'quiet', 
        '-ShowOutput'
    )
    foreach ($d in $Defines) {
        $buildArgs.Add('-Define')
        $buildArgs.Add($d)
    }

    return Invoke-BuildPipeline -InspectArgs $inspectArgs -BuildArgs $buildArgs.ToArray() -Engine $BuildEngine
}
