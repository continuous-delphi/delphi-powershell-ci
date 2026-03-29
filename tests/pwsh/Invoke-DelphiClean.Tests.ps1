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
                (Invoke-DelphiClean -Root 'C:\Fake').StepName | Should -Be 'Clean'
            }

            It 'Tool is delphi-clean.ps1' {
                (Invoke-DelphiClean -Root 'C:\Fake').Tool | Should -Be 'delphi-clean.ps1'
            }

            It 'Duration is a TimeSpan' {
                (Invoke-DelphiClean -Root 'C:\Fake').Duration | Should -BeOfType [timespan]
            }

            It 'ProjectFile is null' {
                (Invoke-DelphiClean -Root 'C:\Fake').ProjectFile | Should -BeNullOrEmpty
            }

        }

        Context 'success and failure' {

            It 'Success is true when tool exits 0' {
                Mock Invoke-BundledTool { [PSCustomObject]@{ ExitCode = 0; Success = $true } }
                (Invoke-DelphiClean -Root 'C:\Fake').Success | Should -Be $true
            }

            It 'ExitCode is 0 on success' {
                Mock Invoke-BundledTool { [PSCustomObject]@{ ExitCode = 0; Success = $true } }
                (Invoke-DelphiClean -Root 'C:\Fake').ExitCode | Should -Be 0
            }

            It 'Success is false when tool exits non-zero' {
                Mock Invoke-BundledTool { [PSCustomObject]@{ ExitCode = 1; Success = $false } }
                (Invoke-DelphiClean -Root 'C:\Fake').Success | Should -Be $false
            }

            It 'ExitCode reflects tool exit code on failure' {
                Mock Invoke-BundledTool { [PSCustomObject]@{ ExitCode = 1; Success = $false } }
                (Invoke-DelphiClean -Root 'C:\Fake').ExitCode | Should -Be 1
            }

            It 'Message says Clean completed on success' {
                Mock Invoke-BundledTool { [PSCustomObject]@{ ExitCode = 0; Success = $true } }
                (Invoke-DelphiClean -Root 'C:\Fake').Message | Should -Be 'Clean completed'
            }

            It 'Message contains exit code on failure' {
                Mock Invoke-BundledTool { [PSCustomObject]@{ ExitCode = 2; Success = $false } }
                (Invoke-DelphiClean -Root 'C:\Fake').Message | Should -BeLike '*2*'
            }

        }

        Context 'WhatIf' {

            It 'does not invoke the tool when -WhatIf is set' {
                Invoke-DelphiClean -Root 'C:\Fake' -WhatIf
                Should -Invoke Invoke-BundledTool -Times 0
            }

        }

        Context 'argument passing' {

            It 'invokes delphi-clean.ps1' {
                Invoke-DelphiClean -Root 'C:\Fake'
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $ToolName -eq 'delphi-clean.ps1'
                }
            }

            It 'passes -Level basic by default' {
                Invoke-DelphiClean -Root 'C:\Fake'
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $Arguments -contains '-Level' -and $Arguments -contains 'basic'
                }
            }

            It 'passes -Level standard when specified' {
                Invoke-DelphiClean -Root 'C:\Fake' -Level 'standard'
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $Arguments -contains '-Level' -and $Arguments -contains 'standard'
                }
            }

            It 'passes -Level deep when specified' {
                Invoke-DelphiClean -Root 'C:\Fake' -Level 'deep'
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $Arguments -contains '-Level' -and $Arguments -contains 'deep'
                }
            }

            It 'passes -RootPath matching the Root parameter' {
                Invoke-DelphiClean -Root 'C:\Fake\MyProject'
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $Arguments -contains '-RootPath' -and $Arguments -contains 'C:\Fake\MyProject'
                }
            }

            It 'does not pass -IncludeFilePattern when IncludeFiles is empty' {
                Invoke-DelphiClean -Root 'C:\Fake'
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $Arguments -notcontains '-IncludeFilePattern'
                }
            }

            It 'passes -IncludeFilePattern for each entry in IncludeFiles' {
                Invoke-DelphiClean -Root 'C:\Fake' -IncludeFiles @('*.res', '*.mab')
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $Arguments -contains '-IncludeFilePattern' -and
                    $Arguments -contains '*.res' -and
                    $Arguments -contains '*.mab'
                }
            }

            It 'does not pass -ExcludeDirPattern when ExcludeDirectories is empty' {
                Invoke-DelphiClean -Root 'C:\Fake'
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $Arguments -notcontains '-ExcludeDirPattern'
                }
            }

            It 'passes -ExcludeDirPattern for each entry in ExcludeDirectories' {
                Invoke-DelphiClean -Root 'C:\Fake' -ExcludeDirectories @('vendor', 'assets')
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $Arguments -contains '-ExcludeDirPattern' -and
                    $Arguments -contains 'vendor' -and
                    $Arguments -contains 'assets'
                }
            }

        }

    }

    Describe 'Invoke-DelphiClean -- integration' {

        It 'succeeds with level basic on real ConsoleProjectGroup source' {
            $sourceRoot = [System.IO.Path]::GetFullPath(
                (Join-Path $PSScriptRoot '..\..' 'Examples\ConsoleProjectGroup\Source')
            )
            $result = Invoke-DelphiClean -Root $sourceRoot -Level 'basic'
            $result.Success    | Should -Be $true
            $result.StepName   | Should -Be 'Clean'
            $result.ExitCode   | Should -Be 0
        }

    }

}
