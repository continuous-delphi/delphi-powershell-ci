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

        It 'returns false as default build noConfig' {
            $config = Get-DelphiCiConfig
            $config.Pipeline[1].Defaults['noConfig'] | Should -Be $false
        }

        It 'sets build noConfig true when -NoConfig is supplied' {
            $config = Get-DelphiCiConfig -NoConfig
            $config.Pipeline[1].Defaults['noConfig'] | Should -Be $true
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

        It 'resolves a job-level noConfig true from a config file' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            $json = @{
                pipeline = @(
                    @{ action = 'Build'; engine = 'DCCBuild'; jobs = @(
                        @{ projectFile = 'src/App.dpr'; noConfig = $true }
                    )}
                )
            } | ConvertTo-Json -Depth 5
            Set-Content -LiteralPath $cfgFile -Value $json

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile
            $config.Pipeline[0].Jobs[0]['noConfig'] | Should -Be $true
        }

    }

    Context 'unsupported legacy JSON config' {

        It 'throws when a config file defines steps without pipeline' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{ steps = @('Clean') } | ConvertTo-Json)

            { Get-DelphiCiConfig -ConfigFile $cfgFile } | Should -Throw "*must define a 'pipeline' array*"
        }

        It 'throws when a config file uses named sections without pipeline' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{ build = @{ platform = 'Win64' } } | ConvertTo-Json -Depth 5)

            { Get-DelphiCiConfig -ConfigFile $cfgFile } | Should -Throw "*must define a 'pipeline' array*"
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

        It 'preserves an absolute root from the config file' {
            $subDir  = Join-Path $TestDrive 'ci'
            $rootDir = Join-Path $TestDrive 'repo-root'
            $null    = New-Item -ItemType Directory -Path $subDir -Force
            $null    = New-Item -ItemType Directory -Path $rootDir -Force
            $cfgFile = Join-Path $subDir 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{ root = $rootDir; pipeline = @(@{ action = 'Clean' }) } | ConvertTo-Json -Depth 5)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile
            $config.Root | Should -Be ([System.IO.Path]::GetFullPath($rootDir))
        }

    }

    Context 'CLI overrides beat config file values' {

        It '-Platform overrides config file platform' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{
                defaults = @{ build = @{ platform = 'Win32' } }
                pipeline = @(@{ action = 'Build' })
            } | ConvertTo-Json -Depth 5)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile -Platform 'Win64'
            $config.Pipeline[0].Defaults['platform'] | Should -Be 'Win64'
        }

        It '-Configuration overrides config file configuration' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{
                defaults = @{ build = @{ configuration = 'Debug' } }
                pipeline = @(@{ action = 'Build' })
            } | ConvertTo-Json -Depth 5)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile -Configuration 'Release'
            $config.Pipeline[0].Defaults['configuration'] | Should -Be 'Release'
        }

        It '-Steps does not override a config file pipeline' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{ pipeline = @(@{ action = 'Clean' }) } | ConvertTo-Json -Depth 5)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile -Steps 'Build'
            $config.Pipeline.Count | Should -Be 1
            $config.Pipeline[0].Action | Should -Be 'Clean'
        }

        It '-Toolchain overrides config file toolchain version' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{
                defaults = @{ build = @{ toolchain = @{ version = 'Athens' } } }
                pipeline = @(@{ action = 'Build' })
            } | ConvertTo-Json -Depth 5)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile -Toolchain 'Florence'
            $config.Pipeline[0].Defaults['toolchain']['version'] | Should -Be 'Florence'
        }

        It 'carries toolchain.rootDir from the config file through resolution' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{
                defaults = @{ build = @{ toolchain = @{ rootDir = 'G:\rad\rad-buildfiles-d28' } } }
                pipeline = @(@{ action = 'Build' })
            } | ConvertTo-Json -Depth 5)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile
            $config.Pipeline[0].Defaults['toolchain']['rootDir'] | Should -Be 'G:\rad\rad-buildfiles-d28'
            # version default is preserved by the shallow toolchain merge
            $config.Pipeline[0].Defaults['toolchain']['version'] | Should -Be 'Latest'
        }

        It '-ToolchainRootDir overrides config file toolchain rootDir' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{
                defaults = @{ build = @{ toolchain = @{ rootDir = 'G:\rad\old' } } }
                pipeline = @(@{ action = 'Build' })
            } | ConvertTo-Json -Depth 5)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile -ToolchainRootDir 'G:\rad\new'
            $config.Pipeline[0].Defaults['toolchain']['rootDir'] | Should -Be 'G:\rad\new'
        }

        It '-BuildEngine overrides config file engine' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{
                defaults = @{ build = @{ engine = 'MSBuild' } }
                pipeline = @(@{ action = 'Build' })
            } | ConvertTo-Json -Depth 5)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile -BuildEngine 'DCCBuild'
            $config.Pipeline[0].Defaults['engine'] | Should -Be 'DCCBuild'
        }

        It '-Defines overrides config file defines' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{
                defaults = @{ build = @{ defines = @('FROM_FILE') } }
                pipeline = @(@{ action = 'Build' })
            } | ConvertTo-Json -Depth 5)

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

        It '-ToolchainRootDir sets toolchain.rootDir while preserving version default' {
            $config = Get-DelphiCiConfig -ToolchainRootDir 'G:\rad\rad-buildfiles-d28'
            $config.Pipeline[1].Defaults['toolchain']['rootDir'] | Should -Be 'G:\rad\rad-buildfiles-d28'
            $config.Pipeline[1].Defaults['toolchain']['version'] | Should -Be 'Latest'
        }

        It 'leaves toolchain.rootDir unset when -ToolchainRootDir is not supplied' {
            $config = Get-DelphiCiConfig
            $config.Pipeline[1].Defaults['toolchain'].ContainsKey('rootDir') | Should -Be $false
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

    Context 'incver defaults and pipeline resolution' {

        It 'incver action gets empty defaults for target, style, part, and pattern' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{
                pipeline = @(@{ action = 'IncVer'; jobs = @(@{ file = 'ver.rc' }) })
            } | ConvertTo-Json -Depth 5)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile
            $job = $config.Pipeline[0].Jobs[0]
            $job['target']  | Should -Be ''
            $job['style']   | Should -Be ''
            $job['part']    | Should -Be ''
            $job['pattern'] | Should -Be ''
        }

        It 'incver defaults dateformat to yyyy.mm.dd' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{
                pipeline = @(@{ action = 'IncVer'; jobs = @(@{ file = 'ver.rc' }) })
            } | ConvertTo-Json -Depth 5)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile
            $config.Pipeline[0].Jobs[0]['dateformat'] | Should -Be 'yyyy.mm.dd'
        }

        It 'incver defaults section merges into job' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{
                defaults = @{ incver = @{ target = 'RC'; style = 'WinVer'; part = 'build' } }
                pipeline = @(@{ action = 'IncVer'; jobs = @(@{ file = 'ver.rc' }) })
            } | ConvertTo-Json -Depth 5)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile
            $job = $config.Pipeline[0].Jobs[0]
            $job['target'] | Should -Be 'RC'
            $job['style']  | Should -Be 'WinVer'
            $job['part']   | Should -Be 'build'
        }

        It 'job-level properties override defaults' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{
                defaults = @{ incver = @{ target = 'RC'; part = 'build' } }
                pipeline = @(@{ action = 'IncVer'; jobs = @(@{ file = 'tool.ps1'; target = 'Text'; style = 'SemVer'; part = 'minor' }) })
            } | ConvertTo-Json -Depth 5)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile
            $job = $config.Pipeline[0].Jobs[0]
            $job['target'] | Should -Be 'Text'
            $job['style']  | Should -Be 'SemVer'
            $job['part']   | Should -Be 'minor'
        }

    }

    Context 'incver CLI overrides' {

        It '-IncverTarget overrides default' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{
                pipeline = @(@{ action = 'IncVer'; jobs = @(@{ file = 'ver.rc' }) })
            } | ConvertTo-Json -Depth 5)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile -IncverTarget 'Text'
            $config.Pipeline[0].Jobs[0]['target'] | Should -Be 'Text'
        }

        It '-IncverStyle overrides default' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{
                pipeline = @(@{ action = 'IncVer'; jobs = @(@{ file = 'ver.txt' }) })
            } | ConvertTo-Json -Depth 5)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile -IncverStyle 'WinVer'
            $config.Pipeline[0].Jobs[0]['style'] | Should -Be 'WinVer'
        }

        It '-IncverPart overrides default' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{
                pipeline = @(@{ action = 'IncVer'; jobs = @(@{ file = 'ver.rc' }) })
            } | ConvertTo-Json -Depth 5)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile -IncverPart 'minor'
            $config.Pipeline[0].Jobs[0]['part'] | Should -Be 'minor'
        }

        It '-IncverFile creates a single incver job' {
            $config = Get-DelphiCiConfig -Steps 'IncVer' -IncverFile 'ver.rc'
            $config.Pipeline[0].Action | Should -Be 'IncVer'
            $config.Pipeline[0].Jobs.Count | Should -Be 1
            $config.Pipeline[0].Jobs[0]['file'] | Should -Be 'ver.rc'
        }

    }

    Context 'incver validation' {

        It 'throws on an invalid incver target' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{
                pipeline = @(@{ action = 'IncVer'; target = 'Binary' })
            } | ConvertTo-Json -Depth 5)

            { Get-DelphiCiConfig -ConfigFile $cfgFile } | Should -Throw '*Invalid incver target*'
        }

        It 'throws on an invalid incver style' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{
                pipeline = @(@{ action = 'IncVer'; style = 'CalVer' })
            } | ConvertTo-Json -Depth 5)

            { Get-DelphiCiConfig -ConfigFile $cfgFile } | Should -Throw '*Invalid incver style*'
        }

        It 'throws on RC target with SemVer style' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{
                pipeline = @(@{ action = 'IncVer'; target = 'RC'; style = 'SemVer' })
            } | ConvertTo-Json -Depth 5)

            { Get-DelphiCiConfig -ConfigFile $cfgFile } | Should -Throw '*RC*SemVer*'
        }

        It 'throws on an invalid incver part' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{
                pipeline = @(@{ action = 'IncVer'; part = 'revision' })
            } | ConvertTo-Json -Depth 5)

            { Get-DelphiCiConfig -ConfigFile $cfgFile } | Should -Throw '*Invalid incver part*'
        }

    }

    Context 'copy defaults and pipeline resolution' {

        It 'copy action gets correct defaults' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{
                pipeline = @(@{ action = 'Copy'; jobs = @(@{ source = 'src/*.exe'; destination = 'dist/' }) })
            } | ConvertTo-Json -Depth 5)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile
            $job = $config.Pipeline[0].Jobs[0]
            $job['flatten']           | Should -Be $false
            $job['overwrite']         | Should -Be $true
            $job['createDestination'] | Should -Be $true
            $job['checksum']          | Should -Be $false
        }

        It '-CopySource creates a single copy job' {
            $config = Get-DelphiCiConfig -Steps 'Copy' -CopySource 'src/*.exe' -CopyDestination 'dist/'
            $config.Pipeline[0].Action | Should -Be 'Copy'
            $config.Pipeline[0].Jobs.Count | Should -Be 1
            $config.Pipeline[0].Jobs[0]['source'] | Should -Be 'src/*.exe'
        }

    }

    Context 'compress defaults and pipeline resolution' {

        It 'compress action gets correct defaults' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{
                pipeline = @(@{ action = 'Compress'; jobs = @(@{ source = 'dist/'; destination = 'out.zip' }) })
            } | ConvertTo-Json -Depth 5)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile
            $job = $config.Pipeline[0].Jobs[0]
            $job['overwrite'] | Should -Be $true
            $job['checksum']  | Should -Be $false
        }

        It '-CompressSource creates a single compress job' {
            $config = Get-DelphiCiConfig -Steps 'Compress' -CompressSource 'dist/' -CompressDestination 'out.zip'
            $config.Pipeline[0].Action | Should -Be 'Compress'
            $config.Pipeline[0].Jobs.Count | Should -Be 1
            $config.Pipeline[0].Jobs[0]['source'] | Should -Be 'dist/'
        }

    }

    Context 'coverage defaults and pipeline resolution' {

        It 'coverage action gets correct defaults' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{
                pipeline = @(@{ action = 'Coverage'; jobs = @(@{ execute = 'test.exe'; mapFile = 'test.map' }) })
            } | ConvertTo-Json -Depth 5)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile
            $job = $config.Pipeline[0].Jobs[0]
            $job['engine']    | Should -Be 'DelphiCodeCoverage'
            $job['outputDir'] | Should -Be 'coverage'
            $job['threshold'] | Should -Be 0
            $job['formats']   | Should -Contain 'html'
        }

        It '-CoverageExecute creates a single coverage job' {
            $config = Get-DelphiCiConfig -Steps 'Coverage' -CoverageExecute 'test.exe' -CoverageMapFile 'test.map'
            $config.Pipeline[0].Action | Should -Be 'Coverage'
            $config.Pipeline[0].Jobs.Count | Should -Be 1
            $config.Pipeline[0].Jobs[0]['execute'] | Should -Be 'test.exe'
        }

    }

    Context 'coverage validation' {

        It 'throws on an invalid coverage engine' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{
                pipeline = @(@{ action = 'Coverage'; engine = 'FakeEngine' })
            } | ConvertTo-Json -Depth 5)

            { Get-DelphiCiConfig -ConfigFile $cfgFile } | Should -Throw '*Invalid coverage engine*'
        }

        It 'throws on an invalid coverage format' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{
                pipeline = @(@{ action = 'Coverage'; formats = @('pdf') })
            } | ConvertTo-Json -Depth 5)

            { Get-DelphiCiConfig -ConfigFile $cfgFile } | Should -Throw '*Invalid coverage format*'
        }

    }

    Context 'callgraph defaults and pipeline resolution' {

        It 'callgraph action gets correct defaults' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{
                pipeline = @(@{ action = 'CallGraph'; jobs = @(@{ path = @('source') }) })
            } | ConvertTo-Json -Depth 5)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile
            $job = $config.Pipeline[0].Jobs[0]
            $job['engine']      | Should -Be 'radCallGraph'
            $job['outputDir']   | Should -Be 'callgraph'
            $job['annotations'] | Should -Be $true
            $job['deterministic'] | Should -Be $true
            $job['formats']     | Should -Contain 'json'
        }

        It '-CallGraphDeterministic can disable deterministic output' {
            $config = Get-DelphiCiConfig -Steps 'CallGraph' -CallGraphPath 'source' -CallGraphDeterministic $false
            $config.Pipeline[0].Jobs[0]['deterministic'] | Should -Be $false
        }

        It '-CallGraphPath creates a single callgraph job' {
            $config = Get-DelphiCiConfig -Steps 'CallGraph' -CallGraphPath 'source'
            $config.Pipeline[0].Action | Should -Be 'CallGraph'
            $config.Pipeline[0].Jobs.Count | Should -Be 1
            $config.Pipeline[0].Jobs[0]['path'] | Should -Contain 'source'
        }

        It '-CallGraphProjectFile creates a single callgraph job' {
            $config = Get-DelphiCiConfig -Steps 'CallGraph' -CallGraphProjectFile 'source/App.dpr'
            $config.Pipeline[0].Jobs.Count | Should -Be 1
            $config.Pipeline[0].Jobs[0]['projectFile'] | Should -Be 'source/App.dpr'
        }

    }

    Context 'callgraph validation' {

        It 'throws on an invalid callgraph engine' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{
                pipeline = @(@{ action = 'CallGraph'; engine = 'FakeEngine' })
            } | ConvertTo-Json -Depth 5)

            { Get-DelphiCiConfig -ConfigFile $cfgFile } | Should -Throw '*Invalid callgraph engine*'
        }

        It 'throws on an invalid callgraph format' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{
                pipeline = @(@{ action = 'CallGraph'; formats = @('xml') })
            } | ConvertTo-Json -Depth 5)

            { Get-DelphiCiConfig -ConfigFile $cfgFile } | Should -Throw '*Invalid callgraph format*'
        }

        It 'throws on an invalid callgraph graphKind' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{
                pipeline = @(@{ action = 'CallGraph'; graphKind = 'packages' })
            } | ConvertTo-Json -Depth 5)

            { Get-DelphiCiConfig -ConfigFile $cfgFile } | Should -Throw '*Invalid callgraph graphKind*'
        }

    }

    Context 'format defaults and pipeline resolution' {

        It 'format action gets correct defaults' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{
                pipeline = @(@{ action = 'Format' })
            } | ConvertTo-Json -Depth 5)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile
            $defaults = $config.Pipeline[0].Defaults
            $defaults['engine']        | Should -Be 'formatter'
            $defaults['outputLevel']   | Should -Be 'detailed'
            $defaults['createBackups'] | Should -Be $false
            $defaults['check']         | Should -Be $false
        }

        It 'injects the CI root as the format action default root' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{ pipeline = @(@{ action = 'Format' }) } | ConvertTo-Json -Depth 5)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile
            $config.Pipeline[0].Defaults['root'] | Should -Be ([System.IO.Path]::GetFullPath($TestDrive))
        }

        It 'format defaults section merges into job' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{
                defaults = @{ format = @{ engine = 'radFormatter'; check = $true } }
                pipeline = @(@{ action = 'Format'; jobs = @(@{ name = 'src' }) })
            } | ConvertTo-Json -Depth 5)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile
            $job = $config.Pipeline[0].Jobs[0]
            $job['engine'] | Should -Be 'radFormatter'
            $job['check']  | Should -Be $true
        }

        It 'job-level format properties override action-level' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{
                pipeline = @(@{ action = 'Format'; engine = 'formatter'; jobs = @(@{ engine = 'radFormatter' }) })
            } | ConvertTo-Json -Depth 5)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile
            $config.Pipeline[0].Jobs[0]['engine'] | Should -Be 'radFormatter'
        }

        It 'format includeFilePattern arrays append across merge levels' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            $json = @{
                defaults = @{ format = @{ includeFilePattern = @('*.pas') } }
                pipeline = @(@{ action = 'Format'; includeFilePattern = @('*.inc'); jobs = @(@{ includeFilePattern = @('*.dpr') }) })
            } | ConvertTo-Json -Depth 5
            Set-Content -LiteralPath $cfgFile -Value $json

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile
            $config.Pipeline[0].Jobs[0]['includeFilePattern'] | Should -Be @('*.pas', '*.inc', '*.dpr')
        }

    }

    Context 'format CLI overrides' {

        It '-FormatEngine overrides default engine' {
            $config = Get-DelphiCiConfig -Steps 'Format' -FormatEngine 'radFormatter'
            $config.Pipeline[0].Defaults['engine'] | Should -Be 'radFormatter'
        }

        It '-FormatCheck sets the check flag' {
            $config = Get-DelphiCiConfig -Steps 'Format' -FormatCheck $true
            $config.Pipeline[0].Defaults['check'] | Should -Be $true
        }

        It '-FormatOutputLevel overrides default output level' {
            $config = Get-DelphiCiConfig -Steps 'Format' -FormatOutputLevel 'quiet'
            $config.Pipeline[0].Defaults['outputLevel'] | Should -Be 'quiet'
        }

        It '-FormatPath replaces the path list' {
            $config = Get-DelphiCiConfig -Steps 'Format' -FormatPath 'source', 'tests'
            $config.Pipeline[0].Defaults['path'] | Should -Be @('source', 'tests')
        }

    }

    Context 'format validation' {

        It 'throws on an invalid format engine' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{
                pipeline = @(@{ action = 'Format'; engine = 'astyle' })
            } | ConvertTo-Json -Depth 5)

            { Get-DelphiCiConfig -ConfigFile $cfgFile } | Should -Throw '*Invalid format engine*'
        }

        It 'throws on an invalid format output level' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{
                pipeline = @(@{ action = 'Format'; outputLevel = 'verbose' })
            } | ConvertTo-Json -Depth 5)

            { Get-DelphiCiConfig -ConfigFile $cfgFile } | Should -Throw '*Invalid format output level*'
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
