function Invoke-CompressFiles {
    <#
    .SYNOPSIS
        Compresses files or a directory into a .zip archive.

    .DESCRIPTION
        Creates a zip archive from the source path (file, directory, or
        glob pattern) with optional SHA256 checksum sidecar file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Source,

        [Parameter(Mandatory)]
        [string]$Destination,

        [bool]$Overwrite = $true,
        [bool]$Checksum = $false
    )

    # Validate source exists or glob resolves
    $sourceExists = $false
    if (Test-Path -LiteralPath $Source) {
        $sourceExists = $true
    }
    else {
        $resolved = @(Get-ChildItem -Path $Source -ErrorAction SilentlyContinue)
        if ($resolved.Count -gt 0) {
            $sourceExists = $true
        }
    }

    if (-not $sourceExists) {
        return [PSCustomObject]@{
            Success     = $false
            ExitCode    = 1
            Message     = "Source not found: $Source"
            ArchiveSize = [long]0
            Checksum    = $null
        }
    }

    # Ensure destination parent directory exists
    $destDir = [System.IO.Path]::GetDirectoryName($Destination)
    if (-not [string]::IsNullOrEmpty($destDir) -and
        -not (Test-Path -LiteralPath $destDir -PathType Container)) {
        New-Item -Path $destDir -ItemType Directory -Force | Out-Null
    }

    # Handle existing archive
    if (Test-Path -LiteralPath $Destination -PathType Leaf) {
        if ($Overwrite) {
            Remove-Item -LiteralPath $Destination -Force
        }
        else {
            return [PSCustomObject]@{
                Success     = $false
                ExitCode    = 1
                Message     = "Archive already exists and overwrite is disabled: $Destination"
                ArchiveSize = [long]0
                Checksum    = $null
            }
        }
    }

    # Create the archive
    Compress-Archive -Path $Source -DestinationPath $Destination

    $archiveSize = (Get-Item -LiteralPath $Destination).Length
    $checksumValue = $null

    # Generate checksum sidecar
    if ($Checksum) {
        $hash = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash.ToLower()
        $checksumValue = $hash
        $archiveName = [System.IO.Path]::GetFileName($Destination)
        $sidecarPath = "$Destination.sha256"
        Set-Content -LiteralPath $sidecarPath -Value "$hash  $archiveName" -NoNewline -Encoding UTF8
    }

    return [PSCustomObject]@{
        Success     = $true
        ExitCode    = 0
        Message     = "Archive created ($archiveSize bytes)"
        ArchiveSize = $archiveSize
        Checksum    = $checksumValue
    }
}
