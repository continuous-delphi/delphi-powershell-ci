function Invoke-DelphiCompress {
    <#
    .SYNOPSIS
        Compresses files into a .zip archive as a CI step.

    .DESCRIPTION
        Creates a zip archive from the source path with optional SHA256
        checksum sidecar file. Returns a structured step result.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Source,

        [Parameter(Mandatory)]
        [string]$Destination,

        [bool]$Overwrite = $true,
        [bool]$Checksum = $false
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    Write-DelphiCiMessage -Level 'STEP' -Message "Compress -- $Source -> $Destination"

    $compressResult = [PSCustomObject]@{
        Success     = $true
        ExitCode    = 0
        Message     = 'Completed (compress skipped)'
        ArchiveSize = [long]0
        Checksum    = $null
    }

    if ($PSCmdlet.ShouldProcess("$Source -> $Destination", "Compress")) {
        $compressResult = Invoke-CompressFiles `
            -Source      $Source `
            -Destination $Destination `
            -Overwrite   $Overwrite `
            -Checksum    $Checksum
    }

    $stopwatch.Stop()

    if ($compressResult.Success) {
        Write-DelphiCiMessage -Level 'OK' -Message "Compress completed -- $($compressResult.ArchiveSize) bytes"
    }
    else {
        Write-DelphiCiMessage -Level 'ERROR' -Message "Compress failed -- $($compressResult.Message)"
    }

    return [PSCustomObject]@{
        StepName    = 'Compress'
        Success     = $compressResult.Success
        Duration    = $stopwatch.Elapsed
        ExitCode    = $compressResult.ExitCode
        Tool        = 'compress'
        Message     = $compressResult.Message
        Source      = $Source
        Destination = $Destination
        ArchiveSize = $compressResult.ArchiveSize
        Checksum    = $compressResult.Checksum
    }
}
