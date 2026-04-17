#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

# Import at script scope so the module is available during Pester discovery,
# which is required for InModuleScope to resolve the module name.
Import-Module ([System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..' 'source' 'Delphi.PowerShell.CI.psm1'))) -Force

InModuleScope 'Delphi.PowerShell.CI' {

    Describe 'Invoke-DelphiClean -- unit' {

        BeforeAll {
            Mock Invoke-BundledTool {
                [PSCustomObject]@{ ExitCode = 0; Success = $true }
            }
            Mock Write-DelphiCiMessage {}
        }

        Context 'step result shape' {

            It 'StepName is Clean' {
                (Invoke-DelphiClean -CleanRoot 'C:\Fake').StepName | Should -Be 'Clean'
            }

            It 'Tool is delphi-clean.ps1' {
                (Invoke-DelphiClean -CleanRoot 'C:\Fake').Tool | Should -Be 'delphi-clean.ps1'
            }

            It 'Duration is a TimeSpan' {
                (Invoke-DelphiClean -CleanRoot 'C:\Fake').Duration | Should -BeOfType [timespan]
            }

            It 'ProjectFile is null' {
                (Invoke-DelphiClean -CleanRoot 'C:\Fake').ProjectFile | Should -BeNullOrEmpty
            }

        }

        Context 'success and failure' {

            It 'Success is true when tool exits 0' {
                Mock Invoke-BundledTool { [PSCustomObject]@{ ExitCode = 0; Success = $true } }
                (Invoke-DelphiClean -CleanRoot 'C:\Fake').Success | Should -Be $true
            }

            It 'ExitCode is 0 on success' {
                Mock Invoke-BundledTool { [PSCustomObject]@{ ExitCode = 0; Success = $true } }
                (Invoke-DelphiClean -CleanRoot 'C:\Fake').ExitCode | Should -Be 0
            }

            It 'Success is false when tool exits non-zero' {
                Mock Invoke-BundledTool { [PSCustomObject]@{ ExitCode = 1; Success = $false } }
                (Invoke-DelphiClean -CleanRoot 'C:\Fake').Success | Should -Be $false
            }

            It 'ExitCode reflects tool exit code on failure' {
                Mock Invoke-BundledTool { [PSCustomObject]@{ ExitCode = 1; Success = $false } }
                (Invoke-DelphiClean -CleanRoot 'C:\Fake').ExitCode | Should -Be 1
            }

            It 'Message says Clean completed on success' {
                Mock Invoke-BundledTool { [PSCustomObject]@{ ExitCode = 0; Success = $true } }
                (Invoke-DelphiClean -CleanRoot 'C:\Fake').Message | Should -Be 'Clean completed'
            }

            It 'Message contains exit code on failure' {
                Mock Invoke-BundledTool { [PSCustomObject]@{ ExitCode = 2; Success = $false } }
                (Invoke-DelphiClean -CleanRoot 'C:\Fake').Message | Should -BeLike '*2*'
            }

        }

        Context 'WhatIf' {

            It 'does not invoke the tool when -WhatIf is set' {
                Invoke-DelphiClean -CleanRoot 'C:\Fake' -WhatIf
                Should -Invoke Invoke-BundledTool -Times 0
            }

        }

        Context 'argument passing' {

            It 'invokes delphi-clean.ps1' {
                Invoke-DelphiClean -CleanRoot 'C:\Fake'
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $ToolName -eq 'delphi-clean.ps1'
                }
            }

            It 'passes -RootPath matching the Root parameter' {
                Invoke-DelphiClean -CleanRoot 'C:\Fake\MyProject'
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $Arguments -contains '-RootPath' -and $Arguments -contains 'C:\Fake\MyProject'
                }
            }

            It 'passes -Level basic by default' {
                Invoke-DelphiClean -CleanRoot 'C:\Fake'
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $Arguments -contains '-Level' -and $Arguments -contains 'basic'
                }
            }

            It 'passes -Level standard when CleanLevel is standard' {
                Invoke-DelphiClean -CleanRoot 'C:\Fake' -CleanLevel 'standard'
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $Arguments -contains '-Level' -and $Arguments -contains 'standard'
                }
            }

            It 'passes -Level deep when CleanLevel is deep' {
                Invoke-DelphiClean -CleanRoot 'C:\Fake' -CleanLevel 'deep'
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $Arguments -contains '-Level' -and $Arguments -contains 'deep'
                }
            }

            It 'does not pass -IncludeFilePattern when CleanIncludeFilePattern is empty' {
                Invoke-DelphiClean -CleanRoot 'C:\Fake'
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $Arguments -notcontains '-IncludeFilePattern'
                }
            }

            It 'passes -IncludeFilePattern for each entry in CleanIncludeFilePattern' {
                Invoke-DelphiClean -CleanRoot 'C:\Fake' -CleanIncludeFilePattern @('*.res', '*.mab')
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $Arguments -contains '-IncludeFilePattern' -and
                    $Arguments -contains '*.res' -and
                    $Arguments -contains '*.mab'
                }
            }

            It 'does not pass -ExcludeDirectoryPattern when CleanExcludeDirectoryPattern is empty' {
                Invoke-DelphiClean -CleanRoot 'C:\Fake'
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $Arguments -notcontains '-ExcludeDirectoryPattern'
                }
            }

            It 'passes -ExcludeDirectoryPattern for each entry in CleanExcludeDirectoryPattern' {
                Invoke-DelphiClean -CleanRoot 'C:\Fake' -CleanExcludeDirectoryPattern @('vendor', 'assets')
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $Arguments -contains '-ExcludeDirectoryPattern' -and
                    $Arguments -contains 'vendor' -and
                    $Arguments -contains 'assets'
                }
            }

            It 'does not pass -ConfigFile when CleanConfigFile is empty' {
                Invoke-DelphiClean -CleanRoot 'C:\Fake'
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $Arguments -notcontains '-ConfigFile'
                }
            }

            It 'passes -ConfigFile when CleanConfigFile is specified' {
                Invoke-DelphiClean -CleanRoot 'C:\Fake' -CleanConfigFile 'C:\ci\delphi-clean-ci.json'
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $Arguments -contains '-ConfigFile' -and
                    $Arguments -contains 'C:\ci\delphi-clean-ci.json'
                }
            }

            It 'does not pass -RecycleBin when CleanRecycleBin is omitted' {
                Invoke-DelphiClean -CleanRoot 'C:\Fake'
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $Arguments -notcontains '-RecycleBin'
                }
            }

            It 'passes -RecycleBin when CleanRecycleBin is set' {
                Invoke-DelphiClean -CleanRoot 'C:\Fake' -CleanRecycleBin
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $Arguments -contains '-RecycleBin'
                }
            }

            It 'does not pass -Check when CleanCheck is omitted' {
                Invoke-DelphiClean -CleanRoot 'C:\Fake'
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $Arguments -notcontains '-Check'
                }
            }

            It 'passes -Check when CleanCheck is set' {
                Invoke-DelphiClean -CleanRoot 'C:\Fake' -CleanCheck
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $Arguments -contains '-Check'
                }
            }

        }

    }

    Describe 'Invoke-DelphiClean -- integration' {

        It 'succeeds on real ConsoleProjectGroup source' {
            $sourceRoot = [System.IO.Path]::GetFullPath(
                (Join-Path $PSScriptRoot '..\..' 'Examples\ConsoleProjectGroup\Source')
            )
            $result = Invoke-DelphiClean -CleanRoot $sourceRoot
            $result.Success    | Should -Be $true
            $result.StepName   | Should -Be 'Clean'
            $result.ExitCode   | Should -Be 0
        }

    }

}
