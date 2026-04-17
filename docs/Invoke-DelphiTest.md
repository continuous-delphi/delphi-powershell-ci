# Invoke-DelphiTest

Runs a pre-built test executable as a CI step.

## Syntax

```powershell
Invoke-DelphiTest
    -TestExeFile <string>
    [-Arguments <string[]>]
    [-TimeoutSeconds <int>]
    [-WhatIf]
```

## Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `-TestExeFile` | string | (required) | Path to the test executable to run. Must already exist (built by a prior Build step). |
| `-Arguments` | string[] | `@()` | Extra command-line arguments forwarded to the test EXE at runtime. |
| `-TimeoutSeconds` | int | `10` | Maximum seconds the test process may run before it is killed. If killed, the step fails. |
| `-WhatIf` | switch | | Shows what would happen without executing the test. |

## The CI Define and DUnitX

DUnitX test projects are typically written so that when built with the `CI`
define set, they use the headless console runner instead of the TestInsight
IDE runner. Since `Invoke-DelphiTest` no longer builds, the `CI` define must
be passed when building the test project via `Invoke-DelphiBuild` or a build
job in the config file.

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
| `TestExeFile` | string | Path to the test executable that was run |

## Usage Examples

### Basic: run a pre-built test executable

```powershell
Invoke-DelphiTest -TestExeFile .\test\Win32\Debug\MyApp.Tests.exe
```

### With custom timeout

```powershell
Invoke-DelphiTest -TestExeFile .\test\Win32\Debug\MyApp.Tests.exe -TimeoutSeconds 30
```

### Build then test as separate steps

```powershell
# Build the test project with CI define
Invoke-DelphiBuild -ProjectFile .\test\MyApp.Tests.dproj -Defines CI

# Run the test executable
Invoke-DelphiTest -TestExeFile .\test\Win32\Debug\MyApp.Tests.exe
```

### Via Invoke-DelphiCi config file

The test project is built as a build job and run as a test job:

```json
{
  "steps": ["Build", "Test"],
  "build": {
    "jobs": [
      { "name": "Test project",
        "projectFile": "test/MyApp.Tests.dproj",
        "defines": ["CI"] }
    ]
  },
  "test": {
    "jobs": [
      { "name": "Unit tests",
        "testExeFile": "test/Win32/Debug/MyApp.Tests.exe" }
    ]
  }
}
```

## JSON Config Equivalent

Test options are controlled by the `test` section of the JSON config file:

```json
{
  "test": {
    "timeoutSeconds": 10,
    "arguments": [],
    "jobs": [
      { "name": "Tests Win32",
        "testExeFile": "test/Win32/Debug/MyApp.Tests.exe" },
      { "name": "Tests Win64",
        "testExeFile": "test/Win64/Debug/MyApp.Tests.exe" }
    ]
  }
}
```

Each job inherits `timeoutSeconds` and `arguments` from the test defaults
and can override them.

## Notes

- This command does not build anything. The test executable must already
  exist, built by a prior `Invoke-DelphiBuild` call or a build job in the
  config file.
- If the test process is killed due to timeout, `ExitCode` is `-1` and
  `Message` will say `Timed out after Ns`.
- If the executable does not exist on disk, the step fails immediately with
  a clear error message.
