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
            [string[]]$Configuration = @('Debug')
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

    # ---------------------------------------------------------------------------

    Describe 'Invoke-DelphiCi -- unit' {

        BeforeAll {
            Mock Resolve-DelphiCiConfig  {
                script:New-MockConfig
            }
            Mock Invoke-DelphiClean      { script:New-CleanResult }
            Mock Invoke-DelphiBuild      { script:New-BuildResult }
            Mock Invoke-DelphiRun        { script:New-RunResult }
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

            It 'does not run Build when pipeline is only Clean' {
                Mock Resolve-DelphiCiConfig {
                    script:New-MockConfig -Pipeline @(
                        script:New-PipelineEntry -Action 'Clean'
                    )
                }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiBuild -Times 0
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
