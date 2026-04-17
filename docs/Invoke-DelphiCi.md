# Invoke-DelphiCi

Primary orchestration command. Loads configuration, then runs the requested
step types (Clean, Build, and/or Test) in order. Each step type can have
multiple jobs. Always returns a structured result object.

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
    [-TestExeFile <String>]
    [-TestArguments <String[]>]
    [-TestTimeoutSeconds <Int>]
    [<CommonParameters>]
```

Version info mode:

```powershell
Invoke-DelphiCi -VersionInfo
```

---

## Jobs model

Each step type (Clean, Build, Test) supports multiple **jobs** defined in
the config file. Jobs within a step run sequentially. Build jobs support
**matrix expansion** -- `platform` and `configuration` can be arrays,
producing a cross product of builds.

When no jobs are defined:
- **Clean** creates a default job from the clean defaults + root.
- **Build** throws an error (a project file is required).
- **Test** throws an error (a test executable is required).

For CLI shorthand, `-ProjectFile` creates a single build job and
`-TestExeFile` creates a single test job.

---

## Parameters

### -ConfigFile

Path to a JSON configuration file. See the JSON config section below.

### -Root

Root directory used for project discovery and as the default clean root.

### -Steps

Step types to run, in order. Valid values: `Clean`, `Build`, `Test`.
Default: `Clean, Build`.

### -ProjectFile

CLI shorthand: creates a single build job with this project file. Overrides
any `build.jobs` in the config file.

### -Platform, -Configuration, -Toolchain, -BuildEngine, -Defines, -BuildVerbosity, -BuildTarget, -ExeOutputDir, -DcuOutputDir, -UnitSearchPath, -IncludePath, -Namespace

Build defaults. Apply to all build jobs that do not override these fields.
See `Invoke-DelphiBuild` for descriptions.

### -CleanLevel, -CleanOutputLevel, -CleanIncludeFilePattern, -CleanExcludeDirectoryPattern, -CleanConfigFile, -CleanRecycleBin, -CleanCheck

Clean defaults. Apply to all clean jobs that do not override these fields.
See `Invoke-DelphiClean` for descriptions.

### -TestExeFile

CLI shorthand: creates a single test job with this executable path.
Overrides any `test.jobs` in the config file.

### -TestArguments, -TestTimeoutSeconds

Test defaults. Apply to all test jobs that do not override these fields.
See `Invoke-DelphiTest` for descriptions.

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

## JSON config file

```json
{
  "root": ".",
  "steps": ["Clean", "Build", "Test"],
  "clean": {
    "level": "deep",
    "outputLevel": "detailed",
    "recycleBin": false,
    "check": false,
    "jobs": [
      { "name": "Repo clean", "root": "./" }
    ]
  },
  "build": {
    "engine": "MSBuild",
    "toolchain": { "version": "Latest" },
    "platform": "Win64",
    "configuration": "Release",
    "verbosity": "minimal",
    "jobs": [
      { "name": "Main App",
        "projectFile": "source/MyApp.dproj" },
      { "name": "Test project",
        "projectFile": "test/MyApp.Tests.dproj",
        "platform": ["Win32", "Win64"],
        "configuration": ["Debug", "Release"],
        "defines": ["CI"] }
    ]
  },
  "test": {
    "timeoutSeconds": 10,
    "jobs": [
      { "name": "Tests Win32 Debug",
        "testExeFile": "test/Win32/Debug/MyApp.Tests.exe" },
      { "name": "Tests Win64 Release",
        "testExeFile": "test/Win64/Release/MyApp.Tests.exe" }
    ]
  }
}
```

### Key concepts

- **Step defaults** (top-level fields in `clean`, `build`, `test`) are
  inherited by every job in that section.
- **Per-job overrides**: any field can be overridden in a job entry.
- **Matrix expansion** (build only): `platform` and `configuration` can be
  string or array. Arrays produce a cross product of builds.
- `includePath` and `namespace` are DCCBuild-only and ignored for MSBuild.
- CLI parameters override the corresponding defaults but not per-job values.

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

### Config-file-driven multi-project build

```powershell
Invoke-DelphiCi -ConfigFile .\delphi-ci.json
```

### Version info

```powershell
Invoke-DelphiCi -VersionInfo
```

---

## Notes

- Steps run in the order listed in `-Steps`. All jobs within a step complete
  before the next step begins.
- Execution halts on the first failing job in any step.
- Clean-only runs work without a project file on disk.
- `-CleanRecycleBin` and `-CleanCheck` are `[Bool]` (not `[Switch]`) so a
  CLI value of `$false` can override a config file that set them to `true`.
