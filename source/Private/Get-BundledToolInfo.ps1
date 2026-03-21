function Get-BundledToolInfo {
    [CmdletBinding()]
    param()

    $toolDefs = @(
        [PSCustomObject]@{ FileName = 'delphi-inspect.ps1';  SupportsVersionApi = $true }
        [PSCustomObject]@{ FileName = 'delphi-clean.ps1';    SupportsVersionApi = $true }
        [PSCustomObject]@{ FileName = 'delphi-msbuild.ps1';  SupportsVersionApi = $false }
        [PSCustomObject]@{ FileName = 'delphi-dccbuild.ps1'; SupportsVersionApi = $false }
    )

    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($toolDef in $toolDefs) {
        $toolPath = Join-Path $script:BundledToolsDir $toolDef.FileName
        $present  = Test-Path -LiteralPath $toolPath -PathType Leaf
        $version  = $null

        if ($present) {
            if ($toolDef.SupportsVersionApi) {
                try {
                    $jsonOutput = & pwsh -NoProfile -NonInteractive -File $toolPath -Version -Format json 2>&1
                    if ($LASTEXITCODE -eq 0) {
                        $parsed  = ($jsonOutput -join '') | ConvertFrom-Json
                        $version = $parsed.tool.version
                    }
                }
                catch {
                    Write-Verbose "Version API call failed for $($toolDef.FileName): $_"
                }
            }
            else {
                $content = Get-Content -LiteralPath $toolPath -Raw
                if ($content -match '\$script:(?:Tool)?Version\s*=\s*''([^'']+)''') {
                    $version = $Matches[1]
                }
            }
        }

        $toolName = [System.IO.Path]::GetFileNameWithoutExtension($toolDef.FileName)
        $results.Add([PSCustomObject]@{
            Name    = $toolName
            Version = $version
            Present = $present
            Path    = $toolPath
        })
    }

    return $results.ToArray()
}
