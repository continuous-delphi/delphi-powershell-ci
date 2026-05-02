#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\..' 'source' 'Delphi.PowerShell.CI.psm1'
    Import-Module ([System.IO.Path]::GetFullPath($modulePath)) -Force
}

Describe 'Get-DelphiCiConfig' {

    Context 'defaults when no arguments are supplied' {

        It 'returns a default pipeline with Clean and Build' {
            $config = Get-DelphiCiConfig
            $config.Pipeline.Count | Should -Be 2
            $config.Pipeline[0].Action | Should -Be 'Clean'
            $config.Pipeline[1].Action | Should -Be 'Build'
        }

        It 'returns Win32 as the default build platform' {
            $config = Get-DelphiCiConfig
            $config.Pipeline[1].Defaults['platform'] | Should -Be 'Win32'
        }

        It 'returns Debug as the default build configuration' {
            $config = Get-DelphiCiConfig
            $config.Pipeline[1].Defaults['configuration'] | Should -Be 'Debug'
        }

        It 'returns MSBuild as the default engine' {
            $config = Get-DelphiCiConfig
            $config.Pipeline[1].Defaults['engine'] | Should -Be 'MSBuild'
        }

        It 'returns Latest as the default toolchain version' {
            $config = Get-DelphiCiConfig
            $config.Pipeline[1].Defaults['toolchain']['version'] | Should -Be 'Latest'
        }

        It 'returns basic as the default clean level' {
            $config = Get-DelphiCiConfig
            $config.Pipeline[0].Defaults['level'] | Should -Be 'basic'
        }

        It 'returns empty includeFilePattern array by default' {
            $config = Get-DelphiCiConfig
            $config.Pipeline[0].Defaults['includeFilePattern'] | Should -BeNullOrEmpty
        }

        It 'returns empty excludeDirectoryPattern array by default' {
            $config = Get-DelphiCiConfig
            $config.Pipeline[0].Defaults['excludeDirectoryPattern'] | Should -BeNullOrEmpty
        }

        It 'returns empty configFile by default' {
            $config = Get-DelphiCiConfig
            $config.Pipeline[0].Defaults['configFile'] | Should -BeNullOrEmpty
        }

        It 'returns empty defines array by default' {
            $config = Get-DelphiCiConfig
            $config.Pipeline[1].Defaults['defines'] | Should -BeNullOrEmpty
        }

        It 'returns empty build jobs array by default' {
            $config = Get-DelphiCiConfig
            $config.Pipeline[1].Jobs.Count | Should -Be 0
        }

        It 'returns normal as default build verbosity' {
            $config = Get-DelphiCiConfig
            $config.Pipeline[1].Defaults['verbosity'] | Should -Be 'normal'
        }

        It 'returns Build as default build target' {
            $config = Get-DelphiCiConfig
            $config.Pipeline[1].Defaults['target'] | Should -Be 'Build'
        }

        It 'sets root to the current working directory' {
            $config = Get-DelphiCiConfig
            $expected = [System.IO.Path]::GetFullPath((Get-Location).Path)
            $config.Root | Should -Be $expected
        }

    }

    Context 'defaults with Run in pipeline' {

        It 'returns 10 as default run timeout' {
            $config = Get-DelphiCiConfig -Steps 'Run' -Execute 'test.exe'
            $config.Pipeline[0].Defaults['timeoutSeconds'] | Should -Be 10
        }

        It 'returns empty run jobs when only defaults override is given' {
            $config = Get-DelphiCiConfig -Steps 'Run'
            $config.Pipeline[0].Jobs.Count | Should -Be 0
        }

    }

    Context 'new pipeline format JSON config' {

        It 'loads pipeline from config file' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            $json = @{
                pipeline = @(
                    @{ action = 'Clean'; level = 'deep' }
                    @{ action = 'Build'; jobs = @(
                        @{ name = 'App'; projectFile = 'src/App.dproj' }
                    )}
                )
            } | ConvertTo-Json -Depth 5
            Set-Content -LiteralPath $cfgFile -Value $json

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile
            $config.Pipeline.Count | Should -Be 2
            $config.Pipeline[0].Action | Should -Be 'Clean'
            $config.Pipeline[0].Defaults['level'] | Should -Be 'deep'
            $config.Pipeline[1].Jobs[0]['projectFile'] | Should -Be 'src/App.dproj'
        }

        It 'merges defaults section into pipeline action defaults' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            $json = @{
                defaults = @{
                    build = @{ platform = 'Win64'; configuration = 'Release' }
                }
                pipeline = @(
                    @{ action = 'Build'; jobs = @(
                        @{ projectFile = 'src/App.dproj' }
                    )}
                )
            } | ConvertTo-Json -Depth 5
            Set-Content -LiteralPath $cfgFile -Value $json

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile
            $config.Pipeline[0].Jobs[0]['platform'] | Should -Be @('Win64')
            $config.Pipeline[0].Jobs[0]['configuration'] | Should -Be @('Release')
        }

        It 'action-level properties override defaults' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            $json = @{
                defaults = @{ build = @{ platform = 'Win32' } }
                pipeline = @(
                    @{ action = 'Build'; platform = 'Win64'; jobs = @(
                        @{ projectFile = 'src/App.dproj' }
                    )}
                )
            } | ConvertTo-Json -Depth 5
            Set-Content -LiteralPath $cfgFile -Value $json

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile
            $config.Pipeline[0].Jobs[0]['platform'] | Should -Be @('Win64')
        }

        It 'job-level properties override action-level' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            $json = @{
                pipeline = @(
                    @{ action = 'Build'; platform = 'Win64'; jobs = @(
                        @{ projectFile = 'src/App.dproj'; platform = 'Win32' }
                    )}
                )
            } | ConvertTo-Json -Depth 5
            Set-Content -LiteralPath $cfgFile -Value $json

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile
            $config.Pipeline[0].Jobs[0]['platform'] | Should -Be @('Win32')
        }

        It 'arrays append across merge levels' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            $json = @{
                defaults = @{ build = @{ defines = @('DEFAULT') } }
                pipeline = @(
                    @{ action = 'Build'; defines = @('ACTION'); jobs = @(
                        @{ projectFile = 'src/App.dproj'; defines = @('JOB') }
                    )}
                )
            } | ConvertTo-Json -Depth 5
            Set-Content -LiteralPath $cfgFile -Value $json

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile
            $config.Pipeline[0].Jobs[0]['defines'] | Should -Be @('DEFAULT', 'ACTION', 'JOB')
        }

        It 'key! suffix replaces array instead of appending' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            $json = '{
                "defaults": { "build": { "defines": ["DEFAULT"] } },
                "pipeline": [
                    { "action": "Build", "defines": ["ACTION"], "jobs": [
                        { "projectFile": "src/App.dproj", "defines!": ["ONLY"] }
                    ]}
                ]
            }'
            Set-Content -LiteralPath $cfgFile -Value $json

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile
            $config.Pipeline[0].Jobs[0]['defines'] | Should -Be @('ONLY')
        }

    }

    Context 'legacy format JSON config' {

        It 'loads steps from legacy config file' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{ steps = @('Clean') } | ConvertTo-Json)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile
            $config.Pipeline.Count | Should -Be 1
            $config.Pipeline[0].Action | Should -Be 'Clean'
        }

        It 'loads platform from legacy build section' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{ build = @{ platform = 'Win64' }; steps = @('Build') } | ConvertTo-Json -Depth 5)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile
            $config.Pipeline[0].Defaults['platform'] | Should -Be 'Win64'
        }

        It 'loads configuration from legacy build section' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{ build = @{ configuration = 'Release' }; steps = @('Build') } | ConvertTo-Json -Depth 5)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile
            $config.Pipeline[0].Defaults['configuration'] | Should -Be 'Release'
        }

        It 'loads clean level from legacy config file' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{ clean = @{ level = 'standard' }; steps = @('Clean') } | ConvertTo-Json -Depth 5)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile
            $config.Pipeline[0].Defaults['level'] | Should -Be 'standard'
        }

        It 'loads toolchain version from legacy config file' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{ build = @{ toolchain = @{ version = 'Athens' } }; steps = @('Build') } | ConvertTo-Json -Depth 5)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile
            $config.Pipeline[0].Defaults['toolchain']['version'] | Should -Be 'Athens'
        }

        It 'loads defines array from legacy config file' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{ build = @{ defines = @('CI', 'RELEASE') }; steps = @('Build') } | ConvertTo-Json -Depth 5)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile
            $config.Pipeline[0].Defaults['defines'] | Should -Be @('CI', 'RELEASE')
        }

        It 'loads build jobs from legacy config file' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            $json = @{
                steps = @('Build')
                build = @{
                    jobs = @(
                        @{ name = 'App'; projectFile = 'source/App.dproj' }
                    )
                }
            } | ConvertTo-Json -Depth 5
            Set-Content -LiteralPath $cfgFile -Value $json

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile
            $config.Pipeline[0].Jobs.Count | Should -Be 1
            $config.Pipeline[0].Jobs[0]['name'] | Should -Be 'App'
            $config.Pipeline[0].Jobs[0]['projectFile'] | Should -Be 'source/App.dproj'
        }

        It 'build jobs inherit defaults from the legacy build section' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            $json = @{
                steps = @('Build')
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
            $config.Pipeline[0].Jobs[0]['platform'] | Should -Be @('Win64')
            $config.Pipeline[0].Jobs[0]['configuration'] | Should -Be @('Release')
        }

        It 'build jobs can override defaults' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            $json = @{
                steps = @('Build')
                build = @{
                    platform = 'Win32'
                    jobs = @(
                        @{ projectFile = 'source/App.dproj'; platform = 'Win64' }
                    )
                }
            } | ConvertTo-Json -Depth 5
            Set-Content -LiteralPath $cfgFile -Value $json

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile
            $config.Pipeline[0].Jobs[0]['platform'] | Should -Be @('Win64')
        }

        It 'build job platform can be an array for matrix expansion' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            $json = @{
                steps = @('Build')
                build = @{
                    jobs = @(
                        @{ projectFile = 'source/App.dproj'; platform = @('Win32', 'Win64') }
                    )
                }
            } | ConvertTo-Json -Depth 5
            Set-Content -LiteralPath $cfgFile -Value $json

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile
            $config.Pipeline[0].Jobs[0]['platform'] | Should -Be @('Win32', 'Win64')
        }

        It 'loads run jobs from legacy config file' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            $json = @{
                steps = @('Run')
                run = @{
                    jobs = @(
                        @{ name = 'Unit tests'; execute = 'test/Win32/Debug/App.Tests.exe' }
                    )
                }
            } | ConvertTo-Json -Depth 5
            Set-Content -LiteralPath $cfgFile -Value $json

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile
            $config.Pipeline[0].Jobs.Count | Should -Be 1
            $config.Pipeline[0].Jobs[0]['execute'] | Should -Be 'test/Win32/Debug/App.Tests.exe'
        }

        It 'run jobs inherit defaults from the legacy run section' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            $json = @{
                steps = @('Run')
                run = @{
                    timeoutSeconds = 30
                    jobs = @(
                        @{ execute = 'test/App.Tests.exe' }
                    )
                }
            } | ConvertTo-Json -Depth 5
            Set-Content -LiteralPath $cfgFile -Value $json

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile
            $config.Pipeline[0].Jobs[0]['timeoutSeconds'] | Should -Be 30
        }

        It 'loads clean jobs from legacy config file' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            $json = @{
                steps = @('Clean')
                clean = @{
                    level = 'deep'
                    jobs = @(
                        @{ name = 'Repo clean'; root = './' }
                    )
                }
            } | ConvertTo-Json -Depth 5
            Set-Content -LiteralPath $cfgFile -Value $json

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile
            $config.Pipeline[0].Jobs.Count | Should -Be 1
            $config.Pipeline[0].Jobs[0]['name'] | Should -Be 'Repo clean'
            $config.Pipeline[0].Jobs[0]['level'] | Should -Be 'deep'
        }

        It 'applies built-in defaults for fields absent from legacy config file' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{ steps = @('Clean', 'Build'); build = @{ platform = 'Win64' } } | ConvertTo-Json -Depth 5)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile
            $config.Pipeline[1].Defaults['configuration'] | Should -Be 'Debug'
            $config.Pipeline[1].Defaults['engine']        | Should -Be 'MSBuild'
            $config.Pipeline[0].Defaults['level']         | Should -Be 'basic'
        }

    }

    Context 'root resolution' {

        It 'uses the config file directory as root when root is absent from JSON' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{ pipeline = @(@{ action = 'Clean' }) } | ConvertTo-Json -Depth 5)

            $config   = Get-DelphiCiConfig -ConfigFile $cfgFile
            $expected = [System.IO.Path]::GetFullPath($TestDrive)
            $config.Root | Should -Be $expected
        }

        It 'uses the config file directory as root when root is "."' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{ root = '.'; pipeline = @(@{ action = 'Clean' }) } | ConvertTo-Json -Depth 5)

            $config   = Get-DelphiCiConfig -ConfigFile $cfgFile
            $expected = [System.IO.Path]::GetFullPath($TestDrive)
            $config.Root | Should -Be $expected
        }

        It 'resolves root relative to the config file directory' {
            $subDir  = Join-Path $TestDrive 'ci'
            $null    = New-Item -ItemType Directory -Path $subDir
            $cfgFile = Join-Path $subDir 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{ root = '..'; pipeline = @(@{ action = 'Clean' }) } | ConvertTo-Json -Depth 5)

            $config   = Get-DelphiCiConfig -ConfigFile $cfgFile
            $expected = [System.IO.Path]::GetFullPath((Join-Path $subDir '..'))
            $config.Root | Should -Be $expected
        }

    }

    Context 'CLI overrides beat config file values' {

        It '-Platform overrides config file platform' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{ steps = @('Build'); build = @{ platform = 'Win32' } } | ConvertTo-Json -Depth 5)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile -Platform 'Win64'
            $config.Pipeline[0].Defaults['platform'] | Should -Be 'Win64'
        }

        It '-Configuration overrides config file configuration' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{ steps = @('Build'); build = @{ configuration = 'Debug' } } | ConvertTo-Json -Depth 5)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile -Configuration 'Release'
            $config.Pipeline[0].Defaults['configuration'] | Should -Be 'Release'
        }

        It '-Steps overrides config file steps' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{ steps = @('Clean', 'Build') } | ConvertTo-Json)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile -Steps 'Build'
            $config.Pipeline.Count | Should -Be 1
            $config.Pipeline[0].Action | Should -Be 'Build'
        }

        It '-Toolchain overrides config file toolchain version' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{ steps = @('Build'); build = @{ toolchain = @{ version = 'Athens' } } } | ConvertTo-Json -Depth 5)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile -Toolchain 'Florence'
            $config.Pipeline[0].Defaults['toolchain']['version'] | Should -Be 'Florence'
        }

        It '-BuildEngine overrides config file engine' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{ steps = @('Build'); build = @{ engine = 'MSBuild' } } | ConvertTo-Json -Depth 5)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile -BuildEngine 'DCCBuild'
            $config.Pipeline[0].Defaults['engine'] | Should -Be 'DCCBuild'
        }

        It '-Defines overrides config file defines' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{ steps = @('Build'); build = @{ defines = @('FROM_FILE') } } | ConvertTo-Json -Depth 5)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile -Defines 'CI', 'RELEASE_BUILD'
            $config.Pipeline[0].Defaults['defines'] | Should -Be @('CI', 'RELEASE_BUILD')
        }

        It '-Root overrides root derived from config file location' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{ pipeline = @(@{ action = 'Clean' }) } | ConvertTo-Json -Depth 5)

            $override = Join-Path $TestDrive 'custom-root'
            $null     = New-Item -ItemType Directory -Path $override
            $config   = Get-DelphiCiConfig -ConfigFile $cfgFile -Root $override
            $config.Root | Should -Be ([System.IO.Path]::GetFullPath($override))
        }

        It '-ProjectFile creates a single build job' {
            $config = Get-DelphiCiConfig -Steps 'Build' -ProjectFile 'source/App.dproj'
            $config.Pipeline[0].Jobs.Count | Should -Be 1
            $config.Pipeline[0].Jobs[0]['projectFile'] | Should -Be 'source/App.dproj'
        }

        It '-Execute creates a single run job' {
            $config = Get-DelphiCiConfig -Steps 'Run' -Execute 'test/Win32/Debug/App.Tests.exe'
            $config.Pipeline[0].Jobs.Count | Should -Be 1
            $config.Pipeline[0].Jobs[0]['execute'] | Should -Be 'test/Win32/Debug/App.Tests.exe'
        }

    }

    Context 'CLI overrides beat built-in defaults' {

        It '-Platform overrides default platform' {
            $config = Get-DelphiCiConfig -Platform 'Win64'
            $config.Pipeline[1].Defaults['platform'] | Should -Be 'Win64'
        }

        It '-Configuration overrides default configuration' {
            $config = Get-DelphiCiConfig -Configuration 'Release'
            $config.Pipeline[1].Defaults['configuration'] | Should -Be 'Release'
        }

        It '-Steps overrides default pipeline' {
            $config = Get-DelphiCiConfig -Steps 'Clean'
            $config.Pipeline.Count | Should -Be 1
            $config.Pipeline[0].Action | Should -Be 'Clean'
        }

        It '-Toolchain overrides default toolchain version' {
            $config = Get-DelphiCiConfig -Toolchain 'VER370'
            $config.Pipeline[1].Defaults['toolchain']['version'] | Should -Be 'VER370'
        }

        It '-BuildEngine overrides default engine' {
            $config = Get-DelphiCiConfig -BuildEngine 'DCCBuild'
            $config.Pipeline[1].Defaults['engine'] | Should -Be 'DCCBuild'
        }

        It '-Defines overrides default empty defines' {
            $config = Get-DelphiCiConfig -Defines 'CI'
            $config.Pipeline[1].Defaults['defines'] | Should -Be @('CI')
        }

        It '-CleanLevel overrides default basic level' {
            $config = Get-DelphiCiConfig -CleanLevel 'deep'
            $config.Pipeline[0].Defaults['level'] | Should -Be 'deep'
        }

        It '-RunTimeoutSeconds overrides default timeout' {
            $config = Get-DelphiCiConfig -Steps 'Run' -RunTimeoutSeconds 5
            $config.Pipeline[0].Defaults['timeoutSeconds'] | Should -Be 5
        }

    }

    Context 'comma-split normalisation (PS 7 -File compat)' {

        It 'splits Steps passed as a single comma-separated string' {
            $config = Get-DelphiCiConfig -Steps 'Clean,Build'
            $config.Pipeline.Count | Should -Be 2
            $config.Pipeline[0].Action | Should -Be 'Clean'
            $config.Pipeline[1].Action | Should -Be 'Build'
        }

        It 'splits Steps and trims surrounding spaces' {
            $config = Get-DelphiCiConfig -Steps 'Clean, Build'
            $config.Pipeline.Count | Should -Be 2
            $config.Pipeline[0].Action | Should -Be 'Clean'
            $config.Pipeline[1].Action | Should -Be 'Build'
        }

        It 'accepts a single step without a comma' {
            $config = Get-DelphiCiConfig -Steps 'Build'
            $config.Pipeline.Count | Should -Be 1
            $config.Pipeline[0].Action | Should -Be 'Build'
        }

        It 'splits Defines passed as a single comma-separated string' {
            $config = Get-DelphiCiConfig -Defines 'CI,RELEASE_BUILD'
            $config.Pipeline[1].Defaults['defines'] | Should -Be @('CI', 'RELEASE_BUILD')
        }

        It 'treats an already-split array of steps as-is' {
            $config = Get-DelphiCiConfig -Steps @('Clean', 'Build')
            $config.Pipeline.Count | Should -Be 2
            $config.Pipeline[0].Action | Should -Be 'Clean'
            $config.Pipeline[1].Action | Should -Be 'Build'
        }

    }

    Context 'validation' {

        It 'throws on an invalid clean level in config file' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{ pipeline = @(@{ action = 'Clean'; level = 'nuclear' }) } | ConvertTo-Json -Depth 5)

            { Get-DelphiCiConfig -ConfigFile $cfgFile } | Should -Throw
        }

        It 'throws on an invalid build engine in config file' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{ pipeline = @(@{ action = 'Build'; engine = 'Turbo' }) } | ConvertTo-Json -Depth 5)

            { Get-DelphiCiConfig -ConfigFile $cfgFile } | Should -Throw
        }

        It 'throws when the config file does not exist' {
            { Get-DelphiCiConfig -ConfigFile (Join-Path $TestDrive 'nonexistent.json') } | Should -Throw
        }

    }

}
