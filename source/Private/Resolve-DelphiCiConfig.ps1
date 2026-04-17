function Resolve-DelphiCiConfig {
    [CmdletBinding()]
    param(
        [string]$ConfigFile,
        [hashtable]$Overrides = @{}
    )

    # Built-in defaults
    $root          = $null
    $projectFile   = $null
    $steps         = @('Clean', 'Build')
    $cleanLevel                  = 'basic'
    $cleanIncludeFilePattern     = @()
    $cleanExcludeDirectoryPattern = @()
    $cleanConfigFile             = ''
    $cleanOutputLevel            = 'detailed'
    $cleanRecycleBin             = $false
    $cleanCheck                  = $false
    $buildEngine   = 'MSBuild'
    $buildToolchainVersion = 'Latest'
    $buildPlatform = $null
    $buildConfig   = 'Debug'
    $buildDefines  = @()
    $buildVerbosity = 'normal'
    $buildTarget        = 'Build'
    $buildExeOutputDir  = ''
    $buildDcuOutputDir  = ''
    $buildUnitSearchPath = @()
    $buildIncludePath    = @()
    $buildNamespace      = @()

    $testProjectFile    = $null
    $testExecutable     = $null
    $testDefines        = @()
    $testArguments      = @()
    $testTimeoutSeconds = 10
    $testBuild          = $true
    $testRun            = $true

    # Load JSON config
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

        if ($json.PSObject.Properties['clean']) {
            $c = $json.clean
            if ($c.PSObject.Properties['level'] -and
                -not [string]::IsNullOrWhiteSpace($c.level)) {
                $cleanLevel = $c.level
            }
            if ($c.PSObject.Properties['includeFilePattern'])      { $cleanIncludeFilePattern      = @($c.includeFilePattern) }
            if ($c.PSObject.Properties['excludeDirectoryPattern']) { $cleanExcludeDirectoryPattern = @($c.excludeDirectoryPattern) }
            if ($c.PSObject.Properties['configFile'] -and
                -not [string]::IsNullOrWhiteSpace($c.configFile)) {
                $cleanConfigFile = $c.configFile
            }
            if ($c.PSObject.Properties['outputLevel'] -and
                -not [string]::IsNullOrWhiteSpace($c.outputLevel)) {
                $cleanOutputLevel = $c.outputLevel
            }
            if ($c.PSObject.Properties['recycleBin'] -and
                $null -ne $c.recycleBin) {
                $cleanRecycleBin = [bool]$c.recycleBin
            }
            if ($c.PSObject.Properties['check'] -and
                $null -ne $c.check) {
                $cleanCheck = [bool]$c.check
            }
        }

        if ($json.PSObject.Properties['build']) {
            $b = $json.build
            if ($b.PSObject.Properties['projectFile'] -and
                -not [string]::IsNullOrWhiteSpace($b.projectFile)) {
                $projectFile = $b.projectFile
            }
            if ($b.PSObject.Properties['engine'] -and
                -not [string]::IsNullOrWhiteSpace($b.engine))        { $buildEngine   = $b.engine }
            if ($b.PSObject.Properties['toolchain']) {
                $t = $b.toolchain
                if ($t.PSObject.Properties['version'] -and
                    -not [string]::IsNullOrWhiteSpace($t.version)) { $buildToolchainVersion = $t.version }
            }
            if ($b.PSObject.Properties['platform'] -and
                -not [string]::IsNullOrWhiteSpace($b.platform))      { $buildPlatform = $b.platform }
            if ($b.PSObject.Properties['configuration'] -and
                -not [string]::IsNullOrWhiteSpace($b.configuration)) { $buildConfig   = $b.configuration }
            if ($b.PSObject.Properties['defines'])                   { $buildDefines  = @($b.defines) }
            if ($b.PSObject.Properties['verbosity'] -and
                -not [string]::IsNullOrWhiteSpace($b.verbosity))    { $buildVerbosity = $b.verbosity }
            if ($b.PSObject.Properties['target'] -and
                -not [string]::IsNullOrWhiteSpace($b.target))       { $buildTarget = $b.target }
            if ($b.PSObject.Properties['exeOutputDir'] -and
                -not [string]::IsNullOrWhiteSpace($b.exeOutputDir)) { $buildExeOutputDir = $b.exeOutputDir }
            if ($b.PSObject.Properties['dcuOutputDir'] -and
                -not [string]::IsNullOrWhiteSpace($b.dcuOutputDir)) { $buildDcuOutputDir = $b.dcuOutputDir }
            if ($b.PSObject.Properties['unitSearchPath'])           { $buildUnitSearchPath = @($b.unitSearchPath) }
            if ($b.PSObject.Properties['includePath'])              { $buildIncludePath    = @($b.includePath) }
            if ($b.PSObject.Properties['namespace'])                { $buildNamespace      = @($b.namespace) }
        }

        if ($json.PSObject.Properties['test']) {
            $t = $json.test
            if ($t.PSObject.Properties['testProjectFile'] -and
                -not [string]::IsNullOrWhiteSpace($t.testProjectFile)) { $testProjectFile    = $t.testProjectFile }
            if ($t.PSObject.Properties['testExecutable'] -and
                -not [string]::IsNullOrWhiteSpace($t.testExecutable))  { $testExecutable     = $t.testExecutable }
            if ($t.PSObject.Properties['defines'])                     { $testDefines        = @($t.defines) }
            if ($t.PSObject.Properties['arguments'])                   { $testArguments      = @($t.arguments) }
            if ($t.PSObject.Properties['timeoutSeconds'] -and
                $null -ne $t.timeoutSeconds)                           { $testTimeoutSeconds = [int]$t.timeoutSeconds }
            if ($t.PSObject.Properties['build'] -and
                $null -ne $t.build)                                    { $testBuild          = [bool]$t.build }
            if ($t.PSObject.Properties['run'] -and
                $null -ne $t.run)                                      { $testRun            = [bool]$t.run }
        }
    }

    # CLI overrides -- applied on top of JSON/defaults
    if ($Overrides.ContainsKey('Root') -and
        -not [string]::IsNullOrWhiteSpace($Overrides['Root'])) {
        $root = $Overrides['Root']
    }
    if ($Overrides.ContainsKey('ProjectFile') -and
        -not [string]::IsNullOrWhiteSpace($Overrides['ProjectFile'])) {
        $projectFile = $Overrides['ProjectFile']
    }
    if ($Overrides.ContainsKey('Steps') -and $null -ne $Overrides['Steps']) {
        $steps = @($Overrides['Steps'] | ForEach-Object { $_ -split ',' } |
                   ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
    }
    if ($Overrides.ContainsKey('CleanLevel') -and
        -not [string]::IsNullOrWhiteSpace($Overrides['CleanLevel'])) {
        $cleanLevel = $Overrides['CleanLevel']
    }
    if ($Overrides.ContainsKey('CleanIncludeFilePattern') -and $null -ne $Overrides['CleanIncludeFilePattern']) {
        $cleanIncludeFilePattern = @($Overrides['CleanIncludeFilePattern'])
    }
    if ($Overrides.ContainsKey('CleanExcludeDirectoryPattern') -and $null -ne $Overrides['CleanExcludeDirectoryPattern']) {
        $cleanExcludeDirectoryPattern = @($Overrides['CleanExcludeDirectoryPattern'])
    }
    if ($Overrides.ContainsKey('CleanConfigFile') -and
        -not [string]::IsNullOrWhiteSpace($Overrides['CleanConfigFile'])) {
        $cleanConfigFile = $Overrides['CleanConfigFile']
    }
    if ($Overrides.ContainsKey('CleanOutputLevel') -and
        -not [string]::IsNullOrWhiteSpace($Overrides['CleanOutputLevel'])) {
        $cleanOutputLevel = $Overrides['CleanOutputLevel']
    }
    if ($Overrides.ContainsKey('CleanRecycleBin') -and $null -ne $Overrides['CleanRecycleBin']) {
        $cleanRecycleBin = [bool]$Overrides['CleanRecycleBin']
    }
    if ($Overrides.ContainsKey('CleanCheck') -and $null -ne $Overrides['CleanCheck']) {
        $cleanCheck = [bool]$Overrides['CleanCheck']
    }
    if ($Overrides.ContainsKey('Platform') -and
        -not [string]::IsNullOrWhiteSpace($Overrides['Platform'])) {
        $buildPlatform = $Overrides['Platform']
    }
    if ($Overrides.ContainsKey('Configuration') -and
        -not [string]::IsNullOrWhiteSpace($Overrides['Configuration'])) {
        $buildConfig = $Overrides['Configuration']
    }
    if ($Overrides.ContainsKey('Toolchain') -and
        -not [string]::IsNullOrWhiteSpace($Overrides['Toolchain'])) {
        $buildToolchainVersion = $Overrides['Toolchain']
    }
    if ($Overrides.ContainsKey('BuildEngine') -and
        -not [string]::IsNullOrWhiteSpace($Overrides['BuildEngine'])) {
        $buildEngine = $Overrides['BuildEngine']
    }
    if ($Overrides.ContainsKey('Defines') -and $null -ne $Overrides['Defines']) {
        $buildDefines = @($Overrides['Defines'] | ForEach-Object { $_ -split ',' } |
                          ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
    }
    if ($Overrides.ContainsKey('BuildVerbosity') -and
        -not [string]::IsNullOrWhiteSpace($Overrides['BuildVerbosity'])) {
        $buildVerbosity = $Overrides['BuildVerbosity']
    }
    if ($Overrides.ContainsKey('BuildTarget') -and
        -not [string]::IsNullOrWhiteSpace($Overrides['BuildTarget'])) {
        $buildTarget = $Overrides['BuildTarget']
    }
    if ($Overrides.ContainsKey('ExeOutputDir') -and
        -not [string]::IsNullOrWhiteSpace($Overrides['ExeOutputDir'])) {
        $buildExeOutputDir = $Overrides['ExeOutputDir']
    }
    if ($Overrides.ContainsKey('DcuOutputDir') -and
        -not [string]::IsNullOrWhiteSpace($Overrides['DcuOutputDir'])) {
        $buildDcuOutputDir = $Overrides['DcuOutputDir']
    }
    if ($Overrides.ContainsKey('UnitSearchPath') -and $null -ne $Overrides['UnitSearchPath']) {
        $buildUnitSearchPath = @($Overrides['UnitSearchPath'])
    }
    if ($Overrides.ContainsKey('IncludePath') -and $null -ne $Overrides['IncludePath']) {
        $buildIncludePath = @($Overrides['IncludePath'])
    }
    if ($Overrides.ContainsKey('Namespace') -and $null -ne $Overrides['Namespace']) {
        $buildNamespace = @($Overrides['Namespace'])
    }
    if ($Overrides.ContainsKey('TestProjectFile') -and
        -not [string]::IsNullOrWhiteSpace($Overrides['TestProjectFile'])) {
        $testProjectFile = $Overrides['TestProjectFile']
    }
    if ($Overrides.ContainsKey('TestExecutable') -and
        -not [string]::IsNullOrWhiteSpace($Overrides['TestExecutable'])) {
        $testExecutable = $Overrides['TestExecutable']
    }
    if ($Overrides.ContainsKey('TestDefines') -and $null -ne $Overrides['TestDefines']) {
        $testDefines = @($Overrides['TestDefines'] | ForEach-Object { $_ -split ',' } |
                         ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
    }
    if ($Overrides.ContainsKey('TestArguments') -and $null -ne $Overrides['TestArguments']) {
        $testArguments = @($Overrides['TestArguments'])
    }
    if ($Overrides.ContainsKey('TestTimeoutSeconds') -and $null -ne $Overrides['TestTimeoutSeconds']) {
        $testTimeoutSeconds = [int]$Overrides['TestTimeoutSeconds']
    }
    if ($Overrides.ContainsKey('TestBuild') -and $null -ne $Overrides['TestBuild']) {
        $testBuild = [bool]$Overrides['TestBuild']
    }
    if ($Overrides.ContainsKey('TestRun') -and $null -ne $Overrides['TestRun']) {
        $testRun = [bool]$Overrides['TestRun']
    }

    # Resolve root to an absolute path
    if ($null -eq $root) {
        $root = (Get-Location).Path
    } elseif (-not [System.IO.Path]::IsPathRooted($root)) {
        $root = Join-Path (Get-Location).Path $root
    }
    $root = [System.IO.Path]::GetFullPath($root)

    # Validate known enum-like fields so errors surface early
    $validLevels        = @('basic', 'standard', 'deep')
    $validOutputLevels  = @('detailed', 'summary', 'quiet')
    $validEngines       = @('MSBuild', 'DCCBuild')
    $validVerbosities   = @('quiet', 'minimal', 'normal', 'detailed', 'diagnostic')
    $validTargets       = @('Build', 'Clean', 'Rebuild')
    $validSteps         = @('Clean', 'Build', 'Test')

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
    foreach ($step in $steps) {
        if ($step -notin $validSteps) {
            throw "Invalid step '$step'. Valid values: $($validSteps -join ', ')"
        }
    }

    return [PSCustomObject]@{
        Root        = $root
        ProjectFile = $projectFile
        Steps       = $steps
        Clean       = [PSCustomObject]@{
            Level                   = $cleanLevel
            OutputLevel             = $cleanOutputLevel
            IncludeFilePattern      = $cleanIncludeFilePattern
            ExcludeDirectoryPattern = $cleanExcludeDirectoryPattern
            ConfigFile              = $cleanConfigFile
            RecycleBin              = $cleanRecycleBin
            Check                   = $cleanCheck
        }
        Build       = [PSCustomObject]@{
            Engine         = $buildEngine
            Toolchain      = [PSCustomObject]@{
                Version = $buildToolchainVersion
            }
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
        Test        = [PSCustomObject]@{
            TestProjectFile  = $testProjectFile
            TestExecutable   = $testExecutable
            Defines          = $testDefines
            Arguments        = $testArguments
            TimeoutSeconds   = $testTimeoutSeconds
            Build            = $testBuild
            Run              = $testRun
        }
    }
}
