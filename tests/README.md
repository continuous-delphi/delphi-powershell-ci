# Tests

## Structure

```
tests/
+- run-tests.ps1        PowerShell runner (requires PowerShell 7+)
+- run-tests.bat        Convenience wrapper for interactive Windows use
+- pwsh/
   +- PesterConfig.psd1                  Pester 5.7+ configuration
   +- TestHelpers.ps1                    Shared utilities dot-sourced by test files
   +- Smoke.Tests.ps1                    Infrastructure smoke test
   +- PSScriptAnalyzer.Tests.ps1         Lint gate
   +- Get-DelphiCiConfig.Tests.ps1       Config normalization tests
   +- Find-DelphiProjects.Tests.ps1      Project discovery tests
   +- Resolve-DefaultPlatform.Tests.ps1  Platform resolution tests
   +- Resolve-TestProject.Tests.ps1      Test project discovery tests
   +- Invoke-DelphiCi.Tests.ps1          Orchestration command tests
   +- Invoke-DelphiBuild.Tests.ps1       Build step tests
   +- Invoke-DelphiClean.Tests.ps1       Clean step tests
   +- Invoke-DelphiTest.Tests.ps1        Test step tests
   +- results/
      +- pester-results.xml     NUnitXml output (generated, git-ignored)
```

## Running the tests

### From the repository root (recommended)

```powershell
./tests/run-tests.ps1
```

Exits with code `0` on success, `1` if any test fails.

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

### Smoke.Tests.ps1

Minimal infrastructure check. Verifies that the test runner, Pester
configuration, and source script are all wired up correctly. Not a
substitute for unit tests.

### PSScriptAnalyzer.Tests.ps1

Lint gate. Runs `Invoke-ScriptAnalyzer` on the source and asserts zero
violations using the default rule set. Violations are listed with rule
name, severity, and line number on failure.

### Find-DelphiProjects.Tests.ps1

Behaviour-contract tests for the private `Find-DelphiProjects` function.
Uses `InModuleScope` to access the private function. Covers:

- `.dproj` found directly in root
- Falls through to `root/source` when root has none
- Falls through to `root/../source` (tools-folder convention) when both above have none
- Stops at first location that yields results (no over-searching)
- Non-recursive search (files in subdirectories are not returned)
- Empty result when no `.dproj` exists in any search location

### Resolve-DefaultPlatform.Tests.ps1

Behaviour-contract tests for the private `Resolve-DefaultPlatform` function.
Uses `InModuleScope` to access the private function. Covers:

- Returns `Win32` when multiple platforms are active (default)
- Returns `Win32` when no platforms are active (fallback)
- Returns `Win32` when the `<Platforms>` element is empty (PS XML edge case)
- Returns the single platform name when exactly one platform is active
- Integration test against the real `ConsoleProject.dproj`

### Invoke-DelphiCi.Tests.ps1

Behaviour-contract tests for `Invoke-DelphiCi`. Uses `InModuleScope` with
mocked step commands and private helpers for unit tests. Covers:

- Step routing: Clean-only, Build-only, Clean+Build, Test-only, and
  Clean+Build+Test
- Halt-on-failure: Build does not run when Clean fails; Success reflects failure
- PassThru result shape: Success, Duration, ProjectFile, Steps array with names
- Steps array contains only executed steps when halted by failure
- Project discovery: explicit config ProjectFile skips Find-DelphiProjects;
  absent ProjectFile triggers discovery; no-project and multi-project errors
- Parameter forwarding: Level to Invoke-DelphiClean; Platform, Configuration,
  and Defines to Invoke-DelphiBuild; Defines, Arguments, TimeoutSeconds, Build,
  and Run to Invoke-DelphiTest
- Platform auto-resolution: resolved from main project for Build, from test
  project for Test; DCCBuild defaults to Win32
- Integration test: real clean + build of ConsoleProject for Win32 Debug

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

### Resolve-TestProject.Tests.ps1

Behaviour-contract tests for the private `Resolve-TestProject` function.
Uses `InModuleScope` with per-test isolated directories under `$TestDrive`.
Covers:

- Explicit `TestProjectFile`: returns path when file exists; throws when absent
- Discovery in `tests/` subfolder: single `.dproj`, single `.dpr`, `.dproj`
  preferred when both exist for the same base name, throws on ambiguity
- Discovery by name convention in root: `Tests*` and `*Tests` basenames,
  `.dproj` preferred over `.dpr`, throws on ambiguity, ignores non-matching files
- Precedence: `tests/` result returned when both `tests/` and root convention match
- Nothing found: returns `$null`
- Integration test against `ConsoleProjectGroup`

### Get-DelphiCiConfig.Tests.ps1

Behaviour-contract tests for `Get-DelphiCiConfig` and its private
normalization logic. Covers:

- Built-in defaults when no arguments are supplied (including all Test defaults)
- JSON config file loading (all supported fields, including the `test` section)
- Root resolution relative to the config file directory
- CLI parameter override precedence over config file values (including all
  Test parameters)
- CLI parameter override precedence over built-in defaults
- Validation errors for invalid field values

### Invoke-DelphiTest.Tests.ps1

Behaviour-contract tests for `Invoke-DelphiTest` and its private helpers.
Uses `InModuleScope`. Covers:

- Step result shape (StepName, Tool, Duration, TestProjectFile, TestExecutable)
- Success and ExitCode reflect runner exit code
- Build phase failure: runner not called, TestExecutable is null, message
  indicates build failure
- Build/run phase control: `-Build $false` skips build; `-Run $false` skips run
- WhatIf: neither build nor run phase executes
- Project discovery: Root and TestProjectFile forwarded to Resolve-TestProject;
  throws when Resolve-TestProject returns null
- Platform auto-resolution: calls Resolve-DefaultPlatform when no platform
  given (MSBuild); uses Win32 for DCCBuild; explicit value bypasses resolution
- Parameter forwarding to Invoke-TestBuild (Platform, Configuration, Defines,
  BuildEngine) and Invoke-TestRunner (TimeoutSeconds, Arguments)
- Invoke-TestRunner unit tests with real `pwsh.exe`: timeout kill path,
  success (exit 0), failure (exit non-zero), missing executable
- Resolve-TestExecutable unit tests: path formula, platform, configuration,
  extension variants (`.dproj` and `.dpr`)
- Integration test: real build and run of `ConsoleProject.Tests.dproj` with
  `-Defines CI`

## Result output

Test results are written to `tests/pwsh/results/pester-results.xml` in
NUnitXml format after every run. This file is git-ignored and regenerated
on each run.
