# Invoke-DelphiIncVer

Increments a version number in an RC, DProj, or text file as a CI step.

## Syntax

```powershell
Invoke-DelphiIncVer
    -File <string>
    [-IncverTarget <string>]
    [-IncverStyle <string>]
    [-IncverPart <string>]
    [-IncverPattern <string>]
    [-WhatIf]
```

## Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `-File` | string | (required) | Path to the file containing the version to increment. |
| `-IncverTarget` | string | auto-detect | File type: `RC`, `DProj`, or `Text`. Auto-detected from extension when empty. |
| `-IncverStyle` | string | auto-detect | Version format: `WinVer` or `SemVer`. Auto-detected from target when empty. |
| `-IncverPart` | string | last component | Which component to bump: `major`, `minor`, `patch`, `build`, or `pre-release`. |
| `-IncverPattern` | string | | Regex with capture group for Text targets. Required for Text, ignored for RC/DProj. |
| `-WhatIf` | switch | | Shows what would happen without modifying the file. |

## Auto-detection

| Extension | Target | Default Style |
|-----------|--------|---------------|
| `.rc`     | RC     | WinVer        |
| `.dproj`  | DProj  | WinVer        |
| anything else | Text | SemVer     |

## Target Behavior

### RC

Updates all four VERSIONINFO locations: `FILEVERSION`, `PRODUCTVERSION`
(comma-separated) and `VALUE "FileVersion"`, `VALUE "ProductVersion"`
(dot-separated strings).

### DProj

Updates `FileVersion=` inside every `VerInfo_Keys` element across all
`PropertyGroup` sections. `ProductVersion` and discrete elements
(`VerInfo_MajorVer`, etc.) are left unchanged.

### Text

Uses the `-IncverPattern` regex to locate and replace the version string.
The pattern must contain a capture group around the version portion.

## Default Bump Behavior

When `-IncverPart` is omitted, the last component of the existing version
is incremented regardless of width:

| Source | Result |
|--------|--------|
| `1.0.0.4` | `1.0.0.5` |
| `9.4.0` | `9.4.1` |
| `1.3` | `1.4` |

Bumping a component zeros everything to its right:

```text
1.2.3.4  -IncverPart minor  ->  1.3.0.0
```

## Return Value

Returns a `PSCustomObject` with these fields:

| Field | Type | Description |
|---|---|---|
| `StepName` | string | Always `'IncVer'` |
| `Success` | bool | `$true` if the version was incremented successfully |
| `ExitCode` | int | Exit code from the bundled tool |
| `Duration` | TimeSpan | Total time for this step |
| `Tool` | string | Always `'delphi-incver.ps1'` |
| `Message` | string | Version transition on success; exit code on failure |
| `File` | string | Path to the file that was modified |
| `OldVersion` | string | Version before increment (null on failure) |
| `NewVersion` | string | Version after increment (null on failure) |

## Usage Examples

### Bump an RC file (default: last component)

```powershell
Invoke-DelphiIncVer -File .\source\versioninfo.rc
```

### Bump the minor version in a DProj

```powershell
Invoke-DelphiIncVer -File .\source\MyApp.dproj -IncverPart minor
```

### Bump a SemVer version in a PowerShell script

```powershell
Invoke-DelphiIncVer -File .\source\mytool.ps1 `
    -IncverPattern '\$script:ToolVersion\s*=\s*''([^'']+)'''
```

### Via Invoke-DelphiCi config file

```json
{
  "pipeline": [
    { "action": "IncVer",
      "jobs": [
        { "name": "Bump RC version",
          "file": "source/versioninfo.rc" },
        { "name": "Bump DProj version",
          "file": "source/MyApp.dproj",
          "part": "build" }
      ]
    }
  ]
}
```

## JSON Config Equivalent

IncVer options are controlled by the `incver` key in `defaults` and by
IncVer action entries in the pipeline:

```json
{
  "defaults": {
    "incver": {
      "target": "",
      "style": "",
      "part": "",
      "pattern": "",
      "dateformat": "yyyy.mm.dd"
    }
  }
}
```

## Notes

- RC and DProj targets always use WinVer style. Combining them with SemVer
  is an error.
- The `-IncverPattern` is required for Text targets and ignored for RC/DProj.
- When using `-IncverPattern` on the command line, use single quotes to prevent
  PowerShell variable interpolation. Embed literal single quotes by doubling
  them (`''`).
- The `pre-release` part is only valid with SemVer style.
- The tool never adds or removes version components from the source value.
