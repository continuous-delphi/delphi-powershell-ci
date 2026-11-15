# Tests

## Structure

```
tests/
+- run-tests.ps1        PowerShell runner (requires PowerShell 7+)
+- run-tests.bat        Convenience wrapper for interactive Windows use
+- pwsh/
   +- PesterConfig.psd1                       Pester 5.7+ configuration
   +- TestHelpers.ps1                         Shared utilities dot-sourced by test files
   +- PSScriptAnalyzer.Tests.ps1              Lint gate
   +- Schema.Tests.ps1                        Schema / resolver drift gate
   +- Resolve-DefaultPlatform.Tests.ps1       Platform resolution tests
   +- Get-DelphiCiConfig.Tests.ps1            Config normalization tests
   +- Invoke-DelphiCi.Tests.ps1               Orchestration command tests
   +- Invoke-DelphiCi.VersionInfo.Tests.ps1   -VersionInfo flag tests
   +- Invoke-DelphiBuild.Tests.ps1            Build action tests
   +- Invoke-DelphiClean.Tests.ps1            Clean action tests
   +- Invoke-DelphiRun.Tests.ps1              Run action tests
   +- Invoke-DelphiIncVer.Tests.ps1           IncVer action tests
   +- Invoke-DelphiCopy.Tests.ps1             Copy action tests
   +- Invoke-DelphiCompress.Tests.ps1         Compress action tests
   +- Invoke-DelphiCallGraph.Tests.ps1        CallGraph action tests
   +- results/
      +- pester-results.xml     NUnitXml output (generated, git-ignored)
```

## Running the tests

### From the repository root (recommended)

```powershell
./tests/run-tests.ps1
```

Exits with code `0` on success, `1` if any test fails.

It also exits `1` when a test file **fails discovery** or **contributes no tests
at all**, naming the file in either case. Neither of those produces a failed
test, so a runner that gated on the failed-test count alone reported success
while a whole file silently went missing -- a trailing comma in the schema once
dropped 85 tests, printed the parse error in red, and still exited `0`
([#28](https://github.com/continuous-delphi/delphi-powershell-ci/issues/28)).
There is deliberately no expected-total constant: a stale one is itself a silent
gate, and the per-file zero-test check catches one file emptying out while the
suite total stays high.

### From Windows Explorer or a command prompt

```
tests\run-tests.bat
```

Pauses before exit so the result is visible in an interactive window.

### Directly with Pester

```powershell
Invoke-Pester -Configuration (
    New-PesterConfiguration -Hashtable (
        Import-PowerShellDataFile ./tests/pwsh/PesterConfig.psd1
    )
)
```

Run from the repository root so that relative paths in the config resolve
correctly.

## Requirements

| Tool | Minimum version |
|---|---|
| PowerShell | 7.0 |
| Pester | 5.7.0 |
| PSScriptAnalyzer | 1.21.0 |

Install the required modules if not already present:

```powershell
Install-Module Pester          -MinimumVersion 5.7.0  -Force
Install-Module PSScriptAnalyzer -MinimumVersion 1.21.0 -Force
```

## Test files

### PSScriptAnalyzer.Tests.ps1

The lint gate. Runs `Invoke-ScriptAnalyzer` over the code this repo authors and
asserts zero violations, listing each with rule name, severity, file and line.

Analyses `source/`, `tests/` and `tools/` (`*.ps1`, `*.psm1`, `*.psd1`) using
`PSScriptAnalyzerSettings.psd1` at the repo root -- the same file the VS Code
PowerShell extension picks up, so an editor warns about what CI fails on.
`source/bundled-tools/` is deliberately **excluded**: those nine scripts are
vendored verbatim from their own standalone Continuous-Delphi repos and are linted
there, so linting them here would either cause drift from upstream or report
violations nobody in this repo may fix.

**Adding a violation is not a reason to widen the exclusions.** Fix it, suppress it
at the site with `[Diagnostics.CodeAnalysis.SuppressMessageAttribute]` and a
`Justification`, or exclude the rule in the settings file with a recorded reason.
Current state: three rules excluded (each with its reasoning and site count in the
settings file) and four individual suppressions.

It also asserts that the gate is *running*, which is not the same as passing:

- specific known files were analysed, one per covered directory, so a path typo or
  a layout change fails by name instead of silently shrinking the analysed set
- no `bundled-tools` file is in the set, so the carve-out cannot widen unnoticed
- a file planted with an assigned-but-unread variable still produces a violation,
  so the gate cannot go vacuous if the settings file over-excludes or the module
  stops loading

That last group exists because this file previously did none of its job: the only
assertion read a `$script:violations` variable nothing ever assigned, so it
evaluated `$null | Should -BeNullOrEmpty`, passed unconditionally in ~15ms, and the
analyzer was never invoked -- hiding 23 real violations in `source/` for the gate's
whole lifetime
([#27](https://github.com/continuous-delphi/delphi-powershell-ci/issues/27)). A lint
gate reports zero violations both when the code is clean and when it analysed
nothing, and those two states must not look alike.

### Schema.Tests.ps1

Drift gate between `schemas/delphi-ci.schema.json` (the editor-facing contract,
which rejects unknown keys) and `Resolve-DelphiCiConfig.ps1` (the runtime source
of truth). Nothing compared the two before, and drift was silent in both
directions: a resolver-only key puts a red squiggle on working config, and a
schema-only key completes in the editor then does nothing at runtime.

Reads the resolver's `$builtInDefaults` hashtable literal via the PowerShell
parser, so no production change was needed to expose it, and compares per action:

- every resolver default key is declared in `<action>Config`
- every `<action>Config` key is a resolver default or an explicitly allow-listed
  required input (`projectFile`, `source`, `execute`, ...), with the allow-list
  itself checked for stale entries
- array-valued defaults have a matching `key!` replacement spelling, and vice
  versa -- an exact invariant, since `Merge-ActionConfig` appends exactly those
  keys whose base value is an array
- `<action>Job` and `<action>Action` re-list every `<action>Config` property as a
  `$ref` (a forgotten one is the defect this file is really about), and
  `<action>Action.action` is the pipeline discriminator rather than the
  same-named config key -- which only collides for `codesign`
- the schema parses, every local `$ref` resolves to a node that exists, and every
  action is reachable via `defaults` and `pipelineAction.oneOf`

Each assertion was verified to FIRE by perturbing one side and reverting.

Note the parse errors are captured at discovery and reported by a run-time
assertion rather than thrown. A throw during discovery yields `FailedCount = 0`
with `TotalCount = 0`, so that file's tests vanish without failing anything --
which is how [#28](https://github.com/continuous-delphi/delphi-powershell-ci/issues/28)
was found and why the runner no longer gates on `FailedCount` alone. Keeping the
parse out of the script body means a malformed schema reads as a failed
assertion, which is the clearer signal either way. There is an anti-vacuity
assertion for the same reason: it fails if the per-action comparisons were not
generated for every action the resolver declares.

### Resolve-DefaultPlatform.Tests.ps1

Behaviour-contract tests for the private `Resolve-DefaultPlatform` function.
Uses `InModuleScope` to access the private function. Covers:

- Returns `Win32` when multiple platforms are active (default)
- Returns `Win32` when no platforms are active (fallback)
- Returns `Win32` when the `<Platforms>` element is empty (PS XML edge case)
- Returns the single platform name when exactly one platform is active
- Integration test against the real `ConsoleProject.dproj`

### Get-DelphiCiConfig.Tests.ps1

Behaviour-contract tests for `Get-DelphiCiConfig` and its private
normalization logic. Covers:

- Built-in defaults when no arguments are supplied
- JSON config file loading (all supported fields)
- Root resolution relative to the config file directory
- CLI parameter override precedence over config file values
- CLI parameter override precedence over built-in defaults
- Validation errors for invalid field values

### Invoke-DelphiCi.Tests.ps1

Behaviour-contract tests for `Invoke-DelphiCi`. Uses `InModuleScope` with
mocked step commands and private helpers for unit tests. Covers:

- Pipeline action routing and ordering
- Halt-on-failure: subsequent actions do not run when an earlier action fails
- PassThru result shape: Success, Duration, ProjectFile, Steps array
- Parameter forwarding to each action command
- Platform auto-resolution from project files
- Integration test: real clean + build of ConsoleProject for Win32 Debug

### Invoke-DelphiCi.VersionInfo.Tests.ps1

Tests for the `-VersionInfo` flag on `Invoke-DelphiCi`. Verifies that
the module version and bundled tool inventory are reported correctly.

### Invoke-DelphiBuild.Tests.ps1

Behaviour-contract tests for `Invoke-DelphiBuild` and its interaction with
the private `Invoke-BuildPipeline` helper. Uses `InModuleScope` with mocked
`Invoke-BuildPipeline` for unit tests. Covers:

- Step result shape (StepName, Tool, Duration type, ProjectFile echoed back)
- Success and ExitCode reflect pipeline exit code (0 and non-zero)
- Message content on success and failure
- Inspect args: -DetectLatest for Latest, -Locate/-Name for pinned version,
  -Platform and -BuildSystem forwarding
- Msbuild args: -ProjectFile, -Platform, -Config defaults and overrides,
  -ShowOutput, -Define single/multiple/none
- Integration test: real build of ConsoleProject.dproj for Win32 Debug

### Invoke-DelphiClean.Tests.ps1

Behaviour-contract tests for `Invoke-DelphiClean` and its interaction with
the private `Invoke-BundledTool` helper. Uses `InModuleScope` with mocked
`Invoke-BundledTool` for unit tests. Covers:

- Step result shape (StepName, Tool, Duration type, ProjectFile null)
- Success and ExitCode reflect tool exit code (0 and non-zero)
- Message content on success and failure
- Argument passing: tool name, -Level default and explicit values, -RootPath
- Integration test against the real `ConsoleProjectGroup/Source` with level `basic`

### Invoke-DelphiRun.Tests.ps1

Behaviour-contract tests for `Invoke-DelphiRun`. Covers tool invocation,
argument forwarding, timeout handling, and structured result shape.

### Invoke-DelphiIncVer.Tests.ps1

Behaviour-contract tests for `Invoke-DelphiIncVer`. Uses `InModuleScope`
with mocked `Invoke-BundledTool`. Covers:

- Step result shape (StepName, Tool, Duration, File, OldVersion, NewVersion)
- Success and failure paths with exit code reflection
- WhatIf support (tool not invoked)
- Argument passing: -File, -Target, -Style, -Part, -Pattern, -OutputFile
- Temp result file cleanup after success and failure

### Invoke-DelphiCopy.Tests.ps1

Behaviour-contract tests for `Invoke-DelphiCopy`. Covers source/destination
argument forwarding, flatten mode, and structured result shape.

### Invoke-DelphiCompress.Tests.ps1

Behaviour-contract tests for `Invoke-DelphiCompress`. Covers source/destination
argument forwarding and structured result shape.

### Invoke-DelphiCallGraph.Tests.ps1

Behaviour-contract tests for `Invoke-DelphiCallGraph`. Covers tool invocation,
argument forwarding, deterministic output control, and structured result shape.

## Result output

Test results are written to `tests/pwsh/results/pester-results.xml` in
NUnitXml format after every run. This file is git-ignored and regenerated
on each run.
