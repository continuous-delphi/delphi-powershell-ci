function Invoke-DelphiCoverage {
    <#
    .SYNOPSIS
        Runs Delphi code coverage analysis as a CI step.

    .DESCRIPTION
        Invokes the delphi-coverage bundled tool to run a test executable
        with coverage instrumentation. Returns a structured step result
        with coverage percentage, line counts, and threshold status.

        When -CoverageDproj is provided the engine auto-discovers the
        executable, MAP file, units, and source paths from the .dproj,
        so -Execute and -MapFile are not required.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$Execute = '',

        [string]$MapFile = '',

        [string]$CoverageDproj = '',
        [string]$CoverageEngine = 'DelphiCodeCoverage',
        [string]$CoverageEnginePath = '',
        [string[]]$CoverageSourceDir = @(),
        [string[]]$CoverageUnits = @(),
        [string[]]$CoverageExcludeUnits = @(),
        [string]$CoverageOutputDir = 'coverage',
        [string[]]$CoverageFormats = @('html'),
        [int]$CoverageThreshold = 0,
        [string[]]$CoverageArguments = @(),
        [int]$CoverageTimeoutSeconds = 300,
        [string]$CoverageBadge = ''
    )

    $hasDproj = -not [string]::IsNullOrEmpty($CoverageDproj)
    if (-not $hasDproj) {
        if ([string]::IsNullOrEmpty($Execute)) { throw 'Either -Execute or -CoverageDproj must be provided.' }
        if ([string]::IsNullOrEmpty($MapFile))  { throw 'Either -MapFile or -CoverageDproj must be provided.' }
    }

    $tool      = 'delphi-coverage.ps1'
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    $displayTarget = if ($hasDproj) { $CoverageDproj } else { $Execute }
    Write-DelphiCiMessage -Level 'STEP' -Message "Coverage -- $displayTarget"

    $toolArgs = [System.Collections.Generic.List[string]]::new()
    if ($hasDproj) {
        $toolArgs.Add('-Dproj')
        $toolArgs.Add($CoverageDproj)
    } else {
        $toolArgs.Add('-Execute')
        $toolArgs.Add($Execute)
        $toolArgs.Add('-MapFile')
        $toolArgs.Add($MapFile)
    }
    $toolArgs.Add('-Engine')
    $toolArgs.Add($CoverageEngine)
    $toolArgs.Add('-OutputDir')
    $toolArgs.Add($CoverageOutputDir)
    $toolArgs.Add('-Threshold')
    $toolArgs.Add($CoverageThreshold.ToString())
    $toolArgs.Add('-TimeoutSeconds')
    $toolArgs.Add($CoverageTimeoutSeconds.ToString())

    if (-not [string]::IsNullOrEmpty($CoverageEnginePath))  { $toolArgs.Add('-EnginePath');  $toolArgs.Add($CoverageEnginePath) }
    if ($CoverageSourceDir.Count -gt 0)   { $toolArgs.Add('-SourceDir'); $toolArgs.Add(($CoverageSourceDir -join ',')) }
    if ($CoverageUnits.Count -gt 0)        { $toolArgs.Add('-Units');        $toolArgs.Add(($CoverageUnits -join ',')) }
    if ($CoverageExcludeUnits.Count -gt 0) { $toolArgs.Add('-ExcludeUnits'); $toolArgs.Add(($CoverageExcludeUnits -join ',')) }
    if ($CoverageFormats.Count -gt 0)     { $toolArgs.Add('-Formats');      $toolArgs.Add(($CoverageFormats -join ',')) }
    if (-not [string]::IsNullOrEmpty($CoverageBadge))       { $toolArgs.Add('-Badge');       $toolArgs.Add($CoverageBadge) }

    $resultFile = [System.IO.Path]::GetTempFileName()
    $toolArgs.Add('-OutputFile')
    $toolArgs.Add($resultFile)

    # Pass test arguments via environment variable to avoid PowerShell
    # -File mode interpreting values like '-b' as parameter names.
    $env:DELPHI_COVERAGE_ARGS = ''
    if ($CoverageArguments.Count -gt 0) {
        $env:DELPHI_COVERAGE_ARGS = $CoverageArguments -join ','
    }

    $toolResult     = [PSCustomObject]@{ ExitCode = 0; Success = $true }
    $coveragePercent = 0.0
    $linesCovered    = 0
    $linesTotal      = 0
    $thresholdMet    = $true

    try {
        if ($PSCmdlet.ShouldProcess($displayTarget, "Coverage")) {
            Write-Verbose "Tool: $tool"
            Write-Verbose "Args: $($toolArgs.ToArray() -join ' ')"
            $toolResult = Invoke-BundledTool -ToolName $tool -Arguments $toolArgs.ToArray()

            try {
                $raw    = Get-Content -LiteralPath $resultFile -Raw -ErrorAction Stop
                $parsed = $raw | ConvertFrom-Json
                $coveragePercent = if ($null -ne $parsed.coveragePercent) { $parsed.coveragePercent } else { 0.0 }
                $linesCovered    = if ($null -ne $parsed.linesCovered)    { $parsed.linesCovered }    else { 0 }
                $linesTotal      = if ($null -ne $parsed.linesTotal)      { $parsed.linesTotal }      else { 0 }
                $thresholdMet    = if ($null -ne $parsed.thresholdMet)    { $parsed.thresholdMet }    else { $true }
            }
            catch {
                # Result file missing or malformed
            }
        }
    }
    finally {
        Remove-Item -LiteralPath $resultFile -Force -ErrorAction SilentlyContinue
    }

    $stopwatch.Stop()

    if ($toolResult.Success) {
        Write-DelphiCiMessage -Level 'OK' -Message "Coverage completed: $coveragePercent% ($linesCovered/$linesTotal lines)"
    }
    else {
        Write-DelphiCiMessage -Level 'ERROR' -Message "Coverage failed (exit code $($toolResult.ExitCode))"
    }

    return [PSCustomObject]@{
        StepName        = 'Coverage'
        Success         = $toolResult.Success
        Duration        = $stopwatch.Elapsed
        ExitCode        = $toolResult.ExitCode
        Tool            = $tool
        Message         = if ($toolResult.Success) { "$coveragePercent% ($linesCovered/$linesTotal lines)" } else { "Exit code $($toolResult.ExitCode)" }
        Execute         = $displayTarget
        CoveragePercent = $coveragePercent
        LinesCovered    = $linesCovered
        LinesTotal      = $linesTotal
        ThresholdMet    = $thresholdMet
        OutputDir       = $CoverageOutputDir
        Badge           = if ([string]::IsNullOrEmpty($CoverageBadge)) { $null } else { $CoverageBadge }
    }
}
