function Invoke-DelphiTest {
    <#
    .SYNOPSIS
        Runs a pre-built test executable as a CI step.

    .DESCRIPTION
        Runs the specified test executable with an optional timeout and
        command-line arguments. Returns a structured step result.

        The test executable must already exist (built by a prior Build step
        or by calling Invoke-DelphiBuild directly). This command does not
        build anything.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        # Path to the test executable to run.
        [Parameter(Mandatory)]
        [string]$TestExeFile,

        # Extra command-line arguments forwarded to the test executable at runtime.
        [string[]]$Arguments = @(),

        # Maximum seconds the test process is allowed to run before it is killed.
        # Default is 10 seconds -- test suites should be fast.
        [int]$TimeoutSeconds = 10
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    Write-DelphiCiMessage -Level 'STEP' -Message "Test -- $TestExeFile"

    $runResult = [PSCustomObject]@{ ExitCode = 0; Success = $true; Message = 'Tests passed (run skipped)' }

    if ($PSCmdlet.ShouldProcess($TestExeFile, "Run tests")) {
        $runResult = Invoke-TestRunner `
            -TestExecutable $TestExeFile `
            -Arguments      $Arguments `
            -TimeoutSeconds $TimeoutSeconds
    }

    $stopwatch.Stop()

    if ($runResult.Success) {
        Write-DelphiCiMessage -Level 'OK' -Message 'Tests passed'
    }
    else {
        Write-DelphiCiMessage -Level 'ERROR' -Message "Tests failed -- $($runResult.Message)"
    }

    return [PSCustomObject]@{
        StepName       = 'Test'
        Success        = $runResult.Success
        Duration       = $stopwatch.Elapsed
        ExitCode       = $runResult.ExitCode
        Tool           = 'test runner'
        Message        = $runResult.Message
        TestExeFile    = $TestExeFile
    }
}
