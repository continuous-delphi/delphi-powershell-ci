#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

# Import at script scope so the module is available during Pester discovery,
# which is required for InModuleScope to resolve the module name.
Import-Module ([System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..' 'source' 'Delphi.PowerShell.CI.psm1'))) -Force

InModuleScope 'Delphi.PowerShell.CI' {

    Describe 'Find-DelphiProjects' {

        Context 'finds a project in the root directory' {

            It 'returns the path when one .dproj exists in root' {
                $d = Join-Path $TestDrive 'test01'
                $null = New-Item -ItemType Directory -Path $d
                $null = New-Item -Path (Join-Path $d 'MyApp.dproj') -ItemType File
                $result = Find-DelphiProjects -Root $d
                $result | Should -HaveCount 1
                $result | Should -BeLike '*MyApp.dproj'
            }

            It 'returns all paths when multiple .dproj files exist in root' {
                $d = Join-Path $TestDrive 'test02'
                $null = New-Item -ItemType Directory -Path $d
                $null = New-Item -Path (Join-Path $d 'MyApp.dproj')       -ItemType File
                $null = New-Item -Path (Join-Path $d 'MyApp.Tests.dproj') -ItemType File
                $result = Find-DelphiProjects -Root $d
                $result | Should -HaveCount 2
            }

            It 'does not search subdirectories recursively' {
                $d   = Join-Path $TestDrive 'test03'
                $sub = Join-Path $d 'nested'
                $null = New-Item -ItemType Directory -Path $d
                $null = New-Item -ItemType Directory -Path $sub
                $null = New-Item -Path (Join-Path $sub 'MyApp.dproj') -ItemType File
                $result = Find-DelphiProjects -Root $d
                $result | Should -BeNullOrEmpty
            }

        }

        Context 'searches root/source when root has no .dproj' {

            It 'returns the path when one .dproj exists in root/source' {
                $d   = Join-Path $TestDrive 'test04'
                $src = Join-Path $d 'source'
                $null = New-Item -ItemType Directory -Path $d
                $null = New-Item -ItemType Directory -Path $src
                $null = New-Item -Path (Join-Path $src 'MyApp.dproj') -ItemType File
                $result = Find-DelphiProjects -Root $d
                $result | Should -HaveCount 1
                $result | Should -BeLike '*source*MyApp.dproj'
            }

            It 'stops at root when root already has results' {
                $d   = Join-Path $TestDrive 'test05'
                $src = Join-Path $d 'source'
                $null = New-Item -ItemType Directory -Path $d
                $null = New-Item -ItemType Directory -Path $src
                $null = New-Item -Path (Join-Path $d   'RootApp.dproj')   -ItemType File
                $null = New-Item -Path (Join-Path $src 'SourceApp.dproj') -ItemType File
                $result = Find-DelphiProjects -Root $d
                $result | Should -HaveCount 1
                $result | Should -BeLike '*RootApp.dproj'
            }

        }

        Context 'tools-folder convention: searches ../source when root and root/source have no .dproj' {

            It 'returns the path when one .dproj exists in root/../source' {
                # Simulate: Root is /tools, project lives in /source
                $base   = Join-Path $TestDrive 'test06'
                $tools  = Join-Path $base 'tools'
                $src    = Join-Path $base 'source'
                $null   = New-Item -ItemType Directory -Path $base
                $null   = New-Item -ItemType Directory -Path $tools
                $null   = New-Item -ItemType Directory -Path $src
                $null   = New-Item -Path (Join-Path $src 'MyApp.dproj') -ItemType File
                $result = Find-DelphiProjects -Root $tools
                $result | Should -HaveCount 1
                $result | Should -BeLike '*source*MyApp.dproj'
            }

            It 'stops at root/source when root/source already has results' {
                $base   = Join-Path $TestDrive 'test07'
                $tools  = Join-Path $base 'tools'
                $src    = Join-Path $base 'source'
                $null   = New-Item -ItemType Directory -Path $base
                $null   = New-Item -ItemType Directory -Path $tools
                $null   = New-Item -ItemType Directory -Path $src
                $null   = New-Item -Path (Join-Path $src 'LocalApp.dproj') -ItemType File
                # No .dproj in tools itself, but one in tools/../source (= base/source)
                $result = Find-DelphiProjects -Root $tools
                $result | Should -HaveCount 1
                $result | Should -BeLike '*source*LocalApp.dproj'
            }

        }

        Context 'returns empty when no .dproj found anywhere' {

            It 'returns an empty collection when root is empty' {
                $d = Join-Path $TestDrive 'test08'
                $null = New-Item -ItemType Directory -Path $d
                $result = Find-DelphiProjects -Root $d
                $result | Should -BeNullOrEmpty
            }

            It 'returns an empty collection when directories exist but contain no .dproj' {
                $d   = Join-Path $TestDrive 'test09'
                $src = Join-Path $d 'source'
                $null = New-Item -ItemType Directory -Path $d
                $null = New-Item -ItemType Directory -Path $src
                $null = New-Item -Path (Join-Path $src 'readme.txt') -ItemType File
                $result = Find-DelphiProjects -Root $d
                $result | Should -BeNullOrEmpty
            }

        }

    }

}
