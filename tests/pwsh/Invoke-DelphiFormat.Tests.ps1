#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

# Import at script scope so the module is available during Pester discovery,
# which is required for InModuleScope to resolve the module name.
Import-Module ([System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..' 'source' 'Delphi.PowerShell.CI.psm1'))) -Force

InModuleScope 'Delphi.PowerShell.CI' {

    Describe 'Invoke-DelphiFormat -- unit' {

        BeforeAll {
            Mock Invoke-BundledTool {
                [PSCustomObject]@{ ExitCode = 0; Success = $true }
            }
            Mock Write-DelphiCiMessage {}
        }

        Context 'step result shape' {

            It 'StepName is Format' {
                (Invoke-DelphiFormat -FormatRoot 'C:\Fake').StepName | Should -Be 'Format'
            }

            It 'Tool is delphi-format.ps1' {
                (Invoke-DelphiFormat -FormatRoot 'C:\Fake').Tool | Should -Be 'delphi-format.ps1'
            }

            It 'Duration is a TimeSpan' {
                (Invoke-DelphiFormat -FormatRoot 'C:\Fake').Duration | Should -BeOfType [timespan]
            }

            It 'ProjectFile is null' {
                (Invoke-DelphiFormat -FormatRoot 'C:\Fake').ProjectFile | Should -BeNullOrEmpty
            }

        }

        Context 'success and failure' {

            It 'Success is true when tool exits 0' {
                Mock Invoke-BundledTool { [PSCustomObject]@{ ExitCode = 0; Success = $true } }
                (Invoke-DelphiFormat -FormatRoot 'C:\Fake').Success | Should -Be $true
            }

            It 'ExitCode is 0 on success' {
                Mock Invoke-BundledTool { [PSCustomObject]@{ ExitCode = 0; Success = $true } }
                (Invoke-DelphiFormat -FormatRoot 'C:\Fake').ExitCode | Should -Be 0
            }

            It 'Success is false when tool exits non-zero' {
                Mock Invoke-BundledTool { [PSCustomObject]@{ ExitCode = 1; Success = $false } }
                (Invoke-DelphiFormat -FormatRoot 'C:\Fake').Success | Should -Be $false
            }

            It 'ExitCode reflects tool exit code on failure' {
                Mock Invoke-BundledTool { [PSCustomObject]@{ ExitCode = 1; Success = $false } }
                (Invoke-DelphiFormat -FormatRoot 'C:\Fake').ExitCode | Should -Be 1
            }

            It 'Message says Format completed on success' {
                Mock Invoke-BundledTool { [PSCustomObject]@{ ExitCode = 0; Success = $true } }
                (Invoke-DelphiFormat -FormatRoot 'C:\Fake').Message | Should -Be 'Format completed'
            }

            It 'Message says Check completed on success in check mode' {
                Mock Invoke-BundledTool { [PSCustomObject]@{ ExitCode = 0; Success = $true } }
                (Invoke-DelphiFormat -FormatRoot 'C:\Fake' -FormatCheck).Message | Should -Be 'Check completed'
            }

            It 'Message contains exit code on failure' {
                Mock Invoke-BundledTool { [PSCustomObject]@{ ExitCode = 2; Success = $false } }
                (Invoke-DelphiFormat -FormatRoot 'C:\Fake').Message | Should -BeLike '*2*'
            }

        }

        Context 'WhatIf' {

            It 'does not invoke the tool when -WhatIf is set' {
                Invoke-DelphiFormat -FormatRoot 'C:\Fake' -WhatIf
                Should -Invoke Invoke-BundledTool -Times 0
            }

        }

        Context 'argument passing' {

            It 'invokes delphi-format.ps1' {
                Invoke-DelphiFormat -FormatRoot 'C:\Fake'
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $ToolName -eq 'delphi-format.ps1'
                }
            }

            It 'passes -RootPath matching the FormatRoot parameter' {
                Invoke-DelphiFormat -FormatRoot 'C:\Fake\MyProject'
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $Arguments -contains '-RootPath' -and $Arguments -contains 'C:\Fake\MyProject'
                }
            }

            It 'passes -Engine formatter by default' {
                Invoke-DelphiFormat -FormatRoot 'C:\Fake'
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $Arguments -contains '-Engine' -and $Arguments -contains 'formatter'
                }
            }

            It 'passes -Engine radFormatter when FormatEngine is radFormatter' {
                Invoke-DelphiFormat -FormatRoot 'C:\Fake' -FormatEngine 'radFormatter'
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $Arguments -contains '-Engine' -and $Arguments -contains 'radFormatter'
                }
            }

            It 'passes -OutputLevel detailed by default' {
                Invoke-DelphiFormat -FormatRoot 'C:\Fake'
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $Arguments -contains '-OutputLevel' -and $Arguments -contains 'detailed'
                }
            }

            It 'does not pass -EnginePath when FormatEnginePath is empty' {
                Invoke-DelphiFormat -FormatRoot 'C:\Fake'
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $Arguments -notcontains '-EnginePath'
                }
            }

            It 'passes -EnginePath when FormatEnginePath is specified' {
                Invoke-DelphiFormat -FormatRoot 'C:\Fake' -FormatEnginePath 'C:\bin\radFormatter.exe'
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $Arguments -contains '-EnginePath' -and $Arguments -contains 'C:\bin\radFormatter.exe'
                }
            }

            It 'does not pass -EngineConfigFile when FormatEngineConfigFile is empty' {
                Invoke-DelphiFormat -FormatRoot 'C:\Fake'
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $Arguments -notcontains '-EngineConfigFile'
                }
            }

            It 'passes -EngineConfigFile when FormatEngineConfigFile is specified' {
                Invoke-DelphiFormat -FormatRoot 'C:\Fake' -FormatEngineConfigFile 'C:\ci\engine.cfg'
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $Arguments -contains '-EngineConfigFile' -and $Arguments -contains 'C:\ci\engine.cfg'
                }
            }

            It 'does not pass -Path when FormatPath is empty' {
                Invoke-DelphiFormat -FormatRoot 'C:\Fake'
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $Arguments -notcontains '-Path'
                }
            }

            It 'passes -Path for each entry in FormatPath' {
                Invoke-DelphiFormat -FormatRoot 'C:\Fake' -FormatPath @('src\a.pas', 'src\b.pas')
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $Arguments -contains '-Path' -and
                    $Arguments -contains 'src\a.pas' -and
                    $Arguments -contains 'src\b.pas'
                }
            }

            It 'does not pass -IncludeFilePattern when FormatIncludeFilePattern is empty' {
                Invoke-DelphiFormat -FormatRoot 'C:\Fake'
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $Arguments -notcontains '-IncludeFilePattern'
                }
            }

            It 'passes -IncludeFilePattern for each entry in FormatIncludeFilePattern' {
                Invoke-DelphiFormat -FormatRoot 'C:\Fake' -FormatIncludeFilePattern @('*.pas', '*.inc')
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $Arguments -contains '-IncludeFilePattern' -and
                    $Arguments -contains '*.pas' -and
                    $Arguments -contains '*.inc'
                }
            }

            It 'does not pass -ExcludeDirectoryPattern when FormatExcludeDirectoryPattern is empty' {
                Invoke-DelphiFormat -FormatRoot 'C:\Fake'
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $Arguments -notcontains '-ExcludeDirectoryPattern'
                }
            }

            It 'passes -ExcludeDirectoryPattern for each entry in FormatExcludeDirectoryPattern' {
                Invoke-DelphiFormat -FormatRoot 'C:\Fake' -FormatExcludeDirectoryPattern @('vendor', 'thirdparty')
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $Arguments -contains '-ExcludeDirectoryPattern' -and
                    $Arguments -contains 'vendor' -and
                    $Arguments -contains 'thirdparty'
                }
            }

            It 'does not pass -Encoding when FormatEncoding is empty' {
                Invoke-DelphiFormat -FormatRoot 'C:\Fake'
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $Arguments -notcontains '-Encoding'
                }
            }

            It 'passes -Encoding when FormatEncoding is specified' {
                Invoke-DelphiFormat -FormatRoot 'C:\Fake' -FormatEncoding 'utf-8'
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $Arguments -contains '-Encoding' -and $Arguments -contains 'utf-8'
                }
            }

            It 'does not pass -ConfigFile when FormatConfigFile is empty' {
                Invoke-DelphiFormat -FormatRoot 'C:\Fake'
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $Arguments -notcontains '-ConfigFile'
                }
            }

            It 'passes -ConfigFile when FormatConfigFile is specified' {
                Invoke-DelphiFormat -FormatRoot 'C:\Fake' -FormatConfigFile 'C:\ci\delphi-format-ci.json'
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $Arguments -contains '-ConfigFile' -and
                    $Arguments -contains 'C:\ci\delphi-format-ci.json'
                }
            }

            It 'does not pass -CreateBackups when FormatCreateBackups is omitted' {
                Invoke-DelphiFormat -FormatRoot 'C:\Fake'
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $Arguments -notcontains '-CreateBackups'
                }
            }

            It 'passes -CreateBackups when FormatCreateBackups is set' {
                Invoke-DelphiFormat -FormatRoot 'C:\Fake' -FormatCreateBackups
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $Arguments -contains '-CreateBackups'
                }
            }

            It 'does not pass -Check when FormatCheck is omitted' {
                Invoke-DelphiFormat -FormatRoot 'C:\Fake'
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $Arguments -notcontains '-Check'
                }
            }

            It 'passes -Check when FormatCheck is set' {
                Invoke-DelphiFormat -FormatRoot 'C:\Fake' -FormatCheck
                Should -Invoke Invoke-BundledTool -ParameterFilter {
                    $Arguments -contains '-Check'
                }
            }

        }

    }

    Describe 'Invoke-DelphiFormat -- integration' {

        BeforeAll {
            $script:DemoSource = [System.IO.Path]::GetFullPath(
                (Join-Path $PSScriptRoot '..\..' 'Examples\ConsoleProjectGroup\Source')
            )
            $script:SourceExtensions = @('.pas', '.dpr', '.dpk', '.dpkw', '.inc')
        }

        # These exercise the REAL bundled delphi-format.ps1 end-to-end. A
        # formatting engine (formatter.exe / radFormatter.exe) is not guaranteed
        # on CI runners, so each case skips -- rather than fails -- when its
        # engine is absent. Repository source is only ever read in check mode;
        # the clean-path case works on a throwaway copy under $TestDrive.

        It 'flags unformatted source and returns the Format step shape -- <_>' -ForEach @('formatter', 'radFormatter') {
            $engine = $_
            if (-not (Get-Command "$engine.exe" -ErrorAction SilentlyContinue)) {
                Set-ItResult -Skipped -Because "$engine.exe is not on PATH"
                return
            }

            $result = Invoke-DelphiFormat -FormatRoot $script:DemoSource -FormatEngine $engine -FormatCheck -FormatOutputLevel quiet

            $result.StepName    | Should -Be 'Format'
            $result.Tool        | Should -Be 'delphi-format.ps1'
            $result.ProjectFile | Should -BeNullOrEmpty
            # The demo sources are intentionally unformatted -> dirty (exit 1).
            $result.Success  | Should -Be $false
            $result.ExitCode | Should -Be 1
        }

        It 'never modifies repository source in check mode -- <_>' -ForEach @('formatter', 'radFormatter') {
            $engine = $_
            if (-not (Get-Command "$engine.exe" -ErrorAction SilentlyContinue)) {
                Set-ItResult -Skipped -Because "$engine.exe is not on PATH"
                return
            }

            $files = @(Get-ChildItem -LiteralPath $script:DemoSource -Recurse -File |
                Where-Object { $_.Extension -in $script:SourceExtensions })
            $before = @{}
            foreach ($f in $files) { $before[$f.FullName] = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash }

            Invoke-DelphiFormat -FormatRoot $script:DemoSource -FormatEngine $engine -FormatCheck -FormatOutputLevel quiet | Out-Null

            foreach ($f in $files) {
                (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash | Should -Be $before[$f.FullName] -Because "$($f.Name) must be untouched by a check run"
            }
        }

        It 'reports a clean tree (Success, exit 0) for already-formatted source -- <_>' -ForEach @('formatter', 'radFormatter') {
            $engine = $_
            if (-not (Get-Command "$engine.exe" -ErrorAction SilentlyContinue)) {
                Set-ItResult -Skipped -Because "$engine.exe is not on PATH"
                return
            }

            # Canonicalize a throwaway copy: format the demo source once in place
            # (formatting is idempotent), then a check of that copy must report
            # clean. Repository source is never modified.
            $workDir = Join-Path $TestDrive "formatted-$engine"
            New-Item -ItemType Directory -Path $workDir -Force | Out-Null
            Get-ChildItem -LiteralPath $script:DemoSource -File |
                Where-Object { $_.Extension -in $script:SourceExtensions } |
                Copy-Item -Destination $workDir -Force

            $fmt = Invoke-DelphiFormat -FormatRoot $workDir -FormatEngine $engine -FormatOutputLevel quiet
            $fmt.Success | Should -Be $true -Because 'formatting a throwaway copy in place should succeed'

            $check = Invoke-DelphiFormat -FormatRoot $workDir -FormatEngine $engine -FormatCheck -FormatOutputLevel quiet
            $check.Success  | Should -Be $true
            $check.ExitCode | Should -Be 0
        }

    }

}
