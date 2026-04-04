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

        It 'returns null test project file' {
            $config = Get-DelphiCiConfig
            $config.Test.TestProjectFile | Should -BeNullOrEmpty
        }

        It 'returns null test executable' {
            $config = Get-DelphiCiConfig
            $config.Test.TestExecutable | Should -BeNullOrEmpty
        }

        It 'returns empty test defines array' {
            $config = Get-DelphiCiConfig
            $config.Test.Defines | Should -BeNullOrEmpty
        }

        It 'returns 10 as default test timeout' {
            $config = Get-DelphiCiConfig
            $config.Test.TimeoutSeconds | Should -Be 10
        }

        It 'returns true for test build by default' {
            $config = Get-DelphiCiConfig
            $config.Test.Build | Should -Be $true
        }

        It 'returns true for test run by default' {
            $config = Get-DelphiCiConfig
            $config.Test.Run | Should -Be $true
        }

        It 'returns null platform when not specified (auto-resolved at run time)' {
            $config = Get-DelphiCiConfig
            $config.Build.Platform | Should -BeNullOrEmpty
        }

        It 'returns Debug configuration' {
            $config = Get-DelphiCiConfig
            $config.Build.Configuration | Should -Be 'Debug'
        }

        It 'returns MSBuild engine' {
            $config = Get-DelphiCiConfig
            $config.Build.Engine | Should -Be 'MSBuild'
        }

        It 'returns Latest as the default toolchain version' {
            $config = Get-DelphiCiConfig
            $config.Build.Toolchain.Version | Should -Be 'Latest'
        }

        It 'returns basic as the default clean level' {
            $config = Get-DelphiCiConfig
            $config.Clean.Level | Should -Be 'basic'
        }

        It 'returns empty CleanIncludeFilePattern array by default' {
            $config = Get-DelphiCiConfig
            $config.Clean.IncludeFilePattern | Should -BeNullOrEmpty
        }

        It 'returns empty CleanExcludeDirectoryPattern array by default' {
            $config = Get-DelphiCiConfig
            $config.Clean.ExcludeDirectoryPattern | Should -BeNullOrEmpty
        }

        It 'returns empty CleanConfigFile by default' {
            $config = Get-DelphiCiConfig
            $config.Clean.ConfigFile | Should -BeNullOrEmpty
        }

        It 'returns empty defines array' {
            $config = Get-DelphiCiConfig
            $config.Build.Defines | Should -BeNullOrEmpty
        }

        It 'returns null ProjectFile' {
            $config = Get-DelphiCiConfig
            $config.ProjectFile | Should -BeNullOrEmpty
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
            $config.Build.Platform | Should -Be 'Win64'
        }

        It 'loads configuration from config file' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{ build = @{ configuration = 'Release' } } | ConvertTo-Json)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile
            $config.Build.Configuration | Should -Be 'Release'
        }

        It 'loads clean level from config file' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{ clean = @{ level = 'standard' } } | ConvertTo-Json)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile
            $config.Clean.Level | Should -Be 'standard'
        }

        It 'loads clean includeFilePattern from config file' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{ clean = @{ includeFilePattern = @('*.res', '*.mab') } } | ConvertTo-Json)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile
            $config.Clean.IncludeFilePattern | Should -Be @('*.res', '*.mab')
        }

        It 'loads clean excludeDirectoryPattern from config file' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{ clean = @{ excludeDirectoryPattern = @('vendor', 'assets') } } | ConvertTo-Json)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile
            $config.Clean.ExcludeDirectoryPattern | Should -Be @('vendor', 'assets')
        }

        It 'loads clean configFile from config file' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{ clean = @{ configFile = 'C:/ci/delphi-clean-ci.json' } } | ConvertTo-Json)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile
            $config.Clean.ConfigFile | Should -Be 'C:/ci/delphi-clean-ci.json'
        }

        It 'loads toolchain version from config file' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{ build = @{ toolchain = @{ version = 'Athens' } } } | ConvertTo-Json -Depth 5)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile
            $config.Build.Toolchain.Version | Should -Be 'Athens'
        }

        It 'accepts VER### identifiers as the toolchain version' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{ build = @{ toolchain = @{ version = 'VER370' } } } | ConvertTo-Json -Depth 5)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile
            $config.Build.Toolchain.Version | Should -Be 'VER370'
        }

        It 'loads defines array from config file' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{ build = @{ defines = @('CI', 'RELEASE') } } | ConvertTo-Json)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile
            $config.Build.Defines | Should -Be @('CI', 'RELEASE')
        }

        It 'loads projectFile from build section of config file' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{ build = @{ projectFile = 'source/MyApp.dproj' } } | ConvertTo-Json)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile
            $config.ProjectFile | Should -Be 'source/MyApp.dproj'
        }

        It 'loads testProjectFile from test section of config file' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{ test = @{ testProjectFile = 'tests/MyApp.Tests.dproj' } } | ConvertTo-Json)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile
            $config.Test.TestProjectFile | Should -Be 'tests/MyApp.Tests.dproj'
        }

        It 'loads test defines from config file' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{ test = @{ defines = @('CI') } } | ConvertTo-Json)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile
            $config.Test.Defines | Should -Be @('CI')
        }

        It 'loads test timeoutSeconds from config file' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{ test = @{ timeoutSeconds = 30 } } | ConvertTo-Json)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile
            $config.Test.TimeoutSeconds | Should -Be 30
        }

        It 'loads test build flag from config file' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{ test = @{ build = $false } } | ConvertTo-Json)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile
            $config.Test.Build | Should -Be $false
        }

        It 'loads test run flag from config file' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{ test = @{ run = $false } } | ConvertTo-Json)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile
            $config.Test.Run | Should -Be $false
        }

        It 'applies built-in defaults for fields absent from config file' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{ build = @{ platform = 'Win64' } } | ConvertTo-Json)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile
            $config.Build.Configuration        | Should -Be 'Debug'
            $config.Build.Engine               | Should -Be 'MSBuild'
            $config.Clean.Level                | Should -Be 'basic'
            $config.Clean.IncludeFilePattern   | Should -BeNullOrEmpty
            $config.Clean.ConfigFile           | Should -BeNullOrEmpty
            $config.Steps                      | Should -Be @('Clean', 'Build')
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
            $config.Build.Platform | Should -Be 'Win64'
        }

        It '-Configuration overrides config file configuration' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{ build = @{ configuration = 'Debug' } } | ConvertTo-Json)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile -Configuration 'Release'
            $config.Build.Configuration | Should -Be 'Release'
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
            $config.Build.Toolchain.Version | Should -Be 'Florence'
        }

        It '-BuildEngine overrides config file engine' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{ build = @{ engine = 'MSBuild' } } | ConvertTo-Json)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile -BuildEngine 'DCCBuild'
            $config.Build.Engine | Should -Be 'DCCBuild'
        }

        It '-Defines overrides config file defines' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{ build = @{ defines = @('FROM_FILE') } } | ConvertTo-Json)

            $config = Get-DelphiCiConfig -ConfigFile $cfgFile -Defines 'CI', 'RELEASE_BUILD'
            $config.Build.Defines | Should -Be @('CI', 'RELEASE_BUILD')
        }

        It '-Root overrides root derived from config file location' {
            $cfgFile = Join-Path $TestDrive 'test.json'
            Set-Content -LiteralPath $cfgFile -Value (@{} | ConvertTo-Json)

            $override = Join-Path $TestDrive 'custom-root'
            $null     = New-Item -ItemType Directory -Path $override
            $config   = Get-DelphiCiConfig -ConfigFile $cfgFile -Root $override
            $config.Root | Should -Be ([System.IO.Path]::GetFullPath($override))
        }

    }

    Context 'CLI overrides beat built-in defaults' {

        It '-Platform overrides default platform' {
            $config = Get-DelphiCiConfig -Platform 'Win64'
            $config.Build.Platform | Should -Be 'Win64'
        }

        It '-Configuration overrides default configuration' {
            $config = Get-DelphiCiConfig -Configuration 'Release'
            $config.Build.Configuration | Should -Be 'Release'
        }

        It '-Steps overrides default steps' {
            $config = Get-DelphiCiConfig -Steps 'Clean'
            $config.Steps | Should -Be @('Clean')
        }

        It '-Toolchain overrides default toolchain version' {
            $config = Get-DelphiCiConfig -Toolchain 'VER370'
            $config.Build.Toolchain.Version | Should -Be 'VER370'
        }

        It '-BuildEngine overrides default engine' {
            $config = Get-DelphiCiConfig -BuildEngine 'DCCBuild'
            $config.Build.Engine | Should -Be 'DCCBuild'
        }

        It '-Defines overrides default empty defines' {
            $config = Get-DelphiCiConfig -Defines 'CI'
            $config.Build.Defines | Should -Be @('CI')
        }

        It '-CleanLevel overrides default basic level' {
            $config = Get-DelphiCiConfig -CleanLevel 'deep'
            $config.Clean.Level | Should -Be 'deep'
        }

        It '-CleanIncludeFilePattern overrides default empty array' {
            $config = Get-DelphiCiConfig -CleanIncludeFilePattern '*.res', '*.mab'
            $config.Clean.IncludeFilePattern | Should -Be @('*.res', '*.mab')
        }

        It '-CleanExcludeDirectoryPattern overrides default empty array' {
            $config = Get-DelphiCiConfig -CleanExcludeDirectoryPattern 'vendor', 'assets'
            $config.Clean.ExcludeDirectoryPattern | Should -Be @('vendor', 'assets')
        }

        It '-CleanConfigFile overrides default empty CleanConfigFile' {
            $config = Get-DelphiCiConfig -CleanConfigFile 'C:/ci/delphi-clean-ci.json'
            $config.Clean.ConfigFile | Should -Be 'C:/ci/delphi-clean-ci.json'
        }

        It '-TestProjectFile overrides default null test project file' {
            $config = Get-DelphiCiConfig -TestProjectFile 'tests/MyApp.Tests.dproj'
            $config.Test.TestProjectFile | Should -Be 'tests/MyApp.Tests.dproj'
        }

        It '-TestExecutable overrides default null test executable' {
            $config = Get-DelphiCiConfig -TestExecutable 'C:\Build\Tests\Win32\Debug\App.Tests.exe'
            $config.Test.TestExecutable | Should -Be 'C:\Build\Tests\Win32\Debug\App.Tests.exe'
        }

        It '-TestDefines overrides default empty test defines' {
            $config = Get-DelphiCiConfig -TestDefines 'CI'
            $config.Test.Defines | Should -Be @('CI')
        }

        It '-TestTimeoutSeconds overrides default timeout' {
            $config = Get-DelphiCiConfig -TestTimeoutSeconds 5
            $config.Test.TimeoutSeconds | Should -Be 5
        }

        It '-TestBuild $false overrides default true' {
            $config = Get-DelphiCiConfig -TestBuild $false
            $config.Test.Build | Should -Be $false
        }

        It '-TestRun $false overrides default true' {
            $config = Get-DelphiCiConfig -TestRun $false
            $config.Test.Run | Should -Be $false
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
            $config.Build.Defines | Should -Be @('CI', 'RELEASE_BUILD')
        }

        It 'splits Defines and trims surrounding spaces' {
            $config = Get-DelphiCiConfig -Defines 'CI, RELEASE_BUILD'
            $config.Build.Defines | Should -Be @('CI', 'RELEASE_BUILD')
        }

        It 'treats an already-split array of steps as-is' {
            $config = Get-DelphiCiConfig -Steps @('Clean', 'Build')
            $config.Steps | Should -Be @('Clean', 'Build')
        }

        It 'treats an already-split array of defines as-is' {
            $config = Get-DelphiCiConfig -Defines @('CI', 'RELEASE_BUILD')
            $config.Build.Defines | Should -Be @('CI', 'RELEASE_BUILD')
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
