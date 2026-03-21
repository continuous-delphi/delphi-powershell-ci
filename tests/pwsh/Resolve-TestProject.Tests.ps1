#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

Import-Module ([System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..' 'source' 'Delphi.PowerShell.CI.psm1'))) -Force

InModuleScope 'Delphi.PowerShell.CI' {

    # Each test gets its own isolated root directory under $TestDrive.
    function script:New-IsolatedRoot {
        $dir = Join-Path $TestDrive ([System.Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir | Out-Null
        return $dir
    }

    Describe 'Resolve-TestProject' {

        Context 'explicit TestProjectFile' {

            It 'returns the path when the file exists' {
                $root = script:New-IsolatedRoot
                $file = Join-Path $root 'MyApp.Tests.dproj'
                Set-Content -LiteralPath $file -Value ''
                Resolve-TestProject -Root $root -TestProjectFile $file |
                    Should -Be ([System.IO.Path]::GetFullPath($file))
            }

            It 'returns an absolute path even when given a rooted path' {
                $root = script:New-IsolatedRoot
                $file = Join-Path $root 'MyApp.Tests.dproj'
                Set-Content -LiteralPath $file -Value ''
                $result = Resolve-TestProject -Root $root -TestProjectFile $file
                [System.IO.Path]::IsPathRooted($result) | Should -Be $true
            }

            It 'throws when the explicit file does not exist' {
                $root = script:New-IsolatedRoot
                { Resolve-TestProject -Root $root -TestProjectFile 'C:\DoesNotExist\App.Tests.dproj' } |
                    Should -Throw
            }

        }

        Context 'discovery -- tests/ subfolder' {

            It 'returns the single .dproj found in tests/' {
                $root     = script:New-IsolatedRoot
                $testsDir = Join-Path $root 'tests'
                New-Item -ItemType Directory -Path $testsDir | Out-Null
                $file = Join-Path $testsDir 'App.Tests.dproj'
                Set-Content -LiteralPath $file -Value ''
                Resolve-TestProject -Root $root |
                    Should -Be ([System.IO.Path]::GetFullPath($file))
            }

            It 'returns the single .dpr found in tests/' {
                $root     = script:New-IsolatedRoot
                $testsDir = Join-Path $root 'tests'
                New-Item -ItemType Directory -Path $testsDir | Out-Null
                $file = Join-Path $testsDir 'App.Tests.dpr'
                Set-Content -LiteralPath $file -Value ''
                Resolve-TestProject -Root $root |
                    Should -Be ([System.IO.Path]::GetFullPath($file))
            }

            It 'prefers .dproj over .dpr when both exist for the same base name in tests/' {
                $root     = script:New-IsolatedRoot
                $testsDir = Join-Path $root 'tests'
                New-Item -ItemType Directory -Path $testsDir | Out-Null
                $dproj = Join-Path $testsDir 'App.Tests.dproj'
                $dpr   = Join-Path $testsDir 'App.Tests.dpr'
                Set-Content -LiteralPath $dproj -Value ''
                Set-Content -LiteralPath $dpr   -Value ''
                Resolve-TestProject -Root $root |
                    Should -Be ([System.IO.Path]::GetFullPath($dproj))
            }

            It 'throws when multiple .dproj files exist in tests/' {
                $root     = script:New-IsolatedRoot
                $testsDir = Join-Path $root 'tests'
                New-Item -ItemType Directory -Path $testsDir | Out-Null
                Set-Content -LiteralPath (Join-Path $testsDir 'A.Tests.dproj') -Value ''
                Set-Content -LiteralPath (Join-Path $testsDir 'B.Tests.dproj') -Value ''
                { Resolve-TestProject -Root $root } | Should -Throw
            }

        }

        Context 'discovery -- root folder name convention' {

            It 'returns a .dproj whose name ends with Tests' {
                $root = script:New-IsolatedRoot
                $file = Join-Path $root 'MyApp.Tests.dproj'
                Set-Content -LiteralPath $file -Value ''
                Resolve-TestProject -Root $root |
                    Should -Be ([System.IO.Path]::GetFullPath($file))
            }

            It 'returns a .dproj whose name starts with Tests' {
                $root = script:New-IsolatedRoot
                $file = Join-Path $root 'TestsMyApp.dproj'
                Set-Content -LiteralPath $file -Value ''
                Resolve-TestProject -Root $root |
                    Should -Be ([System.IO.Path]::GetFullPath($file))
            }

            It 'returns a .dpr whose name ends with Tests' {
                $root = script:New-IsolatedRoot
                $file = Join-Path $root 'MyApp.Tests.dpr'
                Set-Content -LiteralPath $file -Value ''
                Resolve-TestProject -Root $root |
                    Should -Be ([System.IO.Path]::GetFullPath($file))
            }

            It 'prefers .dproj over .dpr when both exist for the same base name in root' {
                $root  = script:New-IsolatedRoot
                $dproj = Join-Path $root 'MyApp.Tests.dproj'
                $dpr   = Join-Path $root 'MyApp.Tests.dpr'
                Set-Content -LiteralPath $dproj -Value ''
                Set-Content -LiteralPath $dpr   -Value ''
                Resolve-TestProject -Root $root |
                    Should -Be ([System.IO.Path]::GetFullPath($dproj))
            }

            It 'throws when multiple test-named .dproj files exist in root' {
                $root = script:New-IsolatedRoot
                Set-Content -LiteralPath (Join-Path $root 'App.Tests.dproj')  -Value ''
                Set-Content -LiteralPath (Join-Path $root 'Other.Tests.dproj') -Value ''
                { Resolve-TestProject -Root $root } | Should -Throw
            }

            It 'ignores a .dproj whose name does not match the Tests convention' {
                $root = script:New-IsolatedRoot
                Set-Content -LiteralPath (Join-Path $root 'MyApp.dproj') -Value ''
                Resolve-TestProject -Root $root | Should -BeNullOrEmpty
            }

        }

        Context 'precedence -- tests/ beats root convention' {

            It 'returns the tests/ result when both tests/ and a root Tests.dproj exist' {
                $root     = script:New-IsolatedRoot
                $testsDir = Join-Path $root 'tests'
                New-Item -ItemType Directory -Path $testsDir | Out-Null
                $inTests = Join-Path $testsDir 'App.Tests.dproj'
                Set-Content -LiteralPath $inTests -Value ''
                Set-Content -LiteralPath (Join-Path $root 'Root.Tests.dproj') -Value ''
                Resolve-TestProject -Root $root |
                    Should -Be ([System.IO.Path]::GetFullPath($inTests))
            }

        }

        Context 'nothing found' {

            It 'returns null when no test project exists' {
                $root = script:New-IsolatedRoot
                Resolve-TestProject -Root $root | Should -BeNullOrEmpty
            }

        }

        Context 'integration -- ConsoleProjectGroup' {

            It 'discovers ConsoleProject.Tests.dproj in tests/' {
                $root = [System.IO.Path]::GetFullPath(
                    (Join-Path $PSScriptRoot '..\..' 'Examples\ConsoleProjectGroup')
                )
                $result = Resolve-TestProject -Root $root
                $result | Should -Not -BeNullOrEmpty
                [System.IO.Path]::GetFileName($result) | Should -Be 'ConsoleProject.Tests.dproj'
            }

        }

    }

}
