function Invoke-TestRunner {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TestExecutable,

        [string[]]$Arguments = @(),

        [int]$TimeoutSeconds = 10
    )

    if (-not (Test-Path -LiteralPath $TestExecutable)) {
        return [PSCustomObject]@{
            ExitCode = 1
            Success  = $false
            Message  = "Test executable not found: $TestExecutable"
        }
    }

    $startParams = @{
        FilePath    = $TestExecutable
        PassThru    = $true
        NoNewWindow = $true
        ErrorAction = 'Stop'
    }
    if ($Arguments.Count -gt 0) {
        $startParams['ArgumentList'] = $Arguments
    }

    $proc     = Start-Process @startParams
    $finished = $proc.WaitForExit($TimeoutSeconds * 1000)

    if (-not $finished) {
        try { $proc.Kill() } catch {}
        $proc.Dispose()
        return [PSCustomObject]@{
            ExitCode = -1
            Success  = $false
            Message  = "Timed out after ${TimeoutSeconds}s"
        }
    }

    $exitCode = $proc.ExitCode
    $proc.Dispose()

    return [PSCustomObject]@{
        ExitCode = $exitCode
        Success  = ($exitCode -eq 0)
        Message  = if ($exitCode -eq 0) { 'Tests passed' } else { "Exit code $exitCode" }
    }
}
