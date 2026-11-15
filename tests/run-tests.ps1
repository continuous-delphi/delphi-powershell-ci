# tests/run-tests.ps1
if ($PSVersionTable.PSVersion.Major -lt 7) {
  Write-Error "Tests require PowerShell 7+."
  exit 1
}

if ($IsWindows) {
  Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
}
Import-Module Pester -MinimumVersion 5.7.0 -Force
Push-Location (Join-Path $PSScriptRoot '..')
$config = New-PesterConfiguration -Hashtable (Import-PowerShellDataFile "$PSScriptRoot/pwsh/PesterConfig.psd1")
$config.Run.PassThru = $true
$result = $null
try {
  $result = Invoke-Pester -Configuration $config
} finally {
  Pop-Location
}
if ($null -eq $result) {
  Write-Host '[ERROR] Invoke-Pester returned no result object.'
  exit 1
}

# A FAILED TEST COUNT IS NOT THE ONLY WAY A RUN CAN BE BAD (#28).
# A Pester DISCOVERY failure -- a syntax error in a .Tests.ps1, or anything that
# throws while building -ForEach data -- produces no failed TESTS. It produces a
# failed CONTAINER whose TotalCount is 0, so the file contributes nothing and
# `FailedCount -gt 0` stays false. MEASURED: a trailing comma in
# schemas/delphi-ci.schema.json dropped all 85 of Schema.Tests.ps1's tests,
# printed the parse error in red, reported "Tests Passed: 477, Failed: 0" and
# EXITED 0 -- a green build with an entire file silently missing.
#
# So the container results are inspected individually and named here, rather than
# leaving the red text to be spotted in several hundred lines of scroll.
#
# ON A DISCOVERED-TEST FLOOR: a single expected total would have to be bumped by
# every new test file, and a stale one is itself a silent gate. The per-container
# "discovered zero tests" check below is the same protection without a constant
# to maintain -- and it is strictly sharper, because it also catches ONE file
# going empty (an `-ForEach` collection that computes to nothing generates no
# It blocks at all and is perfectly "passing") while the suite total stays high.
$exitCode = 0

foreach ($container in $result.Containers) {
  if ($container.Result -eq 'Failed' -and $container.TotalCount -eq 0) {
    Write-Host "[ERROR] DISCOVERY FAILED -- no tests ran from: $($container.Item)"
    if ($container.ErrorRecord) {
      foreach ($errorRecord in $container.ErrorRecord) { Write-Host "          $errorRecord" }
    }
    $exitCode = 1
  }
  elseif ($container.TotalCount -eq 0) {
    Write-Host "[ERROR] DISCOVERED ZERO TESTS in: $($container.Item)"
    Write-Host '          A file that contributes no tests cannot fail. Check for an empty -ForEach collection.'
    $exitCode = 1
  }
}

if ($result.FailedCount -gt 0)   { $exitCode = 1 }
# Covers whatever the per-container loop does not. Deliberately -eq 'Failed'
# rather than -ne 'Passed', so a future skipped test cannot fail the suite.
if ($result.Result -eq 'Failed') { $exitCode = 1 }

exit $exitCode
