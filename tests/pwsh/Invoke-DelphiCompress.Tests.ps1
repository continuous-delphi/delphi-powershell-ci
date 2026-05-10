#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

Import-Module ([System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..' 'source' 'Delphi.PowerShell.CI.psm1'))) -Force

InModuleScope 'Delphi.PowerShell.CI' {

    Describe 'Invoke-DelphiCompress -- unit' {

        BeforeAll {
            Mock Invoke-CompressFiles {
                [PSCustomObject]@{ Success = $true; ExitCode = 0; Message = 'Archive created (2048 bytes)'; ArchiveSize = [long]2048; Checksum = $null }
            }
            Mock Write-DelphiCiMessage {}
        }

        Context 'step result shape' {

            It 'StepName is Compress' {
                (Invoke-DelphiCompress -Source 'C:\Fake\dist' -Destination 'C:\Fake\out.zip').StepName | Should -Be 'Compress'
            }

            It 'Tool is compress' {
                (Invoke-DelphiCompress -Source 'C:\Fake\dist' -Destination 'C:\Fake\out.zip').Tool | Should -Be 'compress'
            }

            It 'Duration is a TimeSpan' {
                (Invoke-DelphiCompress -Source 'C:\Fake\dist' -Destination 'C:\Fake\out.zip').Duration | Should -BeOfType [timespan]
            }

            It 'ArchiveSize is populated from result' {
                (Invoke-DelphiCompress -Source 'C:\Fake\dist' -Destination 'C:\Fake\out.zip').ArchiveSize | Should -Be 2048
            }

        }

        Context 'success and failure' {

            It 'Success is true when compress succeeds' {
                (Invoke-DelphiCompress -Source 'C:\Fake\dist' -Destination 'C:\Fake\out.zip').Success | Should -Be $true
            }

            It 'Success is false when compress fails' {
                Mock Invoke-CompressFiles { [PSCustomObject]@{ Success = $false; ExitCode = 1; Message = 'Source not found'; ArchiveSize = [long]0; Checksum = $null } }
                (Invoke-DelphiCompress -Source 'C:\Fake\dist' -Destination 'C:\Fake\out.zip').Success | Should -Be $false
            }

        }

        Context 'WhatIf' {

            It 'does not invoke Invoke-CompressFiles when -WhatIf is set' {
                Invoke-DelphiCompress -Source 'C:\Fake\dist' -Destination 'C:\Fake\out.zip' -WhatIf
                Should -Invoke Invoke-CompressFiles -Times 0
            }

        }

        Context 'argument passing' {

            It 'forwards all parameters to Invoke-CompressFiles' {
                Invoke-DelphiCompress -Source 'C:\Fake\dist' -Destination 'C:\Fake\out.zip' -Checksum $true
                Should -Invoke Invoke-CompressFiles -ParameterFilter {
                    $Source -eq 'C:\Fake\dist' -and
                    $Destination -eq 'C:\Fake\out.zip' -and
                    $Checksum -eq $true
                }
            }

        }

    }

    Describe 'Invoke-CompressFiles -- integration' {

        Context 'archive creation' {

            It 'creates a zip archive from a directory' {
                $srcDir = Join-Path $TestDrive 'csrc'
                New-Item -Path $srcDir -ItemType Directory -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $srcDir 'a.txt') -Value 'hello'
                Set-Content -LiteralPath (Join-Path $srcDir 'b.txt') -Value 'world'
                $archive = Join-Path $TestDrive 'test.zip'

                $result = Invoke-CompressFiles -Source (Join-Path $srcDir '*') -Destination $archive
                $result.Success | Should -Be $true
                $result.ArchiveSize | Should -BeGreaterThan 0
                Test-Path $archive | Should -Be $true
            }

        }

        Context 'checksum sidecar' {

            It 'generates .sha256 sidecar when checksum is true' {
                $srcDir = Join-Path $TestDrive 'csrc2'
                New-Item -Path $srcDir -ItemType Directory -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $srcDir 'file.txt') -Value 'data'
                $archive = Join-Path $TestDrive 'test2.zip'

                $result = Invoke-CompressFiles -Source (Join-Path $srcDir '*') -Destination $archive -Checksum $true
                $result.Success | Should -Be $true
                $result.Checksum | Should -Match '[a-f0-9]{64}'
                Test-Path "$archive.sha256" | Should -Be $true
                $sidecar = Get-Content -LiteralPath "$archive.sha256" -Raw
                $sidecar | Should -Match 'test2\.zip'
            }

        }

        Context 'overwrite' {

            It 'overwrites existing archive when overwrite is true' {
                $srcDir = Join-Path $TestDrive 'csrc3'
                New-Item -Path $srcDir -ItemType Directory -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $srcDir 'f.txt') -Value 'v1'
                $archive = Join-Path $TestDrive 'test3.zip'
                Set-Content -LiteralPath $archive -Value 'placeholder'

                $result = Invoke-CompressFiles -Source (Join-Path $srcDir '*') -Destination $archive -Overwrite $true
                $result.Success | Should -Be $true
            }

            It 'fails when archive exists and overwrite is false' {
                $srcDir = Join-Path $TestDrive 'csrc4'
                New-Item -Path $srcDir -ItemType Directory -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $srcDir 'f.txt') -Value 'v1'
                $archive = Join-Path $TestDrive 'test4.zip'
                Set-Content -LiteralPath $archive -Value 'placeholder'

                $result = Invoke-CompressFiles -Source (Join-Path $srcDir '*') -Destination $archive -Overwrite $false
                $result.Success | Should -Be $false
                $result.Message | Should -BeLike '*overwrite*'
            }

        }

        Context 'no match' {

            It 'returns failure when source does not exist' {
                $result = Invoke-CompressFiles -Source (Join-Path $TestDrive 'nonexistent') -Destination (Join-Path $TestDrive 'fail.zip')
                $result.Success | Should -Be $false
                $result.Message | Should -BeLike '*not found*'
            }

        }

    }

}
