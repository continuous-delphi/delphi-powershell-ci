function Invoke-DelphiCi {
    [CmdletBinding(DefaultParameterSetName = 'Run')]
    param(
        [Parameter(ParameterSetName = 'VersionInfo', Mandatory)]
        [switch]$VersionInfo,

        [Parameter(ParameterSetName = 'Run')]
        [string]$ConfigFile,

        [Parameter(ParameterSetName = 'Run')]
        [string]$Root,

        [Parameter(ParameterSetName = 'Run')]
        [string]$ProjectFile,

        [Parameter(ParameterSetName = 'Run')]
        [string[]]$Steps,

        [Parameter(ParameterSetName = 'Run')]
        [string]$Platform,

        [Parameter(ParameterSetName = 'Run')]
        [string]$Configuration,

        [Parameter(ParameterSetName = 'Run')]
        [string]$Toolchain,

        [Parameter(ParameterSetName = 'Run')]
        [string]$BuildEngine,

        [Parameter(ParameterSetName = 'Run')]
        [string[]]$Defines,

        [Parameter(ParameterSetName = 'Run')]
        [ValidateSet('quiet', 'minimal', 'normal', 'detailed', 'diagnostic')]
        [string]$BuildVerbosity,

        [Parameter(ParameterSetName = 'Run')]
        [ValidateSet('basic', 'standard', 'deep')]
        [string]$CleanLevel,

        [Parameter(ParameterSetName = 'Run')]
        [ValidateSet('detailed', 'summary', 'quiet')]
        [string]$CleanOutputLevel,

        [Parameter(ParameterSetName = 'Run')]
        [string[]]$CleanIncludeFilePattern,

        [Parameter(ParameterSetName = 'Run')]
        [string[]]$CleanExcludeDirectoryPattern,

        [Parameter(ParameterSetName = 'Run')]
        [string]$CleanConfigFile,

        [Parameter(ParameterSetName = 'Run')]
        [string]$TestProjectFile,

        [Parameter(ParameterSetName = 'Run')]
        [string]$TestExecutable,

        [Parameter(ParameterSetName = 'Run')]
        [string[]]$TestDefines,

        [Parameter(ParameterSetName = 'Run')]
        [string[]]$TestArguments,

        [Parameter(ParameterSetName = 'Run')]
        [int]$TestTimeoutSeconds,

        [Parameter(ParameterSetName = 'Run')]
        [bool]$TestBuild,

        [Parameter(ParameterSetName = 'Run')]
        [bool]$TestRun
    )

    # ---------------------------------------------------------------------------
    # VersionInfo branch -- display module and bundled tool versions, then return
    # ---------------------------------------------------------------------------

    if ($VersionInfo) {
        $tools = Get-BundledToolInfo

        Write-DelphiCiMessage -Level 'INFO' -Message "Delphi.PowerShell.CI $script:ModuleVersion"
        foreach ($t in $tools) {
            $versionLabel = if ($null -ne $t.Version) { $t.Version } else { '(unknown)' }
            $presentLabel = if ($t.Present) { '' } else { ' [not found]' }
            Write-DelphiCiMessage -Level 'INFO' -Message "$($t.Name) $versionLabel$presentLabel"
        }

        return [PSCustomObject]@{
            Module = [PSCustomObject]@{
                Name    = 'Delphi.PowerShell.CI'
                Version = $script:ModuleVersion
            }
            Tools  = $tools
        }
    }

    # ---------------------------------------------------------------------------
    # Run branch
    # ---------------------------------------------------------------------------

    # Build overrides from explicitly bound parameters
    $overrides = @{}
    if ($PSBoundParameters.ContainsKey('Root'))             { $overrides['Root']             = $Root }
    if ($PSBoundParameters.ContainsKey('ProjectFile'))      { $overrides['ProjectFile']      = $ProjectFile }
    if ($PSBoundParameters.ContainsKey('Steps'))            { $overrides['Steps']            = $Steps }
    if ($PSBoundParameters.ContainsKey('Platform'))         { $overrides['Platform']         = $Platform }
    if ($PSBoundParameters.ContainsKey('Configuration'))    { $overrides['Configuration']    = $Configuration }
    if ($PSBoundParameters.ContainsKey('Toolchain'))        { $overrides['Toolchain']        = $Toolchain }
    if ($PSBoundParameters.ContainsKey('BuildEngine'))      { $overrides['BuildEngine']      = $BuildEngine }
    if ($PSBoundParameters.ContainsKey('Defines'))                      { $overrides['Defines']                      = $Defines }
    if ($PSBoundParameters.ContainsKey('BuildVerbosity'))               { $overrides['BuildVerbosity']               = $BuildVerbosity }
    if ($PSBoundParameters.ContainsKey('CleanLevel'))                   { $overrides['CleanLevel']                   = $CleanLevel }
    if ($PSBoundParameters.ContainsKey('CleanOutputLevel'))            { $overrides['CleanOutputLevel']             = $CleanOutputLevel }
    if ($PSBoundParameters.ContainsKey('CleanIncludeFilePattern'))      { $overrides['CleanIncludeFilePattern']      = $CleanIncludeFilePattern }
    if ($PSBoundParameters.ContainsKey('CleanExcludeDirectoryPattern')) { $overrides['CleanExcludeDirectoryPattern'] = $CleanExcludeDirectoryPattern }
    if ($PSBoundParameters.ContainsKey('CleanConfigFile'))              { $overrides['CleanConfigFile']              = $CleanConfigFile }
    if ($PSBoundParameters.ContainsKey('TestProjectFile'))          { $overrides['TestProjectFile']          = $TestProjectFile }
    if ($PSBoundParameters.ContainsKey('TestExecutable'))       { $overrides['TestExecutable']       = $TestExecutable }
    if ($PSBoundParameters.ContainsKey('TestDefines'))          { $overrides['TestDefines']          = $TestDefines }
    if ($PSBoundParameters.ContainsKey('TestArguments'))        { $overrides['TestArguments']        = $TestArguments }
    if ($PSBoundParameters.ContainsKey('TestTimeoutSeconds'))   { $overrides['TestTimeoutSeconds']   = $TestTimeoutSeconds }
    if ($PSBoundParameters.ContainsKey('TestBuild'))            { $overrides['TestBuild']            = $TestBuild }
    if ($PSBoundParameters.ContainsKey('TestRun'))              { $overrides['TestRun']              = $TestRun }

    $config = Resolve-DelphiCiConfig -ConfigFile $ConfigFile -Overrides $overrides

    # Resolve main project file -- explicit > config file > discovery
    $resolvedProject = $config.ProjectFile
    if ([string]::IsNullOrWhiteSpace($resolvedProject)) {
        $candidates = @(Find-DelphiProjects -Root $config.Root)
        if ($candidates.Count -eq 0) {
            throw "No .dproj files found under '$($config.Root)'. Use -ProjectFile or -Root to point at the project."
        }
        if ($candidates.Count -gt 1) {
            $list = ($candidates | ForEach-Object { [System.IO.Path]::GetFileName($_) }) -join ', '
            throw "Multiple .dproj files found; use -ProjectFile to select one. Found: $list"
        }
        $resolvedProject = $candidates[0]
    }

    $resolvedBuildPlatform = if ($null -eq $config.Build.Platform) {
        if ($config.Build.Engine -ne 'DCCBuild') {
            Resolve-DefaultPlatform -ProjectFile ([System.IO.Path]::ChangeExtension($resolvedProject, '.dproj'))
        } else {
            'Win32'
        }
    } else {
        $config.Build.Platform
    }

    Write-DelphiCiMessage -Level 'INFO' -Message "Project : $resolvedProject"
    Write-DelphiCiMessage -Level 'INFO' -Message "Steps   : $($config.Steps -join ', ')"

    $stepResults    = [System.Collections.Generic.List[object]]::new()
    $overallSuccess = $true
    $stopwatch      = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        foreach ($step in $config.Steps) {
            switch ($step) {
                'Clean' {
                    $result = Invoke-DelphiClean `
                        -CleanRoot                   $config.Root `
                        -CleanLevel                  $config.Clean.Level `
                        -CleanOutputLevel            $config.Clean.OutputLevel `
                        -CleanIncludeFilePattern     @($config.Clean.IncludeFilePattern) `
                        -CleanExcludeDirectoryPattern @($config.Clean.ExcludeDirectoryPattern) `
                        -CleanConfigFile             $config.Clean.ConfigFile
                }
                'Build' {
                    $result = Invoke-DelphiBuild `
                        -ProjectFile    $resolvedProject `
                        -Platform       $resolvedBuildPlatform `
                        -Configuration  $config.Build.Configuration `
                        -Toolchain      $config.Build.Toolchain.Version `
                        -BuildEngine    $config.Build.Engine `
                        -Defines        @($config.Build.Defines) `
                        -BuildVerbosity $config.Build.Verbosity
                }
                'Test' {
                    $result = Invoke-DelphiTest `
                        -Root            $config.Root `
                        -TestProjectFile $config.Test.TestProjectFile `
                        -TestExecutable  ([string]$config.Test.TestExecutable) `
                        -Platform        ([string]$config.Build.Platform) `
                        -Configuration   $config.Build.Configuration `
                        -Toolchain       $config.Build.Toolchain.Version `
                        -BuildEngine     $config.Build.Engine `
                        -Defines         @($config.Test.Defines) `
                        -Arguments       @($config.Test.Arguments) `
                        -TimeoutSeconds  $config.Test.TimeoutSeconds `
                        -Build           $config.Test.Build `
                        -Run             $config.Test.Run
                }
                default {
                    throw "Unknown step: $step"
                }
            }

            $stepResults.Add($result)

            if (-not $result.Success) {
                $overallSuccess = $false
                break
            }
        }
    }
    catch {
        $overallSuccess = $false
        Write-DelphiCiMessage -Level 'ERROR' -Message $_.Exception.Message
    }

    $stopwatch.Stop()

    $elapsed = $stopwatch.Elapsed.TotalSeconds.ToString('F2')
    Write-DelphiCiMessage -Level 'INFO' -Message "Duration: ${elapsed}s"
    if ($overallSuccess) {
        Write-DelphiCiMessage -Level 'OK'    -Message 'All steps completed successfully'
    }
    else {
        Write-DelphiCiMessage -Level 'ERROR' -Message 'One or more steps failed'
    }

    return [PSCustomObject]@{
        Success     = $overallSuccess
        Duration    = $stopwatch.Elapsed
        ProjectFile = $resolvedProject
        Steps       = $stepResults.ToArray()
    }
}
