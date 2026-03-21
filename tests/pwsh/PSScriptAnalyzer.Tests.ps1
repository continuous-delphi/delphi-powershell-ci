#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.7.0' }
#Requires -Modules @{ ModuleName='PSScriptAnalyzer'; ModuleVersion='1.21.0' }
<#
.SYNOPSIS
  PSScriptAnalyzer lint test

.DESCRIPTION
  Runs Invoke-ScriptAnalyzer using the default
  rule set and asserts zero violations.  On failure each violation is listed
  with its rule name, severity, and line number.
#>

Describe 'PSScriptAnalyzer - lint tests' {

  It 'has no PSScriptAnalyzer violations' {
    $lines = $script:violations | ForEach-Object {
      "  [$($_.Severity)] $($_.RuleName) at line $($_.Line): $($_.Message)"
    }
    $because = if ($lines) { "`n" + ($lines -join [System.Environment]::NewLine) } else { '' }
    $script:violations | Should -BeNullOrEmpty -Because $because
  }

}
