function Invoke-BuildPipeline {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$InspectArgs,

        [Parameter(Mandatory)]
        [string[]]$BuildArgs,

        [Parameter(Mandatory)]
        [ValidateSet('MSBuild', 'DCCBuild')]
        [string]$Engine
    )

    $inspectPath   = Join-Path $script:BundledToolsDir 'delphi-inspect.ps1'
    $buildToolName = if ($Engine -eq 'DCCBuild') { 'delphi-dccbuild.ps1' } else { 'delphi-msbuild.ps1' }
    $buildToolPath = Join-Path $script:BundledToolsDir $buildToolName

    # Run inspect with JSON output so we can extract rootDir from it
    $jsonArgs    = $InspectArgs + @('-Format', 'json')
    $jsonOutput  = & $script:PowerShellExe -NoProfile -NonInteractive -File $inspectPath @jsonArgs 2>&1
    $inspectExit = $LASTEXITCODE

    if ($inspectExit -ne 0) {
        Write-Error "delphi-inspect.ps1 exited with code $inspectExit"
        return [PSCustomObject]@{ ExitCode = $inspectExit; Success = $false }
    }

    try {
        $parsed  = ($jsonOutput -join '') | ConvertFrom-Json
        $rootDir = $parsed.result.installation.rootDir
    }
    catch {
        Write-Error "Failed to parse delphi-inspect.ps1 output as JSON: $($_.Exception.Message)"
        return [PSCustomObject]@{ ExitCode = 3; Success = $false }
    }

    if ([string]::IsNullOrWhiteSpace($rootDir)) {
        Write-Error 'delphi-inspect.ps1 returned an empty rootDir'
        return [PSCustomObject]@{ ExitCode = 3; Success = $false }
    }

    # Run the build tool with the resolved rootDir prepended to the caller's args
    $allBuildArgs = @('-RootDir', $rootDir) + $BuildArgs
    & $script:PowerShellExe -NoProfile -NonInteractive -File $buildToolPath @allBuildArgs | Out-Host
    $buildExit = $LASTEXITCODE

    return [PSCustomObject]@{
        ExitCode = $buildExit
        Success  = ($buildExit -eq 0)
    }
}
