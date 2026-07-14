#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

Import-Module ([System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..' 'source' 'Delphi.PowerShell.CI.psm1'))) -Force

InModuleScope 'Delphi.PowerShell.CI' {

    Describe 'Invoke-DelphiCodesign -- unit' {

        BeforeAll {
            Mock Invoke-BundledTool {
                [PSCustomObject]@{ ExitCode = 0; Success = $true }
            }
            Mock Write-DelphiCiMessage {}
            Mock Get-Content {
                '{"ok":true,"command":"sign","result":{"signed":1,"failed":0,"total":1}}'
            }
            Mock Remove-Item {}
        }

        Context 'step result shape' {

            It 'StepName is CodesignSign for a Sign action' {
                (Invoke-DelphiCodesign -Action Sign -Files 'C:\Fake\app.exe').StepName | Should -Be 'CodesignSign'
            }

            It 'StepName is CodesignVerify for a Verify action' {
                (Invoke-DelphiCodesign -Action Verify -FilePath 'C:\Fake\app.exe').StepName | Should -Be 'CodesignVerify'
            }

            It 'Tool is delphi-codesign-azure.ps1' {
                (Invoke-DelphiCodesign -Action Sign -Files 'C:\Fake\app.exe').Tool | Should -Be 'delphi-codesign-azure.ps1'
            }

            It 'Duration is a TimeSpan' {
                (Invoke-DelphiCodesign -Action Sign -Files 'C:\Fake\app.exe').Duration | Should -BeOfType [timespan]
            }

            It 'Engine defaults to AzureTrustedSigning' {
                (Invoke-DelphiCodesign -Action Sign -Files 'C:\Fake\app.exe').Engine | Should -Be 'AzureTrustedSigning'
            }

        }

        Context 'input validation' {

            It 'throws when Sign has no files' {
                { Invoke-DelphiCodesign -Action Sign } | Should -Throw '*-Files*'
            }

            It 'throws when Verify has no file path' {
                { Invoke-DelphiCodesign -Action Verify } | Should -Throw '*-FilePath*'
            }

        }

        Context 'WhatIf' {

            It 'does not invoke the tool when -WhatIf is set' {
                Invoke-DelphiCodesign -Action Sign -Files 'C:\Fake\app.exe' -WhatIf
                Should -Invoke Invoke-BundledTool -Times 0
            }

        }

        Context 'Sign argument passing' {

            It 'invokes delphi-codesign-azure.ps1' {
                Invoke-DelphiCodesign -Action Sign -Files 'C:\Fake\app.exe'
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $ToolName -eq 'delphi-codesign-azure.ps1'
                }
            }

            It 'passes -Sign and -Files' {
                Invoke-DelphiCodesign -Action Sign -Files @('C:\Fake\a.exe', 'C:\Fake\b.exe')
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $Arguments -contains '-Sign' -and
                    $Arguments -contains '-Files' -and
                    $Arguments -contains 'C:\Fake\a.exe,C:\Fake\b.exe'
                }
            }

            It 'passes -DlibPath, -MetadataPath, and -EnvFile when provided' {
                Invoke-DelphiCodesign -Action Sign -Files 'C:\Fake\app.exe' `
                    -CodesignDlibPath 'C:\Fake\Dlib.dll' `
                    -CodesignMetadataPath 'C:\Fake\metadata.json' `
                    -CodesignEnvFile 'C:\Fake\.env'
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $Arguments -contains '-DlibPath' -and
                    $Arguments -contains 'C:\Fake\Dlib.dll' -and
                    $Arguments -contains '-MetadataPath' -and
                    $Arguments -contains 'C:\Fake\metadata.json' -and
                    $Arguments -contains '-EnvFile' -and
                    $Arguments -contains 'C:\Fake\.env'
                }
            }

            It 'always passes -OutputFile' {
                Invoke-DelphiCodesign -Action Sign -Files 'C:\Fake\app.exe'
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $Arguments -contains '-OutputFile'
                }
            }

        }

        Context 'Verify argument passing' {

            It 'passes -Verify and -FilePath' {
                Invoke-DelphiCodesign -Action Verify -FilePath 'C:\Fake\app.exe'
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $Arguments -contains '-Verify' -and
                    $Arguments -contains '-FilePath' -and
                    $Arguments -contains 'C:\Fake\app.exe'
                }
            }

            It 'passes -SignToolPath when provided (valid for the Verify parameter set)' {
                Invoke-DelphiCodesign -Action Verify -FilePath 'C:\Fake\app.exe' -CodesignSignToolPath 'C:\Fake\signtool.exe'
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $Arguments -contains '-SignToolPath' -and
                    $Arguments -contains 'C:\Fake\signtool.exe'
                }
            }

            # Regression: issue #13. The bundled tool scopes -DlibPath/-MetadataPath/-EnvFile
            # to its Sign parameter set. When a Verify job inherits those values (e.g. from
            # action-level codesign defaults), the wrapper must NOT forward them, otherwise the
            # tool fails with "Parameter set cannot be resolved".
            It 'does NOT pass Sign-only params on a Verify call even when they are set' {
                Invoke-DelphiCodesign -Action Verify -FilePath 'C:\Fake\app.exe' `
                    -CodesignDlibPath 'C:\Fake\Dlib.dll' `
                    -CodesignMetadataPath 'C:\Fake\metadata.json' `
                    -CodesignEnvFile 'C:\Fake\.env'
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $Arguments -notcontains '-DlibPath' -and
                    $Arguments -notcontains '-MetadataPath' -and
                    $Arguments -notcontains '-EnvFile'
                }
            }

        }

        Context 'success and failure' {

            It 'Success is true when the tool reports ok' {
                (Invoke-DelphiCodesign -Action Sign -Files 'C:\Fake\app.exe').Success | Should -Be $true
            }

            It 'Success is false when the tool reports not ok' {
                Mock Get-Content { '{"ok":false,"command":"sign","result":{"signed":0,"failed":1,"total":1}}' }
                (Invoke-DelphiCodesign -Action Sign -Files 'C:\Fake\app.exe').Success | Should -Be $false
            }

        }

    }

}
