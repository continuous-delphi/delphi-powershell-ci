# Invoke-DelphiCompress

Compresses files or a directory into a .zip archive as a CI step. Optionally
generates a SHA256 checksum sidecar file.

## Syntax

```powershell
Invoke-DelphiCompress
    -Source <string>
    -Destination <string>
    [-Overwrite <bool>]
    [-Checksum <bool>]
    [-WhatIf]
```

## Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `-Source` | string | (required) | File, directory, or glob pattern to compress. |
| `-Destination` | string | (required) | Output archive path (`.zip`). |
| `-Overwrite` | bool | `$true` | When `$true`, replaces an existing archive. When `$false`, fails if the archive already exists. |
| `-Checksum` | bool | `$false` | When `$true`, generates a `.sha256` sidecar file next to the archive. |
| `-WhatIf` | switch | | Shows what would happen without creating the archive. |

## Checksum Sidecar

When `-Checksum` is `$true`, a sidecar file is created at
`<archive>.sha256` (e.g., `release.zip.sha256`). It uses the standard
`sha256sum` format:

```text
a1b2c3d4e5f6...  release.zip
```

The checksum value is also returned in the result object's `Checksum`
property for programmatic use.

## Return Value

Returns a `PSCustomObject` with these fields:

| Field | Type | Description |
|---|---|---|
| `StepName` | string | Always `'Compress'` |
| `Success` | bool | `$true` if the archive was created successfully |
| `ExitCode` | int | `0` on success, `1` on failure |
| `Duration` | TimeSpan | Total time for this step |
| `Tool` | string | Always `'compress'` |
| `Message` | string | Summary (e.g., `Archive created (2048 bytes)`) |
| `Source` | string | The source path that was compressed |
| `Destination` | string | Path to the created archive |
| `ArchiveSize` | long | Size of the archive in bytes |
| `Checksum` | string | SHA256 hash of the archive (null if checksum was not requested) |

## Usage Examples

### Compress a directory into a zip

```powershell
Invoke-DelphiCompress -Source .\dist -Destination .\release\app.zip
```

### Compress with checksum

```powershell
Invoke-DelphiCompress -Source .\dist -Destination .\release\app.zip -Checksum $true
```

### Compress specific files via glob

```powershell
Invoke-DelphiCompress -Source .\dist\*.exe -Destination .\release\binaries.zip
```

### Pipeline 'Compress' action in Invoke-DelphiCi config file

```json
{
  "pipeline": [
    { "action": "Compress",
      "jobs": [
        { "name": "Package release",
          "source": "dist/binaries",
          "destination": "dist/release.zip",
          "checksum": true }
      ]
    }
  ]
}
```

## JSON `compress` Key

Default `Compress` action options can be set by the `compress` key in `defaults` 

```json
{
  "defaults": {
    "compress": {
      "overwrite": true,
      "checksum": false
    }
  }
}
```

Each job inherits defaults through the three-level merge
(defaults > action-level > job-level) and can override them at any level.

## Typical Pipeline Usage

Copy and Compress are commonly used together after Build and Run to
collect outputs and package them for release:

```json
{
  "pipeline": [
    { "action": "Clean" },
    { "action": "Build", "jobs": [
      { "projectFile": "source/App.dproj",
        "platform": ["Win32", "Win64"], "configuration": "Release" }
    ]},
    { "action": "Run", "jobs": [
      { "execute": "test/Win32/Release/App.Tests.exe" }
    ]},
    { "action": "Copy", "jobs": [
      { "source": "source/*/Release/*.exe",
        "destination": "dist/", "flatten": true, "checksum": true }
    ]},
    { "action": "Compress", "jobs": [
      { "source": "dist/",
        "destination": "release/App-v1.0.0.zip", "checksum": true }
    ]}
  ]
}
```

## Notes

- Uses PowerShell's built-in `Compress-Archive` cmdlet. No external tools
  required.
- `Compress-Archive` does not support in-place overwrite. When `-Overwrite`
  is `$true`, the existing archive is removed before creating the new one.
- When the source does not exist or matches no files, the step fails with
  a clear message.
- The destination's parent directory is created automatically if it does
  not exist.
- This is a private module function (not a bundled tool). No subprocess
  overhead -- compression uses PowerShell cmdlets directly.
