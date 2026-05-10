# Invoke-DelphiCopy

Copies files matching a glob pattern to a destination directory as a CI step.
Supports flattening directory structure and generating SHA256 checksum manifests.

## Syntax

```powershell
Invoke-DelphiCopy
    -Source <string>
    -Destination <string>
    [-Flatten <bool>]
    [-Overwrite <bool>]
    [-CreateDestination <bool>]
    [-Checksum <bool>]
    [-WhatIf]
```

## Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `-Source` | string | (required) | Glob pattern for source files (e.g., `projects/*/Release/*.exe`). |
| `-Destination` | string | (required) | Target directory path. |
| `-Flatten` | bool | `$false` | When `$true`, copies all matched files flat into the destination without preserving subdirectory structure. |
| `-Overwrite` | bool | `$true` | When `$true`, overwrites existing files at the destination. When `$false`, fails if a destination file already exists. |
| `-CreateDestination` | bool | `$true` | When `$true`, creates the destination directory if it does not exist. When `$false`, fails if the directory is missing. |
| `-Checksum` | bool | `$false` | When `$true`, generates a `checksums.sha256` file in the destination directory with SHA256 hashes for every copied file. |
| `-WhatIf` | switch | | Shows what would happen without copying any files. |

## Glob Pattern

The source parameter supports PowerShell wildcard patterns:

- `source/*.exe` -- all .exe files in `source/`
- `projects/*/Release/*.exe` -- .exe files across multiple project output dirs
- `source/**/*.dll` -- .dll files at any depth (with `-Recurse`)

Files in subdirectories matching the pattern are included automatically.

## Flatten Mode

When `-Flatten` is `$false` (default), the relative directory structure from
the glob base is preserved under the destination:

```text
source/ProjectA/Release/App.exe    ->  dist/ProjectA/Release/App.exe
source/ProjectB/Release/Tool.exe   ->  dist/ProjectB/Release/Tool.exe
```

When `-Flatten` is `$true`, all matched files are copied directly into the
destination without subdirectories:

```text
source/ProjectA/Release/App.exe    ->  dist/App.exe
source/ProjectB/Release/Tool.exe   ->  dist/Tool.exe
```

This is especially useful for collecting outputs from matrix-expanded builds
into a single release directory.

## Checksum Manifest

When `-Checksum` is `$true`, a `checksums.sha256` file is created in the
destination directory. It uses the standard `sha256sum` format:

```text
a1b2c3d4...  App.exe
e5f6a7b8...  Tool.exe
```

This file can be verified on any platform with `sha256sum -c checksums.sha256`.

## Return Value

Returns a `PSCustomObject` with these fields:

| Field | Type | Description |
|---|---|---|
| `StepName` | string | Always `'Copy'` |
| `Success` | bool | `$true` if all files were copied successfully |
| `ExitCode` | int | `0` on success, `1` on failure |
| `Duration` | TimeSpan | Total time for this step |
| `Tool` | string | Always `'copy'` |
| `Message` | string | Summary (e.g., `Copied 3 file(s)`) |
| `Source` | string | The source pattern that was used |
| `Destination` | string | The destination directory |
| `FileCount` | int | Number of files copied |
| `BytesCopied` | long | Total bytes copied |

## Usage Examples

### Collect build outputs into a staging directory

```powershell
Invoke-DelphiCopy -Source .\source\*\Release\*.exe -Destination .\dist -Flatten $true
```

### Preserve directory structure

```powershell
Invoke-DelphiCopy -Source .\source\*\Release\* -Destination .\dist
```

### Copy with checksums

```powershell
Invoke-DelphiCopy -Source .\source\*\Release\*.exe -Destination .\dist `
    -Flatten $true -Checksum $true
```

### Pipeline `Copy` action in Invoke-DelphiCi config file

```json
{
  "pipeline": [
    { "action": "Copy",
      "jobs": [
        { "name": "Collect binaries",
          "source": "source/*/Release/*.exe",
          "destination": "dist/binaries",
          "flatten": true,
          "checksum": true }
      ]
    }
  ]
}
```

## Default `Copy` action options can be set by the `copy` key in `defaults` 

Copy options are controlled by the `copy` key in `defaults` and by Copy
action entries in the pipeline:

```json
{
  "defaults": {
    "copy": {
      "flatten": false,
      "overwrite": true,
      "createDestination": true,
      "checksum": false
    }
  }
}
```

Each job inherits defaults through the three-level merge
(defaults > action-level > job-level) and can override them at any level.

## Notes

- Source paths in the pipeline config are resolved relative to the pipeline
  root, same as `projectFile` for Build jobs.
- When the source pattern matches zero files, the step fails with a clear
  message.
- When `-Flatten` is `$true` and `-Overwrite` is `$false`, filename collisions
  across different source directories cause the step to fail.
- This is a private module function (not a bundled tool). No subprocess
  overhead -- file operations use PowerShell cmdlets directly.
