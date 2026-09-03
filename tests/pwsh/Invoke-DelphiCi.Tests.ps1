#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

Import-Module ([System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..' 'source' 'Delphi.PowerShell.CI.psm1'))) -Force

InModuleScope 'Delphi.PowerShell.CI' {

    # ---------------------------------------------------------------------------
    # Shared helpers
    # ---------------------------------------------------------------------------

    function script:New-MockConfig {
        param(
            [object[]]$Pipeline = @()
        )
        if ($Pipeline.Count -eq 0) {
            $Pipeline = @(
                (script:New-PipelineEntry -Action 'Clean'),
                (script:New-PipelineEntry -Action 'Build' -Jobs @(script:New-BuildJob))
            )
        }
        [PSCustomObject]@{
            Root     = 'C:\Fake'
            Pipeline = $Pipeline
        }
    }

    function script:New-PipelineEntry {
        param(
            [string]$Action,
            [object[]]$Jobs = @(),
            [hashtable]$Defaults = $null
        )
        if ($null -eq $Defaults) {
            $Defaults = switch ($Action.ToLower()) {
                'clean' {
                    @{
                        root                    = 'C:\Fake'
                        level                   = 'basic'
                        outputLevel             = 'detailed'
                        includeFilePattern      = @()
                        excludeDirectoryPattern = @()
                        configFile              = ''
                        recycleBin              = $false
                        check                   = $false
                    }
                }
                'build' {
                    @{
                        engine         = 'MSBuild'
                        toolchain      = @{ version = 'Latest' }
                        platform       = 'Win32'
                        configuration  = 'Debug'
                        defines        = @()
                        verbosity      = 'normal'
                        target         = 'Build'
                        exeOutputDir   = ''
                        dcuOutputDir   = ''
                        unitSearchPath = @()
                        includePath    = @()
                        namespace      = @()
                    }
                }
                'run' {
                    @{
                        timeoutSeconds = 10
                        arguments      = @()
                    }
                }
                'callgraph' {
                    @{
                        path              = @()
                        engine            = 'radCallGraph'
                        enginePath        = ''
                        outputDir         = 'callgraph'
                        formats           = @('json')
                        jsonFile          = ''
                        dotFile           = ''
                        summaryFile       = ''
                        class             = ''
                        annotations       = $true
                        deterministic     = $true
                        graphKind         = ''
                        graphVizUses      = $false
                        graphVizClasses   = $false
                        pasDocOptions     = @()
                        projectFile       = ''
                        graphVizExclude   = @()
                        engineArguments   = @()
                        timeoutSeconds    = 300
                    }
                }
                'format' {
                    @{
                        root                    = 'C:\Fake'
                        engine                  = 'formatter'
                        enginePath              = ''
                        engineConfigFile        = ''
                        path                    = @()
                        includeFilePattern      = @()
                        excludeDirectoryPattern = @()
                        encoding                = ''
                        createBackups           = $false
                        outputLevel             = 'detailed'
                        configFile              = ''
                        check                   = $false
                    }
                }
                default { @{} }
            }
        }
        [PSCustomObject]@{
            Action   = $Action
            Defaults = $Defaults
            Jobs     = $Jobs
        }
    }

    function script:New-BuildJob {
        param(
            [string]$Name = 'App build',
            [string]$ProjectFile = 'C:\Fake\Source\App.dproj',
            [string[]]$Platform = @('Win32'),
            [string[]]$Configuration = @('Debug'),
            [bool]$NoConfig = $false
        )
        @{
            name           = $Name
            projectFile    = $ProjectFile
            engine         = 'MSBuild'
            toolchain      = @{ version = 'Latest' }
            platform       = $Platform
            configuration  = $Configuration
            defines        = @()
            verbosity      = 'normal'
            target         = 'Build'
            exeOutputDir   = ''
            dcuOutputDir   = ''
            unitSearchPath = @()
            includePath    = @()
            namespace      = @()
            noConfig       = $NoConfig
        }
    }

    function script:New-RunJob {
        param(
            [string]$Name = 'Unit tests',
            [string]$Execute = 'C:\Fake\Tests\Win32\Debug\App.Tests.exe'
        )
        @{
            name           = $Name
            execute        = $Execute
            arguments      = @()
            timeoutSeconds = 10
        }
    }

    function script:New-CleanResult {
        param([bool]$Success = $true)
        [PSCustomObject]@{
            StepName    = 'Clean'
            Success     = $Success
            Duration    = [timespan]::Zero
            ExitCode    = if ($Success) { 0 } else { 1 }
            Tool        = 'delphi-clean.ps1'
            Message     = if ($Success) { 'Clean completed' } else { 'Exit code 1' }
            ProjectFile = $null
        }
    }

    function script:New-BuildResult {
        param([bool]$Success = $true)
        [PSCustomObject]@{
            StepName     = 'Build'
            Success      = $Success
            Duration     = [timespan]::Zero
            ExitCode     = if ($Success) { 0 } else { 5 }
            Tool         = 'delphi-msbuild.ps1'
            Message      = if ($Success) { 'Build completed' } else { 'Exit code 5' }
            ProjectFile  = 'C:\Fake\Source\App.dproj'
            Warnings     = 0
            Errors       = 0
            ExeOutputDir = $null
            Output       = $null
        }
    }

    function script:New-RunResult {
        param([bool]$Success = $true)
        [PSCustomObject]@{
            StepName    = 'Run'
            Success     = $Success
            Duration    = [timespan]::Zero
            ExitCode    = if ($Success) { 0 } else { 1 }
            Tool        = 'runner'
            Message     = if ($Success) { 'Run completed' } else { 'Exit code 1' }
            Execute     = 'C:\Fake\Tests\Win32\Debug\App.Tests.exe'
        }
    }

    function script:New-IncVerJob {
        param(
            [string]$Name = 'Bump version',
            [string]$File = 'C:\Fake\versioninfo.rc'
        )
        @{
            name       = $Name
            file       = $File
            target     = ''
            style      = ''
            part       = ''
            pattern    = ''
            dateformat = 'yyyy.mm.dd'
        }
    }

    function script:New-IncVerResult {
        param([bool]$Success = $true)
        [PSCustomObject]@{
            StepName   = 'IncVer'
            Success    = $Success
            Duration   = [timespan]::Zero
            ExitCode   = if ($Success) { 0 } else { 4 }
            Tool       = 'delphi-incver.ps1'
            Message    = if ($Success) { '1.0.0.0 -> 1.0.0.1' } else { 'Exit code 4' }
            File       = 'C:\Fake\versioninfo.rc'
            OldVersion = if ($Success) { '1.0.0.0' } else { $null }
            NewVersion = if ($Success) { '1.0.0.1' } else { $null }
        }
    }

    function script:New-CopyJob {
        param(
            [string]$Name = 'Collect binaries',
            [string]$Source = 'C:\Fake\src\*.exe',
            [string]$Destination = 'C:\Fake\dist'
        )
        @{
            name              = $Name
            source            = $Source
            destination       = $Destination
            flatten           = $false
            overwrite         = $true
            createDestination = $true
            checksum          = $false
        }
    }

    function script:New-CompressJob {
        param(
            [string]$Name = 'Package release',
            [string]$Source = 'C:\Fake\dist',
            [string]$Destination = 'C:\Fake\release.zip'
        )
        @{
            name        = $Name
            source      = $Source
            destination = $Destination
            overwrite   = $true
            checksum    = $false
        }
    }

    function script:New-CopyResult {
        param([bool]$Success = $true)
        [PSCustomObject]@{
            StepName    = 'Copy'
            Success     = $Success
            Duration    = [timespan]::Zero
            ExitCode    = if ($Success) { 0 } else { 1 }
            Tool        = 'copy'
            Message     = if ($Success) { 'Copied 3 file(s)' } else { 'No files matched' }
            Source      = 'C:\Fake\src\*.exe'
            Destination = 'C:\Fake\dist'
            FileCount   = if ($Success) { 3 } else { 0 }
            BytesCopied = if ($Success) { [long]1024 } else { [long]0 }
        }
    }

    function script:New-CompressResult {
        param([bool]$Success = $true)
        [PSCustomObject]@{
            StepName    = 'Compress'
            Success     = $Success
            Duration    = [timespan]::Zero
            ExitCode    = if ($Success) { 0 } else { 1 }
            Tool        = 'compress'
            Message     = if ($Success) { 'Archive created (2048 bytes)' } else { 'Source not found' }
            Source      = 'C:\Fake\dist'
            Destination = 'C:\Fake\release.zip'
            ArchiveSize = if ($Success) { [long]2048 } else { [long]0 }
            Checksum    = $null
        }
    }

    function script:New-CoverageJob {
        param(
            [string]$Name = 'Unit test coverage',
            [string]$Execute = 'C:\Fake\test\Win32\Debug\MyApp.Tests.exe',
            [string]$MapFile = 'C:\Fake\test\Win32\Debug\MyApp.Tests.map'
        )
        @{
            name           = $Name
            execute        = $Execute
            mapFile        = $MapFile
            engine         = 'DelphiCodeCoverage'
            enginePath     = ''
            sourceDir      = ''
            units          = @()
            excludeUnits   = @()
            outputDir      = 'coverage'
            formats        = @('html')
            threshold      = 0
            arguments      = @()
            timeoutSeconds = 300
            badge          = ''
        }
    }

    function script:New-CoverageResult {
        param([bool]$Success = $true)
        [PSCustomObject]@{
            StepName        = 'Coverage'
            Success         = $Success
            Duration        = [timespan]::Zero
            ExitCode        = if ($Success) { 0 } else { 5 }
            Tool            = 'delphi-coverage.ps1'
            Message         = if ($Success) { '73.4% (1842/2510 lines)' } else { 'Exit code 5' }
            Execute         = 'C:\Fake\test\Win32\Debug\MyApp.Tests.exe'
            CoveragePercent = if ($Success) { 73.4 } else { 0 }
            LinesCovered    = if ($Success) { 1842 } else { 0 }
            LinesTotal      = if ($Success) { 2510 } else { 0 }
            ThresholdMet    = $Success
            OutputDir       = 'coverage'
            Badge           = $null
        }
    }

    function script:New-CallGraphJob {
        param(
            [string]$Name = 'Source call graph',
            [string[]]$Path = @('C:\Fake\source')
        )
        @{
            name             = $Name
            path             = $Path
            engine           = 'radCallGraph'
            enginePath       = ''
            outputDir        = 'callgraph'
            formats          = @('json')
            jsonFile         = ''
            dotFile          = ''
            summaryFile      = ''
            class            = ''
            annotations      = $true
            deterministic    = $true
            graphKind        = ''
            graphVizUses     = $false
            graphVizClasses  = $false
            pasDocOptions    = @()
            projectFile      = ''
            graphVizExclude  = @()
            engineArguments  = @()
            timeoutSeconds   = 300
        }
    }

    function script:New-CallGraphResult {
        param([bool]$Success = $true)
        [PSCustomObject]@{
            StepName  = 'CallGraph'
            Success   = $Success
            Duration  = [timespan]::Zero
            ExitCode  = if ($Success) { 0 } else { 5 }
            Tool      = 'delphi-callgraph.ps1'
            Message   = if ($Success) { 'CallGraph completed: callgraph' } else { 'Exit code 5' }
            Engine    = 'radCallGraph'
            Inputs    = @('C:\Fake\source')
            OutputDir = 'callgraph'
            Formats   = @('json')
            Files     = $null
        }
    }

    function script:New-FormatJob {
        param(
            [string]$Name  = 'Format source',
            [string]$Root  = '',
            [bool]$Check   = $false,
            [string]$Engine = 'formatter'
        )
        @{
            name                    = $Name
            root                    = $Root
            engine                  = $Engine
            enginePath              = ''
            engineConfigFile        = ''
            path                    = @()
            includeFilePattern      = @()
            excludeDirectoryPattern = @()
            encoding                = ''
            createBackups           = $false
            outputLevel             = 'detailed'
            configFile              = ''
            check                   = $Check
        }
    }

    function script:New-FormatResult {
        param([bool]$Success = $true)
        [PSCustomObject]@{
            StepName    = 'Format'
            Success     = $Success
            Duration    = [timespan]::Zero
            ExitCode    = if ($Success) { 0 } else { 1 }
            Tool        = 'delphi-format.ps1'
            Message     = if ($Success) { 'Format completed' } else { 'Exit code 1' }
            ProjectFile = $null
        }
    }

    # ---------------------------------------------------------------------------

    Describe 'Invoke-DelphiCi -- unit' {

        BeforeAll {
            Mock Resolve-DelphiCiConfig  {
                script:New-MockConfig
            }
            Mock Invoke-DelphiClean      { script:New-CleanResult }
            Mock Invoke-DelphiBuild      { script:New-BuildResult }
            Mock Invoke-DelphiRun        { script:New-RunResult }
            Mock Invoke-DelphiIncVer     { script:New-IncVerResult }
            Mock Invoke-DelphiCopy       { script:New-CopyResult }
            Mock Invoke-DelphiCompress   { script:New-CompressResult }
            Mock Invoke-DelphiCoverage   { script:New-CoverageResult }
            Mock Invoke-DelphiCallGraph  { script:New-CallGraphResult }
            Mock Invoke-DelphiFormat     { script:New-FormatResult }
            Mock Write-DelphiCiMessage   {}
        }

        Context 'action routing' {

            It 'runs Invoke-DelphiClean when pipeline contains Clean' {
                Mock Resolve-DelphiCiConfig {
                    script:New-MockConfig -Pipeline @(
                        script:New-PipelineEntry -Action 'Clean'
                    )
                }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiClean -Times 1
            }

            It 'runs Invoke-DelphiBuild when pipeline contains Build' {
                Mock Resolve-DelphiCiConfig {
                    script:New-MockConfig -Pipeline @(
                        script:New-PipelineEntry -Action 'Build' -Jobs @(script:New-BuildJob)
                    )
                }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiBuild -Times 1
            }

            It 'runs Invoke-DelphiRun when pipeline contains Run' {
                Mock Resolve-DelphiCiConfig {
                    script:New-MockConfig -Pipeline @(
                        script:New-PipelineEntry -Action 'Run' -Jobs @(script:New-RunJob)
                    )
                }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiRun -Times 1
            }

            It 'runs all three actions when pipeline is Clean,Build,Test' {
                Mock Resolve-DelphiCiConfig {
                    script:New-MockConfig -Pipeline @(
                        (script:New-PipelineEntry -Action 'Clean'),
                        (script:New-PipelineEntry -Action 'Build' -Jobs @(script:New-BuildJob)),
                        (script:New-PipelineEntry -Action 'Run'  -Jobs @(script:New-RunJob))
                    )
                }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiClean -Times 1
                Should -Invoke Invoke-DelphiBuild -Times 1
                Should -Invoke Invoke-DelphiRun   -Times 1
            }

            It 'runs Invoke-DelphiIncVer when pipeline contains IncVer' {
                Mock Resolve-DelphiCiConfig {
                    script:New-MockConfig -Pipeline @(
                        script:New-PipelineEntry -Action 'IncVer' -Jobs @(script:New-IncVerJob)
                    )
                }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiIncVer -Times 1
            }

            It 'resolves incver file path relative to root' {
                $job = script:New-IncverJob -File 'src\versioninfo.rc'
                Mock Resolve-DelphiCiConfig {
                    script:New-MockConfig -Pipeline @(
                        script:New-PipelineEntry -Action 'IncVer' -Jobs @($job)
                    )
                }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiIncVer -ParameterFilter {
                    $File -like '*C:\Fake*versioninfo.rc*'
                }
            }

            It 'does not run Build when pipeline is only Clean' {
                Mock Resolve-DelphiCiConfig {
                    script:New-MockConfig -Pipeline @(
                        script:New-PipelineEntry -Action 'Clean'
                    )
                }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiBuild -Times 0
            }

            It 'runs Invoke-DelphiCopy when pipeline contains Copy' {
                Mock Resolve-DelphiCiConfig {
                    script:New-MockConfig -Pipeline @(
                        script:New-PipelineEntry -Action 'Copy' -Jobs @(script:New-CopyJob)
                    )
                }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiCopy -Times 1
            }

            It 'runs Invoke-DelphiCompress when pipeline contains Compress' {
                Mock Resolve-DelphiCiConfig {
                    script:New-MockConfig -Pipeline @(
                        script:New-PipelineEntry -Action 'Compress' -Jobs @(script:New-CompressJob)
                    )
                }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiCompress -Times 1
            }

            It 'runs Invoke-DelphiCoverage when pipeline contains Coverage' {
                Mock Resolve-DelphiCiConfig {
                    script:New-MockConfig -Pipeline @(
                        script:New-PipelineEntry -Action 'Coverage' -Jobs @(script:New-CoverageJob)
                    )
                }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiCoverage -Times 1
            }

            It 'runs Invoke-DelphiCallGraph when pipeline contains CallGraph' {
                Mock Resolve-DelphiCiConfig {
                    script:New-MockConfig -Pipeline @(
                        script:New-PipelineEntry -Action 'CallGraph' -Jobs @(script:New-CallGraphJob)
                    )
                }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiCallGraph -Times 1
            }

            It 'runs Invoke-DelphiFormat when pipeline contains Format' {
                Mock Resolve-DelphiCiConfig {
                    script:New-MockConfig -Pipeline @(
                        script:New-PipelineEntry -Action 'Format' -Jobs @(script:New-FormatJob)
                    )
                }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiFormat -Times 1
            }

            It 'runs Invoke-DelphiFormat with a default job when Format has no jobs' {
                Mock Resolve-DelphiCiConfig {
                    script:New-MockConfig -Pipeline @(
                        script:New-PipelineEntry -Action 'Format'
                    )
                }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiFormat -Times 1
            }

            It 'forwards -FormatRoot from the resolved CI root for a default Format job' {
                Mock Resolve-DelphiCiConfig {
                    script:New-MockConfig -Pipeline @(
                        script:New-PipelineEntry -Action 'Format'
                    )
                }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiFormat -ParameterFilter {
                    $FormatRoot -eq 'C:\Fake'
                }
            }

            It 'forwards -FormatCheck when the Format job is in check mode' {
                Mock Resolve-DelphiCiConfig {
                    script:New-MockConfig -Pipeline @(
                        script:New-PipelineEntry -Action 'Format' -Jobs @(script:New-FormatJob -Check $true)
                    )
                }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiFormat -ParameterFilter {
                    $FormatCheck -eq $true
                }
            }

            It 'resolves a relative Format job root against the CI root' {
                Mock Resolve-DelphiCiConfig {
                    script:New-MockConfig -Pipeline @(
                        script:New-PipelineEntry -Action 'Format' -Jobs @(script:New-FormatJob -Root 'source')
                    )
                }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiFormat -ParameterFilter {
                    $FormatRoot -like '*C:\Fake*source*'
                }
            }

            It 'does not run Clean when pipeline is only Build' {
                Mock Resolve-DelphiCiConfig {
                    script:New-MockConfig -Pipeline @(
                        script:New-PipelineEntry -Action 'Build' -Jobs @(script:New-BuildJob)
                    )
                }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiClean -Times 0
            }

        }

        Context 'halt on failure' {

            It 'does not run Build when Clean fails' {
                Mock Resolve-DelphiCiConfig {
                    script:New-MockConfig -Pipeline @(
                        (script:New-PipelineEntry -Action 'Clean'),
                        (script:New-PipelineEntry -Action 'Build' -Jobs @(script:New-BuildJob))
                    )
                }
                Mock Invoke-DelphiClean { script:New-CleanResult -Success $false }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiBuild -Times 0
            }

            It 'returns Success false when an action fails' {
                Mock Invoke-DelphiClean { script:New-CleanResult -Success $false }
                $result = Invoke-DelphiCi
                $result.Success | Should -Be $false
            }

            It 'does not run Compress when Copy fails' {
                Mock Resolve-DelphiCiConfig {
                    script:New-MockConfig -Pipeline @(
                        (script:New-PipelineEntry -Action 'Copy' -Jobs @(script:New-CopyJob)),
                        (script:New-PipelineEntry -Action 'Compress' -Jobs @(script:New-CompressJob))
                    )
                }
                Mock Invoke-DelphiCopy { script:New-CopyResult -Success $false }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiCompress -Times 0
            }

            It 'does not run Build when IncVer fails' {
                Mock Resolve-DelphiCiConfig {
                    script:New-MockConfig -Pipeline @(
                        (script:New-PipelineEntry -Action 'IncVer' -Jobs @(script:New-IncVerJob)),
                        (script:New-PipelineEntry -Action 'Build' -Jobs @(script:New-BuildJob))
                    )
                }
                Mock Invoke-DelphiIncver { script:New-IncVerResult -Success $false }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiBuild -Times 0
            }

            It 'does not run Build when a Format check fails' {
                Mock Resolve-DelphiCiConfig {
                    script:New-MockConfig -Pipeline @(
                        (script:New-PipelineEntry -Action 'Format' -Jobs @(script:New-FormatJob -Check $true)),
                        (script:New-PipelineEntry -Action 'Build' -Jobs @(script:New-BuildJob))
                    )
                }
                Mock Invoke-DelphiFormat { script:New-FormatResult -Success $false }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiBuild -Times 0
            }

            It 'does not run later actions when Build fails' {
                Mock Resolve-DelphiCiConfig {
                    script:New-MockConfig -Pipeline @(
                        (script:New-PipelineEntry -Action 'Build' -Jobs @(script:New-BuildJob)),
                        (script:New-PipelineEntry -Action 'Run' -Jobs @(script:New-RunJob))
                    )
                }
                Mock Invoke-DelphiBuild { script:New-BuildResult -Success $false }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiRun -Times 0
            }

        }

        Context 'result shape' {

            It 'always returns a result object' {
                Mock Resolve-DelphiCiConfig {
                    script:New-MockConfig -Pipeline @(
                        (script:New-PipelineEntry -Action 'Clean'),
                        (script:New-PipelineEntry -Action 'Build' -Jobs @(script:New-BuildJob))
                    )
                }
                $result = Invoke-DelphiCi
                $result | Should -Not -BeNullOrEmpty
            }

            It 'result Success is true when all actions succeed' {
                Mock Resolve-DelphiCiConfig {
                    script:New-MockConfig -Pipeline @(
                        (script:New-PipelineEntry -Action 'Clean'),
                        (script:New-PipelineEntry -Action 'Build' -Jobs @(script:New-BuildJob))
                    )
                }
                $result = Invoke-DelphiCi
                $result.Success | Should -Be $true
            }

            It 'result Duration is a TimeSpan' {
                Mock Resolve-DelphiCiConfig {
                    script:New-MockConfig -Pipeline @(
                        (script:New-PipelineEntry -Action 'Clean'),
                        (script:New-PipelineEntry -Action 'Build' -Jobs @(script:New-BuildJob))
                    )
                }
                $result = Invoke-DelphiCi
                $result.Duration | Should -BeOfType [timespan]
            }

            It 'result Steps array contains one entry per job run' {
                Mock Resolve-DelphiCiConfig {
                    script:New-MockConfig -Pipeline @(
                        (script:New-PipelineEntry -Action 'Clean'),
                        (script:New-PipelineEntry -Action 'Build' -Jobs @(script:New-BuildJob))
                    )
                }
                $result = Invoke-DelphiCi
                $result.Steps.Count | Should -Be 2
            }

            It 'result Steps entries carry the step names' {
                Mock Resolve-DelphiCiConfig {
                    script:New-MockConfig -Pipeline @(
                        (script:New-PipelineEntry -Action 'Clean'),
                        (script:New-PipelineEntry -Action 'Build' -Jobs @(script:New-BuildJob))
                    )
                }
                $result = Invoke-DelphiCi
                $result.Steps[0].StepName | Should -Be 'Clean'
                $result.Steps[1].StepName | Should -Be 'Build'
            }

        }

        Context 'clean-only without project file' {

            It 'does not require a project file when pipeline is Clean only' {
                Mock Resolve-DelphiCiConfig {
                    script:New-MockConfig -Pipeline @(
                        script:New-PipelineEntry -Action 'Clean'
                    )
                }
                $result = Invoke-DelphiCi
                $result.Success | Should -Be $true
            }

        }

        Context 'build matrix expansion' {

            It 'expands platform x configuration matrix for a single build job' {
                Mock Resolve-DelphiCiConfig {
                    script:New-MockConfig -Pipeline @(
                        script:New-PipelineEntry -Action 'Build' -Jobs @(
                            script:New-BuildJob -Platform @('Win32', 'Win64') -Configuration @('Debug', 'Release')
                        )
                    )
                }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiBuild -Times 4
            }

            It 'passes each platform/config combination to Invoke-DelphiBuild' {
                Mock Resolve-DelphiCiConfig {
                    script:New-MockConfig -Pipeline @(
                        script:New-PipelineEntry -Action 'Build' -Jobs @(
                            script:New-BuildJob -Platform @('Win32', 'Win64') -Configuration @('Debug', 'Release')
                        )
                    )
                }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiBuild -ParameterFilter { $Platform -eq 'Win32' -and $Configuration -eq 'Debug' }
                Should -Invoke Invoke-DelphiBuild -ParameterFilter { $Platform -eq 'Win32' -and $Configuration -eq 'Release' }
                Should -Invoke Invoke-DelphiBuild -ParameterFilter { $Platform -eq 'Win64' -and $Configuration -eq 'Debug' }
                Should -Invoke Invoke-DelphiBuild -ParameterFilter { $Platform -eq 'Win64' -and $Configuration -eq 'Release' }
            }

            It 'propagates a job noConfig=true to Invoke-DelphiBuild' {
                Mock Resolve-DelphiCiConfig {
                    script:New-MockConfig -Pipeline @(
                        script:New-PipelineEntry -Action 'Build' -Jobs @(
                            script:New-BuildJob -NoConfig $true
                        )
                    )
                }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiBuild -ParameterFilter { $NoConfig -eq $true }
            }

            It 'passes NoConfig false when the job does not set it' {
                Mock Resolve-DelphiCiConfig {
                    script:New-MockConfig -Pipeline @(
                        script:New-PipelineEntry -Action 'Build' -Jobs @(
                            script:New-BuildJob
                        )
                    )
                }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiBuild -ParameterFilter { -not $NoConfig }
            }

            It 'runs multiple build jobs in sequence' {
                Mock Resolve-DelphiCiConfig {
                    script:New-MockConfig -Pipeline @(
                        script:New-PipelineEntry -Action 'Build' -Jobs @(
                            (script:New-BuildJob -Name 'App' -ProjectFile 'C:\Fake\App.dproj'),
                            (script:New-BuildJob -Name 'Lib' -ProjectFile 'C:\Fake\Lib.dproj')
                        )
                    )
                }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiBuild -Times 2
                Should -Invoke Invoke-DelphiBuild -ParameterFilter { $ProjectFile -eq 'C:\Fake\App.dproj' }
                Should -Invoke Invoke-DelphiBuild -ParameterFilter { $ProjectFile -eq 'C:\Fake\Lib.dproj' }
            }

            It 'halts on first build job failure' {
                Mock Invoke-DelphiBuild { script:New-BuildResult -Success $false }
                Mock Resolve-DelphiCiConfig {
                    script:New-MockConfig -Pipeline @(
                        script:New-PipelineEntry -Action 'Build' -Jobs @(
                            (script:New-BuildJob -Name 'A' -ProjectFile 'C:\Fake\A.dproj'),
                            (script:New-BuildJob -Name 'B' -ProjectFile 'C:\Fake\B.dproj')
                        )
                    )
                }
                $result = Invoke-DelphiCi
                $result.Success | Should -Be $false
                Should -Invoke Invoke-DelphiBuild -Times 1
            }

            It 'resolves relative projectFile paths from the CI root' {
                Mock Resolve-DelphiCiConfig {
                    script:New-MockConfig -Pipeline @(
                        script:New-PipelineEntry -Action 'Build' -Jobs @(
                            script:New-BuildJob -ProjectFile 'Source\App.dproj'
                        )
                    )
                }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiBuild -ParameterFilter {
                    $ProjectFile -eq 'C:\Fake\Source\App.dproj'
                }
            }

        }

        Context 'multiple run jobs' {

            It 'runs multiple run jobs in sequence' {
                Mock Resolve-DelphiCiConfig {
                    script:New-MockConfig -Pipeline @(
                        script:New-PipelineEntry -Action 'Run' -Jobs @(
                            (script:New-RunJob -Name 'Win32' -Execute 'C:\Fake\Win32\App.Tests.exe'),
                            (script:New-RunJob -Name 'Win64' -Execute 'C:\Fake\Win64\App.Tests.exe')
                        )
                    )
                }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiRun -Times 2
            }

            It 'passes execute target to Invoke-DelphiRun for each job' {
                Mock Resolve-DelphiCiConfig {
                    script:New-MockConfig -Pipeline @(
                        script:New-PipelineEntry -Action 'Run' -Jobs @(
                            (script:New-RunJob -Name 'Win32' -Execute 'C:\Fake\Win32\App.Tests.exe'),
                            (script:New-RunJob -Name 'Win64' -Execute 'C:\Fake\Win64\App.Tests.exe')
                        )
                    )
                }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiRun -ParameterFilter { $Execute -eq 'C:\Fake\Win32\App.Tests.exe' }
                Should -Invoke Invoke-DelphiRun -ParameterFilter { $Execute -eq 'C:\Fake\Win64\App.Tests.exe' }
            }

            It 'resolves relative execute paths from the CI root' {
                Mock Resolve-DelphiCiConfig {
                    script:New-MockConfig -Pipeline @(
                        script:New-PipelineEntry -Action 'Run' -Jobs @(
                            script:New-RunJob -Execute 'Tests\Win32\App.Tests.exe'
                        )
                    )
                }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiRun -ParameterFilter {
                    $Execute -eq 'C:\Fake\Tests\Win32\App.Tests.exe'
                }
            }

        }

        Context 'parameter forwarding' {

            It 'passes build job fields to Invoke-DelphiBuild' {
                $job = script:New-BuildJob
                $job['verbosity'] = 'minimal'
                $job['target'] = 'Rebuild'
                Mock Resolve-DelphiCiConfig {
                    script:New-MockConfig -Pipeline @(
                        script:New-PipelineEntry -Action 'Build' -Jobs @($job)
                    )
                }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiBuild -ParameterFilter {
                    $BuildVerbosity -eq 'minimal' -and $BuildTarget -eq 'Rebuild'
                }
            }

            It 'forwards toolchain.rootDir to Invoke-DelphiBuild as -ToolchainRootDir' {
                $job = script:New-BuildJob
                $job['toolchain'] = @{ version = 'Latest'; rootDir = 'G:\radprogrammer\rad-buildfiles-d28.11-Alexandria' }
                Mock Resolve-DelphiCiConfig {
                    script:New-MockConfig -Pipeline @(
                        script:New-PipelineEntry -Action 'Build' -Jobs @($job)
                    )
                }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiBuild -ParameterFilter {
                    $ToolchainRootDir -eq 'G:\radprogrammer\rad-buildfiles-d28.11-Alexandria'
                }
            }

            It 'forwards an empty -ToolchainRootDir when the job has no toolchain.rootDir' {
                $job = script:New-BuildJob
                Mock Resolve-DelphiCiConfig {
                    script:New-MockConfig -Pipeline @(
                        script:New-PipelineEntry -Action 'Build' -Jobs @($job)
                    )
                }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiBuild -ParameterFilter {
                    [string]::IsNullOrEmpty($ToolchainRootDir)
                }
            }

            It 'passes run job fields to Invoke-DelphiRun' {
                $job = script:New-RunJob
                $job['timeoutSeconds'] = 30
                $job['arguments'] = @('--verbose')
                Mock Resolve-DelphiCiConfig {
                    script:New-MockConfig -Pipeline @(
                        script:New-PipelineEntry -Action 'Run' -Jobs @($job)
                    )
                }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiRun -ParameterFilter {
                    $TimeoutSeconds -eq 30
                }
            }

        }

    }

    Describe 'Invoke-DelphiCi -- integration' {

        It 'cleans and builds ConsoleProject with default steps' {
            $root  = [System.IO.Path]::GetFullPath(
                (Join-Path $PSScriptRoot '..\..' 'Examples\ConsoleProjectGroup')
            )
            $dproj = [System.IO.Path]::GetFullPath(
                (Join-Path $PSScriptRoot '..\..' 'Examples\ConsoleProjectGroup\Source\ConsoleProject.dproj')
            )
            $result = Invoke-DelphiCi -Root $root -ProjectFile $dproj
            $result.Success       | Should -Be $true
            $result.Steps.Count   | Should -Be 2
            $result.Steps[0].StepName | Should -Be 'Clean'
            $result.Steps[1].StepName | Should -Be 'Build'
            $result.Steps[0].Success  | Should -Be $true
            $result.Steps[1].Success  | Should -Be $true
        }

    }

}
