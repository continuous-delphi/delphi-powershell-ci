#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

Import-Module ([System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..' 'source' 'Delphi.PowerShell.CI.psm1'))) -Force

InModuleScope 'Delphi.PowerShell.CI' {

    Describe 'Invoke-DelphiCallGraph -- unit' {

        BeforeAll {
            Mock Invoke-BundledTool {
                [PSCustomObject]@{ ExitCode = 0; Success = $true }
            }
            Mock Write-DelphiCiMessage {}
            Mock Get-Content {
                '{"engine":"radCallGraph","inputs":["C:\\Fake\\source"],"success":true,"formats":["json","dot"],"files":{"json":"C:\\Fake\\callgraph\\callgraph.json","dot":"C:\\Fake\\callgraph\\callgraph.dot"}}'
            }
            Mock Remove-Item {}
        }

        Context 'step result shape' {

            It 'StepName is CallGraph' {
                (Invoke-DelphiCallGraph -CallGraphPath 'C:\Fake\source').StepName | Should -Be 'CallGraph'
            }

            It 'Tool is delphi-callgraph.ps1' {
                (Invoke-DelphiCallGraph -CallGraphPath 'C:\Fake\source').Tool | Should -Be 'delphi-callgraph.ps1'
            }

            It 'Duration is a TimeSpan' {
                (Invoke-DelphiCallGraph -CallGraphPath 'C:\Fake\source').Duration | Should -BeOfType [timespan]
            }

            It 'Engine defaults to radCallGraph' {
                (Invoke-DelphiCallGraph -CallGraphPath 'C:\Fake\source').Engine | Should -Be 'radCallGraph'
            }

            It 'Formats are populated from result file' {
                (Invoke-DelphiCallGraph -CallGraphPath 'C:\Fake\source').Formats | Should -Contain 'dot'
            }

        }

        Context 'success and failure' {

            It 'Success is true when tool exits 0' {
                Mock Invoke-BundledTool { [PSCustomObject]@{ ExitCode = 0; Success = $true } }
                (Invoke-DelphiCallGraph -CallGraphPath 'C:\Fake\source').Success | Should -Be $true
            }

            It 'ExitCode reflects tool exit code on failure' {
                Mock Invoke-BundledTool { [PSCustomObject]@{ ExitCode = 5; Success = $false } }
                (Invoke-DelphiCallGraph -CallGraphPath 'C:\Fake\source').ExitCode | Should -Be 5
            }

            It 'throws when no path or project file is provided' {
                { Invoke-DelphiCallGraph } | Should -Throw '*CallGraphPath*CallGraphProjectFile*'
            }

        }

        Context 'WhatIf' {

            It 'does not invoke the tool when -WhatIf is set' {
                Invoke-DelphiCallGraph -CallGraphPath 'C:\Fake\source' -WhatIf
                Should -Invoke Invoke-BundledTool -Times 0
            }

        }

        Context 'argument passing' {

            It 'invokes delphi-callgraph.ps1' {
                Invoke-DelphiCallGraph -CallGraphPath 'C:\Fake\source'
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $ToolName -eq 'delphi-callgraph.ps1'
                }
            }

            It 'passes -Path and -Formats' {
                Invoke-DelphiCallGraph -CallGraphPath 'C:\Fake\source' -CallGraphFormats @('json', 'dot')
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $Arguments -contains '-Path' -and
                    $Arguments -contains 'C:\Fake\source' -and
                    $Arguments -contains '-Formats' -and
                    $Arguments -contains 'json,dot'
                }
            }

            It 'passes project file for DCC mode' {
                Invoke-DelphiCallGraph -CallGraphEngine DCC -CallGraphProjectFile 'C:\Fake\App.dpr' -CallGraphFormats dot
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $Arguments -contains '-ProjectFile' -and
                    $Arguments -contains 'C:\Fake\App.dpr'
                }
            }

            It 'passes PasDoc graph options' {
                Invoke-DelphiCallGraph -CallGraphPath 'C:\Fake\source' -CallGraphEngine PasDoc -CallGraphGraphKind all -CallGraphGraphVizUses $true
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $Arguments -contains '-GraphKind' -and
                    $Arguments -contains 'all' -and
                    $Arguments -contains '-GraphVizUses'
                }
            }

            It 'passes engine arguments through environment variable' {
                Invoke-DelphiCallGraph -CallGraphPath 'C:\Fake\source' -CallGraphEngineArguments @('--fake-option')
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $env:DELPHI_CALLGRAPH_ENGINE_ARGS -eq '--fake-option'
                }
            }

            It 'always passes -OutputFile' {
                Invoke-DelphiCallGraph -CallGraphPath 'C:\Fake\source'
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $Arguments -contains '-OutputFile'
                }
            }

        }

    }

}
