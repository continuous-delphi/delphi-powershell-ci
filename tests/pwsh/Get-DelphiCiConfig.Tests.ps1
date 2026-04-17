#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\..' 'source' 'Delphi.PowerShell.CI.psm1'
    Import-Module ([System.IO.Path]::GetFullPath($modulePath)) -Force
}

Describe 'Get-DelphiCiConfig' {

    Context 'defaults when no arguments are supplied' {

        It 'returns Clean and Build steps' {
            $config = Get-DelphiCiConfig
            $config.Steps | Should -Be @('Clean', 'Build')
        }

        It 'returns Win32 as the default platform' {
            $config = Get-DelphiCiConfig
            $config.Build.Defaults.Platform | Should -Be 'Win32'
        }

        It 'returns Debug configuration' {
            $config = Get-DelphiCiConfig
            $config.Build.Defaults.Configuration | Should -Be 'Debug'
        }

        It 'returns MSBuild engine' {
            $config = Get-DelphiCiConfig
            $config.Build.Defaults.Engine | Should -Be 'MSBuild'
        }

        It 'returns Latest as the default toolchain version' {
            $config = Get-DelphiCiConfig
            $config.Build.Defaults.Toolchain.Version | Should -Be 'Latest'
        }

        It 'returns basic as the default clean level' {
            $config = Get-DelphiCiConfig
            $config.Clean.Defaults.Level | Should -Be 'basic'
        }

        It 'returns empty CleanIncludeFilePattern array by default' {
            $config = Get-DelphiCiConfig
            $config.Clean.Defaults.IncludeFilePattern | Should -BeNullOrEmpty
        }

        It 'returns empty CleanExcludeDirectoryPattern array by default' {
            $config = Get-DelphiCiConfig
            $config.Clean.Defaults.ExcludeDirectoryPattern | Should -BeNullOrEmpty
        }

        It 'returns empty CleanConfigFile by default' {
            $config = Get-DelphiCiConfig
            $config.Clean.Defaults.ConfigFile | Should -BeNullOrEmpty
        }

        It 'returns empty defines array' {
            $config = Get-DelphiCiConfig
            $config.Build.Defaults.Defines | Should -BeNullOrEmpty
        }

        It 'returns empty build jobs array' {
            $config = Get-DelphiCiConfig
            $config.Build.Jobs.Count | Should -Be 0
        }

        It 'returns empty test jobs array' {
            $config = Get-DelphiCiConfig
            $config.Test.Jobs.Count | Should -Be 0
        }

        It 'returns 10 as default test timeout' {
            $config = Get-DelphiCiConfig
            $config.Test.Defaults.TimeoutSeconds | Should -Be 10
        }

        It 'returns normal as default build verbosity' {
            $config = Get-DelphiCiConfig
            $config.Build.Defaults.Verbosity | Should -Be 'normal'
        }

        It 'returns Build as default build target' {
            $config = Get-DelphiCiConfig
            $config.Build.Defaults.Target | Should -Be 'Build'
        }

        It 'sets root to the current working directory' {
            $config = Get-DelphiCiConfig
            $expected = [System.IO.Path]::GetFullPath((Get-Location).Path)
            $config.Root | Should -Be $expected
        }

    }

    Context 'JSON config loading' {

        It 'loads steps from config file' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{ steps = @('Clean') } | ConvertTo-Json)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile
            $config.Steps | Should -Be @('Clean')
        }

        It 'loads platform from config file' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{ build = @{ platform = 'Win64' } } | ConvertTo-Json)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile
            $config.Build.Defaults.Platform | Should -Be 'Win64'
        }

        It 'loads configuration from config file' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{ build = @{ configuration = 'Release' } } | ConvertTo-Json)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile
            $config.Build.Defaults.Configuration | Should -Be 'Release'
        }

        It 'loads clean level from config file' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{ clean = @{ level = 'standard' } } | ConvertTo-Json)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile
            $config.Clean.Defaults.Level | Should -Be 'standard'
        }

        It 'loads toolchain version from config file' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{ build = @{ toolchain = @{ version = 'Athens' } } } | ConvertTo-Json -Depth 5)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile
            $config.Build.Defaults.Toolchain.Version | Should -Be 'Athens'
        }

        It 'loads defines array from config file' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{ build = @{ defines = @('CI', 'RELEASE') } } | ConvertTo-Json)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile
            $config.Build.Defaults.Defines | Should -Be @('CI', 'RELEASE')
        }

        It 'loads build jobs from config file' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            $json = @{
                build = @{
                    jobs = @(
                        @{ name = 'App'; projectFile = 'source/App.dproj' }
                    )
                }
            } | ConvertTo-Json -Depth 5
            Set-Content -LiteralPath $cfgFile -Value $json

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile
            $config.Build.Jobs.Count | Should -Be 1
            $config.Build.Jobs[0].Name | Should -Be 'App'
            $config.Build.Jobs[0].ProjectFile | Should -Be 'source/App.dproj'
        }

        It 'build jobs inherit defaults from the build section' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            $json = @{
                build = @{
                    platform = 'Win64'
                    configuration = 'Release'
                    jobs = @(
                        @{ projectFile = 'source/App.dproj' }
                    )
                }
            } | ConvertTo-Json -Depth 5
            Set-Content -LiteralPath $cfgFile -Value $json

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile
            $config.Build.Jobs[0].Platform | Should -Be @('Win64')
            $config.Build.Jobs[0].Configuration | Should -Be @('Release')
        }

        It 'build jobs can override defaults' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            $json = @{
                build = @{
                    platform = 'Win32'
                    jobs = @(
                        @{ projectFile = 'source/App.dproj'; platform = 'Win64' }
                    )
                }
            } | ConvertTo-Json -Depth 5
            Set-Content -LiteralPath $cfgFile -Value $json

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile
            $config.Build.Jobs[0].Platform | Should -Be @('Win64')
        }

        It 'build job platform can be an array for matrix expansion' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            $json = @{
                build = @{
                    jobs = @(
                        @{ projectFile = 'source/App.dproj'; platform = @('Win32', 'Win64') }
                    )
                }
            } | ConvertTo-Json -Depth 5
            Set-Content -LiteralPath $cfgFile -Value $json

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile
            $config.Build.Jobs[0].Platform | Should -Be @('Win32', 'Win64')
        }

        It 'loads test jobs from config file' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            $json = @{
                test = @{
                    jobs = @(
                        @{ name = 'Unit tests'; testExeFile = 'test/Win32/Debug/App.Tests.exe' }
                    )
                }
            } | ConvertTo-Json -Depth 5
            Set-Content -LiteralPath $cfgFile -Value $json

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile
            $config.Test.Jobs.Count | Should -Be 1
            $config.Test.Jobs[0].TestExeFile | Should -Be 'test/Win32/Debug/App.Tests.exe'
        }

        It 'test jobs inherit defaults from the test section' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            $json = @{
                test = @{
                    timeoutSeconds = 30
                    jobs = @(
                        @{ testExeFile = 'test/App.Tests.exe' }
                    )
                }
            } | ConvertTo-Json -Depth 5
            Set-Content -LiteralPath $cfgFile -Value $json

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile
            $config.Test.Jobs[0].TimeoutSeconds | Should -Be 30
        }

        It 'loads clean jobs from config file' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            $json = @{
                clean = @{
                    level = 'deep'
                    jobs = @(
                        @{ name = 'Repo clean'; root = './' }
                    )
                }
            } | ConvertTo-Json -Depth 5
            Set-Content -LiteralPath $cfgFile -Value $json

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile
            $config.Clean.Jobs.Count | Should -Be 1
            $config.Clean.Jobs[0].Name | Should -Be 'Repo clean'
            $config.Clean.Jobs[0].Level | Should -Be 'deep'
        }

        It 'applies built-in defaults for fields absent from config file' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{ build = @{ platform = 'Win64' } } | ConvertTo-Json)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile
            $config.Build.Defaults.Configuration | Should -Be 'Debug'
            $config.Build.Defaults.Engine        | Should -Be 'MSBuild'
            $config.Clean.Defaults.Level         | Should -Be 'basic'
            $config.Steps                        | Should -Be @('Clean', 'Build')
        }

    }

    Context 'root resolution' {

        It 'uses the config file directory as root when root is absent from JSON' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{} | ConvertTo-Json)

            $config   = Get-DelphiCiConfig -ConfigFile $cfgFile
            $expected = [System.IO.Path]::GetFullPath($TestDrive)
            $config.Root | Should -Be $expected
        }

        It 'uses the config file directory as root when root is "."' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{ root = '.' } | ConvertTo-Json)

            $config   = Get-DelphiCiConfig -ConfigFile $cfgFile
            $expected = [System.IO.Path]::GetFullPath($TestDrive)
            $config.Root | Should -Be $expected
        }

        It 'resolves root relative to the config file directory' {
            $subDir  = Join-Path $TestDrive 'ci'
            $null    = New-Item -ItemType Directory -Path $subDir
            $cfgFile = Join-Path $subDir 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{ root = '..' } | ConvertTo-Json)

            $config   = Get-DelphiCiConfig -ConfigFile $cfgFile
            $expected = [System.IO.Path]::GetFullPath((Join-Path $subDir '..'))
            $config.Root | Should -Be $expected
        }

    }

    Context 'CLI overrides beat config file values' {

        It '-Platform overrides config file platform' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{ build = @{ platform = 'Win32' } } | ConvertTo-Json)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile -Platform 'Win64'
            $config.Build.Defaults.Platform | Should -Be 'Win64'
        }

        It '-Configuration overrides config file configuration' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{ build = @{ configuration = 'Debug' } } | ConvertTo-Json)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile -Configuration 'Release'
            $config.Build.Defaults.Configuration | Should -Be 'Release'
        }

        It '-Steps overrides config file steps' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{ steps = @('Clean', 'Build') } | ConvertTo-Json)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile -Steps 'Build'
            $config.Steps | Should -Be @('Build')
        }

        It '-Toolchain overrides config file toolchain version' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{ build = @{ toolchain = @{ version = 'Athens' } } } | ConvertTo-Json -Depth 5)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile -Toolchain 'Florence'
            $config.Build.Defaults.Toolchain.Version | Should -Be 'Florence'
        }

        It '-BuildEngine overrides config file engine' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{ build = @{ engine = 'MSBuild' } } | ConvertTo-Json)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile -BuildEngine 'DCCBuild'
            $config.Build.Defaults.Engine | Should -Be 'DCCBuild'
        }

        It '-Defines overrides config file defines' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{ build = @{ defines = @('FROM_FILE') } } | ConvertTo-Json)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile -Defines 'CI', 'RELEASE_BUILD'
            $config.Build.Defaults.Defines | Should -Be @('CI', 'RELEASE_BUILD')
        }

        It '-Root overrides root derived from config file location' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{} | ConvertTo-Json)

            $override = Join-Path $TestDrive 'custom-root'
            $null     = New-Item -ItemType Directory -Path $override
            $config   = Get-DelphiCiConfig -ConfigFile $cfgFile -Root $override
            $config.Root | Should -Be ([System.IO.Path]::GetFullPath($override))
        }

        It '-ProjectFile creates a single build job' {
            $config = Get-DelphiCiConfig -ProjectFile 'source/App.dproj'
            $config.Build.Jobs.Count | Should -Be 1
            $config.Build.Jobs[0].ProjectFile | Should -Be 'source/App.dproj'
        }

        It '-TestExeFile creates a single test job' {
            $config = Get-DelphiCiConfig -TestExeFile 'test/Win32/Debug/App.Tests.exe'
            $config.Test.Jobs.Count | Should -Be 1
            $config.Test.Jobs[0].TestExeFile | Should -Be 'test/Win32/Debug/App.Tests.exe'
        }

    }

    Context 'CLI overrides beat built-in defaults' {

        It '-Platform overrides default platform' {
            $config = Get-DelphiCiConfig -Platform 'Win64'
            $config.Build.Defaults.Platform | Should -Be 'Win64'
        }

        It '-Configuration overrides default configuration' {
            $config = Get-DelphiCiConfig -Configuration 'Release'
            $config.Build.Defaults.Configuration | Should -Be 'Release'
        }

        It '-Steps overrides default steps' {
            $config = Get-DelphiCiConfig -Steps 'Clean'
            $config.Steps | Should -Be @('Clean')
        }

        It '-Toolchain overrides default toolchain version' {
            $config = Get-DelphiCiConfig -Toolchain 'VER370'
            $config.Build.Defaults.Toolchain.Version | Should -Be 'VER370'
        }

        It '-BuildEngine overrides default engine' {
            $config = Get-DelphiCiConfig -BuildEngine 'DCCBuild'
            $config.Build.Defaults.Engine | Should -Be 'DCCBuild'
        }

        It '-Defines overrides default empty defines' {
            $config = Get-DelphiCiConfig -Defines 'CI'
            $config.Build.Defaults.Defines | Should -Be @('CI')
        }

        It '-CleanLevel overrides default basic level' {
            $config = Get-DelphiCiConfig -CleanLevel 'deep'
            $config.Clean.Defaults.Level | Should -Be 'deep'
        }

        It '-TestTimeoutSeconds overrides default timeout' {
            $config = Get-DelphiCiConfig -TestTimeoutSeconds 5
            $config.Test.Defaults.TimeoutSeconds | Should -Be 5
        }

    }

    Context 'comma-split normalisation (PS 7 -File compat)' {

        It 'splits Steps passed as a single comma-separated string' {
            $config = Get-DelphiCiConfig -Steps 'Clean,Build'
            $config.Steps | Should -Be @('Clean', 'Build')
        }

        It 'splits Steps and trims surrounding spaces' {
            $config = Get-DelphiCiConfig -Steps 'Clean, Build'
            $config.Steps | Should -Be @('Clean', 'Build')
        }

        It 'accepts a single step without a comma' {
            $config = Get-DelphiCiConfig -Steps 'Build'
            $config.Steps | Should -Be @('Build')
        }

        It 'splits Defines passed as a single comma-separated string' {
            $config = Get-DelphiCiConfig -Defines 'CI,RELEASE_BUILD'
            $config.Build.Defaults.Defines | Should -Be @('CI', 'RELEASE_BUILD')
        }

        It 'treats an already-split array of steps as-is' {
            $config = Get-DelphiCiConfig -Steps @('Clean', 'Build')
            $config.Steps | Should -Be @('Clean', 'Build')
        }

    }

    Context 'validation' {

        It 'throws on an invalid clean level in config file' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{ clean = @{ level = 'nuclear' } } | ConvertTo-Json)

            { Get-DelphiCiConfig -ConfigFile $cfgFile } | Should -Throw
        }

        It 'throws on an invalid build engine in config file' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{ build = @{ engine = 'Turbo' } } | ConvertTo-Json)

            { Get-DelphiCiConfig -ConfigFile $cfgFile } | Should -Throw
        }

        It 'throws on an invalid step name in config file' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{ steps = @('Deploy') } | ConvertTo-Json)

            { Get-DelphiCiConfig -ConfigFile $cfgFile } | Should -Throw
        }

        It 'accepts Test as a valid step' {
            $config = Get-DelphiCiConfig -Steps 'Test'
            $config.Steps | Should -Be @('Test')
        }

        It 'accepts Clean,Build,Test as valid steps' {
            $config = Get-DelphiCiConfig -Steps @('Clean', 'Build', 'Test')
            $config.Steps | Should -Be @('Clean', 'Build', 'Test')
        }

        It 'throws when the config file does not exist' {
            { Get-DelphiCiConfig -ConfigFile (Join-Path $TestDrive 'nonexistent.json') } | Should -Throw
        }

    }

}
