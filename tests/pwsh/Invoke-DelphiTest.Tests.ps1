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

    # ---------------------------------------------------------------------------

    Describe 'Invoke-DelphiTest -- unit' {

        BeforeAll {
            Mock Invoke-TestRunner      { script:New-RunResult }
            Mock Write-DelphiCiMessage  {}
        }

        Context 'step result shape' {

            It 'StepName is Test' {
                (Invoke-DelphiTest -TestExeFile 'C:\Fake\Tests\App.Tests.exe').StepName | Should -Be 'Test'
            }

            It 'Tool is test runner' {
                (Invoke-DelphiTest -TestExeFile 'C:\Fake\Tests\App.Tests.exe').Tool | Should -Be 'test runner'
            }

            It 'Duration is a TimeSpan' {
                (Invoke-DelphiTest -TestExeFile 'C:\Fake\Tests\App.Tests.exe').Duration | Should -BeOfType [timespan]
            }

            It 'TestExeFile is echoed back in the result' {
                (Invoke-DelphiTest -TestExeFile 'C:\Fake\Tests\App.Tests.exe').TestExeFile | Should -Be 'C:\Fake\Tests\App.Tests.exe'
            }

        }

        Context 'success and failure' {

            It 'Success is true when runner exits 0' {
                Mock Invoke-TestRunner { script:New-RunResult -Success $true }
                (Invoke-DelphiTest -TestExeFile 'C:\Fake\App.Tests.exe').Success | Should -Be $true
            }

            It 'ExitCode is 0 on success' {
                Mock Invoke-TestRunner { script:New-RunResult -Success $true }
                (Invoke-DelphiTest -TestExeFile 'C:\Fake\App.Tests.exe').ExitCode | Should -Be 0
            }

            It 'Success is false when runner exits non-zero' {
                Mock Invoke-TestRunner { script:New-RunResult -Success $false }
                (Invoke-DelphiTest -TestExeFile 'C:\Fake\App.Tests.exe').Success | Should -Be $false
            }

            It 'ExitCode reflects runner exit code on failure' {
                Mock Invoke-TestRunner { script:New-RunResult -Success $false }
                (Invoke-DelphiTest -TestExeFile 'C:\Fake\App.Tests.exe').ExitCode | Should -Be 1
            }

            It 'Message says Tests passed on success' {
                Mock Invoke-TestRunner { script:New-RunResult -Success $true }
                (Invoke-DelphiTest -TestExeFile 'C:\Fake\App.Tests.exe').Message | Should -Be 'Tests passed'
            }

            It 'Message contains exit code on failure' {
                Mock Invoke-TestRunner { script:New-RunResult -Success $false }
                (Invoke-DelphiTest -TestExeFile 'C:\Fake\App.Tests.exe').Message | Should -BeLike '*1*'
            }

        }

        Context 'WhatIf' {

            It 'does not invoke Invoke-TestRunner when -WhatIf is set' {
                Invoke-DelphiTest -TestExeFile 'C:\Fake\App.Tests.exe' -WhatIf
                Should -Invoke Invoke-TestRunner -Times 0
            }

        }

        Context 'parameter forwarding to Invoke-TestRunner' {

            It 'passes TestExeFile as TestExecutable to Invoke-TestRunner' {
                Invoke-DelphiTest -TestExeFile 'C:\Fake\App.Tests.exe'
                Should -Invoke Invoke-TestRunner -ParameterFilter {
                    $TestExecutable -eq 'C:\Fake\App.Tests.exe'
                }
            }

            It 'passes TimeoutSeconds to Invoke-TestRunner' {
                Invoke-DelphiTest -TestExeFile 'C:\Fake\App.Tests.exe' -TimeoutSeconds 5
                Should -Invoke Invoke-TestRunner -ParameterFilter { $TimeoutSeconds -eq 5 }
            }

            It 'passes Arguments to Invoke-TestRunner' {
                Invoke-DelphiTest -TestExeFile 'C:\Fake\App.Tests.exe' -Arguments @('--output', 'xml')
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
    # Keep Resolve-TestExecutable and Resolve-TestProject tests -- these private
    # helpers still exist and may be useful in other contexts.
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

}
