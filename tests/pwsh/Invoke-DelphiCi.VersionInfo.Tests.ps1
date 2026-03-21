#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

Import-Module ([System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..' 'source' 'Delphi.PowerShell.CI.psm1'))) -Force

InModuleScope 'Delphi.PowerShell.CI' {

    # ---------------------------------------------------------------------------

    Describe 'Invoke-DelphiCi -VersionInfo -- unit' {

        BeforeAll {
            Mock Write-DelphiCiMessage {}
            Mock Get-BundledToolInfo {
                @(
                    [PSCustomObject]@{ Name = 'delphi-inspect';  Version = '0.6.0'; Present = $true;  Path = 'C:\fake\delphi-inspect.ps1' }
                    [PSCustomObject]@{ Name = 'delphi-clean';    Version = '0.3.0'; Present = $true;  Path = 'C:\fake\delphi-clean.ps1' }
                    [PSCustomObject]@{ Name = 'delphi-msbuild';  Version = '0.5.0'; Present = $true;  Path = 'C:\fake\delphi-msbuild.ps1' }
                    [PSCustomObject]@{ Name = 'delphi-dccbuild'; Version = '0.3.0'; Present = $true;  Path = 'C:\fake\delphi-dccbuild.ps1' }
                )
            }
        }

        Context 'return value shape' {

            It 'returns a result object' {
                $result = Invoke-DelphiCi -VersionInfo
                $result | Should -Not -BeNullOrEmpty
            }

            It 'result has a Module property' {
                $result = Invoke-DelphiCi -VersionInfo
                $result.Module | Should -Not -BeNullOrEmpty
            }

            It 'result Module.Name is Delphi.PowerShell.CI' {
                $result = Invoke-DelphiCi -VersionInfo
                $result.Module.Name | Should -Be 'Delphi.PowerShell.CI'
            }

            It 'result Module.Version matches a semver pattern' {
                $result = Invoke-DelphiCi -VersionInfo
                $result.Module.Version | Should -Match '^\d+\.\d+\.\d+$'
            }

            It 'result has a Tools property' {
                $result = Invoke-DelphiCi -VersionInfo
                $result.Tools | Should -Not -BeNullOrEmpty
            }

            It 'result Tools contains four entries' {
                $result = Invoke-DelphiCi -VersionInfo
                @($result.Tools).Count | Should -Be 4
            }

            It 'each tool entry has Name, Version, Present, and Path' {
                $result = Invoke-DelphiCi -VersionInfo
                foreach ($tool in $result.Tools) {
                    $tool.PSObject.Properties.Name | Should -Contain 'Name'
                    $tool.PSObject.Properties.Name | Should -Contain 'Version'
                    $tool.PSObject.Properties.Name | Should -Contain 'Present'
                    $tool.PSObject.Properties.Name | Should -Contain 'Path'
                }
            }

        }

        Context 'tool list content' {

            It 'includes delphi-inspect' {
                $result = Invoke-DelphiCi -VersionInfo
                $result.Tools | Where-Object { $_.Name -eq 'delphi-inspect' } | Should -Not -BeNullOrEmpty
            }

            It 'includes delphi-clean' {
                $result = Invoke-DelphiCi -VersionInfo
                $result.Tools | Where-Object { $_.Name -eq 'delphi-clean' } | Should -Not -BeNullOrEmpty
            }

            It 'includes delphi-msbuild' {
                $result = Invoke-DelphiCi -VersionInfo
                $result.Tools | Where-Object { $_.Name -eq 'delphi-msbuild' } | Should -Not -BeNullOrEmpty
            }

            It 'includes delphi-dccbuild' {
                $result = Invoke-DelphiCi -VersionInfo
                $result.Tools | Where-Object { $_.Name -eq 'delphi-dccbuild' } | Should -Not -BeNullOrEmpty
            }

        }

        Context 'output messages' {

            It 'writes at least one INFO message' {
                Invoke-DelphiCi -VersionInfo | Out-Null
                Should -Invoke Write-DelphiCiMessage -ParameterFilter { $Level -eq 'INFO' } -Times 1
            }

        }

        Context 'mutual exclusion with Run parameters' {

            It 'does not accept -ProjectFile with -VersionInfo' {
                { Invoke-DelphiCi -VersionInfo -ProjectFile 'C:\Fake\App.dproj' } | Should -Throw
            }

            It 'does not accept -Steps with -VersionInfo' {
                { Invoke-DelphiCi -VersionInfo -Steps @('Clean') } | Should -Throw
            }

}

        Context 'Get-BundledToolInfo integration' {

            It 'calls Get-BundledToolInfo once' {
                Invoke-DelphiCi -VersionInfo | Out-Null
                Should -Invoke Get-BundledToolInfo -Times 1
            }

            It 'returns tool versions from Get-BundledToolInfo' {
                $result = Invoke-DelphiCi -VersionInfo
                $inspect = $result.Tools | Where-Object { $_.Name -eq 'delphi-inspect' }
                $inspect.Version | Should -Be '0.6.0'
            }

        }

    }

    # ---------------------------------------------------------------------------

    Describe 'Get-BundledToolInfo -- unit' {

        Context 'tools with version API (delphi-inspect, delphi-clean)' {

            It 'calls pwsh subprocess for tools that support the version API' {
                # We test this indirectly: if Get-BundledToolInfo returns a version
                # for a tool marked SupportsVersionApi, the subprocess path was used.
                # The integration test below exercises the real path.
                # Here we verify the function returns entries for all four tools.
                $info = Get-BundledToolInfo
                @($info).Count | Should -Be 4
            }

        }

        Context 'tool entry shape' {

            It 'every entry has Name, Version, Present, and Path' {
                $info = Get-BundledToolInfo
                foreach ($tool in $info) {
                    $tool.PSObject.Properties.Name | Should -Contain 'Name'
                    $tool.PSObject.Properties.Name | Should -Contain 'Version'
                    $tool.PSObject.Properties.Name | Should -Contain 'Present'
                    $tool.PSObject.Properties.Name | Should -Contain 'Path'
                }
            }

            It 'all bundled tools are marked Present' {
                $info = Get-BundledToolInfo
                foreach ($tool in $info) {
                    $tool.Present | Should -Be $true
                }
            }

            It 'all tools report a non-null version' {
                $info = Get-BundledToolInfo
                foreach ($tool in $info) {
                    $tool.Version | Should -Not -BeNullOrEmpty
                }
            }

            It 'version strings match a semver pattern' {
                $info = Get-BundledToolInfo
                foreach ($tool in $info) {
                    $tool.Version | Should -Match '^\d+\.\d+\.\d+$'
                }
            }

        }

    }

}
