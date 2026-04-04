#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

Import-Module ([System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..' 'source' 'Delphi.PowerShell.CI.psm1'))) -Force

InModuleScope 'Delphi.PowerShell.CI' {

    # ---------------------------------------------------------------------------
    # Shared helpers
    # ---------------------------------------------------------------------------

    function script:New-MockConfig {
        param(
            [string]$ProjectFile = 'C:\Fake\Source\App.dproj',
            [string[]]$Steps = @('Clean', 'Build')
        )
        [PSCustomObject]@{
            Root        = 'C:\Fake'
            ProjectFile = $ProjectFile
            Steps       = $Steps
            Clean       = [PSCustomObject]@{
                Level                   = 'basic'
                IncludeFilePattern      = @()
                ExcludeDirectoryPattern = @()
                ConfigFile              = ''
            }
            Build       = [PSCustomObject]@{
                Engine        = 'MSBuild'
                Toolchain     = [PSCustomObject]@{ Version = 'Latest' }
                Platform      = 'Win32'
                Configuration = 'Debug'
                Defines       = @()
            }
            Test        = [PSCustomObject]@{
                TestProjectFile  = 'C:\Fake\Tests\App.Tests.dproj'
                TestExecutable   = $null
                Defines          = @()
                Arguments        = @()
                TimeoutSeconds   = 10
                Build            = $true
                Run              = $true
            }
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
            StepName    = 'Build'
            Success     = $Success
            Duration    = [timespan]::Zero
            ExitCode    = if ($Success) { 0 } else { 5 }
            Tool        = 'delphi-msbuild.ps1'
            Message     = if ($Success) { 'Build completed' } else { 'Exit code 5' }
            ProjectFile = 'C:\Fake\Source\App.dproj'
        }
    }

    function script:New-TestResult {
        param([bool]$Success = $true)
        [PSCustomObject]@{
            StepName        = 'Test'
            Success         = $Success
            Duration        = [timespan]::Zero
            ExitCode        = if ($Success) { 0 } else { 1 }
            Tool            = 'test runner'
            Message         = if ($Success) { 'Tests passed' } else { 'Exit code 1' }
            TestProjectFile = 'C:\Fake\Tests\App.Tests.dproj'
            TestExecutable  = 'C:\Fake\Tests\Win32\Debug\App.Tests.exe'
        }
    }

    # ---------------------------------------------------------------------------

    Describe 'Invoke-DelphiCi -- unit' {

        BeforeAll {
            Mock Resolve-DelphiCiConfig  { script:New-MockConfig }
            Mock Find-DelphiProjects     { @('C:\Fake\Source\App.dproj') }
            Mock Invoke-DelphiClean      { script:New-CleanResult }
            Mock Invoke-DelphiBuild      { script:New-BuildResult }
            Mock Invoke-DelphiTest       { script:New-TestResult }
            Mock Write-DelphiCiMessage   {}
            Mock Resolve-DefaultPlatform { 'Win32' }
        }

        Context 'step routing' {

            It 'runs Invoke-DelphiClean when Steps contains Clean' {
                Mock Resolve-DelphiCiConfig { script:New-MockConfig -Steps @('Clean') }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiClean -Times 1
            }

            It 'runs Invoke-DelphiBuild when Steps contains Build' {
                Mock Resolve-DelphiCiConfig { script:New-MockConfig -Steps @('Build') }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiBuild -Times 1
            }

            It 'runs both steps when Steps is Clean,Build (default)' {
                Mock Resolve-DelphiCiConfig { script:New-MockConfig -Steps @('Clean', 'Build') }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiClean -Times 1
                Should -Invoke Invoke-DelphiBuild -Times 1
            }

            It 'does not run Build when Steps is only Clean' {
                Mock Resolve-DelphiCiConfig { script:New-MockConfig -Steps @('Clean') }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiBuild -Times 0
            }

            It 'does not run Clean when Steps is only Build' {
                Mock Resolve-DelphiCiConfig { script:New-MockConfig -Steps @('Build') }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiClean -Times 0
            }

            It 'runs Invoke-DelphiTest when Steps contains Test' {
                Mock Resolve-DelphiCiConfig { script:New-MockConfig -Steps @('Test') }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiTest -Times 1
            }

            It 'does not run Build or Clean when Steps is only Test' {
                Mock Resolve-DelphiCiConfig { script:New-MockConfig -Steps @('Test') }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiBuild -Times 0
                Should -Invoke Invoke-DelphiClean -Times 0
            }

            It 'runs all three steps when Steps is Clean,Build,Test' {
                Mock Resolve-DelphiCiConfig { script:New-MockConfig -Steps @('Clean', 'Build', 'Test') }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiClean -Times 1
                Should -Invoke Invoke-DelphiBuild -Times 1
                Should -Invoke Invoke-DelphiTest  -Times 1
            }

        }

        Context 'step halt on failure' {

            It 'does not run Build when Clean fails' {
                Mock Invoke-DelphiClean { script:New-CleanResult -Success $false }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiBuild -Times 0
            }

            It 'returns Success false when a step fails' {
                Mock Invoke-DelphiClean { script:New-CleanResult -Success $false }
                $result = Invoke-DelphiCi
                $result.Success | Should -Be $false
            }

        }

        Context 'result shape' {

            It 'always returns a result object' {
                $result = Invoke-DelphiCi
                $result | Should -Not -BeNullOrEmpty
            }

            It 'result Success is true when all steps succeed' {
                $result = Invoke-DelphiCi
                $result.Success | Should -Be $true
            }

            It 'result Duration is a TimeSpan' {
                $result = Invoke-DelphiCi
                $result.Duration | Should -BeOfType [timespan]
            }

            It 'result ProjectFile matches the resolved project' {
                $result = Invoke-DelphiCi
                $result.ProjectFile | Should -Be 'C:\Fake\Source\App.dproj'
            }

            It 'result Steps array contains one entry per step run' {
                Mock Resolve-DelphiCiConfig { script:New-MockConfig -Steps @('Clean', 'Build') }
                $result = Invoke-DelphiCi
                $result.Steps.Count | Should -Be 2
            }

            It 'result Steps entries carry the step names' {
                Mock Resolve-DelphiCiConfig { script:New-MockConfig -Steps @('Clean', 'Build') }
                $result = Invoke-DelphiCi
                $result.Steps[0].StepName | Should -Be 'Clean'
                $result.Steps[1].StepName | Should -Be 'Build'
            }

            It 'result Steps contains only executed steps when halted by failure' {
                Mock Invoke-DelphiClean { script:New-CleanResult -Success $false }
                $result = Invoke-DelphiCi
                $result.Steps.Count | Should -Be 1
                $result.Steps[0].StepName | Should -Be 'Clean'
            }

        }

        Context 'project discovery' {

            It 'uses ProjectFile from config when set' {
                Mock Resolve-DelphiCiConfig { script:New-MockConfig -ProjectFile 'C:\Explicit\App.dproj' }
                $result = Invoke-DelphiCi
                $result.ProjectFile | Should -Be 'C:\Explicit\App.dproj'
                Should -Invoke Find-DelphiProjects -Times 0
            }

            It 'calls Find-DelphiProjects when config has no ProjectFile' {
                Mock Resolve-DelphiCiConfig { script:New-MockConfig -ProjectFile '' }
                Mock Find-DelphiProjects    { @('C:\Fake\Source\Discovered.dproj') }
                $result = Invoke-DelphiCi
                Should -Invoke Find-DelphiProjects -Times 1
                $result.ProjectFile | Should -Be 'C:\Fake\Source\Discovered.dproj'
            }

            It 'throws when no .dproj is found' {
                Mock Resolve-DelphiCiConfig { script:New-MockConfig -ProjectFile '' }
                Mock Find-DelphiProjects    { @() }
                { Invoke-DelphiCi } | Should -Throw
            }

            It 'throws when multiple .dproj files are found' {
                Mock Resolve-DelphiCiConfig { script:New-MockConfig -ProjectFile '' }
                Mock Find-DelphiProjects    { @('C:\Fake\A.dproj', 'C:\Fake\B.dproj') }
                { Invoke-DelphiCi } | Should -Throw
            }

        }

        Context 'parameter forwarding' {

            It 'passes CleanLevel from config to Invoke-DelphiClean' {
                Mock Resolve-DelphiCiConfig {
                    $cfg = script:New-MockConfig -Steps @('Clean')
                    $cfg.Clean = [PSCustomObject]@{ Level = 'standard'; IncludeFilePattern = @(); ExcludeDirectoryPattern = @(); ConfigFile = '' }
                    $cfg
                }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiClean -ParameterFilter { $CleanLevel -eq 'standard' }
            }

            It 'passes CleanIncludeFilePattern from config to Invoke-DelphiClean' {
                Mock Resolve-DelphiCiConfig {
                    $cfg = script:New-MockConfig -Steps @('Clean')
                    $cfg.Clean = [PSCustomObject]@{ Level = 'basic'; IncludeFilePattern = @('*.res', '*.mab'); ExcludeDirectoryPattern = @(); ConfigFile = '' }
                    $cfg
                }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiClean -ParameterFilter {
                    $CleanIncludeFilePattern -contains '*.res' -and $CleanIncludeFilePattern -contains '*.mab'
                }
            }

            It 'passes CleanExcludeDirectoryPattern from config to Invoke-DelphiClean' {
                Mock Resolve-DelphiCiConfig {
                    $cfg = script:New-MockConfig -Steps @('Clean')
                    $cfg.Clean = [PSCustomObject]@{ Level = 'basic'; IncludeFilePattern = @(); ExcludeDirectoryPattern = @('vendor', 'assets'); ConfigFile = '' }
                    $cfg
                }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiClean -ParameterFilter {
                    $CleanExcludeDirectoryPattern -contains 'vendor' -and $CleanExcludeDirectoryPattern -contains 'assets'
                }
            }

            It 'passes CleanConfigFile from config to Invoke-DelphiClean' {
                Mock Resolve-DelphiCiConfig {
                    $cfg = script:New-MockConfig -Steps @('Clean')
                    $cfg.Clean = [PSCustomObject]@{ Level = 'basic'; IncludeFilePattern = @(); ExcludeDirectoryPattern = @(); ConfigFile = 'C:/ci/delphi-clean-ci.json' }
                    $cfg
                }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiClean -ParameterFilter {
                    $CleanConfigFile -eq 'C:/ci/delphi-clean-ci.json'
                }
            }

            It 'passes Platform from config to Invoke-DelphiBuild' {
                Mock Resolve-DelphiCiConfig {
                    $cfg = script:New-MockConfig -Steps @('Build')
                    $cfg.Build = [PSCustomObject]@{
                        Engine = 'MSBuild'; Toolchain = [PSCustomObject]@{ Version = 'Latest' }
                        Platform = 'Win64'; Configuration = 'Debug'; Defines = @()
                    }
                    $cfg
                }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiBuild -ParameterFilter { $Platform -eq 'Win64' }
            }

            It 'passes Configuration from config to Invoke-DelphiBuild' {
                Mock Resolve-DelphiCiConfig {
                    $cfg = script:New-MockConfig -Steps @('Build')
                    $cfg.Build = [PSCustomObject]@{
                        Engine = 'MSBuild'; Toolchain = [PSCustomObject]@{ Version = 'Latest' }
                        Platform = 'Win32'; Configuration = 'Release'; Defines = @()
                    }
                    $cfg
                }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiBuild -ParameterFilter { $Configuration -eq 'Release' }
            }

            It 'passes Defines from config to Invoke-DelphiBuild' {
                Mock Resolve-DelphiCiConfig {
                    $cfg = script:New-MockConfig -Steps @('Build')
                    $cfg.Build = [PSCustomObject]@{
                        Engine = 'MSBuild'; Toolchain = [PSCustomObject]@{ Version = 'Latest' }
                        Platform = 'Win32'; Configuration = 'Debug'; Defines = @('CI', 'RELEASE_BUILD')
                    }
                    $cfg
                }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiBuild -ParameterFilter {
                    $Defines -contains 'CI' -and $Defines -contains 'RELEASE_BUILD'
                }
            }

            It 'passes TestExecutable from config to Invoke-DelphiTest' {
                Mock Resolve-DelphiCiConfig {
                    $cfg = script:New-MockConfig -Steps @('Test')
                    $cfg.Test = [PSCustomObject]@{
                        TestProjectFile = 'C:\Fake\Tests\App.Tests.dproj'
                        TestExecutable  = 'C:\Custom\Out\App.Tests.exe'
                        Defines = @(); Arguments = @(); TimeoutSeconds = 10; Build = $true; Run = $true
                    }
                    $cfg
                }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiTest -ParameterFilter {
                    $TestExecutable -eq 'C:\Custom\Out\App.Tests.exe'
                }
            }

            It 'passes Defines from config to Invoke-DelphiTest' {
                Mock Resolve-DelphiCiConfig {
                    $cfg = script:New-MockConfig -Steps @('Test')
                    $cfg.Test = [PSCustomObject]@{
                        TestProjectFile = 'C:\Fake\Tests\App.Tests.dproj'
                        TestExecutable  = $null
                        Defines = @('CI'); Arguments = @(); TimeoutSeconds = 10; Build = $true; Run = $true
                    }
                    $cfg
                }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiTest -ParameterFilter { $Defines -contains 'CI' }
            }

            It 'passes Arguments from config to Invoke-DelphiTest' {
                Mock Resolve-DelphiCiConfig {
                    $cfg = script:New-MockConfig -Steps @('Test')
                    $cfg.Test = [PSCustomObject]@{
                        TestProjectFile = 'C:\Fake\Tests\App.Tests.dproj'
                        TestExecutable  = $null
                        Defines = @(); Arguments = @('--output', 'xml'); TimeoutSeconds = 10; Build = $true; Run = $true
                    }
                    $cfg
                }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiTest -ParameterFilter {
                    $Arguments -contains '--output' -and $Arguments -contains 'xml'
                }
            }

            It 'passes TimeoutSeconds from config to Invoke-DelphiTest' {
                Mock Resolve-DelphiCiConfig {
                    $cfg = script:New-MockConfig -Steps @('Test')
                    $cfg.Test = [PSCustomObject]@{
                        TestProjectFile = 'C:\Fake\Tests\App.Tests.dproj'
                        TestExecutable  = $null
                        Defines = @(); Arguments = @(); TimeoutSeconds = 30; Build = $true; Run = $true
                    }
                    $cfg
                }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiTest -ParameterFilter { $TimeoutSeconds -eq 30 }
            }

            It 'passes Build false from config to Invoke-DelphiTest' {
                Mock Resolve-DelphiCiConfig {
                    $cfg = script:New-MockConfig -Steps @('Test')
                    $cfg.Test = [PSCustomObject]@{
                        TestProjectFile = 'C:\Fake\Tests\App.Tests.dproj'
                        TestExecutable  = $null
                        Defines = @(); Arguments = @(); TimeoutSeconds = 10; Build = $false; Run = $true
                    }
                    $cfg
                }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiTest -ParameterFilter { $Build -eq $false }
            }

            It 'passes Run false from config to Invoke-DelphiTest' {
                Mock Resolve-DelphiCiConfig {
                    $cfg = script:New-MockConfig -Steps @('Test')
                    $cfg.Test = [PSCustomObject]@{
                        TestProjectFile = 'C:\Fake\Tests\App.Tests.dproj'
                        TestExecutable  = $null
                        Defines = @(); Arguments = @(); TimeoutSeconds = 10; Build = $true; Run = $false
                    }
                    $cfg
                }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiTest -ParameterFilter { $Run -eq $false }
            }

        }

        Context 'platform auto-resolution' {

            It 'calls Resolve-DefaultPlatform when config platform is null' {
                Mock Resolve-DelphiCiConfig {
                    $cfg = script:New-MockConfig -Steps @('Build')
                    $cfg.Build = [PSCustomObject]@{
                        Engine = 'MSBuild'; Toolchain = [PSCustomObject]@{ Version = 'Latest' }
                        Platform = $null; Configuration = 'Debug'; Defines = @()
                    }
                    $cfg
                }
                Mock Resolve-DefaultPlatform { 'Win64' }
                Invoke-DelphiCi
                Should -Invoke Resolve-DefaultPlatform -Times 1
                Should -Invoke Invoke-DelphiBuild -ParameterFilter { $Platform -eq 'Win64' }
            }

            It 'does not call Resolve-DefaultPlatform when platform is explicitly set' {
                Invoke-DelphiCi
                Should -Invoke Resolve-DefaultPlatform -Times 0
            }

            It 'does not call Resolve-DefaultPlatform when BuildEngine is DCCBuild' {
                Mock Resolve-DelphiCiConfig {
                    $cfg = script:New-MockConfig -Steps @('Build')
                    $cfg.Build = [PSCustomObject]@{
                        Engine = 'DCCBuild'; Toolchain = [PSCustomObject]@{ Version = 'Latest' }
                        Platform = $null; Configuration = 'Debug'; Defines = @()
                    }
                    $cfg
                }
                Mock Resolve-DefaultPlatform { 'Win32' }
                Invoke-DelphiCi
                Should -Invoke Resolve-DefaultPlatform -Times 0
                Should -Invoke Invoke-DelphiBuild -ParameterFilter { $Platform -eq 'Win32' }
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
