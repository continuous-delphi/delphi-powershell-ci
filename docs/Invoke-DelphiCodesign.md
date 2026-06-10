# Invoke-DelphiCodesign

Signs or verifies Authenticode signatures on executables and libraries
as a CI step using a pluggable signing engine. Returns a structured
step result with action outcome, file counts, and engine details.

## Syntax

```powershell
Invoke-DelphiCodesign
    -Action <string>
    [-Files <string[]>]
    [-FilePath <string>]
    [-CodesignEngine <string>]
    [-CodesignSignToolPath <string>]
    [-CodesignDlibPath <string>]
    [-CodesignMetadataPath <string>]
    [-CodesignEnvFile <string>]
    [-WhatIf]
```

## Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `-Action` | string | | **Required.** `Sign` or `Verify`. |
| `-Files` | string[] | `@()` | Files to sign. Required when `-Action Sign`. |
| `-FilePath` | string | | File to verify. Required when `-Action Verify`. |
| `-CodesignEngine` | string | `AzureTrustedSigning` | Signing engine to use. |
| `-CodesignSignToolPath` | string | auto-detect | Explicit path to `signtool.exe`. |
| `-CodesignDlibPath` | string | auto-detect | Path to `Azure.CodeSigning.Dlib.dll`. |
| `-CodesignMetadataPath` | string | auto-detect | Path to `metadata.json` with Azure endpoint and certificate profile. |
| `-CodesignEnvFile` | string | | Path to `.env` file with Azure credentials. |
| `-WhatIf` | switch | | Shows what would happen without signing or verifying. |

## Supported Engines

| Engine | Description |
|--------|-------------|
| `AzureTrustedSigning` | Microsoft Azure Trusted Signing via `signtool.exe` with SHA256 digest and RFC 3161 timestamping |

Future engines may be added 

## Prerequisites (AzureTrustedSigning)

- `signtool.exe` from the Windows SDK
- `Azure.CodeSigning.Dlib.dll` -- install via
  `winget install -e --id Microsoft.Azure.TrustedSigningClientTools`
- `metadata.json` with endpoint, account name, and certificate profile
- Azure credentials: `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`,
  `AZURE_CLIENT_SECRET` (via environment or `-CodesignEnvFile`)

See the standalone tool's
[machine setup guide](https://github.com/continuous-delphi/delphi-codesign-azure/blob/main/docs/machine_setup.md)
for first-time installation.

## Return Value

Returns a `PSCustomObject` with these fields:

| Field | Type | Description |
|---|---|---|
| `StepName` | string | `'CodesignSign'` or `'CodesignVerify'` |
| `Success` | bool | `$true` if all operations succeeded |
| `ExitCode` | int | Exit code from the bundled tool |
| `Duration` | TimeSpan | Total time for this step |
| `Tool` | string | Always `'delphi-codesign-azure.ps1'` |
| `Message` | string | Summary or error description |
| `Action` | string | `'Sign'` or `'Verify'` |
| `Engine` | string | Engine used (e.g. `'AzureTrustedSigning'`) |
| `Signed` | int | Number of files successfully signed (Sign action) |
| `Failed` | int | Number of files that failed (Sign action) |

## Usage Examples

### Sign a single file

```powershell
Invoke-DelphiCodesign -Action Sign `
    -Files .\Win32\Release\MyApp.exe `
    -CodesignEnvFile .env
```

### Sign multiple files

```powershell
Invoke-DelphiCodesign -Action Sign `
    -Files .\Win32\Release\MyApp.exe, .\Win32\Release\MyLib.bpl `
    -CodesignEnvFile .env `
    -CodesignMetadataPath tools\codesign\metadata.json
```

### Verify a signed file

```powershell
Invoke-DelphiCodesign -Action Verify `
    -FilePath .\Win32\Release\MyApp.exe
```

### Pipeline Codesign action in Invoke-DelphiCi config file

```json
{
  "defaults": {
    "codesign": {
      "engine": "AzureTrustedSigning",
      "envFile": ".env",
      "metadataPath": "tools/codesign/metadata.json"
    }
  },
  "pipeline": [
    { "action": "Build", "jobs": [
      { "projectFile": "MyApp.dproj", "configuration": "Release" }
    ]},
    { "action": "Codesign", "jobs": [
      { "name": "Sign release binaries",
        "action": "Sign",
        "files": ["Win32/Release/MyApp.exe", "Win32/Release/MyLib.bpl"] },
      { "name": "Verify signatures",
        "action": "Verify",
        "filePath": "Win32/Release/MyApp.exe" }
    ]}
  ]
}
```

Each job inherits defaults through the three-level merge
(defaults > action-level > job-level) and can override them at any level.

## Notes

- The Codesign action typically runs after Build in the pipeline, signing
  the compiled binaries before Copy or Compress steps.
- Sign and Verify are separate jobs, not combined. A typical pattern is
  to sign all files first, then add a verify job as a sanity check.
- The bundled tool always uses `-Format json` internally so the wrapper
  can parse structured results.
- The standalone tool is maintained at
  [github.com/continuous-delphi/delphi-codesign-azure](https://github.com/continuous-delphi/delphi-codesign-azure).