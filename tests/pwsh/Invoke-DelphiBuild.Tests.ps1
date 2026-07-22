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

            # A fake build tool that records the -RootDir it received.
            $rootArgFile = Join-Path $TestDrive 'build-rootdir.txt'
            Set-Content -LiteralPath (Join-Path $fakeDir 'delphi-msbuild.ps1') -Value @"
param([string]`$RootDir, [string]`$OutputFile, [Parameter(ValueFromRemainingArguments)]`$Rest)
Set-Content -LiteralPath '$rootArgFile' -Value `$RootDir
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
