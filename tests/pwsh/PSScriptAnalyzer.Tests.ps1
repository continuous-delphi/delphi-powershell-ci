#Requires -Version 7.0
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.7.0' }
#Requires -Modules @{ ModuleName='PSScriptAnalyzer'; ModuleVersion='1.21.0' }

<#
.SYNOPSIS
  PSScriptAnalyzer lint gate.

.DESCRIPTION
  Runs Invoke-ScriptAnalyzer over the code this repo authors and asserts zero
  violations, listing each one with rule name, severity and line number.

  THIS FILE USED TO DO NONE OF THAT (#27). Its only assertion read a
  `$script:violations` variable that nothing in the suite ever assigned, so it
  evaluated `$null | Should -BeNullOrEmpty`, passed unconditionally in ~15ms, and
  the analyzer was never invoked. 23 real violations in source/ went unreported
  for the lifetime of the gate.

  Two design rules follow from that, and from the matching discovery-failure hole
  found in #28:

  1. THE SUBJECT IS COMPUTED INSIDE THIS FILE, never read from an ambient
     variable. A test whose subject is assigned elsewhere -- or nowhere -- cannot
     be trusted to fail.
  2. THERE ARE EXPLICIT ANTI-VACUITY ASSERTIONS. A lint gate reports zero
     violations both when the code is clean and when it analyzed nothing at all:
     a mistyped path, a glob that matches no files, or a settings file that
     excludes every rule. Those two states must not look alike, so this file
     asserts that specific known files WERE analyzed, that the vendored tools
     were NOT, and that the analyzer still reports a violation in a file planted
     with one.

  Rule exclusions live in PSScriptAnalyzerSettings.psd1 at the repo root, each
  with a recorded reason; four individual sites carry
  SuppressMessageAttribute with a Justification in the source.
#>

Describe 'PSScriptAnalyzer - lint gate' {

    BeforeAll {
        # Assigned in BeforeAll, not in the script body or a BeforeDiscovery block:
        # Pester runs discovery and execution in separate scopes, so a path computed at
        # discovery time reads as empty inside an It -- which silently turned the
        # relative-path assertions below into comparisons against full paths.
        $script:RepoRoot     = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..' '..'))
        $repoRoot            = $script:RepoRoot
        $script:SettingsFile = Join-Path $repoRoot 'PSScriptAnalyzerSettings.psd1'

        # THE ANALYZED SET IS THE CODE THIS REPO AUTHORS.
        # source/bundled-tools/ is excluded: those nine scripts are vendored verbatim
        # from their own standalone Continuous-Delphi repos, which have their own CI.
        # Linting them here would either cause drift from upstream or report violations
        # nobody in this repo may fix. The exclusion is asserted below so it stays a
        # deliberate carve-out rather than quietly widening.
        $script:AnalyzedFiles = @(
            Get-ChildItem -Path (Join-Path $repoRoot 'source') -Recurse -Include *.ps1, *.psm1, *.psd1 -File |
                Where-Object { $_.FullName -notlike (Join-Path $repoRoot 'source\bundled-tools\*') }
            Get-ChildItem -Path (Join-Path $repoRoot 'tests') -Recurse -Include *.ps1, *.psm1, *.psd1 -File
            Get-ChildItem -Path (Join-Path $repoRoot 'tools') -Recurse -Include *.ps1, *.psm1, *.psd1 -File
        ) | Sort-Object FullName

        # Analyzed one file at a time: -Path takes a single string, and passing an array
        # throws a binding error that -ErrorAction SilentlyContinue would swallow into an
        # empty result -- i.e. a green gate that analyzed nothing. Measured during #27.
        $script:Violations = @(
            foreach ($file in $script:AnalyzedFiles) {
                Invoke-ScriptAnalyzer -Path $file.FullName -Settings $script:SettingsFile
            }
        )
    }

    Context 'the gate is actually running' {

        It 'found the settings file that records the rule exclusions' {
            $script:SettingsFile | Should -Exist
        }

        It 'analyzed a plausible number of files' {
            # Not a target count -- just proof the enumeration matched something. The
            # named-file assertions below are what pin the specific paths.
            @($script:AnalyzedFiles).Count | Should -BeGreaterThan 20 -Because 'the repo has ~30 authored PowerShell files; a much smaller number means the enumeration broke'
        }

        It 'analyzed <_>' -ForEach @(
            'source\Delphi.PowerShell.CI.psm1',
            'source\Delphi.PowerShell.CI.psd1',
            'source\Public\Invoke-DelphiBuild.ps1',
            'source\Private\Resolve-DelphiCiConfig.ps1',
            'tests\pwsh\Schema.Tests.ps1',
            'tests\run-tests.ps1',
            'tools\delphi-ci.ps1'
        ) {
            # One named file per directory the gate is supposed to cover. A path typo or
            # a changed layout fails here, naming the file, instead of silently shrinking
            # what gets linted.
            $relative = @($script:AnalyzedFiles | ForEach-Object { $_.FullName.Substring($script:RepoRoot.Length).TrimStart('\') })
            $relative | Should -Contain $_
        }

        It 'does not analyze the vendored bundled-tools' {
            # Deliberate carve-out, asserted so it cannot widen by accident -- and so a
            # future reader sees it was a decision, not an oversight.
            $bundled = @($script:AnalyzedFiles | Where-Object { $_.FullName -like '*\bundled-tools\*' })
            @($bundled) | Should -BeNullOrEmpty -Because "source/bundled-tools/ is vendored from upstream repos and linted there: $(@($bundled | ForEach-Object { $_.Name }) -join ', ')"
        }

        It 'still reports a violation in a file planted with one' {
            # THE ANTI-VACUITY ASSERTION THAT MATTERS MOST. Everything above proves files
            # were enumerated; this proves the analyzer runs on them under THIS settings
            # file and can still fail. If PSScriptAnalyzerSettings.psd1 ever excluded
            # everything, or the module stopped loading, the real assertion below would
            # report zero violations and look exactly like success.
            $planted = Join-Path $TestDrive 'planted-violation.ps1'
            Set-Content -LiteralPath $planted -Value @'
function Get-Planted {
    $neverUsed = 'assigned and never read'
    return 1
}
'@
            $found = @(Invoke-ScriptAnalyzer -Path $planted -Settings $script:SettingsFile)
            @($found).Count | Should -BeGreaterThan 0 -Because 'a file with an assigned-but-unread variable must still produce a violation; zero here means the gate cannot fail'
            @($found.RuleName) | Should -Contain 'PSUseDeclaredVarsMoreThanAssignments'
        }

    }

    Context 'the code is clean' {

        It 'has no PSScriptAnalyzer violations' {
            $lines = $script:Violations | ForEach-Object {
                $file = $_.ScriptPath.Substring($script:RepoRoot.Length).TrimStart('\')
                "  [$($_.Severity)] $($_.RuleName) at ${file}:$($_.Line): $($_.Message)"
            }
            $because = if ($lines) {
                "$(@($script:Violations).Count) violation(s) across $(@($script:AnalyzedFiles).Count) analyzed files." +
                [System.Environment]::NewLine + ($lines -join [System.Environment]::NewLine) +
                [System.Environment]::NewLine +
                'Fix it, or -- if it is deliberate -- add a SuppressMessageAttribute with a Justification at the site, or a rule exclusion with a recorded reason in PSScriptAnalyzerSettings.psd1.'
            }
            else { '' }
            $script:Violations | Should -BeNullOrEmpty -Because $because
        }

    }

}
