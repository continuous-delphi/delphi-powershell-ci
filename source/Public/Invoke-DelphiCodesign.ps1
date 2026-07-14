function Invoke-DelphiCodesign {
    <#
    .SYNOPSIS
        Signs or verifies Authenticode signatures as a CI step.

    .DESCRIPTION
        Invokes the delphi-codesign-azure bundled tool to sign or verify
        executables and libraries using Azure Trusted Signing.

        -Action Sign: signs one or more files with Azure credentials.
        -Action Verify: verifies the Authenticode signature on a single file.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Sign', 'Verify')]
        [string]$Action,

        [string[]]$Files = @(),

        [string]$FilePath = '',

        [string]$CodesignEngine = 'AzureTrustedSigning',
        [string]$CodesignSignToolPath = '',
        [string]$CodesignDlibPath = '',
        [string]$CodesignMetadataPath = '',
        [string]$CodesignEnvFile = ''
    )

    if ($Action -eq 'Sign' -and $Files.Count -eq 0) {
        throw '-Files must be provided for the Sign action.'
    }
    if ($Action -eq 'Verify' -and [string]::IsNullOrEmpty($FilePath)) {
        throw '-FilePath must be provided for the Verify action.'
    }

    $tool      = 'delphi-codesign-azure.ps1'
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    $displayTarget = if ($Action -eq 'Sign') { "$($Files.Count) file(s)" } else { $FilePath }
    Write-DelphiCiMessage -Level 'STEP' -Message "Codesign $Action -- $displayTarget"

    $toolArgs = [System.Collections.Generic.List[string]]::new()

    if ($Action -eq 'Sign') {
        $toolArgs.Add('-Sign')
        $toolArgs.Add('-Files')
        $toolArgs.Add(($Files -join ','))
    }
    else {
        $toolArgs.Add('-Verify')
        $toolArgs.Add('-FilePath')
        $toolArgs.Add($FilePath)
    }

    $toolArgs.Add('-Format')
    $toolArgs.Add('text')

    # -SignToolPath belongs to both the Sign and Verify parameter sets in the
    # bundled tool, so it is always safe to pass. -DlibPath, -MetadataPath, and
    # -EnvFile are Sign-only; passing them on a Verify call breaks the tool's
    # parameter-set resolution, so gate them behind the Sign action.
    if (-not [string]::IsNullOrEmpty($CodesignSignToolPath))  { $toolArgs.Add('-SignToolPath');  $toolArgs.Add($CodesignSignToolPath) }
    if ($Action -eq 'Sign') {
        if (-not [string]::IsNullOrEmpty($CodesignDlibPath))      { $toolArgs.Add('-DlibPath');      $toolArgs.Add($CodesignDlibPath) }
        if (-not [string]::IsNullOrEmpty($CodesignMetadataPath))  { $toolArgs.Add('-MetadataPath');  $toolArgs.Add($CodesignMetadataPath) }
        if (-not [string]::IsNullOrEmpty($CodesignEnvFile))       { $toolArgs.Add('-EnvFile');       $toolArgs.Add($CodesignEnvFile) }
    }

    $resultFile = [System.IO.Path]::GetTempFileName()
    $toolArgs.Add('-OutputFile')
    $toolArgs.Add($resultFile)

    $toolResult = [PSCustomObject]@{ ExitCode = 0; Success = $true }
    $signed     = 0
    $failed     = 0

    try {
        if ($PSCmdlet.ShouldProcess($displayTarget, "Codesign $Action")) {
            Write-Verbose "Tool: $tool"
            Write-Verbose "Args: $($toolArgs.ToArray() -join ' ')"
            $toolResult = Invoke-BundledTool -ToolName $tool -Arguments $toolArgs.ToArray()

            try {
                $raw    = Get-Content -LiteralPath $resultFile -Raw -ErrorAction Stop
                $parsed = $raw | ConvertFrom-Json
                if ($null -ne $parsed.result) {
                    $signed = if ($null -ne $parsed.result.signed) { [int]$parsed.result.signed } else { 0 }
                    $failed = if ($null -ne $parsed.result.failed) { [int]$parsed.result.failed } else { 0 }
                }
                if ($null -ne $parsed.ok) {
                    $toolResult = [PSCustomObject]@{ ExitCode = $toolResult.ExitCode; Success = [bool]$parsed.ok }
                }
            }
            catch {
                # Result file missing or malformed
            }
        }
    }
    catch {
        $toolResult = [PSCustomObject]@{ ExitCode = 3; Success = $false }
    }
    finally {
        Remove-Item -LiteralPath $resultFile -Force -ErrorAction SilentlyContinue
    }

    $stopwatch.Stop()

    if ($toolResult.Success) {
        $msg = if ($Action -eq 'Sign') { "Signed $signed file(s)" } else { "Signature valid: $FilePath" }
        Write-DelphiCiMessage -Level 'OK' -Message $msg
    }
    else {
        $msg = if ($Action -eq 'Sign') { "Signing failed: $signed ok, $failed failed" } else { "Verification failed (exit code $($toolResult.ExitCode))" }
        Write-DelphiCiMessage -Level 'ERROR' -Message $msg
    }

    return [PSCustomObject]@{
        StepName  = "Codesign$Action"
        Success   = $toolResult.Success
        Duration  = $stopwatch.Elapsed
        ExitCode  = $toolResult.ExitCode
        Tool      = $tool
        Message   = if ($toolResult.Success) { $msg } else { "Exit code $($toolResult.ExitCode)" }
        Action    = $Action
        Engine    = $CodesignEngine
        Signed    = $signed
        Failed    = $failed
    }
}
