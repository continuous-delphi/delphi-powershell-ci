# Get-DelphiCiConfig

Loads and normalizes configuration for a Delphi CI run.

Merges three sources in priority order (highest to lowest):

1. Explicit CLI parameters
2. JSON config file
3. Built-in defaults

Returns a single `PSCustomObject` that all downstream commands consume.
Callers never need to merge sources themselves.

## Syntax

```powershell
Get-DelphiCiConfig
    [-ConfigFile <string>]
    [-Root <string>]
    [-ProjectFile <string>]
    [-Steps <string[]>]
    [-Platform <string>]
    [-Configuration <string>]
    [-Toolchain <string>]
    [-BuildEngine <string>]
    [-Defines <string[]>]
    [-CleanIncludeFiles <string[]>]
    [-CleanExcludeDirectories <string[]>]
    [-TestProjectFile <string>]
    [-TestExecutable <string>]
    [-TestDefines <string[]>]
    [-TestArguments <string[]>]
    [-TestTimeoutSeconds <int>]
    [-TestBuild <bool>]
    [-TestRun <bool>]
```

## Parameters

### -ConfigFile

Path to a structured JSON config file.
When supplied, `root` inside the JSON is resolved relative to the config
file's directory, not the current working directory.

### -Root

Working root for project discovery and clean operations.
Overrides the root derived from the config file or the current directory.

### -ProjectFile

Explicit path to the `.dproj` (or `.dpr` when using DCC) file to build.
Skips convention-based discovery when supplied.

### -Steps

One or more pipeline steps to run.
Valid values: `Clean`, `Build`, `Test`.
Default when omitted: `Clean`, `Build`.

### -Platform

Delphi build platform (e.g. `Win32`, `Win64`).
Default: `null` -- when not specified, Build and Test each resolve the
platform independently from their respective project files (Win32 unless
the project has exactly one active platform). Supply an explicit value to
force the same platform for both steps.

### -Configuration

MSBuild configuration name (e.g. `Debug`, `Release`).
Default: `Debug`.

### -Toolchain

Delphi toolchain version selector passed to `delphi-inspect`.
Accepts any identifier the tool recognises: a display name (`Florence`),
an alias (`Athens`), a compiler version tag (`VER370`), or the sentinel
`Latest` to auto-detect the highest installed version.
Default: `Latest`.

Maps to `build.toolchain.version` in the JSON config file.

### -BuildEngine

Build engine to invoke.
Valid values: `MSBuild`, `DCCBuild`.
Default: `MSBuild`.

### -Defines

Additional conditional compiler defines for the Build step. Overrides any
defines set in the JSON config file. Each value is appended to the
project's existing defines at build time -- the project's own defines are
not replaced.

### -CleanIncludeFiles

Additional file glob patterns forwarded to the Clean step. Files matching
these patterns are deleted in addition to the standard level set.

### -CleanExcludeDirectories

Directory glob patterns forwarded to the Clean step. Directories whose names
match are skipped entirely during cleanup.

### -TestProjectFile

Explicit path to the test `.dproj` or `.dpr` file. When absent, discovery
searches `<root>\tests\` then `<root>` for a project whose name starts or
ends with `Tests`.

### -TestExecutable

Explicit path to the test `.exe`. When supplied, `Invoke-DelphiTest` skips
the standard derivation and uses this path directly. Use when the project
overrides `DCC_ExeOutput` or places output in a non-default location.

### -TestDefines

Conditional compiler defines passed to the test project build. DUnitX
projects typically require `CI` here to activate the headless console
runner. Not injected automatically.

### -TestArguments

Extra command-line arguments forwarded to the test executable at runtime.

### -TestTimeoutSeconds

Maximum seconds the test process may run before it is killed.
Default: `10`.

### -TestBuild

Set to `$false` to skip building the test project (run only).
Default: `$true`.

### -TestRun

Set to `$false` to skip running the test executable (build only).
Default: `$true`.

## Return value

A `PSCustomObject` with the following shape:

```
Root          string     Resolved absolute path to the working root
ProjectFile   string     Path to the .dproj file, or $null if not set
Steps         string[]   Ordered list of steps to run
Clean
  Level              string     Clean depth: lite | build | full
  IncludeFiles       string[]   Additional file patterns to delete (appended to level set)
  ExcludeDirectories string[]   Directory patterns to skip during cleanup
Build
  Engine          string   MSBuild | DCCBuild
  Toolchain
    Version       string   Toolchain selector or "Latest"
  Platform        string   Target platform, or $null if not set (auto-resolve at run time)
  Configuration   string   MSBuild configuration
  Defines         string[] Additional compiler defines (appended, not replaced)
Test
  TestProjectFile  string     Explicit test project path, or $null (auto-discover)
  TestExecutable   string     Explicit test EXE path, or $null (auto-derive)
  Defines          string[]   Compiler defines for the test build
  Arguments        string[]   Runtime arguments forwarded to the test EXE
  TimeoutSeconds   int        Kill timeout for the test process
  Build            bool       Whether to build the test project
  Run              bool       Whether to run the test executable
```

## JSON config file format

```json
{
  "root": ".",
  "steps": ["Clean", "Build", "Test"],
  "clean": {
    "level": "lite",
    "includeFiles": ["*.res"],
    "excludeDirectories": ["vendor"]
  },
  "build": {
    "projectFile": "source/MyApp.dproj",
    "engine": "MSBuild",
    "toolchain": {
      "version": "Latest"
    },
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

All fields are optional. Any field absent from the file falls back to the
built-in default. Fields present in the file are overridden by any
matching CLI parameter.

`root` is resolved relative to the directory that contains the config file.
Use `"."` to anchor to that directory (the typical case) or a relative
path such as `".."` to refer to a parent.

## Examples

### Pure defaults

```powershell
Get-DelphiCiConfig
```

Returns the default configuration with root set to the current directory,
`Win32 Debug` build, `MSBuild` engine, `Latest` toolchain, and default
test settings.

### Load from a config file

```powershell
Get-DelphiCiConfig -ConfigFile .\myapp-ci.json
```

Reads all settings from the file. Fields not present in the file use
built-in defaults.

### Override a single field at the CLI

```powershell
Get-DelphiCiConfig -ConfigFile .\myapp-ci.json -Platform Win64
```

All settings come from the file except `Platform`, which is forced to
`Win64` regardless of what the file says.

### Explicit project with no config file

```powershell
Get-DelphiCiConfig -ProjectFile .\source\MyApp.dproj -Toolchain Florence
```

No config file. Project file and toolchain version are set explicitly;
everything else uses defaults.

### Full pipeline with test settings

```powershell
Get-DelphiCiConfig -Steps Clean,Build,Test `
    -TestProjectFile .\tests\MyApp.Tests.dproj `
    -TestDefines CI `
    -TestTimeoutSeconds 30
```

### Test-only run

```powershell
Get-DelphiCiConfig -Steps Test
```

Returns a config where only the `Test` step is requested.

### Build-only run

```powershell
Get-DelphiCiConfig -Steps Build
```

Returns a config where only the `Build` step is requested.

## Notes

- `build.defines` and `test.defines` are appended to the project's existing
  defines, not substituted. The project's own defines remain intact.
- `build.toolchain` is an object to allow future extensibility. Currently
  only `version` is supported.
- `build.toolchain.version` selects the compiler toolchain to use. It is
  unrelated to a future `build.setVersion` field, which will control the
  version number stamped into the built executable.
- When `build.platform` is `$null` (not set), `Invoke-DelphiCi` resolves
  the Build platform from the main project file and the Test platform from
  the test project file independently at run time.
- Validation errors (invalid step name, clean level, or engine value)
  are thrown immediately so problems surface before any build work begins.
