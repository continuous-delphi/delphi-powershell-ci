function Invoke-BuildPipeline {
    [CmdletBinding()]
    param(
        # Inspect args drive registry-based toolchain detection. Not required
        # when an explicit root is supplied via -ExplicitRootDir.
        [string[]]$InspectArgs = @(),

        [Parameter(Mandatory)]
        [string[]]$BuildArgs,

        [Parameter(Mandatory)]
        [ValidateSet('MSBuild', 'DCCBuild')]
        [string]$Engine,

        # Explicit Delphi installation root. When non-empty, delphi-inspect is
        # not run at all -- registry detection (and its readiness gating) is
        # bypassed and this path is passed straight to the build tool's -RootDir.
        [string]$ExplicitRootDir
    )

    $buildToolName = if ($Engine -eq 'DCCBuild') { 'delphi-dccbuild.ps1' } else { 'delphi-msbuild.ps1' }
    $buildToolPath = Join-Path $script:BundledToolsDir $buildToolName

    # Failure results must carry the full property set the caller reads
    # (Warnings/Errors/ExeOutputDir/Output). The module runs under
    # Set-StrictMode -Version Latest, so a partial object would throw when
    # Invoke-DelphiBuild dereferences the missing properties.
    $newFailure = {
        param([int]$Code)
        [PSCustomObject]@{ ExitCode = $Code; Success = $false; Warnings = 0; Errors = 0; ExeOutputDir = $null; Output = $null }
    }

    if (-not [string]::IsNullOrWhiteSpace($ExplicitRootDir)) {
        # Explicit root: skip the inspect subprocess entirely. Fail fast with a
        # clear error if the caller-supplied path does not exist.
        if (-not (Test-Path -LiteralPath $ExplicitRootDir -PathType Container)) {
            Write-Error "Toolchain rootDir does not exist: $ExplicitRootDir"
            return & $newFailure 3
        }
        $rootDir = $ExplicitRootDir
    }
    else {
        $inspectPath = Join-Path $script:BundledToolsDir 'delphi-inspect.ps1'

        # Run inspect with JSON output so we can extract rootDir from it
        $jsonArgs    = $InspectArgs + @('-Format', 'json')
        $jsonOutput  = & $script:PowerShellExe -NoProfile -NonInteractive -File $inspectPath @jsonArgs 2>&1
        $inspectExit = $LASTEXITCODE

        if ($inspectExit -ne 0) {
            Write-Error "delphi-inspect.ps1 exited with code $inspectExit"
            return & $newFailure $inspectExit
        }

        try {
            $parsed  = ($jsonOutput -join '') | ConvertFrom-Json
            $rootDir = $parsed.result.installation.rootDir
        }
        catch {
            Write-Error "Failed to parse delphi-inspect.ps1 output as JSON: $($_.Exception.Message)"
            return & $newFailure 3
        }

        if ([string]::IsNullOrWhiteSpace($rootDir)) {
            Write-Error 'delphi-inspect.ps1 returned an empty rootDir'
            return & $newFailure 3
        }
    }

    # Run the build tool with | Out-Host so build output streams to the terminal
    # in real time.  A temp file carries the structured JSON result back to the
    # caller without interfering with the streamed output.
    $resultFile   = [System.IO.Path]::GetTempFileName()
    $allBuildArgs = @('-RootDir', $rootDir, '-OutputFile', $resultFile) + $BuildArgs
    try {
        & $script:PowerShellExe -NoProfile -NonInteractive -File $buildToolPath @allBuildArgs | Out-Host
        $buildExit = $LASTEXITCODE

        $toolResult = $null
        try {
            $raw = Get-Content -LiteralPath $resultFile -Raw -ErrorAction Stop
            $toolResult = $raw | ConvertFrom-Json
        }
        catch { <# result file missing or malformed; fall back to exit-code only #> }

        return [PSCustomObject]@{
            ExitCode     = $buildExit
            Success      = ($buildExit -eq 0)
            Warnings     = if ($null -ne $toolResult) { [int]$toolResult.warnings    } else { 0 }
            Errors       = if ($null -ne $toolResult) { [int]$toolResult.errors      } else { 0 }
            ExeOutputDir = if ($null -ne $toolResult) { $toolResult.exeOutputDir     } else { $null }
            Output       = if ($null -ne $toolResult) { $toolResult.output           } else { $null }
        }
    }
    finally {
        Remove-Item -LiteralPath $resultFile -Force -ErrorAction SilentlyContinue
    }
}
