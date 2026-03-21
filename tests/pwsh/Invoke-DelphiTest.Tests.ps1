#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

Import-Module ([System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..' 'source' 'Delphi.PowerShell.CI.psm1'))) -Force

InModuleScope 'Delphi.PowerShell.CI' {

    # ---------------------------------------------------------------------------
    # Shared helpers
    # ---------------------------------------------------------------------------

    function script:New-RunResult {
        param([bool]$Success = $true)
        [PSCustomObject]@{
            ExitCode = if ($Success) { 0 } else { 1 }
            Success  = $Success
            Message  = if ($Success) { 'Tests passed' } else { 'Exit code 1' }
        }
    }

    function script:New-BuildPipelineResult {
        param([bool]$Success = $true)
        [PSCustomObject]@{
            ExitCode = if ($Success) { 0 } else { 5 }
            Success  = $Success
        }
    }

    # ---------------------------------------------------------------------------

    Describe 'Invoke-DelphiTest -- unit' {

        BeforeAll {
            Mock Resolve-TestProject    { 'C:\Fake\Tests\App.Tests.dproj' }
            Mock Invoke-TestBuild       { script:New-BuildPipelineResult }
            Mock Resolve-TestExecutable { 'C:\Fake\Tests\Win32\Debug\App.Tests.exe' }
            Mock Invoke-TestRunner      { script:New-RunResult }
            Mock Write-DelphiCiMessage  {}
            Mock Resolve-DefaultPlatform { 'Win32' }
        }

        Context 'step result shape' {

            It 'StepName is Test' {
                (Invoke-DelphiTest).StepName | Should -Be 'Test'
            }

            It 'Tool is test runner' {
                (Invoke-DelphiTest).Tool | Should -Be 'test runner'
            }

            It 'Duration is a TimeSpan' {
                (Invoke-DelphiTest).Duration | Should -BeOfType [timespan]
            }

            It 'TestProjectFile is the resolved test project' {
                (Invoke-DelphiTest).TestProjectFile | Should -Be 'C:\Fake\Tests\App.Tests.dproj'
            }

            It 'TestExecutable is the resolved EXE' {
                (Invoke-DelphiTest).TestExecutable | Should -Be 'C:\Fake\Tests\Win32\Debug\App.Tests.exe'
            }

        }

        Context 'success and failure' {

            It 'Success is true when runner exits 0' {
                Mock Invoke-TestRunner { script:New-RunResult -Success $true }
                (Invoke-DelphiTest).Success | Should -Be $true
            }

            It 'ExitCode is 0 on success' {
                Mock Invoke-TestRunner { script:New-RunResult -Success $true }
                (Invoke-DelphiTest).ExitCode | Should -Be 0
            }

            It 'Success is false when runner exits non-zero' {
                Mock Invoke-TestRunner { script:New-RunResult -Success $false }
                (Invoke-DelphiTest).Success | Should -Be $false
            }

            It 'ExitCode reflects runner exit code on failure' {
                Mock Invoke-TestRunner { script:New-RunResult -Success $false }
                (Invoke-DelphiTest).ExitCode | Should -Be 1
            }

            It 'Message says Tests passed on success' {
                Mock Invoke-TestRunner { script:New-RunResult -Success $true }
                (Invoke-DelphiTest).Message | Should -Be 'Tests passed'
            }

            It 'Message contains exit code on runner failure' {
                Mock Invoke-TestRunner { script:New-RunResult -Success $false }
                (Invoke-DelphiTest).Message | Should -BeLike '*1*'
            }

        }

        Context 'build phase failure' {

            It 'returns Success false when build fails' {
                Mock Invoke-TestBuild { script:New-BuildPipelineResult -Success $false }
                (Invoke-DelphiTest).Success | Should -Be $false
            }

            It 'does not call Invoke-TestRunner when build fails' {
                Mock Invoke-TestBuild { script:New-BuildPipelineResult -Success $false }
                Invoke-DelphiTest
                Should -Invoke Invoke-TestRunner -Times 0
            }

            It 'TestExecutable is null when build fails' {
                Mock Invoke-TestBuild { script:New-BuildPipelineResult -Success $false }
                (Invoke-DelphiTest).TestExecutable | Should -BeNullOrEmpty
            }

            It 'Message mentions build failure when build fails' {
                Mock Invoke-TestBuild { script:New-BuildPipelineResult -Success $false }
                (Invoke-DelphiTest).Message | Should -BeLike 'Build failed*'
            }

        }

        Context 'build and run phase control' {

            It 'does not call Invoke-TestBuild when -Build $false' {
                Invoke-DelphiTest -Build $false
                Should -Invoke Invoke-TestBuild -Times 0
            }

            It 'does not call Invoke-TestRunner when -Run $false' {
                Invoke-DelphiTest -Run $false
                Should -Invoke Invoke-TestRunner -Times 0
            }

            It 'still calls Invoke-TestRunner when -Build $false' {
                Invoke-DelphiTest -Build $false
                Should -Invoke Invoke-TestRunner -Times 1
            }

            It 'still calls Invoke-TestBuild when -Run $false' {
                Invoke-DelphiTest -Run $false
                Should -Invoke Invoke-TestBuild -Times 1
            }

            It 'Success is true when both phases are skipped' {
                (Invoke-DelphiTest -Build $false -Run $false).Success | Should -Be $true
            }

        }

        Context 'WhatIf' {

            It 'does not invoke Invoke-TestBuild when -WhatIf is set' {
                Invoke-DelphiTest -WhatIf
                Should -Invoke Invoke-TestBuild -Times 0
            }

            It 'does not invoke Invoke-TestRunner when -WhatIf is set' {
                Invoke-DelphiTest -WhatIf
                Should -Invoke Invoke-TestRunner -Times 0
            }

        }

        Context 'project discovery' {

            It 'calls Resolve-TestProject with the given Root' {
                Invoke-DelphiTest -Root 'C:\MyProject'
                Should -Invoke Resolve-TestProject -ParameterFilter { $Root -eq 'C:\MyProject' }
            }

            It 'passes TestProjectFile to Resolve-TestProject' {
                Invoke-DelphiTest -TestProjectFile 'C:\Fake\Tests\App.Tests.dproj'
                Should -Invoke Resolve-TestProject -ParameterFilter {
                    $TestProjectFile -eq 'C:\Fake\Tests\App.Tests.dproj'
                }
            }

            It 'throws when Resolve-TestProject returns null' {
                Mock Resolve-TestProject { $null }
                { Invoke-DelphiTest } | Should -Throw
            }

        }

        Context 'parameter forwarding to Invoke-TestBuild' {

            It 'passes Platform to Invoke-TestBuild' {
                Invoke-DelphiTest -Platform 'Win64'
                Should -Invoke Invoke-TestBuild -ParameterFilter { $Platform -eq 'Win64' }
            }

            It 'passes Configuration to Invoke-TestBuild' {
                Invoke-DelphiTest -Configuration 'Release'
                Should -Invoke Invoke-TestBuild -ParameterFilter { $Configuration -eq 'Release' }
            }

            It 'passes Defines to Invoke-TestBuild' {
                Invoke-DelphiTest -Defines @('CI', 'RELEASE')
                Should -Invoke Invoke-TestBuild -ParameterFilter {
                    $Defines -contains 'CI' -and $Defines -contains 'RELEASE'
                }
            }

            It 'passes BuildEngine to Invoke-TestBuild' {
                Invoke-DelphiTest -BuildEngine DCCBuild
                Should -Invoke Invoke-TestBuild -ParameterFilter { $BuildEngine -eq 'DCCBuild' }
            }

        }

        Context 'platform auto-resolution' {

            It 'calls Resolve-DefaultPlatform when Platform is not supplied (MSBuild)' {
                Invoke-DelphiTest
                Should -Invoke Resolve-DefaultPlatform -Times 1
            }

            It 'does not call Resolve-DefaultPlatform when Platform is explicitly supplied' {
                Invoke-DelphiTest -Platform 'Win64'
                Should -Invoke Resolve-DefaultPlatform -Times 0
            }

            It 'does not call Resolve-DefaultPlatform when BuildEngine is DCCBuild' {
                Invoke-DelphiTest -BuildEngine DCCBuild
                Should -Invoke Resolve-DefaultPlatform -Times 0
            }

            It 'passes the resolved platform to Invoke-TestBuild when auto-resolved' {
                Mock Resolve-DefaultPlatform { 'Win64' }
                Invoke-DelphiTest
                Should -Invoke Invoke-TestBuild -ParameterFilter { $Platform -eq 'Win64' }
            }

            It 'passes Win32 to Invoke-TestBuild when DCCBuild and no Platform given' {
                Invoke-DelphiTest -BuildEngine DCCBuild
                Should -Invoke Invoke-TestBuild -ParameterFilter { $Platform -eq 'Win32' }
            }

        }

        Context 'explicit TestExecutable' {

            It 'does not call Resolve-TestExecutable when TestExecutable is supplied' {
                Invoke-DelphiTest -TestExecutable 'C:\Custom\App.Tests.exe'
                Should -Invoke Resolve-TestExecutable -Times 0
            }

            It 'uses the supplied TestExecutable as the resolved EXE path' {
                (Invoke-DelphiTest -TestExecutable 'C:\Custom\App.Tests.exe').TestExecutable |
                    Should -Be 'C:\Custom\App.Tests.exe'
            }

            It 'passes the supplied TestExecutable to Invoke-TestRunner' {
                Invoke-DelphiTest -TestExecutable 'C:\Custom\App.Tests.exe'
                Should -Invoke Invoke-TestRunner -ParameterFilter {
                    $TestExecutable -eq 'C:\Custom\App.Tests.exe'
                }
            }

        }

        Context 'parameter forwarding to Invoke-TestRunner' {

            It 'passes TimeoutSeconds to Invoke-TestRunner' {
                Invoke-DelphiTest -TimeoutSeconds 5
                Should -Invoke Invoke-TestRunner -ParameterFilter { $TimeoutSeconds -eq 5 }
            }

            It 'passes Arguments to Invoke-TestRunner' {
                Invoke-DelphiTest -Arguments @('--output', 'xml')
                Should -Invoke Invoke-TestRunner -ParameterFilter {
                    $Arguments -contains '--output' -and $Arguments -contains 'xml'
                }
            }

        }

    }

    # ---------------------------------------------------------------------------

    Describe 'Invoke-TestRunner -- unit' {

        It 'returns Success false when test executable does not exist' {
            $result = Invoke-TestRunner -TestExecutable 'C:\DoesNotExist\App.Tests.exe'
            $result.Success | Should -Be $false
        }

        It 'returns exit code 1 when test executable does not exist' {
            $result = Invoke-TestRunner -TestExecutable 'C:\DoesNotExist\App.Tests.exe'
            $result.ExitCode | Should -Be 1
        }

        It 'kills the process and returns Success false when timeout is exceeded' {
            # Use pwsh.exe as a slow fake test runner (sleeps 30s, timeout is 1s).
            $psExe = (Get-Command 'pwsh' -ErrorAction SilentlyContinue)?.Source
            if (-not $psExe) { Set-ItResult -Skipped -Because 'pwsh not found' }

            $fakeScript = Join-Path $TestDrive 'slow-test.ps1'
            Set-Content -LiteralPath $fakeScript -Value 'Start-Sleep -Seconds 30'

            $result = Invoke-TestRunner `
                -TestExecutable $psExe `
                -Arguments      @('-NoProfile', '-File', $fakeScript) `
                -TimeoutSeconds 1

            $result.Success | Should -Be $false
            $result.Message | Should -BeLike '*Timed out*'
        }

        It 'returns Success true when process exits 0' {
            $psExe = (Get-Command 'pwsh' -ErrorAction SilentlyContinue)?.Source
            if (-not $psExe) { Set-ItResult -Skipped -Because 'pwsh not found' }

            $fakeScript = Join-Path $TestDrive 'pass-test.ps1'
            Set-Content -LiteralPath $fakeScript -Value 'exit 0'

            $result = Invoke-TestRunner `
                -TestExecutable $psExe `
                -Arguments      @('-NoProfile', '-File', $fakeScript) `
                -TimeoutSeconds 10

            $result.Success  | Should -Be $true
            $result.ExitCode | Should -Be 0
        }

        It 'returns Success false when process exits non-zero' {
            $psExe = (Get-Command 'pwsh' -ErrorAction SilentlyContinue)?.Source
            if (-not $psExe) { Set-ItResult -Skipped -Because 'pwsh not found' }

            $fakeScript = Join-Path $TestDrive 'fail-test.ps1'
            Set-Content -LiteralPath $fakeScript -Value 'exit 2'

            $result = Invoke-TestRunner `
                -TestExecutable $psExe `
                -Arguments      @('-NoProfile', '-File', $fakeScript) `
                -TimeoutSeconds 10

            $result.Success  | Should -Be $false
            $result.ExitCode | Should -Be 2
        }

    }

    # ---------------------------------------------------------------------------

    Describe 'Resolve-TestExecutable -- unit' {

        It 'derives path as [ProjectDir]\[Platform]\[Config]\[Name].exe' {
            $result = Resolve-TestExecutable `
                -TestProjectFile 'C:\MyApp\Tests\App.Tests.dproj' `
                -Platform        'Win32' `
                -Configuration   'Debug'
            $result | Should -Be ([System.IO.Path]::Combine('C:\MyApp\Tests', 'Win32', 'Debug', 'App.Tests.exe'))
        }

        It 'uses Win64 when Platform is Win64' {
            $result = Resolve-TestExecutable `
                -TestProjectFile 'C:\App\Tests\App.Tests.dproj' `
                -Platform        'Win64' `
                -Configuration   'Debug'
            $result | Should -BeLike '*\Win64\Debug\App.Tests.exe'
        }

        It 'uses Release when Configuration is Release' {
            $result = Resolve-TestExecutable `
                -TestProjectFile 'C:\App\Tests\App.Tests.dproj' `
                -Platform        'Win32' `
                -Configuration   'Release'
            $result | Should -BeLike '*\Win32\Release\App.Tests.exe'
        }

        It 'base name comes from the .dproj file name, ignoring extension' {
            $result = Resolve-TestExecutable `
                -TestProjectFile 'C:\App\Tests\MyProject.Tests.dproj' `
                -Platform        'Win32' `
                -Configuration   'Debug'
            [System.IO.Path]::GetFileName($result) | Should -Be 'MyProject.Tests.exe'
        }

        It 'works when TestProjectFile has .dpr extension' {
            $result = Resolve-TestExecutable `
                -TestProjectFile 'C:\App\Tests\App.Tests.dpr' `
                -Platform        'Win32' `
                -Configuration   'Debug'
            [System.IO.Path]::GetFileName($result) | Should -Be 'App.Tests.exe'
        }

    }

    # ---------------------------------------------------------------------------

    Describe 'Invoke-DelphiTest -- integration' {

        It 'builds and runs ConsoleProject.Tests with -Defines CI' {
            $testDproj = [System.IO.Path]::GetFullPath(
                (Join-Path $PSScriptRoot '..\..' 'Examples\ConsoleProjectGroup\Tests\ConsoleProject.Tests.dproj')
            )
            $result = Invoke-DelphiTest `
                -TestProjectFile $testDproj `
                -Defines         CI `
                -Platform        Win32 `
                -Configuration   Debug
            $result.Success         | Should -Be $true
            $result.StepName        | Should -Be 'Test'
            $result.ExitCode        | Should -Be 0
            $result.TestProjectFile | Should -Be $testDproj
            $result.TestExecutable  | Should -Not -BeNullOrEmpty
        }

    }

}
