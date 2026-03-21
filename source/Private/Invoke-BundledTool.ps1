function Invoke-BundledTool {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ToolName,

        [string[]]$Arguments = @()
    )

    $toolPath = Join-Path $script:BundledToolsDir $ToolName
    if (-not (Test-Path -LiteralPath $toolPath -PathType Leaf)) {
        throw "Bundled tool not found: $toolPath"
    }

    & $script:PowerShellExe -NoProfile -NonInteractive -File $toolPath @Arguments | Out-Host
    $exitCode = $LASTEXITCODE

    return [PSCustomObject]@{
        ExitCode = $exitCode
        Success  = ($exitCode -eq 0)
    }
}
