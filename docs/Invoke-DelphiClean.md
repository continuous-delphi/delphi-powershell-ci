# Invoke-DelphiClean

Runs the bundled `delphi-clean.ps1` script against a Delphi project root and
returns a structured step result.

---

## Syntax

```powershell
Invoke-DelphiClean
    [-CleanRoot <String>]
    [-CleanLevel <String>]
    [-CleanOutputLevel <String>]
    [-CleanIncludeFilePattern <String[]>]
    [-CleanExcludeDirectoryPattern <String[]>]
    [-CleanConfigFile <String>]
    [-CleanRecycleBin]
    [-CleanCheck]
    [-WhatIf]
    [<CommonParameters>]
```

---

## Parameters

### -CleanRoot

Absolute or relative path to the directory that `delphi-clean.ps1` should treat
as the repository root. Defaults to the current working directory.

```
Type:     String
Required: No
Default:  (Get-Location).Path
```

### -CleanLevel

Cleanup intensity level passed to `delphi-clean.ps1`.

| Value      | Effect |
|------------|--------|
| `basic`    | Removes common transient files (.dcu, .identcache, `__history`, etc.). Safe, low risk. Default. |
| `standard` | Also removes build outputs and generated files (platform output folders, .exe, .bpl, etc.). |
| `deep`     | Aggressive cleanup including user-local IDE state files (.~*, FireDAC cache, etc.). |

```
Type:     String
Required: No
Default:  basic
```

### -CleanOutputLevel

Controls the amount of plain-text output produced by `delphi-clean.ps1`.

| Value      | Effect |
|------------|--------|
| `detailed` | Header, per-item lines, and summary. Default. |
| `summary`  | Header and summary only; per-item lines are suppressed. |
| `quiet`    | No output at all; use the exit code as the signal. |

```
Type:     String
Accepted: detailed, summary, quiet
Required: No
Default:  detailed
```

### -CleanRecycleBin

When set, sends removed items to the platform recycle bin / trash instead of
deleting them permanently. On Windows, uses the VisualBasic FileSystem API.
On macOS, uses the user trash folder. Not supported on Linux.

```
Type:     SwitchParameter
Required: No
```

### -CleanCheck

Runs `delphi-clean.ps1` in audit-only mode. Scans for artifacts but never
deletes anything. Returns a failing exit code (1) when artifacts are present,
or success (0) when the workspace is clean. Useful for verifying a clean
workspace in CI. Cannot be combined with `-WhatIf`.

```
Type:     SwitchParameter
Required: No
```

### -CleanIncludeFilePattern

Additional file glob patterns passed to `delphi-clean.ps1` as
`-IncludeFilePattern`. Files matching these patterns are deleted regardless
of the active level. Useful for project-specific artifacts not covered by
the standard levels (e.g. `*.res`, `*.mab`).

```
Type:     String[]
Required: No
Default:  (empty -- no extra patterns)
```

### -CleanExcludeDirectoryPattern

Directory glob patterns passed to `delphi-clean.ps1` as `-ExcludeDirectoryPattern`.
Directories whose names match any of these patterns are skipped entirely
during cleanup. Useful for protecting vendored or generated trees that should
not be touched (e.g. `vendor`, `assets`, `vendor*`).

```
Type:     String[]
Required: No
Default:  (empty -- no directories excluded)
```

### -CleanConfigFile

Path to an explicit `delphi-clean` JSON configuration file. Forwarded to the
bundled tool as `-ConfigFile`. Loaded at higher priority than a project-level
`delphi-clean.json` found in the root directory, but lower priority than the
CLI parameters above. Useful in CI pipelines where the config lives outside
the repository tree.

```
Type:     String
Required: No
Default:  (empty -- no explicit config file)
```

### -WhatIf

Shows what the clean step would remove without deleting anything. Passes
`-WhatIf` through to the bundled tool.

```
Type:     SwitchParameter
Required: No
```

---

## Return value

Returns a `PSCustomObject` with the following fields.

| Field        | Type      | Notes |
|-------------|-----------|-------|
| `StepName`  | String    | Always `'Clean'` |
| `Success`   | Boolean   | `$true` when the tool exits with code 0 |
| `Duration`  | TimeSpan  | Wall-clock time for the step |
| `ExitCode`  | Int32     | Exit code from `delphi-clean.ps1` |
| `Tool`      | String    | Always `'delphi-clean.ps1'` |
| `Message`   | String    | `'Clean completed'` on success; `'Exit code N'` on failure |
| `ProjectFile` | (null)  | Not used by the clean step; present for pipeline consistency |

---

## JSON config equivalent

The clean step is controlled by the `clean` section in the JSON config
file used with `Get-DelphiCiConfig` or `Invoke-DelphiCi`.

```json
{
  "clean": {
    "level": "basic",
    "outputLevel": "detailed",
    "includeFilePattern": ["*.res", "*.mab"],
    "excludeDirectoryPattern": ["vendor", "assets"],
    "configFile": "",
    "recycleBin": false,
    "check": false
  }
}
```

`Invoke-DelphiClean` itself does not read a config file -- it is a step command
that receives resolved values from the orchestration layer (`Invoke-DelphiCi`).

---

## Examples

### Default run from the current directory

```powershell
Invoke-DelphiClean
```

### Explicit root and level

```powershell
Invoke-DelphiClean -CleanRoot .\source -CleanLevel standard
```

### Include extra file patterns

```powershell
Invoke-DelphiClean -CleanRoot . -CleanLevel basic -CleanIncludeFilePattern '*.res', '*.mab'
```

Deletes `.res` and `.mab` files in addition to the standard `basic` set.

### Exclude directories from cleanup

```powershell
Invoke-DelphiClean -CleanRoot . -CleanLevel standard -CleanExcludeDirectoryPattern 'vendor', 'assets'
```

Skips any directory named `vendor` or `assets` when searching for files to remove.

### Use an explicit delphi-clean config file

```powershell
Invoke-DelphiClean -CleanRoot . -CleanLevel standard -CleanConfigFile C:\ci\delphi-clean-ci.json
```

### Audit-only mode (check for stale artifacts)

```powershell
Invoke-DelphiClean -CleanRoot . -CleanLevel standard -CleanCheck
```

Exit code 0 means no artifacts were found; exit code 1 means the workspace
is dirty.

### Send removed files to the recycle bin

```powershell
Invoke-DelphiClean -CleanRoot . -CleanLevel standard -CleanRecycleBin
```

### Quiet output (exit code only)

```powershell
Invoke-DelphiClean -CleanRoot . -CleanOutputLevel quiet
```

### Preview what would be removed

```powershell
Invoke-DelphiClean -CleanRoot . -CleanLevel deep -WhatIf
```

### Capture the result

```powershell
$clean = Invoke-DelphiClean -CleanRoot . -CleanLevel basic
if (-not $clean.Success) {
    Write-Error "Clean failed with exit code $($clean.ExitCode)"
}
```

### Result shape when called via Invoke-DelphiCi

`Invoke-DelphiCi -Steps Clean` returns a result whose `Steps` array contains
one entry with the same shape as the object returned by `Invoke-DelphiClean`
directly. The fields are identical.

---

## Notes

- `Invoke-DelphiClean` delegates all file removal to `delphi-clean.ps1` from
  the `source/bundled-tools/` folder. It does not delete anything itself.
- The `basic` level is safe to run repeatedly without risk to source files.
- Passing `-WhatIf` prints a `What if:` message and skips the tool invocation
  entirely. No files are examined or removed.
- The `Duration` field includes subprocess startup time for `pwsh`.
- `ProjectFile` is always `$null` for the clean step. It is present so that
  step result objects returned by all steps share a consistent shape for
  pipeline consumers.
- The bundled `delphi-clean.ps1` also searches for `delphi-clean.json` and
  `delphi-clean.local.json` in the root directory automatically. Use
  `-CleanConfigFile` to supply an additional explicit config (e.g. a CI-specific
  file stored outside the repository).
