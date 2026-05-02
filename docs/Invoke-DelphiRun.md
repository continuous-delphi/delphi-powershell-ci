# Invoke-DelphiRun

Runs an executable or script as a CI step. Success is determined by exit
code 0.

## Syntax

```powershell
Invoke-DelphiRun
    -Execute <string>
    [-Arguments <string[]>]
    [-TimeoutSeconds <int>]
    [-WhatIf]
```

## Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `-Execute` | string | (required) | Path to the executable, script, or command to run. |
| `-Arguments` | string[] | `@()` | Extra command-line arguments forwarded to the command at runtime. |
| `-TimeoutSeconds` | int | `10` | Maximum seconds the process may run before it is killed. If killed, the step fails. |
| `-WhatIf` | switch | | Shows what would happen without executing the command. |

## The CI Define and DUnitX

DUnitX test projects are typically written so that when built with the `CI`
define set, they use the headless console runner instead of the TestInsight
IDE runner. Since `Invoke-DelphiRun` does not build anything, the `CI` define
must be passed when building the test project via `Invoke-DelphiBuild` or a
build job in the config file.

## Return Value

Returns a `PSCustomObject` with these fields:

| Field | Type | Description |
|---|---|---|
| `StepName` | string | Always `'Run'` |
| `Success` | bool | `$true` if the process exited 0; `$false` otherwise |
| `ExitCode` | int | Exit code from the process; `-1` on timeout |
| `Duration` | TimeSpan | Total time for this step |
| `Tool` | string | Always `'runner'` |
| `Message` | string | Human-readable outcome summary |
| `Execute` | string | Path to the command that was run |

## Usage Examples

### Basic: run a pre-built test executable

```powershell
Invoke-DelphiRun -Execute .\test\Win32\Debug\MyApp.Tests.exe
```

### With custom timeout and arguments

```powershell
Invoke-DelphiRun -Execute .\test\Win32\Debug\MyApp.Tests.exe -TimeoutSeconds 30 -Arguments '-b','-l:Warning'
```

### Build then run as separate steps

```powershell
# Build the test project with CI define
Invoke-DelphiBuild -ProjectFile .\test\MyApp.Tests.dproj -Defines CI

# Run the test executable
Invoke-DelphiRun -Execute .\test\Win32\Debug\MyApp.Tests.exe
```

### Via Invoke-DelphiCi config file

The project is built as a build action and executed as a run action:

```json
{
  "pipeline": [
    { "action": "Build",
      "jobs": [
        { "name": "Test project",
          "projectFile": "test/MyApp.Tests.dproj",
          "defines": ["CI"] }
      ]
    },
    { "action": "Run",
      "jobs": [
        { "name": "Unit tests",
          "execute": "test/Win32/Debug/MyApp.Tests.exe" }
      ]
    }
  ]
}
```

## JSON Config Equivalent

Run options are controlled by the `run` key in `defaults` and by Run action
entries in the pipeline:

```json
{
  "defaults": {
    "run": {
      "timeoutSeconds": 10,
      "arguments": []
    }
  },
  "pipeline": [
    { "action": "Run",
      "timeoutSeconds": 30,
      "jobs": [
        { "name": "Tests Win32",
          "execute": "test/Win32/Debug/MyApp.Tests.exe" },
        { "name": "Tests Win64",
          "execute": "test/Win64/Debug/MyApp.Tests.exe",
          "timeoutSeconds": 60 }
      ]
    }
  ]
}
```

Each job inherits `timeoutSeconds` and `arguments` through the three-level
merge (defaults > action-level > job-level) and can override them at any
level. Arrays append; use a `key!` suffix to replace instead.

## Notes

- This command does not build anything. The executable must already exist,
  built by a prior `Invoke-DelphiBuild` call or a build action in the
  pipeline.
- If the process is killed due to timeout, `ExitCode` is `-1` and `Message`
  will say `Timed out after Ns`.
- If the executable does not exist on disk, the step fails immediately with
  a clear error message.
- Works with any executable type: `.exe`, `.bat`, `.cmd`, `.ps1`, or any
  command on PATH.
