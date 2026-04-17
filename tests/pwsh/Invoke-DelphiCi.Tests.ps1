#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

Import-Module ([System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..' 'source' 'Delphi.PowerShell.CI.psm1'))) -Force

InModuleScope 'Delphi.PowerShell.CI' {

    # ---------------------------------------------------------------------------
    # Shared helpers
    # ---------------------------------------------------------------------------

    function script:New-MockConfig {
        param(
            [string[]]$Steps = @('Clean', 'Build'),
            [object[]]$BuildJobs = @(),
            [object[]]$CleanJobs = @(),
            [object[]]$TestJobs  = @()
        )
        [PSCustomObject]@{
            Root  = 'C:\Fake'
            Steps = $Steps
            Clean = [PSCustomObject]@{
                Defaults = [PSCustomObject]@{
                    Level                   = 'basic'
                    OutputLevel             = 'detailed'
                    IncludeFilePattern      = @()
                    ExcludeDirectoryPattern = @()
                    ConfigFile              = ''
                    RecycleBin              = $false
                    Check                   = $false
                }
                Jobs = $CleanJobs
            }
            Build = [PSCustomObject]@{
                Defaults = [PSCustomObject]@{
                    Engine         = 'MSBuild'
                    Toolchain      = [PSCustomObject]@{ Version = 'Latest' }
                    Platform       = 'Win32'
                    Configuration  = 'Debug'
                    Defines        = @()
                    Verbosity      = 'normal'
                    Target         = 'Build'
                    ExeOutputDir   = ''
                    DcuOutputDir   = ''
                    UnitSearchPath = @()
                    IncludePath    = @()
                    Namespace      = @()
                }
                Jobs = $BuildJobs
            }
            Test = [PSCustomObject]@{
                Defaults = [PSCustomObject]@{
                    TimeoutSeconds = 10
                    Arguments      = @()
                }
                Jobs = $TestJobs
            }
        }
    }

    function script:New-BuildJob {
        param(
            [string]$Name = 'App build',
            [string]$ProjectFile = 'C:\Fake\Source\App.dproj',
            [string[]]$Platform = @('Win32'),
            [string[]]$Configuration = @('Debug')
        )
        [PSCustomObject]@{
            Name           = $Name
            ProjectFile    = $ProjectFile
            Engine         = 'MSBuild'
            Toolchain      = [PSCustomObject]@{ Version = 'Latest' }
            Platform       = $Platform
            Configuration  = $Configuration
            Defines        = @()
            Verbosity      = 'normal'
            Target         = 'Build'
            ExeOutputDir   = ''
            DcuOutputDir   = ''
            UnitSearchPath = @()
            IncludePath    = @()
            Namespace      = @()
        }
    }

    function script:New-TestJob {
        param(
            [string]$Name = 'Unit tests',
            [string]$TestExeFile = 'C:\Fake\Tests\Win32\Debug\App.Tests.exe'
        )
        [PSCustomObject]@{
            Name           = $Name
            TestExeFile    = $TestExeFile
            Arguments      = @()
            TimeoutSeconds = 10
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

    function script:New-TestResult {
        param([bool]$Success = $true)
        [PSCustomObject]@{
            StepName    = 'Test'
            Success     = $Success
            Duration    = [timespan]::Zero
            ExitCode    = if ($Success) { 0 } else { 1 }
            Tool        = 'test runner'
            Message     = if ($Success) { 'Tests passed' } else { 'Exit code 1' }
            TestExeFile = 'C:\Fake\Tests\Win32\Debug\App.Tests.exe'
        }
    }

    # ---------------------------------------------------------------------------

    Describe 'Invoke-DelphiCi -- unit' {

        BeforeAll {
            Mock Resolve-DelphiCiConfig  {
                script:New-MockConfig -BuildJobs @(script:New-BuildJob)
            }
            Mock Invoke-DelphiClean      { script:New-CleanResult }
            Mock Invoke-DelphiBuild      { script:New-BuildResult }
            Mock Invoke-DelphiTest       { script:New-TestResult }
            Mock Write-DelphiCiMessage   {}
        }

        Context 'step routing' {

            It 'runs Invoke-DelphiClean when Steps contains Clean' {
                Mock Resolve-DelphiCiConfig { script:New-MockConfig -Steps @('Clean') }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiClean -Times 1
            }

            It 'runs Invoke-DelphiBuild when Steps contains Build' {
                Mock Resolve-DelphiCiConfig {
                    script:New-MockConfig -Steps @('Build') -BuildJobs @(script:New-BuildJob)
                }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiBuild -Times 1
            }

            It 'runs Invoke-DelphiTest when Steps contains Test' {
                Mock Resolve-DelphiCiConfig {
                    script:New-MockConfig -Steps @('Test') -TestJobs @(script:New-TestJob)
                }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiTest -Times 1
            }

            It 'runs all three steps when Steps is Clean,Build,Test' {
                Mock Resolve-DelphiCiConfig {
                    script:New-MockConfig -Steps @('Clean', 'Build', 'Test') `
                        -BuildJobs @(script:New-BuildJob) `
                        -TestJobs  @(script:New-TestJob)
                }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiClean -Times 1
                Should -Invoke Invoke-DelphiBuild -Times 1
                Should -Invoke Invoke-DelphiTest  -Times 1
            }

            It 'does not run Build when Steps is only Clean' {
                Mock Resolve-DelphiCiConfig { script:New-MockConfig -Steps @('Clean') }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiBuild -Times 0
            }

            It 'does not run Clean when Steps is only Build' {
                Mock Resolve-DelphiCiConfig {
                    script:New-MockConfig -Steps @('Build') -BuildJobs @(script:New-BuildJob)
                }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiClean -Times 0
            }

        }

        Context 'step halt on failure' {

            It 'does not run Build when Clean fails' {
                Mock Resolve-DelphiCiConfig {
                    script:New-MockConfig -BuildJobs @(script:New-BuildJob)
                }
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
                Mock Resolve-DelphiCiConfig {
                    script:New-MockConfig -BuildJobs @(script:New-BuildJob)
                }
                $result = Invoke-DelphiCi
                $result | Should -Not -BeNullOrEmpty
            }

            It 'result Success is true when all steps succeed' {
                Mock Resolve-DelphiCiConfig {
                    script:New-MockConfig -BuildJobs @(script:New-BuildJob)
                }
                $result = Invoke-DelphiCi
                $result.Success | Should -Be $true
            }

            It 'result Duration is a TimeSpan' {
                Mock Resolve-DelphiCiConfig {
                    script:New-MockConfig -BuildJobs @(script:New-BuildJob)
                }
                $result = Invoke-DelphiCi
                $result.Duration | Should -BeOfType [timespan]
            }

            It 'result Steps array contains one entry per job run' {
                Mock Resolve-DelphiCiConfig {
                    script:New-MockConfig -Steps @('Clean', 'Build') -BuildJobs @(script:New-BuildJob)
                }
                $result = Invoke-DelphiCi
                $result.Steps.Count | Should -Be 2
            }

            It 'result Steps entries carry the step names' {
                Mock Resolve-DelphiCiConfig {
                    script:New-MockConfig -Steps @('Clean', 'Build') -BuildJobs @(script:New-BuildJob)
                }
                $result = Invoke-DelphiCi
                $result.Steps[0].StepName | Should -Be 'Clean'
                $result.Steps[1].StepName | Should -Be 'Build'
            }

        }

        Context 'clean-only without project file' {

            It 'does not require a project file when Steps is Clean only' {
                Mock Resolve-DelphiCiConfig { script:New-MockConfig -Steps @('Clean') }
                $result = Invoke-DelphiCi
                $result.Success | Should -Be $true
            }

        }

        Context 'build matrix expansion' {

            It 'expands platform x configuration matrix for a single build job' {
                Mock Resolve-DelphiCiConfig {
                    script:New-MockConfig -Steps @('Build') -BuildJobs @(
                        script:New-BuildJob -Platform @('Win32', 'Win64') -Configuration @('Debug', 'Release')
                    )
                }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiBuild -Times 4
            }

            It 'passes each platform/config combination to Invoke-DelphiBuild' {
                Mock Resolve-DelphiCiConfig {
                    script:New-MockConfig -Steps @('Build') -BuildJobs @(
                        script:New-BuildJob -Platform @('Win32', 'Win64') -Configuration @('Debug', 'Release')
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
                    script:New-MockConfig -Steps @('Build') -BuildJobs @(
                        (script:New-BuildJob -Name 'App' -ProjectFile 'C:\Fake\App.dproj'),
                        (script:New-BuildJob -Name 'Lib' -ProjectFile 'C:\Fake\Lib.dproj')
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
                    script:New-MockConfig -Steps @('Build') -BuildJobs @(
                        (script:New-BuildJob -Name 'A' -ProjectFile 'C:\Fake\A.dproj'),
                        (script:New-BuildJob -Name 'B' -ProjectFile 'C:\Fake\B.dproj')
                    )
                }
                $result = Invoke-DelphiCi
                $result.Success | Should -Be $false
                Should -Invoke Invoke-DelphiBuild -Times 1
            }

        }

        Context 'multiple test jobs' {

            It 'runs multiple test jobs in sequence' {
                Mock Resolve-DelphiCiConfig {
                    script:New-MockConfig -Steps @('Test') -TestJobs @(
                        (script:New-TestJob -Name 'Win32' -TestExeFile 'C:\Fake\Win32\App.Tests.exe'),
                        (script:New-TestJob -Name 'Win64' -TestExeFile 'C:\Fake\Win64\App.Tests.exe')
                    )
                }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiTest -Times 2
            }

            It 'passes testExeFile to Invoke-DelphiTest for each job' {
                Mock Resolve-DelphiCiConfig {
                    script:New-MockConfig -Steps @('Test') -TestJobs @(
                        (script:New-TestJob -Name 'Win32' -TestExeFile 'C:\Fake\Win32\App.Tests.exe'),
                        (script:New-TestJob -Name 'Win64' -TestExeFile 'C:\Fake\Win64\App.Tests.exe')
                    )
                }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiTest -ParameterFilter { $TestExeFile -eq 'C:\Fake\Win32\App.Tests.exe' }
                Should -Invoke Invoke-DelphiTest -ParameterFilter { $TestExeFile -eq 'C:\Fake\Win64\App.Tests.exe' }
            }

        }

        Context 'parameter forwarding' {

            It 'passes build job fields to Invoke-DelphiBuild' {
                $job = script:New-BuildJob
                $job.Verbosity = 'minimal'
                $job.Target = 'Rebuild'
                Mock Resolve-DelphiCiConfig {
                    script:New-MockConfig -Steps @('Build') -BuildJobs @($job)
                }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiBuild -ParameterFilter {
                    $BuildVerbosity -eq 'minimal' -and $BuildTarget -eq 'Rebuild'
                }
            }

            It 'passes test job fields to Invoke-DelphiTest' {
                $job = script:New-TestJob
                $job.TimeoutSeconds = 30
                $job.Arguments = @('--verbose')
                Mock Resolve-DelphiCiConfig {
                    script:New-MockConfig -Steps @('Test') -TestJobs @($job)
                }
                Invoke-DelphiCi
                Should -Invoke Invoke-DelphiTest -ParameterFilter {
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
