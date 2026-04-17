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
        [string[]]$Steps,

        # --- Build defaults (CLI shorthand for single-job use) ---

        [Parameter(ParameterSetName = 'Run')]
        [string]$ProjectFile,

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
        [ValidateSet('Build', 'Clean', 'Rebuild')]
        [string]$BuildTarget,

        [Parameter(ParameterSetName = 'Run')]
        [string]$ExeOutputDir,

        [Parameter(ParameterSetName = 'Run')]
        [string]$DcuOutputDir,

        [Parameter(ParameterSetName = 'Run')]
        [string[]]$UnitSearchPath,

        [Parameter(ParameterSetName = 'Run')]
        [string[]]$IncludePath,

        [Parameter(ParameterSetName = 'Run')]
        [string[]]$Namespace,

        # --- Clean defaults (CLI shorthand) ---

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
        [bool]$CleanRecycleBin,

        [Parameter(ParameterSetName = 'Run')]
        [bool]$CleanCheck,

        # --- Test defaults (CLI shorthand for single-job use) ---

        [Parameter(ParameterSetName = 'Run')]
        [string]$TestExeFile,

        [Parameter(ParameterSetName = 'Run')]
        [string[]]$TestArguments,

        [Parameter(ParameterSetName = 'Run')]
        [int]$TestTimeoutSeconds
    )

    # ---------------------------------------------------------------------------
    # VersionInfo branch
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

    $overrides = @{}
    if ($PSBoundParameters.ContainsKey('Root'))                          { $overrides['Root']                         = $Root }
    if ($PSBoundParameters.ContainsKey('Steps'))                         { $overrides['Steps']                        = $Steps }
    if ($PSBoundParameters.ContainsKey('ProjectFile'))                   { $overrides['ProjectFile']                  = $ProjectFile }
    if ($PSBoundParameters.ContainsKey('Platform'))                      { $overrides['Platform']                     = $Platform }
    if ($PSBoundParameters.ContainsKey('Configuration'))                 { $overrides['Configuration']                = $Configuration }
    if ($PSBoundParameters.ContainsKey('Toolchain'))                     { $overrides['Toolchain']                    = $Toolchain }
    if ($PSBoundParameters.ContainsKey('BuildEngine'))                   { $overrides['BuildEngine']                  = $BuildEngine }
    if ($PSBoundParameters.ContainsKey('Defines'))                       { $overrides['Defines']                      = $Defines }
    if ($PSBoundParameters.ContainsKey('BuildVerbosity'))                { $overrides['BuildVerbosity']               = $BuildVerbosity }
    if ($PSBoundParameters.ContainsKey('BuildTarget'))                   { $overrides['BuildTarget']                  = $BuildTarget }
    if ($PSBoundParameters.ContainsKey('ExeOutputDir'))                  { $overrides['ExeOutputDir']                 = $ExeOutputDir }
    if ($PSBoundParameters.ContainsKey('DcuOutputDir'))                  { $overrides['DcuOutputDir']                 = $DcuOutputDir }
    if ($PSBoundParameters.ContainsKey('UnitSearchPath'))                { $overrides['UnitSearchPath']               = $UnitSearchPath }
    if ($PSBoundParameters.ContainsKey('IncludePath'))                   { $overrides['IncludePath']                  = $IncludePath }
    if ($PSBoundParameters.ContainsKey('Namespace'))                     { $overrides['Namespace']                    = $Namespace }
    if ($PSBoundParameters.ContainsKey('CleanLevel'))                    { $overrides['CleanLevel']                   = $CleanLevel }
    if ($PSBoundParameters.ContainsKey('CleanOutputLevel'))              { $overrides['CleanOutputLevel']             = $CleanOutputLevel }
    if ($PSBoundParameters.ContainsKey('CleanIncludeFilePattern'))       { $overrides['CleanIncludeFilePattern']      = $CleanIncludeFilePattern }
    if ($PSBoundParameters.ContainsKey('CleanExcludeDirectoryPattern'))  { $overrides['CleanExcludeDirectoryPattern'] = $CleanExcludeDirectoryPattern }
    if ($PSBoundParameters.ContainsKey('CleanConfigFile'))               { $overrides['CleanConfigFile']              = $CleanConfigFile }
    if ($PSBoundParameters.ContainsKey('CleanRecycleBin'))               { $overrides['CleanRecycleBin']              = $CleanRecycleBin }
    if ($PSBoundParameters.ContainsKey('CleanCheck'))                    { $overrides['CleanCheck']                   = $CleanCheck }
    if ($PSBoundParameters.ContainsKey('TestExeFile'))                   { $overrides['TestExeFile']                  = $TestExeFile }
    if ($PSBoundParameters.ContainsKey('TestArguments'))                 { $overrides['TestArguments']                = $TestArguments }
    if ($PSBoundParameters.ContainsKey('TestTimeoutSeconds'))            { $overrides['TestTimeoutSeconds']           = $TestTimeoutSeconds }

    $config = Resolve-DelphiCiConfig -ConfigFile $ConfigFile -Overrides $overrides

    Write-DelphiCiMessage -Level 'INFO' -Message "Steps : $($config.Steps -join ', ')"

    $stepResults    = [System.Collections.Generic.List[object]]::new()
    $overallSuccess = $true
    $stopwatch      = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        foreach ($step in $config.Steps) {
            switch ($step) {

                'Clean' {
                    $jobs = $config.Clean.Jobs
                    # When no jobs are defined, create a default job from the
                    # clean defaults + the resolved root.
                    if ($jobs.Count -eq 0) {
                        $jobs = @([PSCustomObject]@{
                            Name                    = ''
                            Root                    = $config.Root
                            Level                   = $config.Clean.Defaults.Level
                            OutputLevel             = $config.Clean.Defaults.OutputLevel
                            IncludeFilePattern      = $config.Clean.Defaults.IncludeFilePattern
                            ExcludeDirectoryPattern = $config.Clean.Defaults.ExcludeDirectoryPattern
                            ConfigFile              = $config.Clean.Defaults.ConfigFile
                            RecycleBin              = $config.Clean.Defaults.RecycleBin
                            Check                   = $config.Clean.Defaults.Check
                        })
                    }

                    foreach ($job in $jobs) {
                        if (-not [string]::IsNullOrWhiteSpace($job.Name)) {
                            Write-DelphiCiMessage -Level 'INFO' -Message "Clean job: $($job.Name)"
                        }

                        $result = Invoke-DelphiClean `
                            -CleanRoot                    $job.Root `
                            -CleanLevel                   $job.Level `
                            -CleanOutputLevel             $job.OutputLevel `
                            -CleanIncludeFilePattern      @($job.IncludeFilePattern) `
                            -CleanExcludeDirectoryPattern @($job.ExcludeDirectoryPattern) `
                            -CleanConfigFile              $job.ConfigFile `
                            -CleanRecycleBin:             $job.RecycleBin `
                            -CleanCheck:                  $job.Check

                        $stepResults.Add($result)
                        if (-not $result.Success) {
                            $overallSuccess = $false
                            break
                        }
                    }
                }

                'Build' {
                    $jobs = $config.Build.Jobs
                    if ($jobs.Count -eq 0) {
                        throw 'No build jobs defined. Use -ProjectFile or define build.jobs in the config file.'
                    }

                    :buildJobs foreach ($job in $jobs) {
                        if ([string]::IsNullOrWhiteSpace($job.ProjectFile)) {
                            throw "Build job '$($job.Name)' has no projectFile."
                        }

                        # Expand platform x configuration matrix
                        foreach ($plat in $job.Platform) {
                            foreach ($cfg in $job.Configuration) {
                                $label = "$($job.Name)"
                                if ($label -ne '') { $label += ' ' }
                                $label += "($plat|$cfg)"
                                Write-DelphiCiMessage -Level 'INFO' -Message "Build job: $label"

                                $result = Invoke-DelphiBuild `
                                    -ProjectFile    $job.ProjectFile `
                                    -Platform       $plat `
                                    -Configuration  $cfg `
                                    -Toolchain      $job.Toolchain.Version `
                                    -BuildEngine    $job.Engine `
                                    -Defines        @($job.Defines) `
                                    -BuildVerbosity $job.Verbosity `
                                    -BuildTarget    $job.Target `
                                    -ExeOutputDir   $job.ExeOutputDir `
                                    -DcuOutputDir   $job.DcuOutputDir `
                                    -UnitSearchPath @($job.UnitSearchPath) `
                                    -IncludePath    @($job.IncludePath) `
                                    -Namespace      @($job.Namespace)

                                $stepResults.Add($result)
                                if (-not $result.Success) {
                                    $overallSuccess = $false
                                    break buildJobs
                                }
                            }
                        }
                    }
                }

                'Test' {
                    $jobs = $config.Test.Jobs
                    if ($jobs.Count -eq 0) {
                        throw 'No test jobs defined. Use -TestExeFile or define test.jobs in the config file.'
                    }

                    foreach ($job in $jobs) {
                        if ([string]::IsNullOrWhiteSpace($job.TestExeFile)) {
                            throw "Test job '$($job.Name)' has no testExeFile."
                        }

                        if (-not [string]::IsNullOrWhiteSpace($job.Name)) {
                            Write-DelphiCiMessage -Level 'INFO' -Message "Test job: $($job.Name)"
                        }

                        $result = Invoke-DelphiTest `
                            -TestExeFile    $job.TestExeFile `
                            -Arguments      @($job.Arguments) `
                            -TimeoutSeconds $job.TimeoutSeconds

                        $stepResults.Add($result)
                        if (-not $result.Success) {
                            $overallSuccess = $false
                            break
                        }
                    }
                }

                default {
                    throw "Unknown step: $step"
                }
            }

            if (-not $overallSuccess) { break }
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
        Success  = $overallSuccess
        Duration = $stopwatch.Elapsed
        Steps    = $stepResults.ToArray()
    }
}
