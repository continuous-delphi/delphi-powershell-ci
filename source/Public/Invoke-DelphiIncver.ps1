function Invoke-DelphiIncVer {
    <#
    .SYNOPSIS
        Increments a version number in a source file as a CI step.

    .DESCRIPTION
        Invokes the delphi-incver bundled tool to parse and increment a
        version string in an RC or text file. Returns a structured step
        result with old and new version strings.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        # Path to the file containing the version to increment.
        [Parameter(Mandatory)]
        [string]$File,

        # File type: RC or Text. Auto-detected from extension if empty.
        [string]$IncVerTarget = '',

        # Version style: WinVer or SemVer. Auto-detected from target if empty.
        [string]$IncVerStyle = '',

        # Which version component to bump: major, minor, patch, build,
        # or pre-release. When empty, bumps the last component.
        [string]$IncVerPart = '',

        # Regex pattern with a capture group around the version string.
        # Required for Text targets.
        [string]$IncVerPattern = ''
    )

    $tool      = 'delphi-incver.ps1'
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    Write-DelphiCiMessage -Level 'STEP' -Message "IncVer -- $File"

    $toolArgs = [System.Collections.Generic.List[string]]@('-File', $File)
    if (-not [string]::IsNullOrEmpty($IncVerTarget))  { $toolArgs.Add('-Target');  $toolArgs.Add($IncVerTarget) }
    if (-not [string]::IsNullOrEmpty($IncVerStyle))   { $toolArgs.Add('-Style');   $toolArgs.Add($IncVerStyle) }
    if (-not [string]::IsNullOrEmpty($IncVerPart))    { $toolArgs.Add('-Part');    $toolArgs.Add($IncVerPart) }
    if (-not [string]::IsNullOrEmpty($IncVerPattern)) { $toolArgs.Add('-Pattern'); $toolArgs.Add($IncVerPattern) }

    $resultFile = [System.IO.Path]::GetTempFileName()
    $toolArgs.Add('-OutputFile')
    $toolArgs.Add($resultFile)

    $toolResult = [PSCustomObject]@{ ExitCode = 0; Success = $true }
    $oldVersion = $null
    $newVersion = $null

    try {
        if ($PSCmdlet.ShouldProcess($File, "IncVer")) {
            $toolResult = Invoke-BundledTool -ToolName $tool -Arguments $toolArgs.ToArray()

            try {
                $raw    = Get-Content -LiteralPath $resultFile -Raw -ErrorAction Stop
                $parsed = $raw | ConvertFrom-Json
                $oldVersion = $parsed.oldVersion
                $newVersion = $parsed.newVersion
            }
            catch {
                # Result file missing or malformed -- version info unavailable
            }
        }
    }
    finally {
        Remove-Item -LiteralPath $resultFile -Force -ErrorAction SilentlyContinue
    }

    $stopwatch.Stop()

    if ($toolResult.Success) {
        Write-DelphiCiMessage -Level 'OK' -Message "IncVer completed: $oldVersion -> $newVersion"
    }
    else {
        Write-DelphiCiMessage -Level 'ERROR' -Message "IncVer failed (exit code $($toolResult.ExitCode))"
    }

    return [PSCustomObject]@{
        StepName   = 'IncVer'
        Success    = $toolResult.Success
        Duration   = $stopwatch.Elapsed
        ExitCode   = $toolResult.ExitCode
        Tool       = $tool
        Message    = if ($toolResult.Success) { "$oldVersion -> $newVersion" } else { "Exit code $($toolResult.ExitCode)" }
        File       = $File
        OldVersion = $oldVersion
        NewVersion = $newVersion
    }
}
