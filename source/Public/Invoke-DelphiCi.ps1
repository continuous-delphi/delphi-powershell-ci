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

        # --- Run defaults (CLI shorthand for single-job use) ---

        [Parameter(ParameterSetName = 'Run')]
        [string]$Execute,

        [Parameter(ParameterSetName = 'Run')]
        [string[]]$RunArguments,

        [Parameter(ParameterSetName = 'Run')]
        [int]$RunTimeoutSeconds
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
    if ($PSBoundParameters.ContainsKey('Execute'))                        { $overrides['Execute']                      = $Execute }
    if ($PSBoundParameters.ContainsKey('RunArguments'))                  { $overrides['RunArguments']                 = $RunArguments }
    if ($PSBoundParameters.ContainsKey('RunTimeoutSeconds'))             { $overrides['RunTimeoutSeconds']            = $RunTimeoutSeconds }

    $config = Resolve-DelphiCiConfig -ConfigFile $ConfigFile -Overrides $overrides

    $actions = $config.Pipeline | ForEach-Object { $_.Action }
    Write-DelphiCiMessage -Level 'INFO' -Message "Pipeline: $($actions -join ' > ')"

    $stepResults    = [System.Collections.Generic.List[object]]::new()
    $overallSuccess = $true
    $stopwatch      = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        :pipeline foreach ($entry in $config.Pipeline) {
            switch ($entry.Action.ToLower()) {

                'clean' {
                    $jobs = $entry.Jobs
                    # When no jobs are defined, create a default job from the
                    # action defaults + the resolved root.
                    if ($jobs.Count -eq 0) {
                        $defaultJob = $entry.Defaults.Clone()
                        if (-not $defaultJob.ContainsKey('root')) {
                            $defaultJob['root'] = $config.Root
                        }
                        if (-not $defaultJob.ContainsKey('name')) {
                            $defaultJob['name'] = ''
                        }
                        $jobs = @($defaultJob)
                    }

                    foreach ($job in $jobs) {
                        if (-not [string]::IsNullOrWhiteSpace($job['name'])) {
                            Write-DelphiCiMessage -Level 'INFO' -Message "Clean job: $($job['name'])"
                        }

                        $result = Invoke-DelphiClean `
                            -CleanRoot                    $job['root'] `
                            -CleanLevel                   $job['level'] `
                            -CleanOutputLevel             $job['outputLevel'] `
                            -CleanIncludeFilePattern      @($job['includeFilePattern']) `
                            -CleanExcludeDirectoryPattern @($job['excludeDirectoryPattern']) `
                            -CleanConfigFile              $job['configFile'] `
                            -CleanRecycleBin:             $job['recycleBin'] `
                            -CleanCheck:                  $job['check']

                        $stepResults.Add($result)
                        if (-not $result.Success) {
                            $overallSuccess = $false
                            break pipeline
                        }
                    }
                }

                'build' {
                    $jobs = $entry.Jobs
                    if ($jobs.Count -eq 0) {
                        throw 'No build jobs defined. Use -ProjectFile or define build jobs in the config file.'
                    }

                    :buildJobs foreach ($job in $jobs) {
                        if ([string]::IsNullOrWhiteSpace($job['projectFile'])) {
                            throw "Build job '$($job['name'])' has no projectFile."
                        }

                        # Expand platform x configuration matrix
                        foreach ($plat in $job['platform']) {
                            foreach ($cfg in $job['configuration']) {
                                $label = "$($job['name'])"
                                if ($label -ne '') { $label += ' ' }
                                $label += "($plat|$cfg)"
                                Write-DelphiCiMessage -Level 'INFO' -Message "Build job: $label"

                                $result = Invoke-DelphiBuild `
                                    -ProjectFile    $job['projectFile'] `
                                    -Platform       $plat `
                                    -Configuration  $cfg `
                                    -Toolchain      $job['toolchain']['version'] `
                                    -BuildEngine    $job['engine'] `
                                    -Defines        @($job['defines']) `
                                    -BuildVerbosity $job['verbosity'] `
                                    -BuildTarget    $job['target'] `
                                    -ExeOutputDir   $job['exeOutputDir'] `
                                    -DcuOutputDir   $job['dcuOutputDir'] `
                                    -UnitSearchPath @($job['unitSearchPath']) `
                                    -IncludePath    @($job['includePath']) `
                                    -Namespace      @($job['namespace'])

                                $stepResults.Add($result)
                                if (-not $result.Success) {
                                    $overallSuccess = $false
                                    break buildJobs
                                }
                            }
                        }
                    }
                }

                'run' {
                    $jobs = $entry.Jobs
                    if ($jobs.Count -eq 0) {
                        throw 'No run jobs defined. Use -Execute or define run jobs in the config file.'
                    }

                    foreach ($job in $jobs) {
                        if ([string]::IsNullOrWhiteSpace($job['execute'])) {
                            throw "Run job '$($job['name'])' has no execute target."
                        }

                        if (-not [string]::IsNullOrWhiteSpace($job['name'])) {
                            Write-DelphiCiMessage -Level 'INFO' -Message "Run job: $($job['name'])"
                        }

                        $result = Invoke-DelphiRun `
                            -Execute        $job['execute'] `
                            -Arguments      @($job['arguments']) `
                            -TimeoutSeconds $job['timeoutSeconds']

                        $stepResults.Add($result)
                        if (-not $result.Success) {
                            $overallSuccess = $false
                            break pipeline
                        }
                    }
                }

                default {
                    throw "Unknown action: $($entry.Action)"
                }
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
        Success  = $overallSuccess
        Duration = $stopwatch.Elapsed
        Steps    = $stepResults.ToArray()
    }
}
