function Invoke-DelphiCoverage {
    <#
    .SYNOPSIS
        Runs Delphi code coverage analysis as a CI step.

    .DESCRIPTION
        Invokes the delphi-coverage bundled tool to run a test executable
        with coverage instrumentation. Returns a structured step result
        with coverage percentage, line counts, and threshold status.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Execute,

        [Parameter(Mandatory)]
        [string]$MapFile,

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

    $tool      = 'delphi-coverage.ps1'
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    Write-DelphiCiMessage -Level 'STEP' -Message "Coverage -- $Execute"

    $toolArgs = [System.Collections.Generic.List[string]]@(
        '-Execute', $Execute,
        '-MapFile', $MapFile,
        '-Engine', $CoverageEngine,
        '-OutputDir', $CoverageOutputDir,
        '-Threshold', $CoverageThreshold.ToString(),
        '-TimeoutSeconds', $CoverageTimeoutSeconds.ToString()
    )
    if (-not [string]::IsNullOrEmpty($CoverageEnginePath))  { $toolArgs.Add('-EnginePath');  $toolArgs.Add($CoverageEnginePath) }
    if ($CoverageSourceDir.Count -gt 0)   { $toolArgs.Add('-SourceDir'); $toolArgs.Add(($CoverageSourceDir -join ',')) }
    if ($CoverageUnits.Count -gt 0)        { $toolArgs.Add('-Units');        foreach ($u in $CoverageUnits) { $toolArgs.Add($u) } }
    if ($CoverageExcludeUnits.Count -gt 0) { $toolArgs.Add('-ExcludeUnits'); foreach ($eu in $CoverageExcludeUnits) { $toolArgs.Add($eu) } }
    if ($CoverageFormats.Count -gt 0)     { $toolArgs.Add('-Formats');      foreach ($fmt in $CoverageFormats) { $toolArgs.Add($fmt) } }
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
        if ($PSCmdlet.ShouldProcess($Execute, "Coverage")) {
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
        Execute         = $Execute
        CoveragePercent = $coveragePercent
        LinesCovered    = $linesCovered
        LinesTotal      = $linesTotal
        ThresholdMet    = $thresholdMet
        OutputDir       = $CoverageOutputDir
        Badge           = if ([string]::IsNullOrEmpty($CoverageBadge)) { $null } else { $CoverageBadge }
    }
}
