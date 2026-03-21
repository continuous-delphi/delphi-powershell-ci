function Find-DelphiProjects {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Root
    )

    # Candidate search directories, tried in order.
    # The ../source entry handles the tools-folder convention: if Root is a
    # /tools directory, the project lives one level up in /source.
    $candidates = @(
        $Root,
        (Join-Path $Root 'source'),
        ([System.IO.Path]::GetFullPath((Join-Path $Root '..\source')))
    )

    foreach ($dir in $candidates) {
        $resolved = [System.IO.Path]::GetFullPath($dir)
        if (-not (Test-Path -LiteralPath $resolved -PathType Container)) {
            continue
        }
        $found = @(Get-ChildItem -LiteralPath $resolved -Filter '*.dproj' -File)
        if ($found.Count -gt 0) {
            return $found.FullName
        }
    }

    return @()
}
