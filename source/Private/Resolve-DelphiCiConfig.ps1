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
    $cleanLevel              = 'basic'
    $cleanIncludeFiles       = @()
    $cleanExcludeDirectories = @()
    $buildEngine   = 'MSBuild'
    $buildToolchainVersion = 'Latest'
    $buildPlatform = $null
    $buildConfig   = 'Debug'
    $buildDefines  = @()

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
            if ($c.PSObject.Properties['includeFiles'])       { $cleanIncludeFiles       = @($c.includeFiles) }
            if ($c.PSObject.Properties['excludeDirectories']) { $cleanExcludeDirectories = @($c.excludeDirectories) }
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
    if ($Overrides.ContainsKey('CleanIncludeFiles') -and $null -ne $Overrides['CleanIncludeFiles']) {
        $cleanIncludeFiles = @($Overrides['CleanIncludeFiles'])
    }
    if ($Overrides.ContainsKey('CleanExcludeDirectories') -and $null -ne $Overrides['CleanExcludeDirectories']) {
        $cleanExcludeDirectories = @($Overrides['CleanExcludeDirectories'])
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
    $validLevels  = @('basic', 'standard', 'deep')
    $validEngines = @('MSBuild', 'DCCBuild')
    $validSteps   = @('Clean', 'Build', 'Test')

    if ($cleanLevel -notin $validLevels) {
        throw "Invalid clean level '$cleanLevel'. Valid values: $($validLevels -join ', ')"
    }
    if ($buildEngine -notin $validEngines) {
        throw "Invalid build engine '$buildEngine'. Valid values: $($validEngines -join ', ')"
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
            Level              = $cleanLevel
            IncludeFiles       = $cleanIncludeFiles
            ExcludeDirectories = $cleanExcludeDirectories
        }
        Build       = [PSCustomObject]@{
            Engine        = $buildEngine
            Toolchain     = [PSCustomObject]@{
                Version = $buildToolchainVersion
            }
            Platform      = $buildPlatform
            Configuration = $buildConfig
            Defines       = $buildDefines
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
