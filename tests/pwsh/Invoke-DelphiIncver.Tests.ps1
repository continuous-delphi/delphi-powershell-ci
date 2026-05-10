#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

# Import at script scope so the module is available during Pester discovery,
# which is required for InModuleScope to resolve the module name.
Import-Module ([System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..' 'source' 'Delphi.PowerShell.CI.psm1'))) -Force

InModuleScope 'Delphi.PowerShell.CI' {

    Describe 'Invoke-DelphiIncver -- unit' {

        BeforeAll {
            Mock Invoke-BundledTool {
                [PSCustomObject]@{ ExitCode = 0; Success = $true }
            }
            Mock Write-DelphiCiMessage {}
            Mock Get-Content { '{"oldVersion":"1.0.0","newVersion":"1.0.1"}' }
            Mock Remove-Item {}
        }

        Context 'step result shape' {

            It 'StepName is IncVer' {
                (Invoke-DelphiIncver -File 'C:\Fake\version.rc').StepName | Should -Be 'IncVer'
            }

            It 'Tool is delphi-incver.ps1' {
                (Invoke-DelphiIncver -File 'C:\Fake\version.rc').Tool | Should -Be 'delphi-incver.ps1'
            }

            It 'Duration is a TimeSpan' {
                (Invoke-DelphiIncver -File 'C:\Fake\version.rc').Duration | Should -BeOfType [timespan]
            }

            It 'File matches the input path' {
                (Invoke-DelphiIncver -File 'C:\Fake\version.rc').File | Should -Be 'C:\Fake\version.rc'
            }

            It 'OldVersion is populated from result file' {
                (Invoke-DelphiIncver -File 'C:\Fake\version.rc').OldVersion | Should -Be '1.0.0'
            }

            It 'NewVersion is populated from result file' {
                (Invoke-DelphiIncver -File 'C:\Fake\version.rc').NewVersion | Should -Be '1.0.1'
            }

        }

        Context 'success and failure' {

            It 'Success is true when tool exits 0' {
                Mock Invoke-BundledTool { [PSCustomObject]@{ ExitCode = 0; Success = $true } }
                (Invoke-DelphiIncver -File 'C:\Fake\version.rc').Success | Should -Be $true
            }

            It 'ExitCode is 0 on success' {
                Mock Invoke-BundledTool { [PSCustomObject]@{ ExitCode = 0; Success = $true } }
                (Invoke-DelphiIncver -File 'C:\Fake\version.rc').ExitCode | Should -Be 0
            }

            It 'Success is false when tool exits non-zero' {
                Mock Invoke-BundledTool { [PSCustomObject]@{ ExitCode = 4; Success = $false } }
                (Invoke-DelphiIncver -File 'C:\Fake\version.rc').Success | Should -Be $false
            }

            It 'ExitCode reflects tool exit code on failure' {
                Mock Invoke-BundledTool { [PSCustomObject]@{ ExitCode = 4; Success = $false } }
                (Invoke-DelphiIncver -File 'C:\Fake\version.rc').ExitCode | Should -Be 4
            }

            It 'Message contains version transition on success' {
                Mock Invoke-BundledTool { [PSCustomObject]@{ ExitCode = 0; Success = $true } }
                (Invoke-DelphiIncver -File 'C:\Fake\version.rc').Message | Should -BeLike '*1.0.0*1.0.1*'
            }

            It 'Message contains exit code on failure' {
                Mock Invoke-BundledTool { [PSCustomObject]@{ ExitCode = 5; Success = $false } }
                (Invoke-DelphiIncver -File 'C:\Fake\version.rc').Message | Should -BeLike '*5*'
            }

        }

        Context 'WhatIf' {

            It 'does not invoke the tool when -WhatIf is set' {
                Invoke-DelphiIncver -File 'C:\Fake\version.rc' -WhatIf
                Should -Invoke Invoke-BundledTool -Times 0
            }

        }

        Context 'argument passing' {

            It 'invokes delphi-incver.ps1' {
                Invoke-DelphiIncver -File 'C:\Fake\version.rc'
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $ToolName -eq 'delphi-incver.ps1'
                }
            }

            It 'passes -File matching the File parameter' {
                Invoke-DelphiIncver -File 'C:\Fake\version.rc'
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $Arguments -contains '-File' -and $Arguments -contains 'C:\Fake\version.rc'
                }
            }

            It 'always passes -OutputFile' {
                Invoke-DelphiIncver -File 'C:\Fake\version.rc'
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $Arguments -contains '-OutputFile'
                }
            }

            It 'does not pass -Target when IncverTarget is empty' {
                Invoke-DelphiIncver -File 'C:\Fake\version.rc'
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $Arguments -notcontains '-Target'
                }
            }

            It 'passes -Target when IncverTarget is set' {
                Invoke-DelphiIncver -File 'C:\Fake\version.rc' -IncverTarget 'RC'
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $Arguments -contains '-Target' -and $Arguments -contains 'RC'
                }
            }

            It 'does not pass -Style when IncverStyle is empty' {
                Invoke-DelphiIncver -File 'C:\Fake\version.rc'
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $Arguments -notcontains '-Style'
                }
            }

            It 'passes -Style when IncverStyle is set' {
                Invoke-DelphiIncver -File 'C:\Fake\version.rc' -IncverStyle 'WinVer'
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $Arguments -contains '-Style' -and $Arguments -contains 'WinVer'
                }
            }

            It 'does not pass -Part when IncverPart is empty' {
                Invoke-DelphiIncver -File 'C:\Fake\version.rc'
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $Arguments -notcontains '-Part'
                }
            }

            It 'passes -Part when IncverPart is set' {
                Invoke-DelphiIncver -File 'C:\Fake\version.rc' -IncverPart 'minor'
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $Arguments -contains '-Part' -and $Arguments -contains 'minor'
                }
            }

            It 'does not pass -Pattern when IncverPattern is empty' {
                Invoke-DelphiIncver -File 'C:\Fake\tool.ps1'
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $Arguments -notcontains '-Pattern'
                }
            }

            It 'passes -Pattern when IncverPattern is set' {
                $pat = 'ToolVersion\s*=\s*''([^'']+)'''
                Invoke-DelphiIncver -File 'C:\Fake\tool.ps1' -IncverPattern $pat
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $Arguments -contains '-Pattern' -and $Arguments -contains $pat
                }
            }

        }

        Context 'cleanup' {

            It 'removes the temp result file after success' {
                Invoke-DelphiIncver -File 'C:\Fake\version.rc'
                Should -Invoke Remove-Item -Times 1
            }

            It 'removes the temp result file after failure' {
                Mock Invoke-BundledTool { [PSCustomObject]@{ ExitCode = 4; Success = $false } }
                Invoke-DelphiIncver -File 'C:\Fake\version.rc'
                Should -Invoke Remove-Item -Times 1
            }

        }

    }

}
