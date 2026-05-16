function Invoke-DelphiCallGraph {
    <#
    .SYNOPSIS
        Runs Delphi call graph or dependency graph analysis as a CI step.

    .DESCRIPTION
        Invokes the delphi-callgraph bundled tool. The default engine is
        radCallGraph, with optional PasDoc and DCC GraphViz modes.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string[]]$CallGraphPath = @(),
        [string]$CallGraphEngine = 'radCallGraph',
        [string]$CallGraphEnginePath = '',
        [string]$CallGraphOutputDir = 'callgraph',
        [string[]]$CallGraphFormats = @('json'),
        [string]$CallGraphJsonFile = '',
        [string]$CallGraphDotFile = '',
        [string]$CallGraphSummaryFile = '',
        [string]$CallGraphClass = '',
        [bool]$CallGraphAnnotations = $true,
        [string]$CallGraphGraphKind = '',
        [bool]$CallGraphGraphVizUses = $false,
        [bool]$CallGraphGraphVizClasses = $false,
        [string[]]$CallGraphPasDocOptions = @(),
        [string]$CallGraphProjectFile = '',
        [string[]]$CallGraphGraphVizExclude = @(),
        [string[]]$CallGraphEngineArguments = @(),
        [int]$CallGraphTimeoutSeconds = 300
    )

    if ($CallGraphPath.Count -eq 0 -and [string]::IsNullOrWhiteSpace($CallGraphProjectFile)) {
        throw 'Either -CallGraphPath or -CallGraphProjectFile must be provided.'
    }

    $tool      = 'delphi-callgraph.ps1'
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    $displayTarget = if (-not [string]::IsNullOrWhiteSpace($CallGraphProjectFile)) {
        $CallGraphProjectFile
    } else {
        $CallGraphPath -join ', '
    }
    Write-DelphiCiMessage -Level 'STEP' -Message "CallGraph -- $displayTarget"

    $toolArgs = [System.Collections.Generic.List[string]]::new()
    if ($CallGraphPath.Count -gt 0) {
        $toolArgs.Add('-Path')
        $toolArgs.Add(($CallGraphPath -join ','))
    }

    $toolArgs.Add('-Engine')
    $toolArgs.Add($CallGraphEngine)
    $toolArgs.Add('-OutputDir')
    $toolArgs.Add($CallGraphOutputDir)
    $toolArgs.Add('-TimeoutSeconds')
    $toolArgs.Add($CallGraphTimeoutSeconds.ToString())
    $toolArgs.Add('-Annotations')
    $toolArgs.Add($(if ($CallGraphAnnotations) { '1' } else { '0' }))

    if ($CallGraphFormats.Count -gt 0) { $toolArgs.Add('-Formats'); $toolArgs.Add(($CallGraphFormats -join ',')) }
    if (-not [string]::IsNullOrWhiteSpace($CallGraphEnginePath))  { $toolArgs.Add('-EnginePath');  $toolArgs.Add($CallGraphEnginePath) }
    if (-not [string]::IsNullOrWhiteSpace($CallGraphJsonFile))    { $toolArgs.Add('-JsonFile');    $toolArgs.Add($CallGraphJsonFile) }
    if (-not [string]::IsNullOrWhiteSpace($CallGraphDotFile))     { $toolArgs.Add('-DotFile');     $toolArgs.Add($CallGraphDotFile) }
    if (-not [string]::IsNullOrWhiteSpace($CallGraphSummaryFile)) { $toolArgs.Add('-SummaryFile'); $toolArgs.Add($CallGraphSummaryFile) }
    if (-not [string]::IsNullOrWhiteSpace($CallGraphClass))       { $toolArgs.Add('-Class');       $toolArgs.Add($CallGraphClass) }
    if (-not [string]::IsNullOrWhiteSpace($CallGraphGraphKind))   { $toolArgs.Add('-GraphKind');   $toolArgs.Add($CallGraphGraphKind) }
    if ($CallGraphGraphVizUses)    { $toolArgs.Add('-GraphVizUses') }
    if ($CallGraphGraphVizClasses) { $toolArgs.Add('-GraphVizClasses') }
    if (-not [string]::IsNullOrWhiteSpace($CallGraphProjectFile)) { $toolArgs.Add('-ProjectFile'); $toolArgs.Add($CallGraphProjectFile) }
    if ($CallGraphGraphVizExclude.Count -gt 0) { $toolArgs.Add('-GraphVizExclude'); $toolArgs.Add(($CallGraphGraphVizExclude -join ',')) }

    $resultFile = [System.IO.Path]::GetTempFileName()
    $toolArgs.Add('-OutputFile')
    $toolArgs.Add($resultFile)

    $env:DELPHI_CALLGRAPH_ENGINE_ARGS = ''
    if ($CallGraphEngineArguments.Count -gt 0) {
        $env:DELPHI_CALLGRAPH_ENGINE_ARGS = $CallGraphEngineArguments -join ','
    }

    $env:DELPHI_CALLGRAPH_PASDOC_OPTIONS = ''
    if ($CallGraphPasDocOptions.Count -gt 0) {
        $env:DELPHI_CALLGRAPH_PASDOC_OPTIONS = $CallGraphPasDocOptions -join ','
    }

    $toolResult = [PSCustomObject]@{ ExitCode = 0; Success = $true }
    $resultFormats = @($CallGraphFormats)
    $resultFiles = $null
    $resultInputs = @($CallGraphPath)
    $resultSummary = $null

    try {
        if ($PSCmdlet.ShouldProcess($displayTarget, "CallGraph")) {
            Write-Verbose "Tool: $tool"
            Write-Verbose "Args: $($toolArgs.ToArray() -join ' ')"
            $toolResult = Invoke-BundledTool -ToolName $tool -Arguments $toolArgs.ToArray()

            try {
                $raw = Get-Content -LiteralPath $resultFile -Raw -ErrorAction Stop
                $parsed = $raw | ConvertFrom-Json
                if ($null -ne $parsed.formats) { $resultFormats = @($parsed.formats) }
                if ($null -ne $parsed.files)   { $resultFiles = $parsed.files }
                if ($null -ne $parsed.inputs)  { $resultInputs = @($parsed.inputs) }
                if ($null -ne $parsed.summary) { $resultSummary = $parsed.summary }
            }
            catch {
                # Result file missing or malformed; keep exit-code-only result.
            }
        }
    }
    finally {
        Remove-Item -LiteralPath $resultFile -Force -ErrorAction SilentlyContinue
    }

    $stopwatch.Stop()
    $successMessage = "CallGraph completed: $CallGraphOutputDir"
    if ($null -ne $resultSummary) {
        $summaryNodes = $resultSummary.PSObject.Properties['nodes']
        $summaryEdges = $resultSummary.PSObject.Properties['edges']
        if ($null -ne $summaryNodes -and $null -ne $summaryEdges) {
            $successMessage = "CallGraph completed: $($summaryNodes.Value) nodes, $($summaryEdges.Value) edges"
        }
    }

    if ($toolResult.Success) {
        Write-DelphiCiMessage -Level 'OK' -Message $successMessage
    }
    else {
        Write-DelphiCiMessage -Level 'ERROR' -Message "CallGraph failed (exit code $($toolResult.ExitCode))"
    }

    return [PSCustomObject]@{
        StepName  = 'CallGraph'
        Success   = $toolResult.Success
        Duration  = $stopwatch.Elapsed
        ExitCode  = $toolResult.ExitCode
        Tool      = $tool
        Message   = if ($toolResult.Success) { $successMessage } else { "Exit code $($toolResult.ExitCode)" }
        Engine    = $CallGraphEngine
        Inputs    = $resultInputs
        OutputDir = $CallGraphOutputDir
        Formats   = $resultFormats
        Files     = $resultFiles
        Summary   = $resultSummary
    }
}
