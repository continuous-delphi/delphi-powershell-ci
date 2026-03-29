# Invoke-DelphiCi

Primary orchestration command. Loads configuration, discovers the project if
needed, then runs the requested steps (Clean, Build, and/or Test) in order.
Always returns a structured result object.

---

## Syntax

Run mode (default):

```powershell
Invoke-DelphiCi
    [-ConfigFile <String>]
    [-Root <String>]
    [-ProjectFile <String>]
    [-Steps <String[]>]
    [-Platform <String>]
    [-Configuration <String>]
    [-Toolchain <String>]
    [-BuildEngine <String>]
    [-Defines <String[]>]
    [-CleanIncludeFiles <String[]>]
    [-CleanExcludeDirectories <String[]>]
    [-TestProjectFile <String>]
    [-TestExecutable <String>]
    [-TestDefines <String[]>]
    [-TestArguments <String[]>]
    [-TestTimeoutSeconds <Int>]
    [-TestBuild <Bool>]
    [-TestRun <Bool>]
    [<CommonParameters>]
```

Version info mode:

```powershell
Invoke-DelphiCi
    -VersionInfo
    [<CommonParameters>]
```

---

## Parameters

### -VersionInfo

Reports the module version and the version of each bundled tool. Mutually
exclusive with all Run-mode parameters. Always returns a structured result object.

```
Type:     SwitchParameter
Required: Yes (in VersionInfo parameter set)
```

### -ConfigFile

Path to a JSON configuration file. All fields are optional; absent fields
fall back to built-in defaults. See `Get-DelphiCiConfig` for the supported
schema.

```
Type:     String
Required: No
```

### -Root

Root directory used for project discovery when no `-ProjectFile` is
given. Also passed as the working root to the Clean step.

When a config file is supplied and contains a `root` field, that value is
used if `-Root` is not explicitly bound. An explicit `-Root` parameter
always takes precedence.

```
Type:     String
Required: No
Default:  Current working directory (or config file directory when -ConfigFile is used)
```

### -ProjectFile

Explicit path to the `.dproj` file to build. Skips project discovery.

When absent, discovery runs against the resolved root:
1. `<root>` -- if exactly one `.dproj` is present
2. `<root>\source` -- fallback
3. `<root>\..\source` -- tools-folder convention fallback
4. Fails with a clear error if no `.dproj` is found, or if more than one
   is found and no explicit file was given.

```
Type:     String
Required: No
```

### -Steps

One or more step names to run, in order. Valid values: `Clean`, `Build`, `Test`.

```
Type:     String[]
Required: No
Default:  Clean, Build
```

### -Platform

Target platform. Overrides the config file value.

When not supplied, each step resolves its platform independently: Build reads
from the main project file; Test reads from the test project file. Both fall
back to `Win32` when the project has no active platform set, or when the
engine is `DCCBuild`.

```
Type:     String
Required: No
Default:  auto (resolved per step from the respective project file)
```

### -Configuration

MSBuild configuration. Overrides the config file value.

```
Type:     String
Required: No
Default:  Debug
```

### -Toolchain

Delphi toolchain version. `Latest` detects the highest ready installation;
any other value (e.g. `VER370`, `Delphi 13`) pins to that version.
Overrides the config file value.

```
Type:     String
Required: No
Default:  Latest
```

### -BuildEngine

Build engine to invoke. Valid values: `MSBuild`, `DCCBuild`.

```
Type:     String
Required: No
Default:  MSBuild
```

### -Defines

Additional conditional compiler defines passed to the Build step. Overrides
any `defines` array present in the JSON config file. Values are appended to
the project's existing defines -- they do not replace them.

```
Type:     String[]
Required: No
Default:  (empty, or config file value)
```

### -CleanIncludeFiles

Additional file glob patterns forwarded to the Clean step as
`-IncludeFiles`. Files matching these patterns are deleted in addition to
the standard level set (e.g. `*.res`, `*.mab`).

```
Type:     String[]
Required: No
Default:  (empty, or config file value)
```

### -CleanExcludeDirectories

Directory glob patterns forwarded to the Clean step as `-ExcludeDirectories`.
Directories whose names match are skipped entirely during cleanup
(e.g. `vendor`, `assets`).

```
Type:     String[]
Required: No
Default:  (empty, or config file value)
```

### -TestProjectFile

Explicit path to the test `.dproj` or `.dpr` file. When absent, discovery
searches `<root>\tests\` then `<root>` for a project whose name starts or
ends with `Tests`.

```
Type:     String
Required: No
Default:  (auto-discover)
```

### -TestExecutable

Explicit path to the test `.exe`. When supplied, skips the standard
derivation (`[TestProjectDir]\[Platform]\[Config]\[BaseName].exe`).
Use when the project overrides `DCC_ExeOutput` or places output in a
non-default location.

```
Type:     String
Required: No
Default:  (auto-derive from test project file, platform, and configuration)
```

### -TestDefines

Conditional compiler defines passed to the test project build. DUnitX
projects typically require `CI` here to activate the headless console runner
instead of the TestInsight IDE runner. Not injected automatically.

```
Type:     String[]
Required: No
Default:  (empty, or config file value)
```

### -TestArguments

Extra command-line arguments forwarded to the test executable at runtime.

```
Type:     String[]
Required: No
Default:  (empty, or config file value)
```

### -TestTimeoutSeconds

Maximum seconds the test process may run before it is killed. If killed,
the step fails with exit code `-1`.

```
Type:     Int
Required: No
Default:  10
```

### -TestBuild

Set to `$false` to skip building the test project and only run a previously
built executable.

```
Type:     Bool
Required: No
Default:  $true
```

### -TestRun

Set to `$false` to skip running the test executable and only build.

```
Type:     Bool
Required: No
Default:  $true
```

---

## Return value

### Run mode

Returns a `PSCustomObject` with the following fields.

| Field         | Type       | Notes |
|--------------|------------|-------|
| `Success`    | Boolean    | `$true` when every executed step succeeded |
| `Duration`   | TimeSpan   | Wall-clock time for the entire run |
| `ProjectFile`| String     | Resolved main project file path |
| `Steps`      | Object[]   | One step result per step that ran (see below) |

Execution stops at the first failing step. Steps that did not run are not
included in the `Steps` array.

Each Clean or Build entry in `Steps`:

| Field         | Type    | Notes |
|--------------|---------|-------|
| `StepName`   | String  | `Clean` or `Build` |
| `Success`    | Boolean | |
| `Duration`   | TimeSpan | |
| `ExitCode`   | Int     | |
| `Tool`       | String  | |
| `Message`    | String  | |
| `ProjectFile`| String  | |

Each Test entry in `Steps`:

| Field            | Type    | Notes |
|-----------------|---------|-------|
| `StepName`      | String  | `Test` |
| `Success`       | Boolean | |
| `Duration`      | TimeSpan | |
| `ExitCode`      | Int     | `-1` on timeout |
| `Tool`          | String  | `test runner` |
| `Message`       | String  | |
| `TestProjectFile`| String | Resolved test project path |
| `TestExecutable` | String | Derived EXE path; `$null` if build failed |

### VersionInfo mode

Always returns a `PSCustomObject` with the following fields.

| Field    | Type         | Notes |
|---------|--------------|-------|
| `Module` | PSCustomObject | `Name` (string) and `Version` (string) of the orchestration module |
| `Tools`  | Object[]     | One entry per bundled tool (see below) |

Each entry in `Tools`:

| Field     | Type    | Notes |
|----------|---------|-------|
| `Name`    | String  | Tool file name without extension, e.g. `delphi-inspect` |
| `Version` | String  | Reported version string, or `$null` if it could not be read |
| `Present` | Boolean | `$true` if the tool file exists in the bundled-tools folder |
| `Path`    | String  | Full path to the tool file |

---

## JSON config equivalent

A config file can supply any subset of these fields:

```json
{
  "root": ".",
  "steps": ["Clean", "Build", "Test"],
  "clean": {
    "level": "basic",
    "includeFiles": ["*.res"],
    "excludeDirectories": ["vendor"]
  },
  "build": {
    "projectFile": "source/MyApp.dproj",
    "engine": "MSBuild",
    "toolchain": { "version": "Latest" },
    "platform": "Win32",
    "configuration": "Debug",
    "defines": []
  },
  "test": {
    "testProjectFile": "tests/MyApp.Tests.dproj",
    "testExecutable": "tests/Win32/Debug/MyApp.Tests.exe",
    "defines": ["CI"],
    "arguments": [],
    "timeoutSeconds": 10,
    "build": true,
    "run": true
  }
}
```

CLI parameters always take precedence over config file values, which take
precedence over built-in defaults.

---

## Examples

### Report module and bundled tool versions

```powershell
Invoke-DelphiCi -VersionInfo
```

Displays the module version and the version of each bundled tool. Returns
a structured object so the output can be inspected programmatically:

```powershell
$info = Invoke-DelphiCi -VersionInfo
$info.Module.Version                          # e.g. '0.1.0'
$info.Tools | Where-Object Name -eq 'delphi-inspect' | Select-Object -ExpandProperty Version
```

### Convention-based run from the current directory

```powershell
Invoke-DelphiCi
```

Discovers a single `.dproj` under the current directory, cleans with
`basic` level, then builds Win32 Debug using the latest Delphi.

### Explicit project

```powershell
Invoke-DelphiCi -ProjectFile .\source\MyApp.dproj
```

### Full pipeline: clean, build, and test

```powershell
Invoke-DelphiCi -Steps Clean,Build,Test `
    -ProjectFile .\source\MyApp.dproj `
    -TestProjectFile .\tests\MyApp.Tests.dproj `
    -TestDefines CI
```

The `CI` define switches DUnitX from the TestInsight IDE runner to the
headless console runner. It is not injected automatically.

### Test step only

```powershell
Invoke-DelphiCi -Steps Test `
    -TestProjectFile .\tests\MyApp.Tests.dproj `
    -TestDefines CI
```

The Test step is self-contained and does not require Clean or Build to have
run first.

### Build-only test (verify compilation without running)

```powershell
Invoke-DelphiCi -Steps Test `
    -TestProjectFile .\tests\MyApp.Tests.dproj `
    -TestDefines CI `
    -TestRun $false
```

### Config-file-driven run

```powershell
Invoke-DelphiCi -ConfigFile .\myapp-ci.json
```

### Clean only

```powershell
Invoke-DelphiCi -Steps Clean -ProjectFile .\source\MyApp.dproj
```

### Build only, pinned version, release config

```powershell
Invoke-DelphiCi -Steps Build -ProjectFile .\source\MyApp.dproj `
    -Toolchain VER370 -Configuration Release
```

### Capture and inspect the full result

```powershell
$run = Invoke-DelphiCi -Steps Clean,Build,Test `
    -ProjectFile .\source\MyApp.dproj `
    -TestProjectFile .\tests\MyApp.Tests.dproj `
    -TestDefines CI
if (-not $run.Success) {
    $failed = $run.Steps | Where-Object { -not $_.Success }
    Write-Error "Failed steps: $($failed.StepName -join ', ')"
}
Write-Host "Total time: $($run.Duration.TotalSeconds.ToString('F2'))s"
```

### Map result to a process exit code in a CI wrapper script

```powershell
$run = Invoke-DelphiCi -ProjectFile .\source\MyApp.dproj
exit [int](-not $run.Success)
```

---

## Notes

- Steps run in the order listed in `-Steps` (or in the config file). The
  default order is `Clean` then `Build`.
- Execution stops at the first step that fails. Subsequent steps are skipped.
- The Clean step runs against the resolved root, not the project file's
  directory. Use `-Root` to target a different tree.
- `Defines` (for Build) and `TestDefines` (for Test) are appended to the
  project's existing PropertyGroup defines -- they do not replace them.
- When `-Platform` is not supplied, Build and Test each resolve the platform
  independently from their respective project files. Supply `-Platform`
  explicitly to use the same value for both.
- The `CI` define is not injected automatically into the Test step. Include
  it in `-TestDefines` when the test project requires it.
- The command always returns a structured result. In a CI wrapper script,
  check `$result.Success` and call `exit 1` (or `exit [int](-not $result.Success)`)
  to produce a non-zero process exit code on failure.
