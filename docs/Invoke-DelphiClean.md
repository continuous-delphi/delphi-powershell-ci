# Invoke-DelphiClean

Runs the bundled `delphi-clean.ps1` script against a Delphi project root and
returns a structured step result.

---

## Syntax

```powershell
Invoke-DelphiClean
    [-Root <String>]
    [-Level <String>]
    [-IncludeFiles <String[]>]
    [-ExcludeDirectories <String[]>]
    [-WhatIf]
    [<CommonParameters>]
```

---

## Parameters

### -Root

Absolute or relative path to the directory that `delphi-clean.ps1` should treat
as the repository root. Defaults to the current working directory.

```
Type:     String
Required: No
Default:  (Get-Location).Path
```

### -Level

Cleanup intensity level passed to `delphi-clean.ps1`.

| Value   | Effect |
|---------|--------|
| `basic`  | Removes common transient files (.dcu, .dcp, .dres, etc.). Safe, low risk. Default. |
| `standard` | Also removes build outputs and generated files. |
| `deep`  | Aggressive cleanup including user-local IDE state files. |

```
Type:     String
Required: No
Default:  basic
```

### -IncludeFiles

Additional file glob patterns passed to `delphi-clean.ps1` as
`-IncludeFilePattern`. Files matching these patterns are deleted regardless
of the active level. Useful for project-specific artifacts not covered by
the standard levels (e.g. `*.res`, `*.mab`).

```
Type:     String[]
Required: No
Default:  (empty -- no extra patterns)
```

### -ExcludeDirectories

Directory glob patterns passed to `delphi-clean.ps1` as `-ExcludeDirPattern`.
Directories whose names match any of these patterns are skipped entirely
during cleanup. Useful for protecting vendored or generated trees that should
not be touched (e.g. `vendor`, `assets`, `vendor*`).

```
Type:     String[]
Required: No
Default:  (empty -- no directories excluded)
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

The clean level is controlled by the `clean.level` field in the JSON config
file used with `Get-DelphiCiConfig` or `Invoke-DelphiCi`.

```json
{
  "clean": {
    "level": "build",
    "includeFiles": ["*.res", "*.mab"],
    "excludeDirectories": ["vendor", "assets"]
  }
}
```

`Invoke-DelphiClean` itself does not read a config file -- it is a step command
that receives resolved values from the orchestration layer.

---

## Examples

### Default run from the current directory

```powershell
Invoke-DelphiClean
```

### Explicit root and level

```powershell
Invoke-DelphiClean -Root .\source -Level build
```

### Include extra file patterns

```powershell
Invoke-DelphiClean -Root . -Level basic -IncludeFiles '*.res', '*.mab'
```

Deletes `.res` and `.mab` files in addition to the standard `basic` set.

### Exclude directories from cleanup

```powershell
Invoke-DelphiClean -Root . -Level build -ExcludeDirectories 'vendor', 'assets'
```

Skips any directory named `vendor` or `assets` when searching for files to remove.

### Preview what would be removed

```powershell
Invoke-DelphiClean -Root . -Level deep -WhatIf
```

### Capture the result

```powershell
$clean = Invoke-DelphiClean -Root . -Level basic
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
