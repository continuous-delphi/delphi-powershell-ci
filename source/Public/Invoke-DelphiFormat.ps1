function Invoke-DelphiFormat {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$FormatRoot = (Get-Location).Path,

        [ValidateSet('formatter', 'radFormatter')]
        [string]$FormatEngine = 'formatter',

        # Explicit path to the formatting engine executable. Forwarded as
        # -EnginePath; when empty the tool discovers the engine on PATH.
        [string]$FormatEnginePath = '',

        # Engine-specific configuration file (e.g. a formatter.exe config).
        # Forwarded as -EngineConfigFile.
        [string]$FormatEngineConfigFile = '',

        # Explicit files or directories to format. Forwarded as repeated -Path
        # arguments; when empty the tool scans FormatRoot.
        [string[]]$FormatPath = @(),

        [string[]]$FormatIncludeFilePattern = @(),

        [string[]]$FormatExcludeDirectoryPattern = @(),

        # File encoding passed through to the engine (-e). Forwarded as -Encoding.
        [string]$FormatEncoding = '',

        # When set, the engine writes a backup of each modified file (-b).
        # Forwarded as -CreateBackups.
        [switch]$FormatCreateBackups,

        [ValidateSet('detailed', 'summary', 'quiet')]
        [string]$FormatOutputLevel = 'detailed',

        # Optional path to an explicit delphi-format config file, forwarded as
        # -ConfigFile to delphi-format.ps1. Loaded at higher priority than the
        # delphi-format.json hierarchy but lower than the CLI parameters above.
        [string]$FormatConfigFile = '',

        # When set, run delphi-format in audit-only mode (-Check). Reports which
        # files need formatting but never modifies them; returns a failing exit
        # code when any file is not correctly formatted. Useful for CI gates.
        [switch]$FormatCheck
    )

    $tool      = 'delphi-format.ps1'
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    $modeLabel = if ($FormatCheck) { 'Check' } else { 'Format' }
    Write-DelphiCiMessage -Level 'STEP' -Message "$modeLabel ($FormatEngine) -- $FormatRoot"

    $toolArgs = [System.Collections.Generic.List[string]]@('-RootPath', $FormatRoot, '-Engine', $FormatEngine, '-OutputLevel', $FormatOutputLevel)
    if (-not [string]::IsNullOrEmpty($FormatEnginePath))       { $toolArgs.Add('-EnginePath');       $toolArgs.Add($FormatEnginePath) }
    if (-not [string]::IsNullOrEmpty($FormatEngineConfigFile)) { $toolArgs.Add('-EngineConfigFile'); $toolArgs.Add($FormatEngineConfigFile) }
    foreach ($p in $FormatPath)                    { $toolArgs.Add('-Path');                    $toolArgs.Add($p) }
    foreach ($p in $FormatIncludeFilePattern)      { $toolArgs.Add('-IncludeFilePattern');      $toolArgs.Add($p) }
    foreach ($p in $FormatExcludeDirectoryPattern) { $toolArgs.Add('-ExcludeDirectoryPattern'); $toolArgs.Add($p) }
    if (-not [string]::IsNullOrEmpty($FormatEncoding))   { $toolArgs.Add('-Encoding'); $toolArgs.Add($FormatEncoding) }
    if (-not [string]::IsNullOrEmpty($FormatConfigFile)) { $toolArgs.Add('-ConfigFile'); $toolArgs.Add($FormatConfigFile) }
    if ($FormatCreateBackups) { $toolArgs.Add('-CreateBackups') }
    if ($FormatCheck)         { $toolArgs.Add('-Check') }
    $toolArgs   = $toolArgs.ToArray()
    $toolResult = [PSCustomObject]@{ ExitCode = 0; Success = $true }

    if ($PSCmdlet.ShouldProcess($FormatRoot, "$modeLabel ($FormatEngine)")) {
        $toolResult = Invoke-BundledTool -ToolName $tool -Arguments $toolArgs
    }

    $stopwatch.Stop()

    if ($toolResult.Success) {
        Write-DelphiCiMessage -Level 'OK' -Message "$modeLabel completed"
    }
    else {
        Write-DelphiCiMessage -Level 'ERROR' -Message "$modeLabel failed (exit code $($toolResult.ExitCode))"
    }

    return [PSCustomObject]@{
        StepName    = 'Format'
        Success     = $toolResult.Success
        Duration    = $stopwatch.Elapsed
        ExitCode    = $toolResult.ExitCode
        Tool        = $tool
        Message     = if ($toolResult.Success) { "$modeLabel completed" } else { "Exit code $($toolResult.ExitCode)" }
        ProjectFile = $null
    }
}
