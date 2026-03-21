function Resolve-DefaultPlatform {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectFile
    )

    $xml = [xml](Get-Content -LiteralPath $ProjectFile -Raw -ErrorAction Stop)

    $platformsNode   = $xml.Project.ProjectExtensions.BorlandProject.Platforms
    $activePlatforms = @()
    if ($platformsNode -is [System.Xml.XmlElement]) {
        $activePlatforms = @(
            $platformsNode.ChildNodes |
            Where-Object { $_.LocalName -eq 'Platform' -and $_.'#text' -eq 'True' } |
            ForEach-Object { $_.GetAttribute('value') }
        )
    }

    if ($activePlatforms.Count -eq 1) {
        return $activePlatforms[0]
    }

    return 'Win32'
}
