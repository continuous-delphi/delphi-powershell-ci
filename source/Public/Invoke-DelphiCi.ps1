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
        [string]$ToolchainRootDir,

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

        [Parameter(ParameterSetName = 'Run')]
        [switch]$NoConfig,

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
        [int]$RunTimeoutSeconds,

        # --- IncVer defaults (CLI shorthand for single-job use) ---

        [Parameter(ParameterSetName = 'Run')]
        [string]$IncVerFile,

        [Parameter(ParameterSetName = 'Run')]
        [string]$IncVerTarget,

        [Parameter(ParameterSetName = 'Run')]
        [string]$IncVerStyle,

        [Parameter(ParameterSetName = 'Run')]
        [string]$IncVerPart,

        [Parameter(ParameterSetName = 'Run')]
        [string]$IncVerPattern,

        [Parameter(ParameterSetName = 'Run')]
        [string]$IncVerDateformat,

        # --- Copy defaults (CLI shorthand for single-job use) ---

        [Parameter(ParameterSetName = 'Run')]
        [string]$CopySource,

        [Parameter(ParameterSetName = 'Run')]
        [string]$CopyDestination,

        [Parameter(ParameterSetName = 'Run')]
        [bool]$CopyFlatten,

        [Parameter(ParameterSetName = 'Run')]
        [bool]$CopyOverwrite,

        [Parameter(ParameterSetName = 'Run')]
        [bool]$CopyCreateDestination,

        [Parameter(ParameterSetName = 'Run')]
        [bool]$CopyChecksum,

        # --- Compress defaults (CLI shorthand for single-job use) ---

        [Parameter(ParameterSetName = 'Run')]
        [string]$CompressSource,

        [Parameter(ParameterSetName = 'Run')]
        [string]$CompressDestination,

        [Parameter(ParameterSetName = 'Run')]
        [bool]$CompressOverwrite,

        [Parameter(ParameterSetName = 'Run')]
        [bool]$CompressChecksum,

        # --- Coverage defaults (CLI shorthand for single-job use) ---

        [Parameter(ParameterSetName = 'Run')]
        [string]$CoverageExecute,

        [Parameter(ParameterSetName = 'Run')]
        [string]$CoverageMapFile,

        [Parameter(ParameterSetName = 'Run')]
        [string]$CoverageDproj,

        [Parameter(ParameterSetName = 'Run')]
        [string]$CoverageEngine,

        [Parameter(ParameterSetName = 'Run')]
        [string]$CoverageEnginePath,

        [Parameter(ParameterSetName = 'Run')]
        [string[]]$CoverageSourceDir,

        [Parameter(ParameterSetName = 'Run')]
        [string[]]$CoverageUnits,

        [Parameter(ParameterSetName = 'Run')]
        [string[]]$CoverageExcludeUnits,

        [Parameter(ParameterSetName = 'Run')]
        [string]$CoverageOutputDir,

        [Parameter(ParameterSetName = 'Run')]
        [string[]]$CoverageFormats,

        [Parameter(ParameterSetName = 'Run')]
        [int]$CoverageThreshold,

        [Parameter(ParameterSetName = 'Run')]
        [int]$CoverageTimeoutSeconds,

        [Parameter(ParameterSetName = 'Run')]
        [string]$CoverageBadge,

        # --- CallGraph defaults (CLI shorthand for single-job use) ---

        [Parameter(ParameterSetName = 'Run')]
        [string[]]$CallGraphPath,

        [Parameter(ParameterSetName = 'Run')]
        [string]$CallGraphEngine,

        [Parameter(ParameterSetName = 'Run')]
        [string]$CallGraphEnginePath,

        [Parameter(ParameterSetName = 'Run')]
        [string]$CallGraphOutputDir,

        [Parameter(ParameterSetName = 'Run')]
        [string[]]$CallGraphFormats,

        [Parameter(ParameterSetName = 'Run')]
        [string]$CallGraphJsonFile,

        [Parameter(ParameterSetName = 'Run')]
        [string]$CallGraphDotFile,

        [Parameter(ParameterSetName = 'Run')]
        [string]$CallGraphSummaryFile,

        [Parameter(ParameterSetName = 'Run')]
        [string]$CallGraphClass,

        [Parameter(ParameterSetName = 'Run')]
        [bool]$CallGraphAnnotations,

        [Parameter(ParameterSetName = 'Run')]
        [bool]$CallGraphDeterministic,

        [Parameter(ParameterSetName = 'Run')]
        [string]$CallGraphGraphKind,

        [Parameter(ParameterSetName = 'Run')]
        [bool]$CallGraphGraphVizUses,

        [Parameter(ParameterSetName = 'Run')]
        [bool]$CallGraphGraphVizClasses,

        [Parameter(ParameterSetName = 'Run')]
        [string[]]$CallGraphPasDocOptions,

        [Parameter(ParameterSetName = 'Run')]
        [string]$CallGraphProjectFile,

        [Parameter(ParameterSetName = 'Run')]
        [string[]]$CallGraphGraphVizExclude,

        [Parameter(ParameterSetName = 'Run')]
        [string[]]$CallGraphEngineArguments,

        [Parameter(ParameterSetName = 'Run')]
        [int]$CallGraphTimeoutSeconds,

        # --- Codesign defaults (CLI shorthand for single-job use) ---

        [Parameter(ParameterSetName = 'Run')]
        [ValidateSet('Sign', 'Verify')]
        [string]$CodesignAction,

        [Parameter(ParameterSetName = 'Run')]
        [string]$CodesignEngine,

        [Parameter(ParameterSetName = 'Run')]
        [string]$CodesignSignToolPath,

        [Parameter(ParameterSetName = 'Run')]
        [string]$CodesignDlibPath,

        [Parameter(ParameterSetName = 'Run')]
        [string]$CodesignMetadataPath,

        [Parameter(ParameterSetName = 'Run')]
        [string]$CodesignEnvFile,

        # --- Format defaults (CLI shorthand for single-job use) ---

        [Parameter(ParameterSetName = 'Run')]
        [ValidateSet('formatter', 'radFormatter')]
        [string]$FormatEngine,

        [Parameter(ParameterSetName = 'Run')]
        [string]$FormatEnginePath,

        [Parameter(ParameterSetName = 'Run')]
        [string]$FormatEngineConfigFile,

        [Parameter(ParameterSetName = 'Run')]
        [string[]]$FormatPath,

        [Parameter(ParameterSetName = 'Run')]
        [string[]]$FormatIncludeFilePattern,

        [Parameter(ParameterSetName = 'Run')]
        [string[]]$FormatExcludeDirectoryPattern,

        [Parameter(ParameterSetName = 'Run')]
        [string]$FormatEncoding,

        [Parameter(ParameterSetName = 'Run')]
        [bool]$FormatCreateBackups,

        [Parameter(ParameterSetName = 'Run')]
        [ValidateSet('detailed', 'summary', 'quiet')]
        [string]$FormatOutputLevel,

        [Parameter(ParameterSetName = 'Run')]
        [string]$FormatConfigFile,

        [Parameter(ParameterSetName = 'Run')]
        [bool]$FormatCheck
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
    if ($PSBoundParameters.ContainsKey('ToolchainRootDir'))              { $overrides['ToolchainRootDir']             = $ToolchainRootDir }
    if ($PSBoundParameters.ContainsKey('BuildEngine'))                   { $overrides['BuildEngine']                  = $BuildEngine }
    if ($PSBoundParameters.ContainsKey('Defines'))                       { $overrides['Defines']                      = $Defines }
    if ($PSBoundParameters.ContainsKey('BuildVerbosity'))                { $overrides['BuildVerbosity']               = $BuildVerbosity }
    if ($PSBoundParameters.ContainsKey('BuildTarget'))                   { $overrides['BuildTarget']                  = $BuildTarget }
    if ($PSBoundParameters.ContainsKey('ExeOutputDir'))                  { $overrides['ExeOutputDir']                 = $ExeOutputDir }
    if ($PSBoundParameters.ContainsKey('DcuOutputDir'))                  { $overrides['DcuOutputDir']                 = $DcuOutputDir }
    if ($PSBoundParameters.ContainsKey('UnitSearchPath'))                { $overrides['UnitSearchPath']               = $UnitSearchPath }
    if ($PSBoundParameters.ContainsKey('IncludePath'))                   { $overrides['IncludePath']                  = $IncludePath }
    if ($PSBoundParameters.ContainsKey('Namespace'))                     { $overrides['Namespace']                    = $Namespace }
    if ($PSBoundParameters.ContainsKey('NoConfig'))                      { $overrides['NoConfig']                     = [bool]$NoConfig }
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
    if ($PSBoundParameters.ContainsKey('IncVerFile'))                    { $overrides['IncVerFile']                   = $IncVerFile }
    if ($PSBoundParameters.ContainsKey('IncVerTarget'))                  { $overrides['IncVerTarget']                 = $IncVerTarget }
    if ($PSBoundParameters.ContainsKey('IncVerStyle'))                   { $overrides['IncVerStyle']                  = $IncVerStyle }
    if ($PSBoundParameters.ContainsKey('IncVerPart'))                    { $overrides['IncVerPart']                   = $IncVerPart }
    if ($PSBoundParameters.ContainsKey('IncVerPattern'))                 { $overrides['IncVerPattern']                = $IncVerPattern }
    if ($PSBoundParameters.ContainsKey('IncVerDateformat'))              { $overrides['IncVerDateformat']             = $IncVerDateformat }
    if ($PSBoundParameters.ContainsKey('CopySource'))                    { $overrides['CopySource']                   = $CopySource }
    if ($PSBoundParameters.ContainsKey('CopyDestination'))               { $overrides['CopyDestination']              = $CopyDestination }
    if ($PSBoundParameters.ContainsKey('CopyFlatten'))                   { $overrides['CopyFlatten']                  = $CopyFlatten }
    if ($PSBoundParameters.ContainsKey('CopyOverwrite'))                 { $overrides['CopyOverwrite']                = $CopyOverwrite }
    if ($PSBoundParameters.ContainsKey('CopyCreateDestination'))         { $overrides['CopyCreateDestination']        = $CopyCreateDestination }
    if ($PSBoundParameters.ContainsKey('CopyChecksum'))                  { $overrides['CopyChecksum']                 = $CopyChecksum }
    if ($PSBoundParameters.ContainsKey('CompressSource'))                { $overrides['CompressSource']               = $CompressSource }
    if ($PSBoundParameters.ContainsKey('CompressDestination'))           { $overrides['CompressDestination']          = $CompressDestination }
    if ($PSBoundParameters.ContainsKey('CompressOverwrite'))             { $overrides['CompressOverwrite']            = $CompressOverwrite }
    if ($PSBoundParameters.ContainsKey('CompressChecksum'))              { $overrides['CompressChecksum']             = $CompressChecksum }
    if ($PSBoundParameters.ContainsKey('CoverageExecute'))               { $overrides['CoverageExecute']              = $CoverageExecute }
    if ($PSBoundParameters.ContainsKey('CoverageMapFile'))               { $overrides['CoverageMapFile']              = $CoverageMapFile }
    if ($PSBoundParameters.ContainsKey('CoverageDproj'))                 { $overrides['CoverageDproj']                = $CoverageDproj }
    if ($PSBoundParameters.ContainsKey('CoverageEngine'))                { $overrides['CoverageEngine']               = $CoverageEngine }
    if ($PSBoundParameters.ContainsKey('CoverageEnginePath'))            { $overrides['CoverageEnginePath']           = $CoverageEnginePath }
    if ($PSBoundParameters.ContainsKey('CoverageSourceDir'))             { $overrides['CoverageSourceDir']            = $CoverageSourceDir }
    if ($PSBoundParameters.ContainsKey('CoverageUnits'))                 { $overrides['CoverageUnits']                = $CoverageUnits }
    if ($PSBoundParameters.ContainsKey('CoverageExcludeUnits'))          { $overrides['CoverageExcludeUnits']         = $CoverageExcludeUnits }
    if ($PSBoundParameters.ContainsKey('CoverageOutputDir'))             { $overrides['CoverageOutputDir']            = $CoverageOutputDir }
    if ($PSBoundParameters.ContainsKey('CoverageFormats'))               { $overrides['CoverageFormats']              = $CoverageFormats }
    if ($PSBoundParameters.ContainsKey('CoverageThreshold'))             { $overrides['CoverageThreshold']            = $CoverageThreshold }
    if ($PSBoundParameters.ContainsKey('CoverageTimeoutSeconds'))        { $overrides['CoverageTimeoutSeconds']       = $CoverageTimeoutSeconds }
    if ($PSBoundParameters.ContainsKey('CoverageBadge'))                 { $overrides['CoverageBadge']                = $CoverageBadge }
    if ($PSBoundParameters.ContainsKey('CallGraphPath'))                 { $overrides['CallGraphPath']                = $CallGraphPath }
    if ($PSBoundParameters.ContainsKey('CallGraphEngine'))               { $overrides['CallGraphEngine']              = $CallGraphEngine }
    if ($PSBoundParameters.ContainsKey('CallGraphEnginePath'))           { $overrides['CallGraphEnginePath']          = $CallGraphEnginePath }
    if ($PSBoundParameters.ContainsKey('CallGraphOutputDir'))            { $overrides['CallGraphOutputDir']           = $CallGraphOutputDir }
    if ($PSBoundParameters.ContainsKey('CallGraphFormats'))              { $overrides['CallGraphFormats']             = $CallGraphFormats }
    if ($PSBoundParameters.ContainsKey('CallGraphJsonFile'))             { $overrides['CallGraphJsonFile']            = $CallGraphJsonFile }
    if ($PSBoundParameters.ContainsKey('CallGraphDotFile'))              { $overrides['CallGraphDotFile']             = $CallGraphDotFile }
    if ($PSBoundParameters.ContainsKey('CallGraphSummaryFile'))          { $overrides['CallGraphSummaryFile']         = $CallGraphSummaryFile }
    if ($PSBoundParameters.ContainsKey('CallGraphClass'))                { $overrides['CallGraphClass']               = $CallGraphClass }
    if ($PSBoundParameters.ContainsKey('CallGraphAnnotations'))          { $overrides['CallGraphAnnotations']         = $CallGraphAnnotations }
    if ($PSBoundParameters.ContainsKey('CallGraphDeterministic'))        { $overrides['CallGraphDeterministic']       = $CallGraphDeterministic }
    if ($PSBoundParameters.ContainsKey('CallGraphGraphKind'))            { $overrides['CallGraphGraphKind']           = $CallGraphGraphKind }
    if ($PSBoundParameters.ContainsKey('CallGraphGraphVizUses'))         { $overrides['CallGraphGraphVizUses']        = $CallGraphGraphVizUses }
    if ($PSBoundParameters.ContainsKey('CallGraphGraphVizClasses'))      { $overrides['CallGraphGraphVizClasses']     = $CallGraphGraphVizClasses }
    if ($PSBoundParameters.ContainsKey('CallGraphPasDocOptions'))        { $overrides['CallGraphPasDocOptions']       = $CallGraphPasDocOptions }
    if ($PSBoundParameters.ContainsKey('CallGraphProjectFile'))          { $overrides['CallGraphProjectFile']         = $CallGraphProjectFile }
    if ($PSBoundParameters.ContainsKey('CallGraphGraphVizExclude'))      { $overrides['CallGraphGraphVizExclude']     = $CallGraphGraphVizExclude }
    if ($PSBoundParameters.ContainsKey('CallGraphEngineArguments'))      { $overrides['CallGraphEngineArguments']     = $CallGraphEngineArguments }
    if ($PSBoundParameters.ContainsKey('CallGraphTimeoutSeconds'))       { $overrides['CallGraphTimeoutSeconds']      = $CallGraphTimeoutSeconds }

    if ($PSBoundParameters.ContainsKey('CodesignAction'))               { $overrides['CodesignAction']               = $CodesignAction }
    if ($PSBoundParameters.ContainsKey('CodesignEngine'))               { $overrides['CodesignEngine']               = $CodesignEngine }
    if ($PSBoundParameters.ContainsKey('CodesignSignToolPath'))         { $overrides['CodesignSignToolPath']         = $CodesignSignToolPath }
    if ($PSBoundParameters.ContainsKey('CodesignDlibPath'))             { $overrides['CodesignDlibPath']             = $CodesignDlibPath }
    if ($PSBoundParameters.ContainsKey('CodesignMetadataPath'))         { $overrides['CodesignMetadataPath']         = $CodesignMetadataPath }
    if ($PSBoundParameters.ContainsKey('CodesignEnvFile'))              { $overrides['CodesignEnvFile']              = $CodesignEnvFile }

    if ($PSBoundParameters.ContainsKey('FormatEngine'))                  { $overrides['FormatEngine']                  = $FormatEngine }
    if ($PSBoundParameters.ContainsKey('FormatEnginePath'))             { $overrides['FormatEnginePath']             = $FormatEnginePath }
    if ($PSBoundParameters.ContainsKey('FormatEngineConfigFile'))       { $overrides['FormatEngineConfigFile']       = $FormatEngineConfigFile }
    if ($PSBoundParameters.ContainsKey('FormatPath'))                   { $overrides['FormatPath']                   = $FormatPath }
    if ($PSBoundParameters.ContainsKey('FormatIncludeFilePattern'))     { $overrides['FormatIncludeFilePattern']      = $FormatIncludeFilePattern }
    if ($PSBoundParameters.ContainsKey('FormatExcludeDirectoryPattern')) { $overrides['FormatExcludeDirectoryPattern'] = $FormatExcludeDirectoryPattern }
    if ($PSBoundParameters.ContainsKey('FormatEncoding'))              { $overrides['FormatEncoding']               = $FormatEncoding }
    if ($PSBoundParameters.ContainsKey('FormatCreateBackups'))          { $overrides['FormatCreateBackups']          = $FormatCreateBackups }
    if ($PSBoundParameters.ContainsKey('FormatOutputLevel'))            { $overrides['FormatOutputLevel']            = $FormatOutputLevel }
    if ($PSBoundParameters.ContainsKey('FormatConfigFile'))            { $overrides['FormatConfigFile']             = $FormatConfigFile }
    if ($PSBoundParameters.ContainsKey('FormatCheck'))                  { $overrides['FormatCheck']                  = $FormatCheck }

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

                'format' {
                    $jobs = $entry.Jobs
                    # When no jobs are defined, create a default job from the
                    # action defaults + the resolved root (mirrors Clean).
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
                            Write-DelphiCiMessage -Level 'INFO' -Message "Format job: $($job['name'])"
                        }

                        # Resolve the format root relative to the CI root.
                        $formatRoot = $job['root']
                        if ([string]::IsNullOrWhiteSpace($formatRoot)) {
                            $formatRoot = $config.Root
                        }
                        elseif (-not [System.IO.Path]::IsPathRooted($formatRoot)) {
                            $formatRoot = Join-Path $config.Root $formatRoot
                        }

                        $result = Invoke-DelphiFormat `
                            -FormatRoot                    $formatRoot `
                            -FormatEngine                  $job['engine'] `
                            -FormatEnginePath              $job['enginePath'] `
                            -FormatEngineConfigFile        $job['engineConfigFile'] `
                            -FormatPath                    @($job['path']) `
                            -FormatIncludeFilePattern      @($job['includeFilePattern']) `
                            -FormatExcludeDirectoryPattern @($job['excludeDirectoryPattern']) `
                            -FormatEncoding                $job['encoding'] `
                            -FormatCreateBackups:          ([bool]$job['createBackups']) `
                            -FormatOutputLevel             $job['outputLevel'] `
                            -FormatConfigFile              $job['configFile'] `
                            -FormatCheck:                  ([bool]$job['check'])

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

                    foreach ($job in $jobs) {
                        if ([string]::IsNullOrWhiteSpace($job['projectFile'])) {
                            throw "Build job '$($job['name'])' has no projectFile."
                        }

                        $projectFile = $job['projectFile']
                        if (-not [System.IO.Path]::IsPathRooted($projectFile)) {
                            $projectFile = Join-Path $config.Root $projectFile
                        }

                        # Expand platform x configuration matrix
                        foreach ($plat in $job['platform']) {
                            foreach ($cfg in $job['configuration']) {
                                $label = "$($job['name'])"
                                if ($label -ne '') { $label += ' ' }
                                $label += "($plat|$cfg)"
                                Write-DelphiCiMessage -Level 'INFO' -Message "Build job: $label"

                                $toolchainRootDir = if ($job['toolchain'].ContainsKey('rootDir')) { $job['toolchain']['rootDir'] } else { '' }

                                $result = Invoke-DelphiBuild `
                                    -ProjectFile      $projectFile `
                                    -Platform         $plat `
                                    -Configuration    $cfg `
                                    -Toolchain        $job['toolchain']['version'] `
                                    -ToolchainRootDir $toolchainRootDir `
                                    -BuildEngine    $job['engine'] `
                                    -Defines        @($job['defines']) `
                                    -BuildVerbosity $job['verbosity'] `
                                    -BuildTarget    $job['target'] `
                                    -ExeOutputDir   $job['exeOutputDir'] `
                                    -DcuOutputDir   $job['dcuOutputDir'] `
                                    -UnitSearchPath @($job['unitSearchPath']) `
                                    -IncludePath    @($job['includePath']) `
                                    -Namespace      @($job['namespace']) `
                                    -NoConfig:([bool]$job['noConfig'])

                                $stepResults.Add($result)
                                if (-not $result.Success) {
                                    $overallSuccess = $false
                                    break pipeline
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

                        $executePath = $job['execute']
                        if (-not [System.IO.Path]::IsPathRooted($executePath)) {
                            $executePath = Join-Path $config.Root $executePath
                        }

                        $result = Invoke-DelphiRun `
                            -Execute        $executePath `
                            -Arguments      @($job['arguments']) `
                            -TimeoutSeconds $job['timeoutSeconds']

                        $stepResults.Add($result)
                        if (-not $result.Success) {
                            $overallSuccess = $false
                            break pipeline
                        }
                    }
                }

                'incver' {
                    $jobs = $entry.Jobs
                    if ($jobs.Count -eq 0) {
                        throw 'No incver jobs defined. Use -IncVerFile or define incver jobs in the config file.'
                    }

                    foreach ($job in $jobs) {
                        if ([string]::IsNullOrWhiteSpace($job['file'])) {
                            throw "IncVer job '$($job['name'])' has no file."
                        }

                        if (-not [string]::IsNullOrWhiteSpace($job['name'])) {
                            Write-DelphiCiMessage -Level 'INFO' -Message "IncVer job: $($job['name'])"
                        }

                        # Resolve file path relative to root
                        $filePath = $job['file']
                        if (-not [System.IO.Path]::IsPathRooted($filePath)) {
                            $filePath = Join-Path $config.Root $filePath
                        }

                        $result = Invoke-DelphiIncVer `
                            -File          $filePath `
                            -IncVerTarget  $job['target'] `
                            -IncVerStyle   $job['style'] `
                            -IncVerPart    $job['part'] `
                            -IncVerPattern $job['pattern']

                        $stepResults.Add($result)
                        if (-not $result.Success) {
                            $overallSuccess = $false
                            break pipeline
                        }
                    }
                }

                'copy' {
                    $jobs = $entry.Jobs
                    if ($jobs.Count -eq 0) {
                        throw 'No copy jobs defined. Use -CopySource/-CopyDestination or define copy jobs in the config file.'
                    }

                    foreach ($job in $jobs) {
                        if ([string]::IsNullOrWhiteSpace($job['source'])) {
                            throw "Copy job '$($job['name'])' has no source."
                        }
                        if ([string]::IsNullOrWhiteSpace($job['destination'])) {
                            throw "Copy job '$($job['name'])' has no destination."
                        }

                        if (-not [string]::IsNullOrWhiteSpace($job['name'])) {
                            Write-DelphiCiMessage -Level 'INFO' -Message "Copy job: $($job['name'])"
                        }

                        # Resolve paths relative to root
                        $sourcePath = $job['source']
                        if (-not [System.IO.Path]::IsPathRooted($sourcePath)) {
                            $sourcePath = Join-Path $config.Root $sourcePath
                        }
                        $destPath = $job['destination']
                        if (-not [System.IO.Path]::IsPathRooted($destPath)) {
                            $destPath = Join-Path $config.Root $destPath
                        }

                        $result = Invoke-DelphiCopy `
                            -Source            $sourcePath `
                            -Destination       $destPath `
                            -Flatten           $job['flatten'] `
                            -Overwrite         $job['overwrite'] `
                            -CreateDestination $job['createDestination'] `
                            -Checksum          $job['checksum']

                        $stepResults.Add($result)
                        if (-not $result.Success) {
                            $overallSuccess = $false
                            break pipeline
                        }
                    }
                }

                'compress' {
                    $jobs = $entry.Jobs
                    if ($jobs.Count -eq 0) {
                        throw 'No compress jobs defined. Use -CompressSource/-CompressDestination or define compress jobs in the config file.'
                    }

                    foreach ($job in $jobs) {
                        if ([string]::IsNullOrWhiteSpace($job['source'])) {
                            throw "Compress job '$($job['name'])' has no source."
                        }
                        if ([string]::IsNullOrWhiteSpace($job['destination'])) {
                            throw "Compress job '$($job['name'])' has no destination."
                        }

                        if (-not [string]::IsNullOrWhiteSpace($job['name'])) {
                            Write-DelphiCiMessage -Level 'INFO' -Message "Compress job: $($job['name'])"
                        }

                        # Resolve paths relative to root
                        $sourcePath = $job['source']
                        if (-not [System.IO.Path]::IsPathRooted($sourcePath)) {
                            $sourcePath = Join-Path $config.Root $sourcePath
                        }
                        $destPath = $job['destination']
                        if (-not [System.IO.Path]::IsPathRooted($destPath)) {
                            $destPath = Join-Path $config.Root $destPath
                        }

                        $result = Invoke-DelphiCompress `
                            -Source      $sourcePath `
                            -Destination $destPath `
                            -Overwrite   $job['overwrite'] `
                            -Checksum    $job['checksum']

                        $stepResults.Add($result)
                        if (-not $result.Success) {
                            $overallSuccess = $false
                            break pipeline
                        }
                    }
                }

                'coverage' {
                    $jobs = $entry.Jobs
                    if ($jobs.Count -eq 0) {
                        throw 'No coverage jobs defined. Use -CoverageExecute/-CoverageMapFile or define coverage jobs in the config file.'
                    }

                    foreach ($job in $jobs) {
                        $hasDproj = -not [string]::IsNullOrWhiteSpace($job['dproj'])
                        if (-not $hasDproj) {
                            if ([string]::IsNullOrWhiteSpace($job['execute'])) {
                                throw "Coverage job '$($job['name'])' has no execute target or dproj."
                            }
                            if ([string]::IsNullOrWhiteSpace($job['mapFile'])) {
                                throw "Coverage job '$($job['name'])' has no mapFile."
                            }
                        }

                        if (-not [string]::IsNullOrWhiteSpace($job['name'])) {
                            Write-DelphiCiMessage -Level 'INFO' -Message "Coverage job: $($job['name'])"
                        }

                        # Resolve paths relative to root
                        $dprojPath = $job['dproj']
                        if (-not [string]::IsNullOrEmpty($dprojPath) -and -not [System.IO.Path]::IsPathRooted($dprojPath)) {
                            $dprojPath = Join-Path $config.Root $dprojPath
                        }
                        $exePath = $job['execute']
                        if (-not [string]::IsNullOrEmpty($exePath) -and -not [System.IO.Path]::IsPathRooted($exePath)) {
                            $exePath = Join-Path $config.Root $exePath
                        }
                        $mapPath = $job['mapFile']
                        if (-not [string]::IsNullOrEmpty($mapPath) -and -not [System.IO.Path]::IsPathRooted($mapPath)) {
                            $mapPath = Join-Path $config.Root $mapPath
                        }
                        $srcDirs = @($job['sourceDir']) | Where-Object { -not [string]::IsNullOrEmpty($_) } | ForEach-Object {
                            $p = $_
                            if ($p[0] -eq '/' -or ($p[0] -eq '\' -and $p.Length -gt 1 -and $p[1] -ne '\')) { $p = ".$p" }
                            if (-not [System.IO.Path]::IsPathRooted($p)) { Join-Path $config.Root $p } else { $p }
                        }
                        $outDir = $job['outputDir']
                        if (-not [string]::IsNullOrEmpty($outDir) -and -not [System.IO.Path]::IsPathRooted($outDir)) {
                            $outDir = Join-Path $config.Root $outDir
                        }
                        $badgePath = $job['badge']
                        if (-not [string]::IsNullOrEmpty($badgePath) -and -not [System.IO.Path]::IsPathRooted($badgePath)) {
                            $badgePath = Join-Path $config.Root $badgePath
                        }

                        $covParams = @{
                            CoverageEngine         = $job['engine']
                            CoverageEnginePath     = $job['enginePath']
                            CoverageSourceDir      = $srcDirs
                            CoverageUnits          = @($job['units'])
                            CoverageExcludeUnits   = @($job['excludeUnits'])
                            CoverageOutputDir      = $outDir
                            CoverageFormats        = @($job['formats'])
                            CoverageThreshold      = $job['threshold']
                            CoverageArguments      = @($job['arguments'])
                            CoverageTimeoutSeconds = $job['timeoutSeconds']
                            CoverageBadge          = $badgePath
                        }
                        if ($hasDproj) {
                            $covParams['CoverageDproj'] = $dprojPath
                        } else {
                            $covParams['Execute'] = $exePath
                            $covParams['MapFile'] = $mapPath
                        }

                        $result = Invoke-DelphiCoverage @covParams

                        $stepResults.Add($result)
                        if (-not $result.Success) {
                            $overallSuccess = $false
                            break pipeline
                        }
                    }
                }

                'callgraph' {
                    $jobs = $entry.Jobs
                    if ($jobs.Count -eq 0) {
                        throw 'No callgraph jobs defined. Use -CallGraphPath/-CallGraphProjectFile or define callgraph jobs in the config file.'
                    }

                    foreach ($job in $jobs) {
                        $hasProjectFile = -not [string]::IsNullOrWhiteSpace($job['projectFile'])
                        $hasPath = @($job['path']).Count -gt 0
                        if (-not $hasProjectFile -and -not $hasPath) {
                            throw "CallGraph job '$($job['name'])' has no path or projectFile."
                        }

                        if (-not [string]::IsNullOrWhiteSpace($job['name'])) {
                            Write-DelphiCiMessage -Level 'INFO' -Message "CallGraph job: $($job['name'])"
                        }

                        $graphPaths = @($job['path']) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object {
                            $p = $_
                            if ($p[0] -eq '/' -or ($p[0] -eq '\' -and $p.Length -gt 1 -and $p[1] -ne '\')) { $p = ".$p" }
                            if (-not [System.IO.Path]::IsPathRooted($p)) { Join-Path $config.Root $p } else { $p }
                        }

                        $graphProjectFile = $job['projectFile']
                        if (-not [string]::IsNullOrWhiteSpace($graphProjectFile) -and -not [System.IO.Path]::IsPathRooted($graphProjectFile)) {
                            $graphProjectFile = Join-Path $config.Root $graphProjectFile
                        }

                        $graphOutputDir = $job['outputDir']
                        if (-not [string]::IsNullOrWhiteSpace($graphOutputDir) -and -not [System.IO.Path]::IsPathRooted($graphOutputDir)) {
                            $graphOutputDir = Join-Path $config.Root $graphOutputDir
                        }

                        $graphJsonFile = $job['jsonFile']
                        if (-not [string]::IsNullOrWhiteSpace($graphJsonFile) -and -not [System.IO.Path]::IsPathRooted($graphJsonFile)) {
                            $graphJsonFile = Join-Path $config.Root $graphJsonFile
                        }

                        $graphDotFile = $job['dotFile']
                        if (-not [string]::IsNullOrWhiteSpace($graphDotFile) -and -not [System.IO.Path]::IsPathRooted($graphDotFile)) {
                            $graphDotFile = Join-Path $config.Root $graphDotFile
                        }

                        $graphSummaryFile = $job['summaryFile']
                        if (-not [string]::IsNullOrWhiteSpace($graphSummaryFile) -and -not [System.IO.Path]::IsPathRooted($graphSummaryFile)) {
                            $graphSummaryFile = Join-Path $config.Root $graphSummaryFile
                        }

                        $result = Invoke-DelphiCallGraph `
                            -CallGraphPath              $graphPaths `
                            -CallGraphEngine            $job['engine'] `
                            -CallGraphEnginePath        $job['enginePath'] `
                            -CallGraphOutputDir         $graphOutputDir `
                            -CallGraphFormats           @($job['formats']) `
                            -CallGraphJsonFile          $graphJsonFile `
                            -CallGraphDotFile           $graphDotFile `
                            -CallGraphSummaryFile       $graphSummaryFile `
                            -CallGraphClass             $job['class'] `
                            -CallGraphAnnotations       $job['annotations'] `
                            -CallGraphDeterministic     $job['deterministic'] `
                            -CallGraphGraphKind         $job['graphKind'] `
                            -CallGraphGraphVizUses      $job['graphVizUses'] `
                            -CallGraphGraphVizClasses   $job['graphVizClasses'] `
                            -CallGraphPasDocOptions     @($job['pasDocOptions']) `
                            -CallGraphProjectFile       $graphProjectFile `
                            -CallGraphGraphVizExclude   @($job['graphVizExclude']) `
                            -CallGraphEngineArguments   @($job['engineArguments']) `
                            -CallGraphTimeoutSeconds    $job['timeoutSeconds']

                        $stepResults.Add($result)
                        if (-not $result.Success) {
                            $overallSuccess = $false
                            break pipeline
                        }
                    }
                }

                'codesign' {
                    $jobs = $entry.Jobs
                    if ($jobs.Count -eq 0) {
                        Write-DelphiCiMessage -Level 'WARN' -Message 'Codesign action has no jobs; skipping.'
                        continue
                    }
                    foreach ($job in $jobs) {
                        $jobAction = if ($job.ContainsKey('action')) { $job['action'] } else { 'Sign' }
                        $jobFiles  = if ($job.ContainsKey('files'))  { @($job['files']) } else { @() }
                        $jobFile   = if ($job.ContainsKey('filePath')) { $job['filePath'] } else { '' }

                        # Resolve paths relative to config root
                        if ($jobAction -eq 'Sign') {
                            $jobFiles = @($jobFiles | ForEach-Object {
                                if (-not [System.IO.Path]::IsPathRooted($_)) { Join-Path $config.Root $_ } else { $_ }
                            })
                        }
                        elseif ($jobAction -eq 'Verify' -and -not [string]::IsNullOrEmpty($jobFile) -and -not [System.IO.Path]::IsPathRooted($jobFile)) {
                            $jobFile = Join-Path $config.Root $jobFile
                        }

                        $metadataPath = $job['metadataPath']
                        if (-not [string]::IsNullOrEmpty($metadataPath) -and -not [System.IO.Path]::IsPathRooted($metadataPath)) {
                            $metadataPath = Join-Path $config.Root $metadataPath
                        }

                        $envFile = $job['envFile']
                        if (-not [string]::IsNullOrEmpty($envFile) -and -not [System.IO.Path]::IsPathRooted($envFile)) {
                            $envFile = Join-Path $config.Root $envFile
                        }

                        $codesignParams = @{
                            Action               = $jobAction
                            CodesignEngine       = $job['engine']
                            CodesignSignToolPath = $job['signToolPath']
                            CodesignDlibPath     = $job['dlibPath']
                            CodesignMetadataPath = $metadataPath
                            CodesignEnvFile      = $envFile
                        }
                        if ($jobAction -eq 'Sign')   { $codesignParams['Files']    = $jobFiles }
                        if ($jobAction -eq 'Verify')  { $codesignParams['FilePath'] = $jobFile }

                        $result = Invoke-DelphiCodesign @codesignParams

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
