function Invoke-DelphiClean {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$CleanRoot = (Get-Location).Path,

        [ValidateSet('basic', 'standard', 'deep')]
        [string]$CleanLevel = 'basic',

        [ValidateSet('detailed', 'summary', 'quiet')]
        [string]$CleanOutputLevel = 'detailed',

        [string[]]$CleanIncludeFilePattern = @(),

        [string[]]$CleanExcludeDirectoryPattern = @(),

        # Optional path to an explicit delphi-clean config file, forwarded as
        # -ConfigFile to delphi-clean.ps1. Loaded at higher priority than
        # delphi-clean.json but lower than the CLI parameters above.
        [string]$CleanConfigFile = '',

        # When set, send removed items to the platform recycle bin / trash
        # instead of deleting them permanently. Forwarded as -RecycleBin.
        [switch]$CleanRecycleBin,

        # When set, run delphi-clean in audit-only mode (-Check). Scans for
        # artifacts but never deletes; returns a failing exit code when
        # artifacts are present. Useful for verifying a clean workspace.
        [switch]$CleanCheck
    )

    $tool      = 'delphi-clean.ps1'
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    Write-DelphiCiMessage -Level 'STEP' -Message "Clean ($CleanLevel) -- $CleanRoot"

    $toolArgs = [System.Collections.Generic.List[string]]@('-RootPath', $CleanRoot, '-Level', $CleanLevel, '-OutputLevel', $CleanOutputLevel)
    foreach ($p in $CleanIncludeFilePattern)      { $toolArgs.Add('-IncludeFilePattern');      $toolArgs.Add($p) }
    foreach ($p in $CleanExcludeDirectoryPattern) { $toolArgs.Add('-ExcludeDirectoryPattern'); $toolArgs.Add($p) }
    if (-not [string]::IsNullOrEmpty($CleanConfigFile)) {
        $toolArgs.Add('-ConfigFile')
        $toolArgs.Add($CleanConfigFile)
    }
    if ($CleanRecycleBin) { $toolArgs.Add('-RecycleBin') }
    if ($CleanCheck)      { $toolArgs.Add('-Check') }
    $toolArgs   = $toolArgs.ToArray()
    $toolResult = [PSCustomObject]@{ ExitCode = 0; Success = $true }

    if ($PSCmdlet.ShouldProcess($CleanRoot, "Clean ($CleanLevel)")) {
        $toolResult = Invoke-BundledTool -ToolName $tool -Arguments $toolArgs
    }

    $stopwatch.Stop()

    if ($toolResult.Success) {
        Write-DelphiCiMessage -Level 'OK' -Message 'Clean completed'
    }
    else {
        Write-DelphiCiMessage -Level 'ERROR' -Message "Clean failed (exit code $($toolResult.ExitCode))"
    }

    return [PSCustomObject]@{
        StepName    = 'Clean'
        Success     = $toolResult.Success
        Duration    = $stopwatch.Elapsed
        ExitCode    = $toolResult.ExitCode
        Tool        = $tool
        Message     = if ($toolResult.Success) { 'Clean completed' } else { "Exit code $($toolResult.ExitCode)" }
        ProjectFile = $null
    }
}
