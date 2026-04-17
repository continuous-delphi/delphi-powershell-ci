function Resolve-DelphiCiConfig {
    [CmdletBinding()]
    param(
        [string]$ConfigFile,
        [hashtable]$Overrides = @{}
    )

    # -------------------------------------------------------------------------
    # Built-in defaults
    # -------------------------------------------------------------------------
    $root  = $null
    $steps = @('Clean', 'Build')

    # Clean defaults
    $cleanLevel                   = 'basic'
    $cleanOutputLevel             = 'detailed'
    $cleanIncludeFilePattern      = @()
    $cleanExcludeDirectoryPattern = @()
    $cleanConfigFile              = ''
    $cleanRecycleBin              = $false
    $cleanCheck                   = $false
    $cleanJobs                    = @()

    # Build defaults
    $buildEngine          = 'MSBuild'
    $buildToolchainVersion = 'Latest'
    $buildPlatform        = 'Win32'
    $buildConfig          = 'Debug'
    $buildDefines         = @()
    $buildVerbosity       = 'normal'
    $buildTarget          = 'Build'
    $buildExeOutputDir    = ''
    $buildDcuOutputDir    = ''
    $buildUnitSearchPath  = @()
    $buildIncludePath     = @()
    $buildNamespace       = @()
    $buildJobs            = @()

    # Test defaults
    $testTimeoutSeconds = 10
    $testArguments      = @()
    $testJobs           = @()

    # -------------------------------------------------------------------------
    # Load JSON config
    # -------------------------------------------------------------------------
    if ($ConfigFile) {
        $cfgItem   = Get-Item -LiteralPath $ConfigFile -ErrorAction Stop
        $configDir = $cfgItem.DirectoryName
        $json      = Get-Content -LiteralPath $cfgItem.FullName -Raw -ErrorAction Stop |
                     ConvertFrom-Json

        # root is relative to the config file directory
        if ($json.PSObject.Properties['root'] -and
            -not [string]::IsNullOrWhiteSpace($json.root)) {
            $root = Join-Path $configDir $json.root
        } else {
            $root = $configDir
        }

        if ($json.PSObject.Properties['steps']) {
            $steps = @($json.steps)
        }

        # -- Clean section --
        if ($json.PSObject.Properties['clean']) {
            $c = $json.clean
            if ($c.PSObject.Properties['level'] -and
                -not [string]::IsNullOrWhiteSpace($c.level))        { $cleanLevel        = $c.level }
            if ($c.PSObject.Properties['outputLevel'] -and
                -not [string]::IsNullOrWhiteSpace($c.outputLevel))  { $cleanOutputLevel  = $c.outputLevel }
            if ($c.PSObject.Properties['includeFilePattern'])        { $cleanIncludeFilePattern      = @($c.includeFilePattern) }
            if ($c.PSObject.Properties['excludeDirectoryPattern'])   { $cleanExcludeDirectoryPattern = @($c.excludeDirectoryPattern) }
            if ($c.PSObject.Properties['configFile'] -and
                -not [string]::IsNullOrWhiteSpace($c.configFile))   { $cleanConfigFile   = $c.configFile }
            if ($c.PSObject.Properties['recycleBin'] -and
                $null -ne $c.recycleBin)                            { $cleanRecycleBin   = [bool]$c.recycleBin }
            if ($c.PSObject.Properties['check'] -and
                $null -ne $c.check)                                 { $cleanCheck        = [bool]$c.check }
            if ($c.PSObject.Properties['jobs'])                     { $cleanJobs         = @($c.jobs) }
        }

        # -- Build section --
        if ($json.PSObject.Properties['build']) {
            $b = $json.build
            if ($b.PSObject.Properties['engine'] -and
                -not [string]::IsNullOrWhiteSpace($b.engine))        { $buildEngine   = $b.engine }
            if ($b.PSObject.Properties['toolchain']) {
                $t = $b.toolchain
                if ($t.PSObject.Properties['version'] -and
                    -not [string]::IsNullOrWhiteSpace($t.version))   { $buildToolchainVersion = $t.version }
            }
            if ($b.PSObject.Properties['platform'] -and
                $null -ne $b.platform)                               { $buildPlatform = $b.platform }
            if ($b.PSObject.Properties['configuration'] -and
                -not [string]::IsNullOrWhiteSpace($b.configuration)) { $buildConfig   = $b.configuration }
            if ($b.PSObject.Properties['defines'])                   { $buildDefines  = @($b.defines) }
            if ($b.PSObject.Properties['verbosity'] -and
                -not [string]::IsNullOrWhiteSpace($b.verbosity))     { $buildVerbosity = $b.verbosity }
            if ($b.PSObject.Properties['target'] -and
                -not [string]::IsNullOrWhiteSpace($b.target))        { $buildTarget = $b.target }
            if ($b.PSObject.Properties['exeOutputDir'] -and
                -not [string]::IsNullOrWhiteSpace($b.exeOutputDir))  { $buildExeOutputDir = $b.exeOutputDir }
            if ($b.PSObject.Properties['dcuOutputDir'] -and
                -not [string]::IsNullOrWhiteSpace($b.dcuOutputDir))  { $buildDcuOutputDir = $b.dcuOutputDir }
            if ($b.PSObject.Properties['unitSearchPath'])            { $buildUnitSearchPath = @($b.unitSearchPath) }
            if ($b.PSObject.Properties['includePath'])               { $buildIncludePath    = @($b.includePath) }
            if ($b.PSObject.Properties['namespace'])                 { $buildNamespace      = @($b.namespace) }
            if ($b.PSObject.Properties['jobs'])                      { $buildJobs           = @($b.jobs) }
        }

        # -- Test section --
        if ($json.PSObject.Properties['test']) {
            $t = $json.test
            if ($t.PSObject.Properties['timeoutSeconds'] -and
                $null -ne $t.timeoutSeconds)                         { $testTimeoutSeconds = [int]$t.timeoutSeconds }
            if ($t.PSObject.Properties['arguments'])                 { $testArguments      = @($t.arguments) }
            if ($t.PSObject.Properties['jobs'])                      { $testJobs           = @($t.jobs) }
        }
    }

    # -------------------------------------------------------------------------
    # CLI overrides -- applied on top of JSON/defaults
    # -------------------------------------------------------------------------
    if ($Overrides.ContainsKey('Root') -and
        -not [string]::IsNullOrWhiteSpace($Overrides['Root'])) {
        $root = $Overrides['Root']
    }
    if ($Overrides.ContainsKey('Steps') -and $null -ne $Overrides['Steps']) {
        $steps = @($Overrides['Steps'] | ForEach-Object { $_ -split ',' } |
                   ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
    }

    # Clean overrides (apply to defaults; no CLI-level job overrides)
    if ($Overrides.ContainsKey('CleanLevel') -and
        -not [string]::IsNullOrWhiteSpace($Overrides['CleanLevel']))              { $cleanLevel        = $Overrides['CleanLevel'] }
    if ($Overrides.ContainsKey('CleanOutputLevel') -and
        -not [string]::IsNullOrWhiteSpace($Overrides['CleanOutputLevel']))        { $cleanOutputLevel  = $Overrides['CleanOutputLevel'] }
    if ($Overrides.ContainsKey('CleanIncludeFilePattern') -and
        $null -ne $Overrides['CleanIncludeFilePattern'])                          { $cleanIncludeFilePattern = @($Overrides['CleanIncludeFilePattern']) }
    if ($Overrides.ContainsKey('CleanExcludeDirectoryPattern') -and
        $null -ne $Overrides['CleanExcludeDirectoryPattern'])                     { $cleanExcludeDirectoryPattern = @($Overrides['CleanExcludeDirectoryPattern']) }
    if ($Overrides.ContainsKey('CleanConfigFile') -and
        -not [string]::IsNullOrWhiteSpace($Overrides['CleanConfigFile']))         { $cleanConfigFile   = $Overrides['CleanConfigFile'] }
    if ($Overrides.ContainsKey('CleanRecycleBin') -and
        $null -ne $Overrides['CleanRecycleBin'])                                  { $cleanRecycleBin   = [bool]$Overrides['CleanRecycleBin'] }
    if ($Overrides.ContainsKey('CleanCheck') -and
        $null -ne $Overrides['CleanCheck'])                                       { $cleanCheck        = [bool]$Overrides['CleanCheck'] }

    # Build overrides (apply to defaults; no CLI-level job overrides)
    if ($Overrides.ContainsKey('BuildEngine') -and
        -not [string]::IsNullOrWhiteSpace($Overrides['BuildEngine']))             { $buildEngine       = $Overrides['BuildEngine'] }
    if ($Overrides.ContainsKey('Toolchain') -and
        -not [string]::IsNullOrWhiteSpace($Overrides['Toolchain']))               { $buildToolchainVersion = $Overrides['Toolchain'] }
    if ($Overrides.ContainsKey('Platform') -and
        -not [string]::IsNullOrWhiteSpace($Overrides['Platform']))                { $buildPlatform     = $Overrides['Platform'] }
    if ($Overrides.ContainsKey('Configuration') -and
        -not [string]::IsNullOrWhiteSpace($Overrides['Configuration']))           { $buildConfig       = $Overrides['Configuration'] }
    if ($Overrides.ContainsKey('Defines') -and $null -ne $Overrides['Defines']) {
        $buildDefines = @($Overrides['Defines'] | ForEach-Object { $_ -split ',' } |
                          ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
    }
    if ($Overrides.ContainsKey('BuildVerbosity') -and
        -not [string]::IsNullOrWhiteSpace($Overrides['BuildVerbosity']))          { $buildVerbosity    = $Overrides['BuildVerbosity'] }
    if ($Overrides.ContainsKey('BuildTarget') -and
        -not [string]::IsNullOrWhiteSpace($Overrides['BuildTarget']))             { $buildTarget       = $Overrides['BuildTarget'] }
    if ($Overrides.ContainsKey('ExeOutputDir') -and
        -not [string]::IsNullOrWhiteSpace($Overrides['ExeOutputDir']))            { $buildExeOutputDir = $Overrides['ExeOutputDir'] }
    if ($Overrides.ContainsKey('DcuOutputDir') -and
        -not [string]::IsNullOrWhiteSpace($Overrides['DcuOutputDir']))            { $buildDcuOutputDir = $Overrides['DcuOutputDir'] }
    if ($Overrides.ContainsKey('UnitSearchPath') -and
        $null -ne $Overrides['UnitSearchPath'])                                   { $buildUnitSearchPath = @($Overrides['UnitSearchPath']) }
    if ($Overrides.ContainsKey('IncludePath') -and
        $null -ne $Overrides['IncludePath'])                                      { $buildIncludePath  = @($Overrides['IncludePath']) }
    if ($Overrides.ContainsKey('Namespace') -and
        $null -ne $Overrides['Namespace'])                                        { $buildNamespace    = @($Overrides['Namespace']) }

    # Build job from CLI -ProjectFile (creates a single-entry jobs list)
    if ($Overrides.ContainsKey('ProjectFile') -and
        -not [string]::IsNullOrWhiteSpace($Overrides['ProjectFile'])) {
        $buildJobs = @([PSCustomObject]@{ projectFile = $Overrides['ProjectFile'] })
    }

    # Test overrides (apply to defaults)
    if ($Overrides.ContainsKey('TestTimeoutSeconds') -and
        $null -ne $Overrides['TestTimeoutSeconds'])                               { $testTimeoutSeconds = [int]$Overrides['TestTimeoutSeconds'] }
    if ($Overrides.ContainsKey('TestArguments') -and
        $null -ne $Overrides['TestArguments'])                                    { $testArguments     = @($Overrides['TestArguments']) }

    # Test job from CLI -TestExeFile (creates a single-entry jobs list)
    if ($Overrides.ContainsKey('TestExeFile') -and
        -not [string]::IsNullOrWhiteSpace($Overrides['TestExeFile'])) {
        $testJobs = @([PSCustomObject]@{ testExeFile = $Overrides['TestExeFile'] })
    }

    # -------------------------------------------------------------------------
    # Resolve root to an absolute path
    # -------------------------------------------------------------------------
    if ($null -eq $root) {
        $root = (Get-Location).Path
    } elseif (-not [System.IO.Path]::IsPathRooted($root)) {
        $root = Join-Path (Get-Location).Path $root
    }
    $root = [System.IO.Path]::GetFullPath($root)

    # -------------------------------------------------------------------------
    # Validate enum-like defaults
    # -------------------------------------------------------------------------
    $validLevels       = @('basic', 'standard', 'deep')
    $validOutputLevels = @('detailed', 'summary', 'quiet')
    $validEngines      = @('MSBuild', 'DCCBuild')
    $validVerbosities  = @('quiet', 'minimal', 'normal', 'detailed', 'diagnostic')
    $validTargets      = @('Build', 'Clean', 'Rebuild')
    $validSteps        = @('Clean', 'Build', 'Test')

    if ($cleanLevel -notin $validLevels) {
        throw "Invalid clean level '$cleanLevel'. Valid values: $($validLevels -join ', ')"
    }
    if ($cleanOutputLevel -notin $validOutputLevels) {
        throw "Invalid clean output level '$cleanOutputLevel'. Valid values: $($validOutputLevels -join ', ')"
    }
    if ($buildEngine -notin $validEngines) {
        throw "Invalid build engine '$buildEngine'. Valid values: $($validEngines -join ', ')"
    }
    if ($buildVerbosity -notin $validVerbosities) {
        throw "Invalid build verbosity '$buildVerbosity'. Valid values: $($validVerbosities -join ', ')"
    }
    if ($buildTarget -notin $validTargets) {
        throw "Invalid build target '$buildTarget'. Valid values: $($validTargets -join ', ')"
    }
    foreach ($s in $steps) {
        if ($s -notin $validSteps) {
            throw "Invalid step '$s'. Valid values: $($validSteps -join ', ')"
        }
    }

    # -------------------------------------------------------------------------
    # Build the clean defaults object (inherited by each job)
    # -------------------------------------------------------------------------
    $cleanDefaults = [PSCustomObject]@{
        Level                   = $cleanLevel
        OutputLevel             = $cleanOutputLevel
        IncludeFilePattern      = $cleanIncludeFilePattern
        ExcludeDirectoryPattern = $cleanExcludeDirectoryPattern
        ConfigFile              = $cleanConfigFile
        RecycleBin              = $cleanRecycleBin
        Check                   = $cleanCheck
    }

    # -------------------------------------------------------------------------
    # Build the build defaults object (inherited by each job)
    # -------------------------------------------------------------------------
    $buildDefaults = [PSCustomObject]@{
        Engine         = $buildEngine
        Toolchain      = [PSCustomObject]@{ Version = $buildToolchainVersion }
        Platform       = $buildPlatform
        Configuration  = $buildConfig
        Defines        = $buildDefines
        Verbosity      = $buildVerbosity
        Target         = $buildTarget
        ExeOutputDir   = $buildExeOutputDir
        DcuOutputDir   = $buildDcuOutputDir
        UnitSearchPath = $buildUnitSearchPath
        IncludePath    = $buildIncludePath
        Namespace      = $buildNamespace
    }

    # -------------------------------------------------------------------------
    # Build the test defaults object (inherited by each job)
    # -------------------------------------------------------------------------
    $testDefaults = [PSCustomObject]@{
        TimeoutSeconds = $testTimeoutSeconds
        Arguments      = $testArguments
    }

    # -------------------------------------------------------------------------
    # Assemble resolved clean jobs
    # -------------------------------------------------------------------------
    $resolvedCleanJobs = [System.Collections.Generic.List[object]]::new()
    foreach ($raw in $cleanJobs) {
        $resolvedCleanJobs.Add([PSCustomObject]@{
            Name                    = if ($raw.PSObject.Properties['name'])   { $raw.name }   else { '' }
            Root                    = if ($raw.PSObject.Properties['root'] -and
                                         -not [string]::IsNullOrWhiteSpace($raw.root)) { $raw.root } else { $root }
            Level                   = if ($raw.PSObject.Properties['level'] -and
                                         -not [string]::IsNullOrWhiteSpace($raw.level)) { $raw.level } else { $cleanLevel }
            OutputLevel             = if ($raw.PSObject.Properties['outputLevel'] -and
                                         -not [string]::IsNullOrWhiteSpace($raw.outputLevel)) { $raw.outputLevel } else { $cleanOutputLevel }
            IncludeFilePattern      = if ($raw.PSObject.Properties['includeFilePattern'])      { @($raw.includeFilePattern) }      else { $cleanIncludeFilePattern }
            ExcludeDirectoryPattern = if ($raw.PSObject.Properties['excludeDirectoryPattern']) { @($raw.excludeDirectoryPattern) } else { $cleanExcludeDirectoryPattern }
            ConfigFile              = if ($raw.PSObject.Properties['configFile'] -and
                                         -not [string]::IsNullOrWhiteSpace($raw.configFile)) { $raw.configFile } else { $cleanConfigFile }
            RecycleBin              = if ($raw.PSObject.Properties['recycleBin'] -and $null -ne $raw.recycleBin) { [bool]$raw.recycleBin } else { $cleanRecycleBin }
            Check                   = if ($raw.PSObject.Properties['check'] -and $null -ne $raw.check)          { [bool]$raw.check }      else { $cleanCheck }
        })
    }

    # -------------------------------------------------------------------------
    # Assemble resolved build jobs
    # -------------------------------------------------------------------------
    $resolvedBuildJobs = [System.Collections.Generic.List[object]]::new()
    foreach ($raw in $buildJobs) {
        # Platform and Configuration can be string or array in JSON.
        # Normalize to arrays for matrix expansion downstream.
        $jobPlatform = if ($raw.PSObject.Properties['platform'] -and $null -ne $raw.platform) {
            @($raw.platform)
        } else {
            @($buildPlatform)
        }
        $jobConfig = if ($raw.PSObject.Properties['configuration'] -and $null -ne $raw.configuration) {
            @($raw.configuration)
        } else {
            @($buildConfig)
        }

        $resolvedBuildJobs.Add([PSCustomObject]@{
            Name           = if ($raw.PSObject.Properties['name']) { $raw.name } else { '' }
            ProjectFile    = if ($raw.PSObject.Properties['projectFile'] -and
                                 -not [string]::IsNullOrWhiteSpace($raw.projectFile)) { $raw.projectFile } else { '' }
            Engine         = if ($raw.PSObject.Properties['engine'] -and
                                 -not [string]::IsNullOrWhiteSpace($raw.engine)) { $raw.engine } else { $buildEngine }
            Toolchain      = if ($raw.PSObject.Properties['toolchain']) {
                                 [PSCustomObject]@{ Version = if ($raw.toolchain.PSObject.Properties['version']) { $raw.toolchain.version } else { $buildToolchainVersion } }
                             } else {
                                 [PSCustomObject]@{ Version = $buildToolchainVersion }
                             }
            Platform       = $jobPlatform
            Configuration  = $jobConfig
            Defines        = if ($raw.PSObject.Properties['defines'])        { @($raw.defines) }        else { $buildDefines }
            Verbosity      = if ($raw.PSObject.Properties['verbosity'] -and
                                 -not [string]::IsNullOrWhiteSpace($raw.verbosity)) { $raw.verbosity } else { $buildVerbosity }
            Target         = if ($raw.PSObject.Properties['target'] -and
                                 -not [string]::IsNullOrWhiteSpace($raw.target)) { $raw.target } else { $buildTarget }
            ExeOutputDir   = if ($raw.PSObject.Properties['exeOutputDir'] -and
                                 -not [string]::IsNullOrWhiteSpace($raw.exeOutputDir)) { $raw.exeOutputDir } else { $buildExeOutputDir }
            DcuOutputDir   = if ($raw.PSObject.Properties['dcuOutputDir'] -and
                                 -not [string]::IsNullOrWhiteSpace($raw.dcuOutputDir)) { $raw.dcuOutputDir } else { $buildDcuOutputDir }
            UnitSearchPath = if ($raw.PSObject.Properties['unitSearchPath']) { @($raw.unitSearchPath) } else { $buildUnitSearchPath }
            IncludePath    = if ($raw.PSObject.Properties['includePath'])    { @($raw.includePath) }    else { $buildIncludePath }
            Namespace      = if ($raw.PSObject.Properties['namespace'])      { @($raw.namespace) }      else { $buildNamespace }
        })
    }

    # -------------------------------------------------------------------------
    # Assemble resolved test jobs
    # -------------------------------------------------------------------------
    $resolvedTestJobs = [System.Collections.Generic.List[object]]::new()
    foreach ($raw in $testJobs) {
        $resolvedTestJobs.Add([PSCustomObject]@{
            Name           = if ($raw.PSObject.Properties['name'])        { $raw.name }        else { '' }
            TestExeFile    = if ($raw.PSObject.Properties['testExeFile'] -and
                                 -not [string]::IsNullOrWhiteSpace($raw.testExeFile)) { $raw.testExeFile } else { '' }
            Arguments      = if ($raw.PSObject.Properties['arguments'])   { @($raw.arguments) } else { $testArguments }
            TimeoutSeconds = if ($raw.PSObject.Properties['timeoutSeconds'] -and
                                 $null -ne $raw.timeoutSeconds)           { [int]$raw.timeoutSeconds } else { $testTimeoutSeconds }
        })
    }

    # -------------------------------------------------------------------------
    # Return the resolved configuration
    # -------------------------------------------------------------------------
    return [PSCustomObject]@{
        Root  = $root
        Steps = $steps
        Clean = [PSCustomObject]@{
            Defaults = $cleanDefaults
            Jobs     = $resolvedCleanJobs.ToArray()
        }
        Build = [PSCustomObject]@{
            Defaults = $buildDefaults
            Jobs     = $resolvedBuildJobs.ToArray()
        }
        Test  = [PSCustomObject]@{
            Defaults = $testDefaults
            Jobs     = $resolvedTestJobs.ToArray()
        }
    }
}
