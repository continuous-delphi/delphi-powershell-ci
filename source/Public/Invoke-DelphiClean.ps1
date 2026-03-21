function Invoke-DelphiClean {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$Root = (Get-Location).Path,

        [ValidateSet('lite', 'build', 'full')]
        [string]$Level = 'lite',

        [string[]]$IncludeFiles = @(),

        [string[]]$ExcludeDirectories = @()
    )

    $tool      = 'delphi-clean.ps1'
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    Write-DelphiCiMessage -Level 'STEP' -Message "Clean ($Level) -- $Root"

    $toolArgs = [System.Collections.Generic.List[string]]@('-Level', $Level, '-RootPath', $Root)
    foreach ($p in $IncludeFiles)      { $toolArgs.Add('-IncludeFilePattern'); $toolArgs.Add($p) }
    foreach ($p in $ExcludeDirectories){ $toolArgs.Add('-ExcludeDirPattern');  $toolArgs.Add($p) }
    $toolArgs = $toolArgs.ToArray()
    $toolResult = [PSCustomObject]@{ ExitCode = 0; Success = $true }

    if ($PSCmdlet.ShouldProcess($Root, "Clean ($Level)")) {
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
