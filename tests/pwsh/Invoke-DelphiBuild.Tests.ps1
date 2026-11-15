#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

Import-Module ([System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..' 'source' 'Delphi.PowerShell.CI.psm1'))) -Force

InModuleScope 'Delphi.PowerShell.CI' {

    Describe 'Invoke-DelphiBuild -- unit' {

        BeforeAll {
            # Hints is deliberately NON-ZERO here. Every other count in this mock is 0, so a
            # surfacing test that asserted 0 would pass just as well if the value came from the
            # -WhatIf default object instead of the pipeline result -- which is the one failure
            # mode 'is surfaced from pipeline result' is supposed to rule out.
            Mock Invoke-BuildPipeline {
                [PSCustomObject]@{ ExitCode = 0; Success = $true; Hints = 2; Warnings = 0; Errors = 0; ExeOutputDir = 'C:\Out\Win32\Debug'; Output = 'build output text' }
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

            It 'Hints is surfaced from pipeline result' {
                (Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dproj').Hints | Should -Be 2
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
                Mock Invoke-BuildPipeline { [PSCustomObject]@{ ExitCode = 0; Success = $true; Hints = 0; Warnings = 0; Errors = 0; ExeOutputDir = $null; Output = $null } }
                (Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dproj').Success | Should -Be $true
            }

            It 'ExitCode is 0 on success' {
                Mock Invoke-BuildPipeline { [PSCustomObject]@{ ExitCode = 0; Success = $true; Hints = 0; Warnings = 0; Errors = 0; ExeOutputDir = $null; Output = $null } }
                (Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dproj').ExitCode | Should -Be 0
            }

            It 'Success is false when pipeline exits non-zero' {
                Mock Invoke-BuildPipeline { [PSCustomObject]@{ ExitCode = 5; Success = $false; Hints = 0; Warnings = 0; Errors = 1; ExeOutputDir = $null; Output = $null } }
                (Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dproj').Success | Should -Be $false
            }

            It 'ExitCode reflects pipeline exit code on failure' {
                Mock Invoke-BuildPipeline { [PSCustomObject]@{ ExitCode = 5; Success = $false; Hints = 0; Warnings = 0; Errors = 1; ExeOutputDir = $null; Output = $null } }
                (Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dproj').ExitCode | Should -Be 5
            }

            It 'Message says Build completed on success' {
                Mock Invoke-BuildPipeline { [PSCustomObject]@{ ExitCode = 0; Success = $true; Hints = 0; Warnings = 0; Errors = 0; ExeOutputDir = $null; Output = $null } }
                (Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dproj').Message | Should -Be 'Build completed'
            }

            It 'Message contains exit code on failure' {
                Mock Invoke-BuildPipeline { [PSCustomObject]@{ ExitCode = 5; Success = $false; Hints = 0; Warnings = 0; Errors = 1; ExeOutputDir = $null; Output = $null } }
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

            # The declined-ShouldProcess path builds its own stand-in result. The module runs
            # under Set-StrictMode -Version Latest, so a count missing from that literal throws
            # at the return statement -- which is why every count is asserted here and not just
            # the new one.
            It 'still returns every diagnostic count when -WhatIf is set' {
                $result = Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dproj' -WhatIf
                $result.Hints    | Should -Be 0
                $result.Warnings | Should -Be 0
                $result.Errors   | Should -Be 0
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

        Context 'explicit toolchain root' {

            It 'forwards -ToolchainRootDir to the pipeline as ExplicitRootDir' {
                Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dproj' -ToolchainRootDir 'C:\Portable\D28'
                Should -Invoke Invoke-BuildPipeline -ParameterFilter {
                    $ExplicitRootDir -eq 'C:\Portable\D28'
                }
            }

            It 'does not build or pass InspectArgs when ToolchainRootDir is set' {
                Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dproj' -ToolchainRootDir 'C:\Portable\D28'
                Should -Invoke Invoke-BuildPipeline -ParameterFilter {
                    $null -eq $InspectArgs -or $InspectArgs.Count -eq 0
                }
            }

            It 'does not pass ExplicitRootDir when ToolchainRootDir is absent' {
                Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dproj'
                Should -Invoke Invoke-BuildPipeline -ParameterFilter {
                    [string]::IsNullOrEmpty($ExplicitRootDir)
                }
            }

            It 'still passes InspectArgs when ToolchainRootDir is absent' {
                Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dproj'
                Should -Invoke Invoke-BuildPipeline -ParameterFilter {
                    $InspectArgs -contains '-DetectLatest'
                }
            }

            It 'warns when both -ToolchainRootDir and a specific -Toolchain are supplied' {
                Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dproj' -ToolchainRootDir 'C:\Portable\D28' -Toolchain 'VER370'
                Should -Invoke Write-DelphiCiMessage -ParameterFilter { $Level -eq 'WARN' }
            }

            It 'does not warn when -ToolchainRootDir is supplied with default Toolchain' {
                Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dproj' -ToolchainRootDir 'C:\Portable\D28'
                Should -Invoke Write-DelphiCiMessage -Times 0 -ParameterFilter { $Level -eq 'WARN' }
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

            It 'passes -ExeOutputDir when specified' {
                Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dproj' -ExeOutputDir 'C:\Out\Bin'
                Should -Invoke Invoke-BuildPipeline -ParameterFilter {
                    $BuildArgs -contains '-ExeOutputDir' -and $BuildArgs -contains 'C:\Out\Bin'
                }
            }

            It 'does not pass -ExeOutputDir when omitted' {
                Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dproj'
                Should -Invoke Invoke-BuildPipeline -ParameterFilter {
                    $BuildArgs -notcontains '-ExeOutputDir'
                }
            }

            It 'passes -Verbosity normal by default' {
                Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dproj'
                Should -Invoke Invoke-BuildPipeline -ParameterFilter {
                    $BuildArgs -contains '-Verbosity' -and $BuildArgs -contains 'normal'
                }
            }

            It 'passes -Verbosity minimal when specified' {
                Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dproj' -BuildVerbosity 'minimal'
                Should -Invoke Invoke-BuildPipeline -ParameterFilter {
                    $BuildArgs -contains '-Verbosity' -and $BuildArgs -contains 'minimal'
                }
            }

            It 'passes -Verbosity diagnostic unchanged for MSBuild' {
                Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dproj' -BuildVerbosity 'diagnostic'
                Should -Invoke Invoke-BuildPipeline -ParameterFilter {
                    $BuildArgs -contains '-Verbosity' -and $BuildArgs -contains 'diagnostic'
                }
            }

            It 'passes -Target Build by default' {
                Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dproj'
                Should -Invoke Invoke-BuildPipeline -ParameterFilter {
                    $BuildArgs -contains '-Target' -and $BuildArgs -contains 'Build'
                }
            }

            It 'passes -Target Rebuild when specified' {
                Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dproj' -BuildTarget 'Rebuild'
                Should -Invoke Invoke-BuildPipeline -ParameterFilter {
                    $BuildArgs -contains '-Target' -and $BuildArgs -contains 'Rebuild'
                }
            }

            It 'passes -Target Clean when specified for MSBuild' {
                Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dproj' -BuildTarget 'Clean'
                Should -Invoke Invoke-BuildPipeline -ParameterFilter {
                    $BuildArgs -contains '-Target' -and $BuildArgs -contains 'Clean'
                }
            }

            It 'rejects -BuildTarget Clean for DCCBuild engine' {
                { Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dpr' -BuildEngine DCCBuild -BuildTarget 'Clean' } |
                    Should -Throw -ExpectedMessage '*Clean*DCCBuild*'
            }

            It 'does not pass -UnitSearchPath when omitted' {
                Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dproj'
                Should -Invoke Invoke-BuildPipeline -ParameterFilter {
                    $BuildArgs -notcontains '-UnitSearchPath'
                }
            }

            It 'passes a single -UnitSearchPath' {
                Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dproj' -UnitSearchPath @('C:\Libs\A')
                Should -Invoke Invoke-BuildPipeline -ParameterFilter {
                    $BuildArgs -contains '-UnitSearchPath' -and $BuildArgs -contains 'C:\Libs\A'
                }
            }

            It 'passes multiple -UnitSearchPath values' {
                Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dproj' -UnitSearchPath @('C:\Libs\A', 'C:\Libs\B')
                Should -Invoke Invoke-BuildPipeline -ParameterFilter {
                    $BuildArgs -contains 'C:\Libs\A' -and $BuildArgs -contains 'C:\Libs\B'
                }
            }

            It 'passes -DcuOutputDir when specified' {
                Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dproj' -DcuOutputDir 'C:\Out\Dcu'
                Should -Invoke Invoke-BuildPipeline -ParameterFilter {
                    $BuildArgs -contains '-DcuOutputDir' -and $BuildArgs -contains 'C:\Out\Dcu'
                }
            }

            It 'does not pass -DcuOutputDir when omitted' {
                Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dproj'
                Should -Invoke Invoke-BuildPipeline -ParameterFilter {
                    $BuildArgs -notcontains '-DcuOutputDir'
                }
            }

            It 'does not pass -IncludePath when omitted' {
                Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dproj'
                Should -Invoke Invoke-BuildPipeline -ParameterFilter {
                    $BuildArgs -notcontains '-IncludePath'
                }
            }

            It 'passes -IncludePath for each entry (DCCBuild)' {
                Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dpr' -BuildEngine DCCBuild -IncludePath @('C:\Inc\A', 'C:\Inc\B')
                Should -Invoke Invoke-BuildPipeline -ParameterFilter {
                    $BuildArgs -contains '-IncludePath' -and
                    $BuildArgs -contains 'C:\Inc\A' -and $BuildArgs -contains 'C:\Inc\B'
                }
            }

            It 'rejects -IncludePath for MSBuild engine' {
                { Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dproj' -IncludePath @('C:\Inc\A') } |
                    Should -Throw -ExpectedMessage '*IncludePath*DCCBuild*'
            }

            It 'does not pass -Namespace when omitted' {
                Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dproj'
                Should -Invoke Invoke-BuildPipeline -ParameterFilter {
                    $BuildArgs -notcontains '-Namespace'
                }
            }

            It 'passes -Namespace for each entry (DCCBuild)' {
                Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dpr' -BuildEngine DCCBuild -Namespace @('System', 'Vcl')
                Should -Invoke Invoke-BuildPipeline -ParameterFilter {
                    $BuildArgs -contains '-Namespace' -and
                    $BuildArgs -contains 'System' -and $BuildArgs -contains 'Vcl'
                }
            }

            It 'rejects -Namespace for MSBuild engine' {
                { Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dproj' -Namespace @('System') } |
                    Should -Throw -ExpectedMessage '*Namespace*DCCBuild*'
            }

            It 'does not pass -NoConfig when omitted' {
                Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dpr' -BuildEngine DCCBuild
                Should -Invoke Invoke-BuildPipeline -ParameterFilter {
                    $BuildArgs -notcontains '-NoConfig'
                }
            }

            It 'passes -NoConfig when set (DCCBuild)' {
                Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dpr' -BuildEngine DCCBuild -NoConfig
                Should -Invoke Invoke-BuildPipeline -ParameterFilter {
                    $BuildArgs -contains '-NoConfig'
                }
            }

            It 'rejects -NoConfig for MSBuild engine' {
                { Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dproj' -NoConfig } |
                    Should -Throw -ExpectedMessage '*NoConfig*DCCBuild*'
            }

        }

        Context 'verbosity mapping per engine' {

            # ISSUE #26. -BuildVerbosity offers msbuild's five levels for BOTH engines, but
            # delphi-dccbuild.ps1's own ValidateSet is quiet/normal only -- dcc32 has no
            # five-level verbosity. Forwarding the other three failed the CHILD process's
            # parameter binding, and a PowerShell script that exits without setting a code
            # exits 0, so the bug these tests pin is not "the wrong verbosity reached dcc" but
            # "nothing compiled and the result said Success with no output".
            #
            # The mock records the verbosity each call actually forwarded. Reading it back from
            # a recorded list rather than from a -ParameterFilter closure is deliberate: a
            # filter scriptblock does not close over the enclosing It's loop variable, so the
            # table-driven assertions below would silently compare against $null.

            BeforeAll {
                $script:AllVerbosities  = @('quiet', 'minimal', 'normal', 'detailed', 'diagnostic')
                $script:ForwardedVerb   = [System.Collections.Generic.List[string]]::new()

                Mock Invoke-BuildPipeline {
                    $i = [array]::IndexOf($BuildArgs, '-Verbosity')
                    $script:ForwardedVerb.Add($(if ($i -ge 0) { $BuildArgs[$i + 1] } else { '<absent>' }))
                    [PSCustomObject]@{ ExitCode = 0; Success = $true; Hints = 2; Warnings = 0; Errors = 0; ExeOutputDir = 'C:\Out\Win32\Debug'; Output = 'build output text' }
                }
            }

            BeforeEach { $script:ForwardedVerb.Clear() }

            It 'maps DCCBuild minimal to quiet' {
                Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dpr' -BuildEngine DCCBuild -BuildVerbosity 'minimal' | Out-Null
                $script:ForwardedVerb[0] | Should -Be 'quiet'
            }

            It 'maps DCCBuild detailed to normal' {
                Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dpr' -BuildEngine DCCBuild -BuildVerbosity 'detailed' | Out-Null
                $script:ForwardedVerb[0] | Should -Be 'normal'
            }

            It 'maps DCCBuild diagnostic to normal' {
                Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dpr' -BuildEngine DCCBuild -BuildVerbosity 'diagnostic' | Out-Null
                $script:ForwardedVerb[0] | Should -Be 'normal'
            }

            It 'leaves DCCBuild quiet unchanged' {
                Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dpr' -BuildEngine DCCBuild -BuildVerbosity 'quiet' | Out-Null
                $script:ForwardedVerb[0] | Should -Be 'quiet'
            }

            It 'leaves DCCBuild normal unchanged' {
                Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dpr' -BuildEngine DCCBuild -BuildVerbosity 'normal' | Out-Null
                $script:ForwardedVerb[0] | Should -Be 'normal'
            }

            It 'forwards only values the real DCC tool accepts, for every value in the module ValidateSet' {
                # THE REGRESSION TEST FOR #26, and the one that fails if a sixth level is added
                # to -BuildVerbosity without extending the mapping switch. The accepted set is
                # read from delphi-dccbuild.ps1's own parameter metadata rather than hard-coded,
                # so the two sides cannot drift apart unnoticed: this is exactly the mismatch
                # that produced the silent success.
                $dccAccepts = (Get-Command (Join-Path $script:BundledToolsDir 'delphi-dccbuild.ps1')).Parameters['Verbosity'].Attributes |
                    Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] } |
                    ForEach-Object { $_.ValidValues }
                @($dccAccepts) | Should -Not -BeNullOrEmpty -Because 'the DCC tool must declare a Verbosity ValidateSet'

                foreach ($v in $script:AllVerbosities) {
                    $script:ForwardedVerb.Clear()
                    Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dpr' -BuildEngine DCCBuild -BuildVerbosity $v | Out-Null
                    $script:ForwardedVerb[0] | Should -BeIn $dccAccepts -Because "-BuildVerbosity '$v' must reach the DCC tool as a value it can bind"
                }
            }

            It 'forwards every module verbosity verbatim for the MSBuild engine' {
                # The mapping must not leak into MSBuild, whose tool accepts all five natively.
                foreach ($v in $script:AllVerbosities) {
                    $script:ForwardedVerb.Clear()
                    Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dproj' -BuildEngine MSBuild -BuildVerbosity $v | Out-Null
                    $script:ForwardedVerb[0] | Should -Be $v
                }
            }

            It 'returns a result carrying the build output for every verbosity under DCCBuild' {
                # The acceptance criterion as the CALLER sees it: the three previously broken
                # values must produce a result that came from the build, not the all-zero,
                # no-output shape of a build that never ran.
                foreach ($v in $script:AllVerbosities) {
                    $result = Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dpr' -BuildEngine DCCBuild -BuildVerbosity $v
                    $result.Success | Should -Be $true          -Because "verbosity '$v' must reach the DCC tool"
                    $result.Output  | Should -Be 'build output text' -Because "verbosity '$v' must not silently skip the build"
                    $result.Hints   | Should -Be 2              -Because "verbosity '$v' must surface real counts, not a zeroed stand-in"
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

    Describe 'Invoke-BuildPipeline -- explicit root' {

        BeforeAll {
            Mock Write-Error {}
        }

        It 'fails fast with a clear error when the explicit rootDir does not exist' {
            $missing = Join-Path $TestDrive 'no-such-root'

            $result = Invoke-BuildPipeline `
                -BuildArgs       @('-ProjectFile', 'C:\Fake\App.dproj', '-ShowOutput') `
                -Engine          'MSBuild' `
                -ExplicitRootDir $missing

            $result.Success  | Should -Be $false
            $result.ExitCode | Should -Be 3
            Should -Invoke Write-Error -Times 1 -ParameterFilter { $Message -like '*rootDir does not exist*' }
        }

        It 'skips the inspect subprocess and passes the explicit root to the build tool' {
            $fakeDir = Join-Path $TestDrive 'explicit-tools'
            New-Item -ItemType Directory -Path $fakeDir -Force | Out-Null

            # A fake inspect that would leave a marker if it were ever invoked.
            $marker = Join-Path $TestDrive 'inspect-was-called.txt'
            Set-Content -LiteralPath (Join-Path $fakeDir 'delphi-inspect.ps1') `
                -Value "Set-Content -LiteralPath '$marker' -Value 'called'; Write-Output '{}'"

            # A fake build tool that records the -RootDir it received. It must also write the
            # result file: since #26 a tool that writes none is a failure regardless of its
            # exit code, so a fake that skips it is no longer a stand-in for a real build.
            $rootArgFile = Join-Path $TestDrive 'build-rootdir.txt'
            Set-Content -LiteralPath (Join-Path $fakeDir 'delphi-msbuild.ps1') -Value @"
param([string]`$RootDir, [string]`$OutputFile, [Parameter(ValueFromRemainingArguments)]`$Rest)
Set-Content -LiteralPath '$rootArgFile' -Value `$RootDir
Set-Content -LiteralPath `$OutputFile -Value '{"warnings":0,"errors":0,"output":"fake build output"}'
"@

            # The explicit root must exist (Test-Path -PathType Container).
            $explicitRoot = Join-Path $TestDrive 'portable-d28'
            New-Item -ItemType Directory -Path $explicitRoot -Force | Out-Null

            $saved = $script:BundledToolsDir
            $script:BundledToolsDir = $fakeDir
            try {
                $result = Invoke-BuildPipeline `
                    -BuildArgs       @('-ProjectFile', 'C:\Fake\App.dproj', '-ShowOutput') `
                    -Engine          'MSBuild' `
                    -ExplicitRootDir $explicitRoot
            }
            finally {
                $script:BundledToolsDir = $saved
            }

            $result.Success               | Should -Be $true
            Test-Path -LiteralPath $marker | Should -Be $false   # inspect never ran
            (Get-Content -LiteralPath $rootArgFile -Raw).Trim() | Should -Be $explicitRoot
        }

    }

    Describe 'Invoke-BuildPipeline -- diagnostic count marshalling' {

        # Exercises the REAL (unmocked) pipeline against a fake build tool that writes a result
        # JSON, which is the only way to prove the $getProp marshalling rather than a mock's
        # echo. Issue #23: `hints` is new, and the two arrangements that matter are an engine
        # that REPORTS it (delphi-dccbuild since its #21) and one that does not (delphi-msbuild,
        # which has no separate hint tally) -- the second must marshal to 0 and must not throw
        # under Set-StrictMode.

        BeforeAll {
            Mock Write-Error {}
        }

        It 'marshals hints from an engine result that carries the field' {
            $fakeDir = Join-Path $TestDrive 'hints-tools'
            New-Item -ItemType Directory -Path $fakeDir -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $fakeDir 'delphi-dccbuild.ps1') -Value @'
param([string]$RootDir, [string]$OutputFile, [Parameter(ValueFromRemainingArguments)]$Rest)
Set-Content -LiteralPath $OutputFile -Value '{"hints":3,"warnings":2,"errors":0,"exeOutputDir":"C:\\Out\\Win32","output":"compiler text"}'
'@

            $explicitRoot = Join-Path $TestDrive 'hints-root'
            New-Item -ItemType Directory -Path $explicitRoot -Force | Out-Null

            $saved = $script:BundledToolsDir
            $script:BundledToolsDir = $fakeDir
            try {
                $result = Invoke-BuildPipeline `
                    -BuildArgs       @('-ProjectFile', 'C:\Fake\App.dpr', '-ShowOutput') `
                    -Engine          'DCCBuild' `
                    -ExplicitRootDir $explicitRoot
            }
            finally {
                $script:BundledToolsDir = $saved
            }

            $result.Hints    | Should -Be 3
            $result.Warnings | Should -Be 2
            $result.Errors   | Should -Be 0
            $result.Hints    | Should -BeOfType [int]
        }

        It 'defaults hints to 0 for an engine result that omits the field' {
            $fakeDir = Join-Path $TestDrive 'nohints-tools'
            New-Item -ItemType Directory -Path $fakeDir -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $fakeDir 'delphi-msbuild.ps1') -Value @'
param([string]$RootDir, [string]$OutputFile, [Parameter(ValueFromRemainingArguments)]$Rest)
Set-Content -LiteralPath $OutputFile -Value '{"warnings":4,"errors":0,"exeOutputDir":"C:\\Out\\Win32","output":"compiler text"}'
'@

            $explicitRoot = Join-Path $TestDrive 'nohints-root'
            New-Item -ItemType Directory -Path $explicitRoot -Force | Out-Null

            $saved = $script:BundledToolsDir
            $script:BundledToolsDir = $fakeDir
            try {
                $result = Invoke-BuildPipeline `
                    -BuildArgs       @('-ProjectFile', 'C:\Fake\App.dproj', '-ShowOutput') `
                    -Engine          'MSBuild' `
                    -ExplicitRootDir $explicitRoot
            }
            finally {
                $script:BundledToolsDir = $saved
            }

            # 0 because msbuild publishes no separate hint total -- its warning count already
            # includes them -- NOT because the build had no hints. The warning count proves the
            # result file was read at all, so a 0 here is the default and not a parse failure.
            $result.Hints    | Should -Be 0
            $result.Warnings | Should -Be 4
        }

        It 'carries Hints on the failure object so a StrictMode caller can read it' {
            $missing = Join-Path $TestDrive 'no-such-root-for-hints'

            $result = Invoke-BuildPipeline `
                -BuildArgs       @('-ProjectFile', 'C:\Fake\App.dpr', '-ShowOutput') `
                -Engine          'DCCBuild' `
                -ExplicitRootDir $missing

            $result.Success | Should -Be $false
            $result.PSObject.Properties['Hints'] | Should -Not -BeNullOrEmpty
            $result.Hints | Should -Be 0
        }

    }

    Describe 'Invoke-BuildPipeline -- a tool that produced no result is a failure' {

        # ISSUE #26. This is the shape that makes EVERY unbindable-argument bug silent, so it is
        # tested directly rather than only through the verbosity case that exposed it. A .ps1 that
        # fails parameter binding never runs its body and never sets an exit code, and a
        # PowerShell process that exits without one exits 0 -- so the pipeline used to return
        # Success with $null Output and zero Hints/Warnings/Errors, indistinguishable from a
        # genuinely clean build and enough to pass a failOnWarning/failOnHint gate (#24) on a
        # project nobody compiled.

        BeforeAll {
            Mock Write-Error {}

            # Builds a fake-tools dir whose build tool behaves as described, and runs the real
            # pipeline against it with an explicit root (so no inspect subprocess is involved).
            function script:Invoke-FakeToolPipeline {
                param([string]$Name, [string]$ToolBody, [string]$Engine = 'DCCBuild')

                $fakeDir = Join-Path $TestDrive $Name
                New-Item -ItemType Directory -Path $fakeDir -Force | Out-Null
                $toolName = if ($Engine -eq 'DCCBuild') { 'delphi-dccbuild.ps1' } else { 'delphi-msbuild.ps1' }
                Set-Content -LiteralPath (Join-Path $fakeDir $toolName) -Value $ToolBody

                $root = Join-Path $TestDrive "$Name-root"
                New-Item -ItemType Directory -Path $root -Force | Out-Null

                $saved = $script:BundledToolsDir
                $script:BundledToolsDir = $fakeDir
                try {
                    Invoke-BuildPipeline `
                        -BuildArgs       @('-ProjectFile', 'C:\Fake\App.dpr', '-Verbosity', 'minimal', '-ShowOutput') `
                        -Engine          $Engine `
                        -ExplicitRootDir $root
                }
                finally { $script:BundledToolsDir = $saved }
            }
        }

        It 'fails when the child cannot bind an argument, even though the child exits 0' {
            # The #26 defect reproduced at the layer that has to catch it: a ValidateSet the
            # forwarded value is not in. No -OutputFile is written because the body never runs.
            $result = script:Invoke-FakeToolPipeline -Name 'bindfail-tools' -ToolBody @'
param(
  [string]$RootDir,
  [string]$OutputFile,
  [string]$ProjectFile,
  [ValidateSet('quiet','normal')][string]$Verbosity = 'normal',
  [switch]$ShowOutput
)
Set-Content -LiteralPath $OutputFile -Value '{"hints":0,"warnings":0,"errors":0,"output":"compiled"}'
'@

            $result.Success  | Should -Be $false
            $result.ExitCode | Should -Not -Be 0
        }

        It 'surfaces the child stderr in the error message so the cause is diagnosable' {
            script:Invoke-FakeToolPipeline -Name 'bindfail-stderr-tools' -ToolBody @'
param(
  [string]$RootDir,
  [string]$OutputFile,
  [string]$ProjectFile,
  [ValidateSet('quiet','normal')][string]$Verbosity = 'normal',
  [switch]$ShowOutput
)
Set-Content -LiteralPath $OutputFile -Value '{"warnings":0,"errors":0}'
'@ | Out-Null

            # The binding error names the offending parameter; without it the failure message
            # would say only "no result file" and leave the caller nothing to act on.
            Should -Invoke Write-Error -ParameterFilter { $Message -like "*Verbosity*" }
            Should -Invoke Write-Error -ParameterFilter { $Message -like "*no result file*" }
        }

        It 'fails when the tool writes no result file at all despite exiting 0' {
            # The general case: any tool that returns without writing -OutputFile. Exiting 0 is
            # not evidence a build happened.
            $result = script:Invoke-FakeToolPipeline -Name 'noresult-tools' -ToolBody @'
param([string]$RootDir, [string]$OutputFile, [Parameter(ValueFromRemainingArguments)]$Rest)
exit 0
'@

            $result.Success  | Should -Be $false
            $result.ExitCode | Should -Be 3
        }

        It 'fails when the result file is present but malformed' {
            $result = script:Invoke-FakeToolPipeline -Name 'badjson-tools' -ToolBody @'
param([string]$RootDir, [string]$OutputFile, [Parameter(ValueFromRemainingArguments)]$Rest)
Set-Content -LiteralPath $OutputFile -Value 'this is not json {'
'@

            $result.Success | Should -Be $false
        }

        It 'carries the full property set on the no-result failure so a StrictMode caller can read it' {
            # Invoke-DelphiBuild dereferences every count; a partial object would throw there
            # instead of here, which is why the shape is asserted at the source.
            $result = script:Invoke-FakeToolPipeline -Name 'noresult-shape-tools' -ToolBody @'
param([string]$RootDir, [string]$OutputFile, [Parameter(ValueFromRemainingArguments)]$Rest)
exit 0
'@

            foreach ($p in @('ExitCode', 'Success', 'Hints', 'Warnings', 'Errors', 'ExeOutputDir', 'Output')) {
                $result.PSObject.Properties[$p] | Should -Not -BeNullOrEmpty -Because "a StrictMode caller reads .$p"
            }
        }

        It 'keeps the child exit code when the tool failed loudly AND wrote no result' {
            # A non-zero child code is more informative than the pipeline's own 3, so it wins.
            $result = script:Invoke-FakeToolPipeline -Name 'loudfail-tools' -ToolBody @'
param([string]$RootDir, [string]$OutputFile, [Parameter(ValueFromRemainingArguments)]$Rest)
exit 9
'@

            $result.Success  | Should -Be $false
            $result.ExitCode | Should -Be 9
        }

        It 'does NOT fail a build whose result file reports empty output' {
            # EMPTINESS OF .output IS NOT THE TEST. 'quiet' legitimately produces no build
            # output -- Invoke-TestBuild passes -Verbosity quiet on every test build -- so
            # gating on empty output would fail real, clean builds. A missing result file never
            # happens on a tool that ran to completion; an empty .output routinely does.
            $result = script:Invoke-FakeToolPipeline -Name 'quietok-tools' -ToolBody @'
param([string]$RootDir, [string]$OutputFile, [Parameter(ValueFromRemainingArguments)]$Rest)
Set-Content -LiteralPath $OutputFile -Value '{"hints":0,"warnings":0,"errors":0,"output":""}'
'@

            $result.Success | Should -Be $true
            $result.Output  | Should -Be ''
        }

        It 'surfaces the no-result failure through Invoke-DelphiBuild as an unsuccessful step' {
            # End to end: the guard must reach the public result object, not just the private
            # helper, since that object is what a CI gate reads.
            $fakeDir = Join-Path $TestDrive 'public-noresult-tools'
            New-Item -ItemType Directory -Path $fakeDir -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $fakeDir 'delphi-dccbuild.ps1') -Value @'
param([string]$RootDir, [string]$OutputFile, [Parameter(ValueFromRemainingArguments)]$Rest)
exit 0
'@
            $root = Join-Path $TestDrive 'public-noresult-root'
            New-Item -ItemType Directory -Path $root -Force | Out-Null

            Mock Write-DelphiCiMessage {}

            $saved = $script:BundledToolsDir
            $script:BundledToolsDir = $fakeDir
            try {
                $result = Invoke-DelphiBuild -ProjectFile 'C:\Fake\App.dpr' -BuildEngine DCCBuild -ToolchainRootDir $root
            }
            finally { $script:BundledToolsDir = $saved }

            $result.Success  | Should -Be $false
            $result.ExitCode | Should -Not -Be 0
            Should -Invoke Write-DelphiCiMessage -ParameterFilter { $Level -eq 'ERROR' }
        }

    }

    Describe 'Invoke-BuildPipeline -- multi-value array forwarding' {

        # Exercises the REAL (unmocked) pipeline against a fake build tool that
        # records the array parameters it actually received. This proves the
        # flat -Name/value token list is forwarded so 2+ array values arrive as
        # distinct [string[]] elements rather than failing to bind (issue #15).

        BeforeAll {
            Mock Write-Error {}
        }

        It 'forwards 2+ values for each array param as distinct elements' {
            $fakeDir = Join-Path $TestDrive 'multiarray-tools'
            New-Item -ItemType Directory -Path $fakeDir -Force | Out-Null

            $recordFile = Join-Path $TestDrive 'received-arrays.json'

            # Fake dccbuild that captures its [string[]] params to JSON. Escape
            # the record path so it survives embedding in the here-string.
            $recordLiteral = $recordFile -replace "'", "''"
            Set-Content -LiteralPath (Join-Path $fakeDir 'delphi-dccbuild.ps1') -Value @"
param(
  [string]`$RootDir,
  [string]`$OutputFile,
  [string]`$ProjectFile,
  [string[]]`$UnitSearchPath = @(),
  [string[]]`$IncludePath    = @(),
  [string[]]`$Namespace      = @(),
  [string[]]`$Define         = @(),
  [switch]`$ShowOutput
)
[PSCustomObject]@{
  unitSearchPath = `$UnitSearchPath
  includePath    = `$IncludePath
  namespace      = `$Namespace
  define         = `$Define
} | ConvertTo-Json -Compress | Set-Content -LiteralPath '$recordLiteral'
Set-Content -LiteralPath `$OutputFile -Value '{"hints":0,"warnings":0,"errors":0,"output":"fake build output"}'
"@

            $explicitRoot = Join-Path $TestDrive 'fake-root'
            New-Item -ItemType Directory -Path $explicitRoot -Force | Out-Null

            $buildArgs = @(
                '-ProjectFile', 'C:\Fake\App.dpr',
                '-UnitSearchPath', 'C:\Libs\A', '-UnitSearchPath', 'C:\Libs\B',
                '-IncludePath', 'C:\Inc\A', '-IncludePath', 'C:\Inc\B',
                '-Namespace', 'Winapi', '-Namespace', 'System', '-Namespace', 'Data',
                '-Define', 'CI', '-Define', 'RELEASE_BUILD',
                '-ShowOutput'
            )

            $saved = $script:BundledToolsDir
            $script:BundledToolsDir = $fakeDir
            try {
                $result = Invoke-BuildPipeline `
                    -BuildArgs       $buildArgs `
                    -Engine          'DCCBuild' `
                    -ExplicitRootDir $explicitRoot
            }
            finally {
                $script:BundledToolsDir = $saved
            }

            $result.Success | Should -Be $true

            $received = Get-Content -LiteralPath $recordFile -Raw | ConvertFrom-Json
            @($received.namespace)      | Should -Be @('Winapi', 'System', 'Data')
            @($received.unitSearchPath) | Should -Be @('C:\Libs\A', 'C:\Libs\B')
            @($received.includePath)    | Should -Be @('C:\Inc\A', 'C:\Inc\B')
            @($received.define)         | Should -Be @('CI', 'RELEASE_BUILD')
        }

        It 'forwards a single array value as a one-element array' {
            $fakeDir = Join-Path $TestDrive 'singlearray-tools'
            New-Item -ItemType Directory -Path $fakeDir -Force | Out-Null

            $recordFile = Join-Path $TestDrive 'received-single.json'
            $recordLiteral = $recordFile -replace "'", "''"
            Set-Content -LiteralPath (Join-Path $fakeDir 'delphi-dccbuild.ps1') -Value @"
param(
  [string]`$RootDir,
  [string]`$OutputFile,
  [string]`$ProjectFile,
  [string[]]`$Namespace = @(),
  [switch]`$ShowOutput
)
[PSCustomObject]@{ namespace = `$Namespace } | ConvertTo-Json -Compress | Set-Content -LiteralPath '$recordLiteral'
Set-Content -LiteralPath `$OutputFile -Value '{"hints":0,"warnings":0,"errors":0,"output":"fake build output"}'
"@

            $explicitRoot = Join-Path $TestDrive 'fake-root-single'
            New-Item -ItemType Directory -Path $explicitRoot -Force | Out-Null

            $saved = $script:BundledToolsDir
            $script:BundledToolsDir = $fakeDir
            try {
                $result = Invoke-BuildPipeline `
                    -BuildArgs       @('-ProjectFile', 'C:\Fake\App.dpr', '-Namespace', 'System', '-ShowOutput') `
                    -Engine          'DCCBuild' `
                    -ExplicitRootDir $explicitRoot
            }
            finally {
                $script:BundledToolsDir = $saved
            }

            $result.Success        | Should -Be $true
            $received = Get-Content -LiteralPath $recordFile -Raw | ConvertFrom-Json
            @($received.namespace) | Should -Be @('System')
        }

        It 'forwards the -NoConfig switch as a bound switch parameter' {
            $fakeDir = Join-Path $TestDrive 'noconfig-tools'
            New-Item -ItemType Directory -Path $fakeDir -Force | Out-Null

            $recordFile = Join-Path $TestDrive 'received-noconfig.json'
            $recordLiteral = $recordFile -replace "'", "''"
            Set-Content -LiteralPath (Join-Path $fakeDir 'delphi-dccbuild.ps1') -Value @"
param(
  [string]`$RootDir,
  [string]`$OutputFile,
  [string]`$ProjectFile,
  [switch]`$NoConfig,
  [switch]`$ShowOutput
)
[PSCustomObject]@{ noConfig = [bool]`$NoConfig } | ConvertTo-Json -Compress | Set-Content -LiteralPath '$recordLiteral'
Set-Content -LiteralPath `$OutputFile -Value '{"hints":0,"warnings":0,"errors":0,"output":"fake build output"}'
"@

            $explicitRoot = Join-Path $TestDrive 'fake-root-noconfig'
            New-Item -ItemType Directory -Path $explicitRoot -Force | Out-Null

            $saved = $script:BundledToolsDir
            $script:BundledToolsDir = $fakeDir
            try {
                $result = Invoke-BuildPipeline `
                    -BuildArgs       @('-ProjectFile', 'C:\Fake\App.dpr', '-NoConfig', '-ShowOutput') `
                    -Engine          'DCCBuild' `
                    -ExplicitRootDir $explicitRoot
            }
            finally {
                $script:BundledToolsDir = $saved
            }

            $result.Success | Should -Be $true
            $received = Get-Content -LiteralPath $recordFile -Raw | ConvertFrom-Json
            $received.noConfig | Should -Be $true
        }

    }

    Describe 'Invoke-DelphiBuild -- integration' {

        It 'fails fast with exit code 3 when -ToolchainRootDir does not exist' {
            # Exercises the real (unmocked) pipeline: Test-Path rejects the root
            # before any inspect/build subprocess runs, and the full failure
            # shape survives StrictMode when Invoke-DelphiBuild wraps it.
            $dproj = [System.IO.Path]::GetFullPath(
                (Join-Path $PSScriptRoot '..\..' 'Examples\ConsoleProjectGroup\Source\ConsoleProject.dproj')
            )
            $result = Invoke-DelphiBuild -ProjectFile $dproj -ToolchainRootDir 'C:\no-such-delphi-root' -ErrorAction SilentlyContinue
            $result.Success  | Should -Be $false
            $result.ExitCode | Should -Be 3
        }

        It 'builds ConsoleProject.dproj against an explicit -ToolchainRootDir (registry bypassed)' {
            # Reuses whichever root delphi-inspect would have found, but supplies
            # it explicitly so the inspect subprocess is skipped entirely.
            $dproj = [System.IO.Path]::GetFullPath(
                (Join-Path $PSScriptRoot '..\..' 'Examples\ConsoleProjectGroup\Source\ConsoleProject.dproj')
            )
            $inspect = Join-Path $script:BundledToolsDir 'delphi-inspect.ps1'
            $json    = & $script:PowerShellExe -NoProfile -NonInteractive -File $inspect -DetectLatest -Platform Win32 -BuildSystem MSBuild -Format json 2>&1
            $root    = (($json -join '') | ConvertFrom-Json).result.installation.rootDir
            $root | Should -Not -BeNullOrEmpty

            $result = Invoke-DelphiBuild -ProjectFile $dproj -Platform 'Win32' -Configuration 'Debug' -ToolchainRootDir $root
            $result.Success  | Should -Be $true
            $result.ExitCode | Should -Be 0
        }

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
