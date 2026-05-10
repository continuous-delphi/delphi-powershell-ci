function Invoke-CopyFiles {
    <#
    .SYNOPSIS
        Copies files matching a glob pattern to a destination directory.

    .DESCRIPTION
        Resolves a source glob pattern, copies matched files to the
        destination, optionally flattening directory structure and
        generating a SHA256 checksum manifest.
    #>
    [CmdletBinding()]
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

    $fileCount  = 0
    $bytesCopied = [long]0

    # Ensure destination directory exists
    if (-not (Test-Path -LiteralPath $Destination -PathType Container)) {
        if ($CreateDestination) {
            New-Item -Path $Destination -ItemType Directory -Force | Out-Null
        }
        else {
            return [PSCustomObject]@{
                Success     = $false
                ExitCode    = 1
                Message     = "Destination directory does not exist: $Destination"
                FileCount   = 0
                BytesCopied = [long]0
            }
        }
    }

    # Resolve source files (recurse to find files in subdirectories)
    $files = @(Get-ChildItem -Path $Source -File -Recurse -ErrorAction SilentlyContinue)
    if ($files.Count -eq 0) {
        return [PSCustomObject]@{
            Success     = $false
            ExitCode    = 1
            Message     = "No files matched source pattern: $Source"
            FileCount   = 0
            BytesCopied = [long]0
        }
    }

    # Compute the glob base directory for relative path preservation.
    # Take the path up to the first wildcard character, then find the
    # last directory separator.
    $globBase = $Source
    $wildcardIdx = $globBase.IndexOfAny([char[]]@('*', '?', '['))
    if ($wildcardIdx -ge 0) {
        $globBase = $globBase.Substring(0, $wildcardIdx)
    }
    $lastSep = $globBase.LastIndexOfAny([char[]]@('\', '/'))
    if ($lastSep -ge 0) {
        $globBase = $globBase.Substring(0, $lastSep)
    }
    $globBase = [System.IO.Path]::GetFullPath($globBase)

    # Copy each file
    $copiedFiles = [System.Collections.Generic.List[string]]::new()
    foreach ($file in $files) {
        if ($Flatten) {
            $destPath = Join-Path $Destination $file.Name
        }
        else {
            $fullPath = $file.FullName
            $relativePath = $fullPath
            if ($fullPath.StartsWith($globBase, [System.StringComparison]::OrdinalIgnoreCase)) {
                $relativePath = $fullPath.Substring($globBase.Length).TrimStart('\', '/')
            }
            $destPath = Join-Path $Destination $relativePath
        }

        # Ensure parent directory exists
        $destDir = [System.IO.Path]::GetDirectoryName($destPath)
        if (-not (Test-Path -LiteralPath $destDir -PathType Container)) {
            New-Item -Path $destDir -ItemType Directory -Force | Out-Null
        }

        # Check for existing file when overwrite is disabled
        if (-not $Overwrite -and (Test-Path -LiteralPath $destPath -PathType Leaf)) {
            return [PSCustomObject]@{
                Success     = $false
                ExitCode    = 1
                Message     = "File already exists and overwrite is disabled: $destPath"
                FileCount   = $fileCount
                BytesCopied = $bytesCopied
            }
        }

        Copy-Item -LiteralPath $file.FullName -Destination $destPath -Force:$Overwrite
        $fileCount++
        $bytesCopied += $file.Length
        $copiedFiles.Add($destPath)
    }

    # Generate checksum manifest
    if ($Checksum -and $copiedFiles.Count -gt 0) {
        $checksumPath = Join-Path $Destination 'checksums.sha256'
        $lines = [System.Collections.Generic.List[string]]::new()
        foreach ($copied in $copiedFiles) {
            $hash = (Get-FileHash -LiteralPath $copied -Algorithm SHA256).Hash.ToLower()
            $fileName = [System.IO.Path]::GetFileName($copied)
            $lines.Add("$hash  $fileName")
        }
        Set-Content -LiteralPath $checksumPath -Value ($lines -join "`n") -NoNewline -Encoding UTF8
    }

    return [PSCustomObject]@{
        Success     = $true
        ExitCode    = 0
        Message     = "Copied $fileCount file(s)"
        FileCount   = $fileCount
        BytesCopied = $bytesCopied
    }
}
