#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

# Import at script scope so the module is available during Pester discovery,
# which is required for InModuleScope to resolve the module name.
Import-Module ([System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..' 'source' 'Delphi.PowerShell.CI.psm1'))) -Force

InModuleScope 'Delphi.PowerShell.CI' {

    Describe 'Resolve-DefaultPlatform' {

        BeforeAll {
            $dprojHeader = '<?xml version="1.0" encoding="utf-8"?><Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003"><ProjectExtensions><BorlandProject><Platforms>'
            $dprojFooter = '</Platforms></BorlandProject></ProjectExtensions></Project>'

            function script:New-DprojFile {
                param([string]$Path, [string]$PlatformXml)
                Set-Content -LiteralPath $Path -Value ($dprojHeader + $PlatformXml + $dprojFooter)
            }
        }

        Context 'multiple active platforms -- returns Win32 as default' {

            It 'returns Win32 when Win32 and Win64 are both active' {
                $f = Join-Path $TestDrive 'Multi.dproj'
                New-DprojFile -Path $f -PlatformXml '<Platform value="Win32">True</Platform><Platform value="Win64">True</Platform>'
                Resolve-DefaultPlatform -ProjectFile $f | Should -Be 'Win32'
            }

            It 'returns Win32 when no platforms are marked active' {
                $f = Join-Path $TestDrive 'None.dproj'
                New-DprojFile -Path $f -PlatformXml '<Platform value="Win32">False</Platform><Platform value="Win64">False</Platform>'
                Resolve-DefaultPlatform -ProjectFile $f | Should -Be 'Win32'
            }

            It 'returns Win32 when the Platforms section is empty' {
                $f = Join-Path $TestDrive 'Empty.dproj'
                New-DprojFile -Path $f -PlatformXml ''
                Resolve-DefaultPlatform -ProjectFile $f | Should -Be 'Win32'
            }

        }

        Context 'single active platform -- returns that platform' {

            It 'returns Win32 when only Win32 is active' {
                $f = Join-Path $TestDrive 'Win32Only.dproj'
                New-DprojFile -Path $f -PlatformXml '<Platform value="Win32">True</Platform><Platform value="Win64">False</Platform>'
                Resolve-DefaultPlatform -ProjectFile $f | Should -Be 'Win32'
            }

            It 'returns Win64 when only Win64 is active' {
                $f = Join-Path $TestDrive 'Win64Only.dproj'
                New-DprojFile -Path $f -PlatformXml '<Platform value="Win32">False</Platform><Platform value="Win64">True</Platform>'
                Resolve-DefaultPlatform -ProjectFile $f | Should -Be 'Win64'
            }

            It 'returns the platform name as-is for non-standard platforms' {
                $f = Join-Path $TestDrive 'LinuxOnly.dproj'
                New-DprojFile -Path $f -PlatformXml '<Platform value="Linux64">True</Platform>'
                Resolve-DefaultPlatform -ProjectFile $f | Should -Be 'Linux64'
            }

        }

        Context 'error handling' {

            It 'throws when the project file does not exist' {
                { Resolve-DefaultPlatform -ProjectFile (Join-Path $TestDrive 'Missing.dproj') } | Should -Throw
            }

        }

        Context 'integration -- reads the real ConsoleProject.dproj' {

            It 'returns Win32 for ConsoleProject which supports Win32 and Win64' {
                $dproj = [System.IO.Path]::GetFullPath(
                    (Join-Path $PSScriptRoot '..\..' 'Examples\ConsoleProjectGroup\Source\ConsoleProject.dproj')
                )
                Resolve-DefaultPlatform -ProjectFile $dproj | Should -Be 'Win32'
            }

        }

    }

}
