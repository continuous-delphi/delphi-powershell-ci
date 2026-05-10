function Invoke-DelphiCopy {
    <#
    .SYNOPSIS
        Copies files matching a glob pattern as a CI step.

    .DESCRIPTION
        Resolves the source glob, copies matched files to the destination
        directory with optional flattening and checksum generation.
        Returns a structured step result.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Source,

        [Parameter(Mandatory)]
        [string]$Destination,

        [bool]$Flatten = $false,
        [bool]$Overwrite = $true,
        [bool]$CreateDestination = $true,
        [bool]$Checksum = $false
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    Write-DelphiCiMessage -Level 'STEP' -Message "Copy -- $Source -> $Destination"

    $copyResult = [PSCustomObject]@{
        Success     = $true
        ExitCode    = 0
        Message     = 'Completed (copy skipped)'
        FileCount   = 0
        BytesCopied = [long]0
    }

    if ($PSCmdlet.ShouldProcess("$Source -> $Destination", "Copy")) {
        $copyResult = Invoke-CopyFiles `
            -Source            $Source `
            -Destination       $Destination `
            -Flatten           $Flatten `
            -Overwrite         $Overwrite `
            -CreateDestination $CreateDestination `
            -Checksum          $Checksum
    }

    $stopwatch.Stop()

    if ($copyResult.Success) {
        Write-DelphiCiMessage -Level 'OK' -Message "Copy completed -- $($copyResult.FileCount) file(s)"
    }
    else {
        Write-DelphiCiMessage -Level 'ERROR' -Message "Copy failed -- $($copyResult.Message)"
    }

    return [PSCustomObject]@{
        StepName    = 'Copy'
        Success     = $copyResult.Success
        Duration    = $stopwatch.Elapsed
        ExitCode    = $copyResult.ExitCode
        Tool        = 'copy'
        Message     = $copyResult.Message
        Source      = $Source
        Destination = $Destination
        FileCount   = $copyResult.FileCount
        BytesCopied = $copyResult.BytesCopied
    }
}
