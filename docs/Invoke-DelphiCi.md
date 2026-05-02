# Invoke-DelphiCi

Primary orchestration command. Loads configuration, then runs the pipeline
of actions (Clean, Build, Run, and future action types) in order. Each
action can have multiple jobs. Always returns a structured result object.

---

## Syntax

Run mode (default):

```powershell
Invoke-DelphiCi
    [-ConfigFile <String>]
    [-Root <String>]
    [-Steps <String[]>]
    [-ProjectFile <String>]
    [-Platform <String>]
    [-Configuration <String>]
    [-Toolchain <String>]
    [-BuildEngine <String>]
    [-Defines <String[]>]
    [-BuildVerbosity <String>]
    [-BuildTarget <String>]
    [-ExeOutputDir <String>]
    [-DcuOutputDir <String>]
    [-UnitSearchPath <String[]>]
    [-IncludePath <String[]>]
    [-Namespace <String[]>]
    [-CleanLevel <String>]
    [-CleanOutputLevel <String>]
    [-CleanIncludeFilePattern <String[]>]
    [-CleanExcludeDirectoryPattern <String[]>]
    [-CleanConfigFile <String>]
    [-CleanRecycleBin <Bool>]
    [-CleanCheck <Bool>]
    [-Execute <String>]
    [-RunArguments <String[]>]
    [-RunTimeoutSeconds <Int>]
    [<CommonParameters>]
```

Version info mode:

```powershell
Invoke-DelphiCi -VersionInfo
```

---

## Pipeline model

The configuration defines an ordered **pipeline** of actions. Each action
(Clean, Build, Run) supports multiple **jobs** that run sequentially. Build
jobs support **matrix expansion** -- `platform` and `configuration` can be
arrays, producing a cross product of builds.

When no jobs are defined for an action:
- **Clean** creates a default job from the action defaults + root.
- **Build** throws an error (a project file is required).
- **Run** throws an error (an execute target is required).

For CLI shorthand, `-ProjectFile` creates a single build job and `-Execute`
creates a single run job.

---

## Configuration

### New pipeline format

```json
{
  "root": ".",
  "defaults": {
    "clean": { "level": "standard" },
    "build": {
      "engine": "MSBuild",
      "toolchain": { "version": "Latest" },
      "platform": "Win32",
      "configuration": "Debug"
    },
    "run": { "timeoutSeconds": 10 }
  },
  "pipeline": [
    { "action": "Clean", "level": "deep" },
    { "action": "Build",
      "platform": "Win64",
      "jobs": [
        { "name": "Main App", "projectFile": "source/MyApp.dproj" },
        { "name": "Tests", "projectFile": "test/MyApp.Tests.dproj",
          "platform": "Win32", "defines": ["CI"] }
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

### Merge semantics

Configuration resolves through three levels per job:

    defaults.{action} > action-level properties > job-level properties

- **Scalars**: child overrides parent (last writer wins).
- **Arrays**: child appends to parent.
- **`key!` suffix**: forces array replacement instead of append.
- **Nested objects** (e.g., `toolchain`): shallow merge.

CLI parameters override the defaults layer and always win over config file
defaults.

### Legacy format (still supported)

The old format with `"steps"` and named sections (`clean`, `build`, `test`)
is automatically converted to a pipeline internally.

---

## Parameters

### -ConfigFile

Path to a JSON configuration file.

### -Root

Root directory used as the resolved absolute working directory and as the default clean root.

### -Steps

Action types to include in the pipeline. Valid values: `Clean`, `Build`,
`Run`. Default: `Clean, Build`. Used when no config file pipeline is
present.

### -ProjectFile

CLI shorthand: creates a single build job with this project file.

### -Platform, -Configuration, -Toolchain, -BuildEngine, -Defines, -BuildVerbosity, -BuildTarget, -ExeOutputDir, -DcuOutputDir, -UnitSearchPath, -IncludePath, -Namespace

Build defaults. Apply to all build jobs through the merge chain.
See `Invoke-DelphiBuild` for descriptions.

### -CleanLevel, -CleanOutputLevel, -CleanIncludeFilePattern, -CleanExcludeDirectoryPattern, -CleanConfigFile, -CleanRecycleBin, -CleanCheck

Clean defaults. Apply to all clean jobs through the merge chain.
See `Invoke-DelphiClean` for descriptions.

### -Execute

CLI shorthand: creates a single run job with this command path.

### -RunArguments, -RunTimeoutSeconds

Run defaults. Apply to all run jobs through the merge chain.
See `Invoke-DelphiRun` for descriptions.

---

## Return value

### Run mode

| Field      | Type       | Notes |
|-----------|------------|-------|
| `Success` | Boolean    | `$true` when every job succeeded |
| `Duration`| TimeSpan   | Wall-clock time for the entire run |
| `Steps`   | Object[]   | One result per job that ran |

Execution stops at the first failing job. Jobs that did not run are not
included in the `Steps` array.

### VersionInfo mode

| Field    | Type           | Notes |
|---------|----------------|-------|
| `Module`| PSCustomObject | `Name` and `Version` of the module |
| `Tools` | Object[]       | One entry per bundled tool |

---

## Examples

### Simple single-project build

```powershell
Invoke-DelphiCi -ProjectFile .\source\MyApp.dproj
```

### Clean only (no project needed)

```powershell
Invoke-DelphiCi -Steps Clean -Root C:\MyRepo
```

### Config-file-driven pipeline

```powershell
Invoke-DelphiCi -ConfigFile .\delphi-ci.json
```

### Build and run a test

```powershell
Invoke-DelphiCi -Steps Build,Run -ProjectFile .\test\MyApp.Tests.dproj -Execute .\test\Win32\Debug\MyApp.Tests.exe
```

### Version info

```powershell
Invoke-DelphiCi -VersionInfo
```

---

## Notes

- Actions run in pipeline order. All jobs within an action complete before
  the next action begins.
- Execution halts on the first failing job in any action.
- Clean-only runs work without a project file on disk.
- `-CleanRecycleBin` and `-CleanCheck` are `[Bool]` (not `[Switch]`) so a
  CLI value of `$false` can override a config file that set them to `true`.
- The pipeline can contain the same action type multiple times (e.g.,
  Build > Run > Build > Run).
