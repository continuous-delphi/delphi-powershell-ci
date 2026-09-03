# Invoke-DelphiFormat

Runs the bundled `delphi-format.ps1` script against a Delphi source tree and
returns a structured step result. Formatting is delegated to a pluggable engine
(RAD Studio `formatter.exe` or `radFormatter.exe`); the wrapper only forwards
resolved options and normalizes the result.

---

## Syntax

```powershell
Invoke-DelphiFormat
    [-FormatRoot <String>]
    [-FormatEngine <String>]
    [-FormatEnginePath <String>]
    [-FormatEngineConfigFile <String>]
    [-FormatPath <String[]>]
    [-FormatIncludeFilePattern <String[]>]
    [-FormatExcludeDirectoryPattern <String[]>]
    [-FormatEncoding <String>]
    [-FormatCreateBackups]
    [-FormatOutputLevel <String>]
    [-FormatConfigFile <String>]
    [-FormatCheck]
    [-WhatIf]
    [<CommonParameters>]
```

---

## Parameters

### -FormatRoot

Absolute or relative path to the directory that `delphi-format.ps1` should treat
as the root when scanning for source files. Defaults to the current working
directory.

```
Type:     String
Required: No
Default:  (Get-Location).Path
```

### -FormatEngine

Selects the formatting engine.

| Value          | Effect |
|----------------|--------|
| `formatter`    | RAD Studio `formatter.exe`. Discovered on `PATH` unless `-FormatEnginePath` is set. Default. |
| `radFormatter` | `radFormatter.exe`. Supports a native `-check` (audit) mode. |

```
Type:     String
Accepted: formatter, radFormatter
Required: No
Default:  formatter
```

### -FormatEnginePath

Explicit path to the formatting engine executable. When empty, the engine is
discovered on `PATH`. Forwarded to the bundled tool as `-EnginePath`.

```
Type:     String
Required: No
Default:  (empty -- discover on PATH)
```

### -FormatEngineConfigFile

Engine-specific configuration file passed through to the engine as
`-EngineConfigFile` (for example, a `formatter.exe` options file). Distinct
from `-FormatConfigFile`, which configures `delphi-format` itself.

```
Type:     String
Required: No
Default:  (empty -- engine default)
```

### -FormatPath

Explicit files or directories to format, forwarded to the bundled tool as
repeated `-Path` arguments. Relative entries resolve from `-FormatRoot`. When
empty, the whole root is scanned.

```
Type:     String[]
Required: No
Default:  (empty -- scan the whole root)
```

### -FormatIncludeFilePattern

Additional file glob patterns to include, forwarded as `-IncludeFilePattern`.
Extends the default set of Delphi source extensions (`*.pas`, `*.dpr`, `*.dpk`,
`*.dpkw`, `*.inc`).

```
Type:     String[]
Required: No
Default:  (empty -- no extra patterns)
```

### -FormatExcludeDirectoryPattern

Directory glob patterns to skip, forwarded as `-ExcludeDirectoryPattern`.
Directories whose names match are excluded from the scan (in addition to the
built-in exclusions such as `.git`, `.vs`, and `.claude`).

```
Type:     String[]
Required: No
Default:  (empty -- no extra directories excluded)
```

### -FormatEncoding

File encoding passed through to the engine as `-Encoding`. When empty, the
engine's default encoding is used.

```
Type:     String
Required: No
Default:  (empty -- engine default)
```

### -FormatCreateBackups

When set, the engine writes a backup of each modified file before formatting.
Forwarded to the bundled tool as `-CreateBackups`.

```
Type:     SwitchParameter
Required: No
```

### -FormatOutputLevel

Controls the amount of plain-text output produced by `delphi-format.ps1`.

| Value      | Effect |
|------------|--------|
| `detailed` | Header, per-file lines, and summary. Default. |
| `summary`  | Header and summary only; per-file lines are suppressed. |
| `quiet`    | No output at all; use the exit code as the signal. |

```
Type:     String
Accepted: detailed, summary, quiet
Required: No
Default:  detailed
```

### -FormatConfigFile

Path to an explicit `delphi-format` JSON configuration file. Forwarded to the
bundled tool as `-ConfigFile`. Loaded at higher priority than a project-level
`delphi-format.json` found in the root directory, but lower priority than the
CLI parameters above. Useful in CI pipelines where the config lives outside the
repository tree.

```
Type:     String
Required: No
Default:  (empty -- no explicit config file)
```

### -FormatCheck

Runs `delphi-format.ps1` in audit-only mode (`-Check`). Reports which files
need formatting but never modifies them. Returns a failing exit code (1) when
any file is not correctly formatted, or success (0) when the tree is clean.
This is the natural CI gate. Cannot be combined with `-WhatIf`.

```
Type:     SwitchParameter
Required: No
```

### -WhatIf

Shows that the format step would run without invoking the engine. The wrapper
gates the tool invocation behind `ShouldProcess`, so `-WhatIf` makes no changes
and does not launch the engine.

```
Type:     SwitchParameter
Required: No
```

---

## Return value

Returns a `PSCustomObject` with the following fields.

| Field         | Type      | Notes |
|---------------|-----------|-------|
| `StepName`    | String    | Always `'Format'` |
| `Success`     | Boolean   | `$true` when the tool exits with code 0 |
| `Duration`    | TimeSpan  | Wall-clock time for the step |
| `ExitCode`    | Int32     | Exit code from `delphi-format.ps1` |
| `Tool`        | String    | Always `'delphi-format.ps1'` |
| `Message`     | String    | `'Format completed'` / `'Check completed'` on success; `'Exit code N'` on failure |
| `ProjectFile` | (null)    | Not used by the format step; present for pipeline consistency |

`delphi-format.ps1` uses distinct exit codes: `0` clean/formatted, `1` check
mode found files needing formatting, `2` partial failure, `3` fatal error. A
non-zero exit sets `Success` to `$false`.

---

## JSON config equivalent

The format step is controlled by the `format` section in the JSON config file
used with `Get-DelphiCiConfig` or `Invoke-DelphiCi`, and by a `Format` action in
the pipeline.

```json
{
  "format": {
    "engine": "formatter",
    "enginePath": "",
    "engineConfigFile": "",
    "path": [],
    "includeFilePattern": [],
    "excludeDirectoryPattern": [],
    "encoding": "",
    "createBackups": false,
    "outputLevel": "detailed",
    "configFile": "",
    "check": false
  },
  "pipeline": [
    { "action": "Format", "engine": "radFormatter", "check": true }
  ]
}
```

`Invoke-DelphiFormat` itself does not read a config file -- it is a step command
that receives resolved values from the orchestration layer (`Invoke-DelphiCi`).

---

## Examples

### Format the current directory in place

```powershell
Invoke-DelphiFormat
```

### Explicit root and engine

```powershell
Invoke-DelphiFormat -FormatRoot .\source -FormatEngine radFormatter
```

### Audit-only mode (CI gate)

```powershell
Invoke-DelphiFormat -FormatRoot .\source -FormatCheck
```

Exit code 0 means every file is correctly formatted; exit code 1 means one or
more files need formatting.

### Format only specific files or folders

```powershell
Invoke-DelphiFormat -FormatRoot . -FormatPath 'source', 'tests\App.Tests.pas'
```

### Include extra file patterns and exclude a vendored tree

```powershell
Invoke-DelphiFormat -FormatRoot . -FormatIncludeFilePattern '*.dpk' -FormatExcludeDirectoryPattern 'vendor', 'thirdparty'
```

### Use an explicit delphi-format config file

```powershell
Invoke-DelphiFormat -FormatRoot . -FormatConfigFile C:\ci\delphi-format-ci.json
```

### Write backups before formatting

```powershell
Invoke-DelphiFormat -FormatRoot . -FormatCreateBackups
```

### Quiet output (exit code only)

```powershell
Invoke-DelphiFormat -FormatRoot . -FormatOutputLevel quiet
```

### Preview without invoking the engine

```powershell
Invoke-DelphiFormat -FormatRoot . -WhatIf
```

### Capture the result

```powershell
$fmt = Invoke-DelphiFormat -FormatRoot .\source -FormatCheck
if (-not $fmt.Success) {
    Write-Error "Formatting check failed with exit code $($fmt.ExitCode)"
}
```

### Result shape when called via Invoke-DelphiCi

`Invoke-DelphiCi -Steps Format` returns a result whose `Steps` array contains
one entry with the same shape as the object returned by `Invoke-DelphiFormat`
directly. The fields are identical.

---

## Notes

- `Invoke-DelphiFormat` delegates all formatting to `delphi-format.ps1` from the
  `source/bundled-tools/` folder. It does not modify files itself.
- `-FormatCheck` never writes to disk; it is the correct mode for a CI gate that
  should fail when source is unformatted.
- Passing `-WhatIf` skips the tool invocation entirely -- no files are examined
  or modified.
- The `Duration` field includes subprocess startup time for `pwsh`.
- `ProjectFile` is always `$null` for the format step. It is present so that
  step result objects returned by all steps share a consistent shape for
  pipeline consumers.
- The bundled `delphi-format.ps1` also searches for `delphi-format.json` and
  `delphi-format.local.json` in the root directory automatically. Use
  `-FormatConfigFile` to supply an additional explicit config (e.g. a CI-specific
  file stored outside the repository).
