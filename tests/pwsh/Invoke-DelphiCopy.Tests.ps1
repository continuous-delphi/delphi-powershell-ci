#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

Import-Module ([System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..' 'source' 'Delphi.PowerShell.CI.psm1'))) -Force

InModuleScope 'Delphi.PowerShell.CI' {

    Describe 'Invoke-DelphiCopy -- unit' {

        BeforeAll {
            Mock Invoke-CopyFiles {
                [PSCustomObject]@{ Success = $true; ExitCode = 0; Message = 'Copied 3 file(s)'; FileCount = 3; BytesCopied = [long]1024 }
            }
            Mock Write-DelphiCiMessage {}
        }

        Context 'step result shape' {

            It 'StepName is Copy' {
                (Invoke-DelphiCopy -Source 'C:\Fake\*.exe' -Destination 'C:\Fake\dist').StepName | Should -Be 'Copy'
            }

            It 'Tool is copy' {
                (Invoke-DelphiCopy -Source 'C:\Fake\*.exe' -Destination 'C:\Fake\dist').Tool | Should -Be 'copy'
            }

            It 'Duration is a TimeSpan' {
                (Invoke-DelphiCopy -Source 'C:\Fake\*.exe' -Destination 'C:\Fake\dist').Duration | Should -BeOfType [timespan]
            }

            It 'Source matches the input' {
                (Invoke-DelphiCopy -Source 'C:\Fake\*.exe' -Destination 'C:\Fake\dist').Source | Should -Be 'C:\Fake\*.exe'
            }

            It 'Destination matches the input' {
                (Invoke-DelphiCopy -Source 'C:\Fake\*.exe' -Destination 'C:\Fake\dist').Destination | Should -Be 'C:\Fake\dist'
            }

            It 'FileCount is populated from result' {
                (Invoke-DelphiCopy -Source 'C:\Fake\*.exe' -Destination 'C:\Fake\dist').FileCount | Should -Be 3
            }

            It 'BytesCopied is populated from result' {
                (Invoke-DelphiCopy -Source 'C:\Fake\*.exe' -Destination 'C:\Fake\dist').BytesCopied | Should -Be 1024
            }

        }

        Context 'success and failure' {

            It 'Success is true when copy succeeds' {
                Mock Invoke-CopyFiles { [PSCustomObject]@{ Success = $true; ExitCode = 0; Message = 'OK'; FileCount = 1; BytesCopied = [long]100 } }
                (Invoke-DelphiCopy -Source 'C:\Fake\*.exe' -Destination 'C:\Fake\dist').Success | Should -Be $true
            }

            It 'Success is false when copy fails' {
                Mock Invoke-CopyFiles { [PSCustomObject]@{ Success = $false; ExitCode = 1; Message = 'No files matched'; FileCount = 0; BytesCopied = [long]0 } }
                (Invoke-DelphiCopy -Source 'C:\Fake\*.exe' -Destination 'C:\Fake\dist').Success | Should -Be $false
            }

        }

        Context 'WhatIf' {

            It 'does not invoke Invoke-CopyFiles when -WhatIf is set' {
                Invoke-DelphiCopy -Source 'C:\Fake\*.exe' -Destination 'C:\Fake\dist' -WhatIf
                Should -Invoke Invoke-CopyFiles -Times 0
            }

        }

        Context 'argument passing' {

            It 'forwards all parameters to Invoke-CopyFiles' {
                Invoke-DelphiCopy -Source 'C:\Fake\*.exe' -Destination 'C:\Fake\dist' -Flatten $true -Checksum $true
                Should -Invoke Invoke-CopyFiles -ParameterFilter {
                    $Source -eq 'C:\Fake\*.exe' -and
                    $Destination -eq 'C:\Fake\dist' -and
                    $Flatten -eq $true -and
                    $Checksum -eq $true
                }
            }

        }

    }

    Describe 'Invoke-CopyFiles -- integration' {

        Context 'flatten mode' {

            It 'copies files flat into destination' {
                $srcDir = Join-Path $TestDrive 'src'
                $subDir = Join-Path $srcDir 'sub'
                $dstDir = Join-Path $TestDrive 'dst'
                New-Item -Path $subDir -ItemType Directory -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $srcDir 'a.txt') -Value 'aaa'
                Set-Content -LiteralPath (Join-Path $subDir 'b.txt') -Value 'bbb'

                $result = Invoke-CopyFiles -Source (Join-Path $srcDir '*') -Destination $dstDir -Flatten $true
                $result.Success | Should -Be $true
                $result.FileCount | Should -Be 2
                Test-Path (Join-Path $dstDir 'a.txt') | Should -Be $true
                Test-Path (Join-Path $dstDir 'b.txt') | Should -Be $true
            }

        }

        Context 'non-flatten mode' {

            It 'preserves relative directory structure' {
                $srcDir = Join-Path $TestDrive 'src2'
                $subDir = Join-Path $srcDir 'sub'
                $dstDir = Join-Path $TestDrive 'dst2'
                New-Item -Path $subDir -ItemType Directory -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $srcDir 'a.txt') -Value 'aaa'
                Set-Content -LiteralPath (Join-Path $subDir 'b.txt') -Value 'bbb'

                $result = Invoke-CopyFiles -Source (Join-Path $srcDir '*') -Destination $dstDir -Flatten $false
                $result.Success | Should -Be $true
                Test-Path (Join-Path $dstDir 'a.txt') | Should -Be $true
                Test-Path (Join-Path $dstDir 'sub' 'b.txt') | Should -Be $true
            }

        }

        Context 'checksum' {

            It 'generates checksums.sha256 when checksum is true' {
                $srcDir = Join-Path $TestDrive 'src3'
                $dstDir = Join-Path $TestDrive 'dst3'
                New-Item -Path $srcDir -ItemType Directory -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $srcDir 'file.txt') -Value 'hello'

                Invoke-CopyFiles -Source (Join-Path $srcDir '*.txt') -Destination $dstDir -Flatten $true -Checksum $true
                $checksumFile = Join-Path $dstDir 'checksums.sha256'
                Test-Path $checksumFile | Should -Be $true
                $content = Get-Content -LiteralPath $checksumFile -Raw
                $content | Should -Match 'file\.txt'
                $content | Should -Match '[a-f0-9]{64}'
            }

        }

        Context 'no match' {

            It 'returns failure when no files match' {
                $srcDir = Join-Path $TestDrive 'empty'
                New-Item -Path $srcDir -ItemType Directory -Force | Out-Null
                $result = Invoke-CopyFiles -Source (Join-Path $srcDir '*.xyz') -Destination (Join-Path $TestDrive 'out')
                $result.Success | Should -Be $false
                $result.Message | Should -BeLike '*No files matched*'
            }

        }

        Context 'createDestination' {

            It 'fails when destination does not exist and createDestination is false' {
                $srcDir = Join-Path $TestDrive 'src4'
                New-Item -Path $srcDir -ItemType Directory -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $srcDir 'f.txt') -Value 'x'

                $result = Invoke-CopyFiles -Source (Join-Path $srcDir '*.txt') -Destination (Join-Path $TestDrive 'nodir') -CreateDestination $false
                $result.Success | Should -Be $false
                $result.Message | Should -BeLike '*does not exist*'
            }

        }

    }

}
