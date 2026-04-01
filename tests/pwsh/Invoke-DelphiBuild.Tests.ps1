#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

Import-Module ([System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..' 'source' 'Delphi.PowerShell.CI.psm1'))) -Force

InModuleScope 'Delphi.PowerShell.CI' {

    Describe 'Invoke-DelphiBuild -- unit' {

        BeforeAll {
            Mock Invoke-BuildPipeline {
                [PSCustomObject]@{ ExitCode = 0; Success = $true; Warnings = 0; Errors = 0; ExeOutputDir = 'C:\Out\Win32\Debug'; Output = 'build output text' }
            }
            Mock Write-DelphiCiMessage {}
        }

        Context 'step result shape' {

            It 'StepName is Build' {
                (Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dproj').StepName | Should -Be 'Build'
            }

            It 'Tool is delphi-msbuild.ps1 by default' {
                (Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dproj').Tool | Should -Be 'delphi-msbuild.ps1'
            }

            It 'Tool is delphi-dccbuild.ps1 when BuildEngine is DCCBuild' {
                (Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dpr' -BuildEngine DCCBuild).Tool | Should -Be 'delphi-dccbuild.ps1'
            }

            It 'Duration is a TimeSpan' {
                (Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dproj').Duration | Should -BeOfType [timespan]
            }

            It 'ProjectFile is echoed back in the result' {
                (Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dproj').ProjectFile | Should -Be 'C:\Fake\App.dproj'
            }

            It 'Warnings is surfaced from pipeline result' {
                (Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dproj').Warnings | Should -Be 0
            }

            It 'Errors is surfaced from pipeline result' {
                (Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dproj').Errors | Should -Be 0
            }

            It 'ExeOutputDir is surfaced from pipeline result' {
                (Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dproj').ExeOutputDir | Should -Be 'C:\Out\Win32\Debug'
            }

            It 'Output is surfaced from pipeline result' {
                (Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dproj').Output | Should -Be 'build output text'
            }

        }

        Context 'success and failure' {

            It 'Success is true when pipeline exits 0' {
                Mock Invoke-BuildPipeline { [PSCustomObject]@{ ExitCode = 0; Success = $true; Warnings = 0; Errors = 0; ExeOutputDir = $null; Output = $null } }
                (Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dproj').Success | Should -Be $true
            }

            It 'ExitCode is 0 on success' {
                Mock Invoke-BuildPipeline { [PSCustomObject]@{ ExitCode = 0; Success = $true; Warnings = 0; Errors = 0; ExeOutputDir = $null; Output = $null } }
                (Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dproj').ExitCode | Should -Be 0
            }

            It 'Success is false when pipeline exits non-zero' {
                Mock Invoke-BuildPipeline { [PSCustomObject]@{ ExitCode = 5; Success = $false; Warnings = 0; Errors = 1; ExeOutputDir = $null; Output = $null } }
                (Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dproj').Success | Should -Be $false
            }

            It 'ExitCode reflects pipeline exit code on failure' {
                Mock Invoke-BuildPipeline { [PSCustomObject]@{ ExitCode = 5; Success = $false; Warnings = 0; Errors = 1; ExeOutputDir = $null; Output = $null } }
                (Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dproj').ExitCode | Should -Be 5
            }

            It 'Message says Build completed on success' {
                Mock Invoke-BuildPipeline { [PSCustomObject]@{ ExitCode = 0; Success = $true; Warnings = 0; Errors = 0; ExeOutputDir = $null; Output = $null } }
                (Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dproj').Message | Should -Be 'Build completed'
            }

            It 'Message contains exit code on failure' {
                Mock Invoke-BuildPipeline { [PSCustomObject]@{ ExitCode = 5; Success = $false; Warnings = 0; Errors = 1; ExeOutputDir = $null; Output = $null } }
                (Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dproj').Message | Should -BeLike '*5*'
            }

        }

        Context 'project file extension normalisation' {

            It 'changes .dproj to .dpr when BuildEngine is DCCBuild' {
                Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dproj' -BuildEngine DCCBuild
                Should -Invoke Invoke-BuildPipeline -ParameterFilter {
                    $BuildArgs -contains 'C:\Fake\App.dpr'
                }
            }

            It 'changes .dpr to .dproj when BuildEngine is MSBuild' {
                Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dpr'
                Should -Invoke Invoke-BuildPipeline -ParameterFilter {
                    $BuildArgs -contains 'C:\Fake\App.dproj'
                }
            }

            It 'leaves .dproj unchanged for MSBuild' {
                Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dproj'
                Should -Invoke Invoke-BuildPipeline -ParameterFilter {
                    $BuildArgs -contains 'C:\Fake\App.dproj'
                }
            }

            It 'leaves .dpr unchanged for DCCBuild' {
                Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dpr' -BuildEngine DCCBuild
                Should -Invoke Invoke-BuildPipeline -ParameterFilter {
                    $BuildArgs -contains 'C:\Fake\App.dpr'
                }
            }

        }

        Context 'WhatIf' {

            It 'does not invoke the pipeline when -WhatIf is set' {
                Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dproj' -WhatIf
                Should -Invoke Invoke-BuildPipeline -Times 0
            }

        }

        Context 'inspect args -- toolchain selection' {

            It 'uses -DetectLatest when Toolchain is Latest (default)' {
                Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dproj'
                Should -Invoke Invoke-BuildPipeline -ParameterFilter {
                    $InspectArgs -contains '-DetectLatest'
                }
            }

            It 'does not use -Locate when Toolchain is Latest' {
                Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dproj'
                Should -Invoke Invoke-BuildPipeline -ParameterFilter {
                    $InspectArgs -notcontains '-Locate'
                }
            }

            It 'uses -Locate and -Name when Toolchain is a specific version' {
                Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dproj' -Toolchain 'VER370'
                Should -Invoke Invoke-BuildPipeline -ParameterFilter {
                    $InspectArgs -contains '-Locate' -and
                    $InspectArgs -contains '-Name'   -and
                    $InspectArgs -contains 'VER370'
                }
            }

            It 'passes -Platform to inspect' {
                Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dproj' -Platform 'Win64'
                Should -Invoke Invoke-BuildPipeline -ParameterFilter {
                    $InspectArgs -contains '-Platform' -and $InspectArgs -contains 'Win64'
                }
            }

            It 'passes -BuildSystem MSBuild to inspect for MSBuild engine' {
                Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dproj' -BuildEngine MSBuild
                Should -Invoke Invoke-BuildPipeline -ParameterFilter {
                    $InspectArgs -contains '-BuildSystem' -and $InspectArgs -contains 'MSBuild'
                }
            }

            It 'passes -BuildSystem DCC to inspect for DCCBuild engine' {
                Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dpr' -BuildEngine DCCBuild
                Should -Invoke Invoke-BuildPipeline -ParameterFilter {
                    $InspectArgs -contains '-BuildSystem' -and $InspectArgs -contains 'DCC'
                }
            }

        }

        Context 'build args' {

            It 'passes -ProjectFile to build tool' {
                Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dproj'
                Should -Invoke Invoke-BuildPipeline -ParameterFilter {
                    $BuildArgs -contains '-ProjectFile' -and $BuildArgs -contains 'C:\Fake\App.dproj'
                }
            }

            It 'passes -Platform Win32 by default' {
                Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dproj'
                Should -Invoke Invoke-BuildPipeline -ParameterFilter {
                    $BuildArgs -contains '-Platform' -and $BuildArgs -contains 'Win32'
                }
            }

            It 'passes -Platform Win64 when specified' {
                Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dproj' -Platform 'Win64'
                Should -Invoke Invoke-BuildPipeline -ParameterFilter {
                    $BuildArgs -contains '-Platform' -and $BuildArgs -contains 'Win64'
                }
            }

            It 'passes -Config Debug by default' {
                Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dproj'
                Should -Invoke Invoke-BuildPipeline -ParameterFilter {
                    $BuildArgs -contains '-Config' -and $BuildArgs -contains 'Debug'
                }
            }

            It 'passes -Config Release when specified' {
                Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dproj' -Configuration 'Release'
                Should -Invoke Invoke-BuildPipeline -ParameterFilter {
                    $BuildArgs -contains '-Config' -and $BuildArgs -contains 'Release'
                }
            }

            It 'passes -ShowOutput' {
                Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dproj'
                Should -Invoke Invoke-BuildPipeline -ParameterFilter {
                    $BuildArgs -contains '-ShowOutput'
                }
            }

            It 'passes a single -Define' {
                Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dproj' -Defines @('CI')
                Should -Invoke Invoke-BuildPipeline -ParameterFilter {
                    $BuildArgs -contains '-Define' -and $BuildArgs -contains 'CI'
                }
            }

            It 'passes multiple -Define values' {
                Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dproj' -Defines @('CI', 'RELEASE_BUILD')
                Should -Invoke Invoke-BuildPipeline -ParameterFilter {
                    $BuildArgs -contains 'CI' -and $BuildArgs -contains 'RELEASE_BUILD'
                }
            }

            It 'passes no -Define args when Defines is empty' {
                Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dproj'
                Should -Invoke Invoke-BuildPipeline -ParameterFilter {
                    $BuildArgs -notcontains '-Define'
                }
            }

        }

        Context 'engine routing' {

            It 'passes Engine MSBuild to pipeline for MSBuild engine' {
                Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dproj' -BuildEngine MSBuild
                Should -Invoke Invoke-BuildPipeline -ParameterFilter {
                    $Engine -eq 'MSBuild'
                }
            }

            It 'passes Engine DCCBuild to pipeline for DCCBuild engine' {
                Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dpr' -BuildEngine DCCBuild
                Should -Invoke Invoke-BuildPipeline -ParameterFilter {
                    $Engine -eq 'DCCBuild'
                }
            }

            It 'rejects an invalid engine name' {
                { Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dproj' -BuildEngine 'Fake' } | Should -Throw
            }

        }

    }

    Describe 'Invoke-BuildPipeline -- JSON error handling' {

        BeforeAll {
            Mock Write-Error {}
        }

        It 'returns Success false when inspect output is not valid JSON' {
            Mock Invoke-BundledTool {}  # not used directly, but keep scope clean
            # Simulate inspect exiting 0 with non-JSON output by calling the
            # private function with a mock that injects garbage via pwsh args
            # -- instead, exercise via a helper that replaces the pwsh call:

            # Patch the pipeline at the pwsh level is too heavy; use InModuleScope
            # to call Invoke-BuildPipeline directly with a mocked inspect path.
            # We stub the pwsh invocation by mocking the script block it relies on.
            # The simplest hook: override $script:BundledToolsDir to a temp folder
            # containing a fake delphi-inspect.ps1 that prints garbage.

            $fakeDir = Join-Path $TestDrive 'fake-tools'
            New-Item -ItemType Directory -Path $fakeDir -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $fakeDir 'delphi-inspect.ps1') -Value 'Write-Output "not json at all"'
            Set-Content -LiteralPath (Join-Path $fakeDir 'delphi-msbuild.ps1')  -Value ''

            $saved = $script:BundledToolsDir
            $script:BundledToolsDir = $fakeDir

            try {
                $result = Invoke-BuildPipeline `
                    -InspectArgs  @('-DetectLatest', '-Platform', 'Win32', '-BuildSystem', 'MSBuild') `
                    -BuildArgs    @('-ProjectFile', 'C:\Fake\App.dproj', '-ShowOutput') `
                    -Engine       'MSBuild'
            }
            finally {
                $script:BundledToolsDir = $saved
            }

            $result.Success  | Should -Be $false
            $result.ExitCode | Should -Be 3
            Should -Invoke Write-Error -Times 1
        }

    }

    Describe 'Invoke-DelphiBuild -- integration' {

        It 'builds ConsoleProject.dproj for Win32 Debug' {
            $dproj = [System.IO.Path]::GetFullPath(
                (Join-Path $PSScriptRoot '..\..' 'Examples\ConsoleProjectGroup\Source\ConsoleProject.dproj')
            )
            $result = Invoke-DelphiBuild -ProjectFile $dproj -Platform 'Win32' -Configuration 'Debug'
            $result.Success  | Should -Be $true
            $result.StepName | Should -Be 'Build'
            $result.ExitCode | Should -Be 0
        }

    }

}
