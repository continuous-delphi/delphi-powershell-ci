# Invoke-DelphiBuild

Resolves the Delphi toolchain with the bundled `delphi-inspect.ps1`, then
builds a project with the appropriate bundled build tool. Returns a
structured step result.

---

## Syntax

```powershell
Invoke-DelphiBuild
    -ProjectFile <String>
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
    [-WhatIf]
    [<CommonParameters>]
```

---

## Parameters

### -ProjectFile

Path to the project file to build.

- MSBuild engine: expects a `.dproj` file.
- DCCBuild engine: expects a `.dpr` file.

(Some normalization is attempted if changing the BuildEngine and forget to
change the project extension.)

```
Type:     String
Required: Yes
```

### -Platform

Target platform passed to both `delphi-inspect.ps1` and the build tool.

```
Type:     String
Required: No
Default:  Win32
```

### -Configuration

Build configuration. Common values: `Debug`, `Release`.

- MSBuild: passed as `/p:Config`.
- DCCBuild: passed as a conditional define (`-D<CONFIG>`).

```
Type:     String
Required: No
Default:  Debug
```

### -Toolchain

Selects the Delphi installation to use.

| Value            | Effect |
|-----------------|--------|
| `Latest`         | Runs `delphi-inspect.ps1 -DetectLatest`. Default. |
| Any other value  | Runs `delphi-inspect.ps1 -Locate -Name <value>` to pin by alias or VER### identifier. |

```
Type:     String
Required: No
Default:  Latest
```

### -BuildEngine

Selects the build tool.

| Value      | Tool                  | BuildSystem passed to delphi-inspect |
|-----------|-----------------------|---------------------------------------|
| `MSBuild`  | `delphi-msbuild.ps1`  | `MSBuild`                             |
| `DCCBuild` | `delphi-dccbuild.ps1` | `DCC`                                 |

```
Type:     String
Accepted: MSBuild, DCCBuild
Required: No
Default:  MSBuild
```

### -Defines

Additional conditional defines passed to the build tool via its `-Define`
parameter. Each value is appended to the defines already present in the
project -- existing defines are not replaced.

```
Type:     String[]
Required: No
Default:  (empty)
```

### -BuildVerbosity

Controls the verbosity of the build tool output.

- MSBuild: maps to `/v:<level>`. All five levels are accepted.
- DCCBuild: accepts `quiet` (adds `-Q` to suppress hints/warnings) and
  `normal`. Other values are passed through and may be rejected by the tool.

```
Type:     String
Accepted: quiet, minimal, normal, detailed, diagnostic
Required: No
Default:  normal
```

### -BuildTarget

MSBuild target to run. The CI `Clean` step (`delphi-clean.ps1`) is
unrelated to MSBuild's `Clean` target.

- MSBuild: accepts `Build`, `Clean`, `Rebuild`.
- DCCBuild: accepts `Build` and `Rebuild` only. `Clean` is rejected with
  a clear error.

```
Type:     String
Accepted: Build, Clean, Rebuild
Required: No
Default:  Build
```

### -ExeOutputDir

Output directory for the compiled executable or DLL.

- MSBuild: passed as `/p:DCC_ExeOutput`.
- DCCBuild: passed as the `-E` flag.

```
Type:     String
Required: No
Default:  (project default)
```

### -DcuOutputDir

Output directory for compiled DCU files.

- MSBuild: passed as `/p:DCC_DcuOutput`.
- DCCBuild: passed as the `-N0` flag.

```
Type:     String
Required: No
Default:  (project default)
```

### -UnitSearchPath

Additional unit search paths appended to whatever the project already sets.

- MSBuild: passed as `/p:DCC_UnitSearchPath`.
- DCCBuild: passed as the `-U` flag.

```
Type:     String[]
Required: No
Default:  (empty)
```

### -IncludePath

Additional include file search paths (DCC `-I` flag). **DCCBuild-only** --
rejected with a clear error when `BuildEngine` is `MSBuild`. With MSBuild,
configure include paths via the project's PropertyGroups.

```
Type:     String[]
Required: No
Default:  (empty)
```

### -Namespace

Unit scope names searched when resolving unqualified unit names (DCC `-NS`
flag). Required for modern Delphi projects that use namespaced RTL units
(e.g. `System.SysUtils`) when building outside the IDE without a project
`.cfg` file. **DCCBuild-only** -- rejected with a clear error when
`BuildEngine` is `MSBuild`.

```
Type:     String[]
Required: No
Default:  (empty)
```

### -WhatIf

Shows what would be built without running the toolchain. Toolchain detection
and the build tool are both skipped; the step returns a success result
without executing.

```
Type:     SwitchParameter
Required: No
```

---

## Return value

Returns a `PSCustomObject` with the following fields.

| Field         | Type     | Notes |
|--------------|----------|-------|
| `StepName`   | String   | Always `'Build'` |
| `Success`    | Boolean  | `$true` when the build exits with code 0 |
| `Duration`   | TimeSpan | Wall-clock time including toolchain detection |
| `ExitCode`   | Int32    | Exit code from the build tool |
| `Tool`       | String   | `'delphi-msbuild.ps1'` or `'delphi-dccbuild.ps1'` |
| `Message`    | String   | `'Build completed'` on success; `'Exit code N'` on failure |
| `ProjectFile`| String   | The path passed via `-ProjectFile` |
| `Warnings`   | Int32    | Warning count parsed from MSBuild/DCC output |
| `Errors`     | Int32    | Error count parsed from MSBuild/DCC output |
| `ExeOutputDir`| String  | Resolved output directory for the compiled executable |
| `Output`     | String   | Full build output text |

---

## JSON config equivalent

Build options are controlled by the `build` section of the JSON config file
used with `Get-DelphiCiConfig` or `Invoke-DelphiCi`.

```json
{
  "build": {
    "engine": "MSBuild",
    "toolchain": { "version": "Latest" },
    "platform": "Win32",
    "configuration": "Debug",
    "defines": ["CI"],
    "verbosity": "normal",
    "target": "Build",
    "exeOutputDir": "",
    "dcuOutputDir": "",
    "unitSearchPath": [],
    "includePath": [],
    "namespace": []
  }
}
```

`includePath` and `namespace` apply only when `engine` is `DCCBuild`.

To use DCCBuild, set `"engine": "DCCBuild"` and point `projectFile` at
a `.dpr` file rather than a `.dproj`.

`Invoke-DelphiBuild` is a step command -- it receives resolved values from
the orchestration layer and does not read a config file directly.

---

## Examples

### Convention-based build (latest Delphi, Win32 Debug, MSBuild)

```powershell
Invoke-DelphiBuild -ProjectFile .\source\MyApp.dproj
```

### DCCBuild engine

```powershell
Invoke-DelphiBuild -ProjectFile .\source\MyApp.dpr -BuildEngine DCCBuild
```

### Explicit platform and configuration

```powershell
Invoke-DelphiBuild -ProjectFile .\source\MyApp.dproj -Platform Win64 -Configuration Release
```

### Pin to a specific Delphi version

```powershell
Invoke-DelphiBuild -ProjectFile .\source\MyApp.dproj -Toolchain VER370
```

### Pass extra compiler defines

```powershell
Invoke-DelphiBuild -ProjectFile .\source\MyApp.dproj -Defines @('CI', 'RELEASE_BUILD')
```

### Rebuild with minimal output

```powershell
Invoke-DelphiBuild -ProjectFile .\source\MyApp.dproj -BuildTarget Rebuild -BuildVerbosity minimal
```

### Redirect output directories

```powershell
Invoke-DelphiBuild -ProjectFile .\source\MyApp.dproj `
    -ExeOutputDir C:\Out\Bin -DcuOutputDir C:\Out\Dcu
```

### Additional unit search paths

```powershell
Invoke-DelphiBuild -ProjectFile .\source\MyApp.dproj `
    -UnitSearchPath @('libs\Spring4D', 'libs\DUnitX')
```

### DCCBuild with namespace imports

```powershell
Invoke-DelphiBuild -ProjectFile .\source\MyApp.dpr -BuildEngine DCCBuild `
    -Namespace @('System', 'Vcl', 'Winapi', 'Data')
```

### Capture and inspect the result

```powershell
$build = Invoke-DelphiBuild -ProjectFile .\source\MyApp.dproj
if (-not $build.Success) {
    Write-Error "Build failed with exit code $($build.ExitCode)"
}
Write-Host "Warnings: $($build.Warnings), Errors: $($build.Errors)"
Write-Host "Build took $($build.Duration.TotalSeconds)s"
```

---

## Notes

- Toolchain detection (delphi-inspect) and the build tool run as separate
  child `pwsh` processes. The rootDir from inspect is passed directly to the
  build tool via `-RootDir`.
- `Duration` covers toolchain detection plus the full build tool run.
- Build output streams to the console in real time via `-ShowOutput`.
- For DCCBuild, the `-Config` value is added as a conditional define
  (uppercased) alongside any `-Define` values. Existing defines in the
  project's `.cfg` file are not affected.
- `-IncludePath` and `-Namespace` are rejected when `BuildEngine` is
  `MSBuild`. Configure these via the project's PropertyGroups instead.
- `-BuildTarget Clean` is rejected when `BuildEngine` is `DCCBuild`.
  Use the CI `Clean` step (`delphi-clean.ps1`) or `BuildTarget Rebuild`
  instead.
