function Invoke-DelphiRun {
    <#
    .SYNOPSIS
        Runs an executable or script as a CI step.

    .DESCRIPTION
        Runs the specified command with an optional timeout and
        command-line arguments. Returns a structured step result.
        Success is determined by exit code 0.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        # Path to the executable, script, or command to run.
        [Parameter(Mandatory)]
        [string]$Execute,

        # Extra command-line arguments forwarded to the command at runtime.
        [string[]]$Arguments = @(),

        # Maximum seconds the process is allowed to run before it is killed.
        # Default is 10 seconds.
        [int]$TimeoutSeconds = 10
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    Write-DelphiCiMessage -Level 'STEP' -Message "Run -- $Execute"

    $runResult = [PSCustomObject]@{ ExitCode = 0; Success = $true; Message = 'Completed (run skipped)' }

    if ($PSCmdlet.ShouldProcess($Execute, "Run")) {
        $runResult = Invoke-TestRunner `
            -TestExecutable $Execute `
            -Arguments      $Arguments `
            -TimeoutSeconds $TimeoutSeconds
    }

    $stopwatch.Stop()

    if ($runResult.Success) {
        Write-DelphiCiMessage -Level 'OK' -Message 'Run completed successfully'
    }
    else {
        Write-DelphiCiMessage -Level 'ERROR' -Message "Run failed -- $($runResult.Message)"
    }

    return [PSCustomObject]@{
        StepName       = 'Run'
        Success        = $runResult.Success
        Duration       = $stopwatch.Elapsed
        ExitCode       = $runResult.ExitCode
        Tool           = 'runner'
        Message        = $runResult.Message
        Execute        = $Execute
    }
}
