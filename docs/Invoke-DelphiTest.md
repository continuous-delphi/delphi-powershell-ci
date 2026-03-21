# Invoke-DelphiTest

Builds and runs a DUnitX test project as a CI step.

## Syntax

```powershell
Invoke-DelphiTest
    [-Root <string>]
    [-TestProjectFile <string>]
    [-TestExecutable <string>]
    [-Platform <string>]
    [-Configuration <string>]
    [-Toolchain <string>]
    [-BuildEngine <string>]
    [-Defines <string[]>]
    [-Arguments <string[]>]
    [-TimeoutSeconds <int>]
    [-Build <bool>]
    [-Run <bool>]
    [-WhatIf]
```

## Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `-Root` | string | current directory | Working root used for test project discovery when `-TestProjectFile` is not provided. |
| `-TestProjectFile` | string | (auto-discover) | Path to the test `.dproj` or `.dpr` file. If omitted, discovery runs against `-Root`. |
| `-TestExecutable` | string | (auto-derive) | Explicit path to the test `.exe`. When supplied, skips the standard derivation from project file, platform, and configuration. Use when the project overrides `DCC_ExeOutput` or places output in a non-default location. |
| `-Platform` | string | (auto-resolve) | Target platform. If omitted, resolved from the test project file (MSBuild) or defaults to `Win32` (DCCBuild). |
| `-Configuration` | string | `Debug` | Build configuration. |
| `-Toolchain` | string | `Latest` | Delphi toolchain version. `Latest` detects the newest installed version. Use a name like `VER370` to pin. |
| `-BuildEngine` | string | `MSBuild` | Build engine: `MSBuild` or `DCCBuild`. |
| `-Defines` | string[] | `@()` | Conditional-compilation defines passed to the test project build. See note below. |
| `-Arguments` | string[] | `@()` | Extra command-line arguments forwarded to the test EXE at runtime. |
| `-TimeoutSeconds` | int | `10` | Maximum seconds the test process may run before it is killed. If killed, the step fails. |
| `-Build` | bool | `$true` | Set to `$false` to skip the build phase and run only. |
| `-Run` | bool | `$true` | Set to `$false` to skip the run phase and build only. |
| `-WhatIf` | switch | | Shows what would happen without executing the build or run phases. |

## The CI Define and DUnitX

DUnitX test projects are typically written so that when built with the `CI`
define set, they use the headless console runner instead of the TestInsight
IDE runner:

```delphi
{$IFNDEF TESTINSIGHT}
  {$DEFINE CI}
{$ENDIF}
```

The `CI` define is **not injected automatically** by this command. You must
include it explicitly:

```powershell
Invoke-DelphiTest -TestProjectFile .\tests\MyApp.Tests.dproj -Defines CI
```

If you omit `CI` when the project requires it, the test EXE may launch the
TestInsight runner (which will block waiting for an IDE connection) and the
step will time out.

## Test Project Discovery

When `-TestProjectFile` is not provided, discovery follows this precedence:

1. Exactly one `.dproj` in `Root\tests\`
2. Exactly one `.dproj` in `Root` whose name starts or ends with `Tests`
3. Fails clearly if multiple candidates exist
4. Fails clearly if no test project is found

## Test Executable Resolution

The expected EXE path is derived from the test project file, platform, and
configuration:

```
[TestProjectDir]\[Platform]\[Configuration]\[TestProjectBaseName].exe
```

Example: `tests\MyApp.Tests.dproj` + `Win32` + `Debug`
-> `tests\Win32\Debug\MyApp.Tests.exe`

## Return Value

Returns a `PSCustomObject` with these fields:

| Field | Type | Description |
|---|---|---|
| `StepName` | string | Always `'Test'` |
| `Success` | bool | `$true` if the test process exited 0; `$false` otherwise |
| `ExitCode` | int | Exit code from the test process; `-1` on timeout |
| `Duration` | TimeSpan | Total time for this step |
| `Tool` | string | Always `'test runner'` |
| `Message` | string | Human-readable outcome summary |
| `TestProjectFile` | string | Resolved path to the test `.dproj` |
| `TestExecutable` | string | Derived path to the test `.exe`; `$null` if build failed |

## Usage Examples

### Basic: build and run with CI define

```powershell
Invoke-DelphiTest -TestProjectFile .\tests\MyApp.Tests.dproj -Defines CI
```

### Build only (verify compilation without running)

```powershell
Invoke-DelphiTest -TestProjectFile .\tests\MyApp.Tests.dproj -Defines CI -Run $false
```

### Run only (use a previously built EXE)

```powershell
Invoke-DelphiTest -TestProjectFile .\tests\MyApp.Tests.dproj -Build $false
```

### Convention-based discovery from the project root

```powershell
Invoke-DelphiTest -Root .\MyProject -Defines CI
```

Discovers the test project automatically if exactly one `.dproj` exists in
`.\MyProject\tests\` or matches the `Tests` name convention in the root.

### Custom timeout

```powershell
Invoke-DelphiTest -TestProjectFile .\tests\MyApp.Tests.dproj -Defines CI -TimeoutSeconds 30
```

### Via Invoke-DelphiCi

```powershell
# Test step only
Invoke-DelphiCi -Steps Test -TestProjectFile .\tests\MyApp.Tests.dproj -TestDefines CI

# Full pipeline
Invoke-DelphiCi -Steps Clean,Build,Test -TestProjectFile .\tests\MyApp.Tests.dproj -TestDefines CI
```

## JSON Config Equivalent

```json
{
  "root": ".",
  "build": {
    "projectFile": "source/MyApp.dproj",
    "engine": "MSBuild",
    "platform": "Win32",
    "configuration": "Debug"
  },
  "test": {
    "testProjectFile": "tests/MyApp.Tests.dproj",
    "defines": ["CI"],
    "timeoutSeconds": 10,
    "build": true,
    "run": true
  },
  "steps": ["Clean", "Build", "Test"]
}
```

## Notes

- The step is self-contained and does not depend on `Invoke-DelphiBuild` having already run.
  `-Steps Test` works standalone.
- The project file extension is normalised automatically to match the build engine:
  `.dproj` for MSBuild, `.dpr` for DCCBuild.
- If the test process is killed due to timeout, `ExitCode` is `-1` and
  `Message` will say `Timed out after Ns`.
