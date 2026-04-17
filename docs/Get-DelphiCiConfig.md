# Get-DelphiCiConfig

Loads and normalizes configuration for a Delphi CI run.

Merges three sources in priority order (highest to lowest):

1. Explicit CLI parameters
2. JSON config file
3. Built-in defaults

Returns a single `PSCustomObject` that all downstream commands consume.

## Syntax

```powershell
Get-DelphiCiConfig
    [-ConfigFile <string>]
    [-Root <string>]
    [-Steps <string[]>]
    [-ProjectFile <string>]
    [-Platform <string>]
    [-Configuration <string>]
    [-Toolchain <string>]
    [-BuildEngine <string>]
    [-Defines <string[]>]
    [-BuildVerbosity <string>]
    [-BuildTarget <string>]
    [-ExeOutputDir <string>]
    [-DcuOutputDir <string>]
    [-UnitSearchPath <string[]>]
    [-IncludePath <string[]>]
    [-Namespace <string[]>]
    [-CleanLevel <string>]
    [-CleanOutputLevel <string>]
    [-CleanIncludeFilePattern <string[]>]
    [-CleanExcludeDirectoryPattern <string[]>]
    [-CleanConfigFile <string>]
    [-CleanRecycleBin <bool>]
    [-CleanCheck <bool>]
    [-TestExeFile <string>]
    [-TestArguments <string[]>]
    [-TestTimeoutSeconds <int>]
```

## Return value

```
Root   string     Resolved absolute path to the working root
Steps  string[]   Ordered list of steps to run

Clean
  Defaults
    Level                   string     basic | standard | deep
    OutputLevel             string     detailed | summary | quiet
    IncludeFilePattern      string[]   Additional file patterns to delete
    ExcludeDirectoryPattern string[]   Directory patterns to skip
    ConfigFile              string     Explicit delphi-clean config file
    RecycleBin              bool       Send items to recycle bin
    Check                   bool       Audit-only mode
  Jobs                      object[]   Resolved clean job entries

Build
  Defaults
    Engine          string     MSBuild | DCCBuild
    Toolchain
      Version       string     Toolchain selector or "Latest"
    Platform        string     Default target platform
    Configuration   string     Default MSBuild configuration
    Defines         string[]   Default compiler defines
    Verbosity       string     Build output verbosity
    Target          string     Build | Clean | Rebuild
    ExeOutputDir    string     Output dir for executables
    DcuOutputDir    string     Output dir for DCU files
    UnitSearchPath  string[]   Additional unit search paths
    IncludePath     string[]   Include paths (DCCBuild-only)
    Namespace       string[]   Unit scope names (DCCBuild-only)
  Jobs              object[]   Resolved build job entries (platform/config as arrays)

Test
  Defaults
    TimeoutSeconds  int        Kill timeout for the test process
    Arguments       string[]   Runtime arguments forwarded to test EXE
  Jobs              object[]   Resolved test job entries
```

## JSON config file format

```json
{
  "root": ".",
  "steps": ["Clean", "Build", "Test"],
  "clean": {
    "level": "basic",
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
    "platform": "Win32",
    "configuration": "Debug",
    "verbosity": "normal",
    "target": "Build",
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
      { "name": "Unit tests",
        "testExeFile": "test/Win32/Debug/MyApp.Tests.exe" }
    ]
  }
}
```

All fields are optional. Absent fields use built-in defaults.

`root` is resolved relative to the config file's directory.

Per-job fields inherit from the section defaults and can override any field.
Build job `platform` and `configuration` can be string or array for matrix
expansion.

## Notes

- CLI parameters override section defaults but not per-job values defined
  in the config file.
- `-ProjectFile` creates a single-entry build jobs list.
- `-TestExeFile` creates a single-entry test jobs list.
- Validation errors (invalid step, level, engine, verbosity, target) throw
  immediately before any work begins.
