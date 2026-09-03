# delphi-powershell-ci

![delphi-powershell-ci logo](https://continuous-delphi.github.io/assets/logos/delphi-powershell-ci-480x270.png)

[![Delphi](https://img.shields.io/badge/delphi-red)](https://www.embarcadero.com/products/delphi)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/continuous-delphi/delphi-powershell-ci)
[![Continuous Delphi](https://img.shields.io/badge/org-continuous--delphi-red)](https://github.com/continuous-delphi)

Bundled PowerShell CI orchestration layer for Delphi projects. Packages
compatible versions of the standalone Continuous-Delphi tools and exposes
a single opinionated command surface for local and CI use.

---

## What this repo is

`delphi-powershell-ci` wraps and orchestrates these standalone tools:

| Tool | Role |
|---|---|
| [delphi-compiler-versions](https://github.com/continuous-delphi/delphi-compiler-versions) | Canonical version mapping | 
| [delphi-inspect](https://github.com/continuous-delphi/delphi-inspect) | Detects installed Delphi toolchains |
| [delphi-clean](https://github.com/continuous-delphi/delphi-clean) | Removes Delphi build artifacts |
| [delphi-msbuild](https://github.com/continuous-delphi/delphi-msbuild) | Drives MSBuild for Delphi projects |
| [delphi-dccbuild](https://github.com/continuous-delphi/delphi-dccbuild) | Drives DCC builds for Delphi projects |
| [delphi-incver](https://github.com/continuous-delphi/delphi-incver) | Increments version numbers in RC and text files |
| [delphi-coverage](https://github.com/continuous-delphi/delphi-coverage) | Code coverage orchestrator for Delphi projects |
| [delphi-callgraph](https://github.com/continuous-delphi/delphi-callgraph) | Call graph and dependency graph analyzer |
| [delphi-format](https://github.com/continuous-delphi/delphi-format) | Formats Delphi source with a pluggable engine (formatter.exe / radFormatter) |

The standalone tools remain individually usable and separately versioned.
This repo packages compatible versions together and provides a simpler
public interface for day-to-day CI workflows.

Additional functionality includes `Invoke-DelphiRun` for executing DUnitX
test projects or other utilities as needed.


---

## v1 scope

v1 supports **Clean**, **Format**, **IncVer**, **Build**, **Run**, **Coverage**, **CallGraph**, **Copy**, **Compress**, and **Codesign** steps.

---

## Requirements

Runs on the widely available Windows PowerShell 5.1 (`powershell.exe`)
and the newer PowerShell 7+ (`pwsh`).

Note: the test suite requires `pwsh`.

No additional modules are required at runtime. The bundled tools are
included in this repository under `source/bundled-tools/`.

The module detects which executable is available at load time, preferring
`pwsh` when both are present.

---

## Quick start

Import the module, then call `Invoke-DelphiCi`.

```powershell
Import-Module .\source\Delphi.PowerShell.CI.psd1
```

### Example project

Clean + Build ConsoleProject:

```powershell
Invoke-DelphiCi -ProjectFile .\examples\ConsoleProjectGroup\Source\ConsoleProject.dproj
```

### Clean only (no project file needed)

```powershell
Invoke-DelphiCi -Steps Clean -Root C:\MyRepo
```

### Build only

```powershell
Invoke-DelphiCi -Steps Build -ProjectFile .\source\MyApp.dproj
```

### Format check as a CI gate

```powershell
Invoke-DelphiCi -Steps Format -FormatCheck $true -Root C:\MyRepo
```

Runs the formatter in audit-only mode and fails the run when any source file
needs formatting. Drop `-FormatCheck` to format in place. Select the engine with
`-FormatEngine formatter|radFormatter`.

### Pin the Delphi version

```powershell
Invoke-DelphiCi -ProjectFile .\source\MyApp.dproj -Toolchain VER370
```

`-Toolchain Latest` (the default) detects the highest ready installation.
Any other value is passed to `delphi-inspect` as a version name or
compiler identifier (e.g. `VER370`, `Delphi 13 Florence`).

### Release build

```powershell
Invoke-DelphiCi -ProjectFile .\source\MyApp.dproj `
    -Configuration Release -Platform Win64
```

### Config-file-driven run

```powershell
Invoke-DelphiCi -ConfigFile .\delphi-ci.json
```

See `Examples\delphi-ci.json` for a fully annotated config file.

### Version information

```powershell
Invoke-DelphiCi -VersionInfo
```

Displays the module version and the version of each bundled tool.

---

## Example use as a module function (scripted use)

Import the module and call `Invoke-DelphiCi` directly. The function always
returns a structured result object; your script decides what to do with it:

```powershell
Import-Module .\source\Delphi.PowerShell.CI.psd1

$run = Invoke-DelphiCi -ProjectFile .\source\MyApp.dproj
if (-not $run.Success) { exit 1 }
```

---

## Configuration

### Precedence (highest to lowest)

1. Job-level properties in the pipeline
2. Action-level properties in the pipeline
3. CLI parameters (override defaults)
4. JSON config file `defaults` section
5. Built-in defaults

CLI parameters override the defaults layer. Action-level and job-level
properties in the pipeline config sit above CLI overrides for that
specific entry.

### Config file format (pipeline)

The config file defines an ordered **pipeline** of actions. A `defaults`
section provides base values keyed by action type. Each pipeline entry can
override defaults at the action level, and each job can override further.

Configuration merges through three levels per job:

    defaults.{action} > action-level properties > job-level properties

- **Scalars** override (last writer wins).
- **Arrays** append (child values concatenated after parent).
- **`key!` suffix** forces array replacement instead of append.

Build jobs support **matrix expansion**: `platform` and `configuration` can
be string or array, producing a cross product of builds.

```json
{
  "root": ".",
  "defaults": {
    "clean": { "level": "standard" },
    "build": {
      "engine": "MSBuild",
      "toolchain": { "version": "Latest" },
      "platform": "Win64",
      "configuration": "Release",
      "verbosity": "minimal"
    },
    "run": { "timeoutSeconds": 10 },
    "incver": { "target": "", "style": "", "part": "" },
    "callgraph": {
      "engine": "radCallGraph",
      "formats": ["json"],
      "deterministic": true
    }
  },
  "pipeline": [
    { "action": "Clean", "level": "deep" },
    { "action": "Format", "engine": "radFormatter", "check": true },
    { "action": "IncVer",
      "jobs": [
        { "name": "Bump RC version",
          "file": "source/versioninfo.rc" }
      ]
    },
    { "action": "Build",
      "jobs": [
        { "name": "Main App",
          "projectFile": "source/MyApp.dproj" },
        { "name": "Test project",
          "projectFile": "tests/MyApp.Tests.dproj",
          "platform": ["Win32", "Win64"],
          "configuration": ["Debug", "Release"],
          "defines": ["CI"] }
      ]
    },
    { "action": "Run",
      "jobs": [
        { "name": "Tests Win32 Debug",
          "execute": "tests/Win32/Debug/MyApp.Tests.exe" },
        { "name": "Tests Win64 Release",
          "execute": "tests/Win64/Release/MyApp.Tests.exe" }
      ]
    }
  ]
}
```

`includePath`, `namespace`, and `noConfig` are DCCBuild-only. When `engine` is
`MSBuild`, the build step rejects those fields with a clear error; configure
equivalent settings in the project's MSBuild property groups instead. `noConfig`
skips loading the toolchain's `dcc32.cfg` (dcc32 `--no-config`) -- use it when
that cfg carries actively wrong `-U`/`-I` paths or options.

When `-ConfigFile` is used, the JSON file must define a `pipeline` array.
Without a config file, `Invoke-DelphiCi` generates a pipeline from `-Steps`
or the default `Clean, Build` steps. Absent action and job fields fall back
to built-in defaults and the `defaults` section.

`root` is resolved relative to the config file's directory when it is a
relative path or `.`.

### JSON Schema

For VS Code completion and validation, add a `$schema` property to your
config file:

```json
{
  "$schema": "./schemas/delphi-ci.schema.json",
  "root": ".",
  "pipeline": []
}
```

The repo-local schema is available at `schemas/delphi-ci.schema.json`.

### Clean levels

| Level | What is removed |
|---|---|
| `basic` | Compiler caches, IDE state (`.dcu`, `.identcache`, `__history`, etc.) |
| `standard` | Everything in `basic`, plus build outputs (`.exe`, `.dll`, `.bpl`, platform output folders, etc.) |
| `deep` | Everything in `standard`, plus user-local IDE files (`.~*`, FireDAC project cache, etc.) |

Default level is `basic`.

---

## Step commands

The step commands can also be called directly.

```powershell
# Clean only -- basic level against the current directory
Invoke-DelphiClean

# Clean with standard level
Invoke-DelphiClean -CleanLevel standard -CleanRoot .\source

# Format source in place with the default engine (formatter.exe)
Invoke-DelphiFormat -FormatRoot .\source

# CI gate -- audit only, non-zero exit when any file needs formatting
Invoke-DelphiFormat -FormatRoot .\source -FormatEngine radFormatter -FormatCheck

# Build only -- latest Delphi, Win32 Debug
Invoke-DelphiBuild -ProjectFile .\source\MyApp.dproj

# Build with explicit options
Invoke-DelphiBuild -ProjectFile .\source\MyApp.dproj `
    -Platform Win64 -Configuration Release -Toolchain VER370

# Increment a version number in an RC file (bumps last component)
Invoke-DelphiIncVer -File .\source\versioninfo.rc

# Increment a SemVer version in a PowerShell script
Invoke-DelphiIncVer -File .\source\mytool.ps1 `
    -IncverPattern '\$script:ToolVersion\s*=\s*''([^'']+)'''

# Run a pre-built DUnitX test executable
Invoke-DelphiRun -Execute .\tests\Win32\Debug\MyApp.Tests.exe

# Run code coverage analysis with threshold
Invoke-DelphiCoverage -Execute .\test\Win32\Debug\MyApp.Tests.exe `
    -MapFile .\test\Win32\Debug\MyApp.Tests.map `
    -CoverageSourceDir .\source -CoverageThreshold 60

# Generate a call graph with radCallGraph
# Deterministic output is enabled by default; use -CallGraphDeterministic $false to keep timestamps
Invoke-DelphiCallGraph -CallGraphPath .\source `
    -CallGraphFormats json,dot,txt `
    -CallGraphOutputDir .\artifacts\callgraph

# Copy build outputs into a staging directory (flatten matrix outputs)
Invoke-DelphiCopy -Source .\source\*\Release\*.exe -Destination .\dist -Flatten $true

# Copy with SHA256 checksum manifest
Invoke-DelphiCopy -Source .\source\*\Release\*.exe -Destination .\dist `
    -Flatten $true -Checksum $true

# Compress a directory into a release archive with checksum sidecar
Invoke-DelphiCompress -Source .\dist -Destination .\release\app.zip -Checksum $true
```

---

## Capturing results

`Invoke-DelphiCi` always returns a structured result object.

```powershell
$run = Invoke-DelphiCi -ProjectFile .\source\MyApp.dproj

if (-not $run.Success) {
    $failed = $run.Steps | Where-Object { -not $_.Success }
    Write-Error "Failed steps: $($failed.StepName -join ', ')"
}

Write-Host "Total time: $($run.Duration.TotalSeconds.ToString('F2'))s"
```

### CI wrapper scripts

Because the result is always returned, a CI wrapper script can map it to
a process exit code directly:

```powershell
$run = Invoke-DelphiCi -ProjectFile .\source\MyApp.dproj
exit [int](-not $run.Success)
```

Or use the included wrapper, which does this automatically:

```powershell
.\tools\delphi-ci.ps1 -ProjectFile .\source\MyApp.dproj
```

The wrapper exposes shorthand parameters for the common steps -- Clean, Build
(including `-ToolchainRootDir` and `-NoConfig`), Run, and Format. The data-heavy
actions (IncVer, Copy, Compress, Coverage, CallGraph, Codesign) are intentionally
**not** exposed as wrapper shorthands; drive them through a pipeline config with
`-ConfigFile .\delphi-ci.json`. A format-check gate that fails the build when
source is unformatted is a one-liner:

```powershell
.\tools\delphi-ci.ps1 -Steps Format -FormatCheck $true -Root C:\MyRepo
```

Result shape:

| Field | Type | Notes |
|---|---|---|
| `Success` | Boolean | `$true` when every job succeeded |
| `Duration` | TimeSpan | Wall-clock time for the run |
| `Steps` | Object[] | One result per job that ran |

Clean and Format step results have `StepName`, `Success`, `Duration`,
`ExitCode`, `Tool`, and `Message`. Build results add `ProjectFile`, `Warnings`,
`Errors`, `ExeOutputDir`, and `Output`. IncVer results add `File`,
`OldVersion`, and `NewVersion`. Run results have `Execute` instead of
`ProjectFile`. Coverage results add `Execute`, `CoveragePercent`,
`LinesCovered`, `LinesTotal`, `ThresholdMet`, `OutputDir`, and `Badge`.
CallGraph results add `Engine`, `Inputs`, `OutputDir`, `Formats`, `Files`,
and `Summary`. Copy results add `Source`, `Destination`, `FileCount`,
and `BytesCopied`. Compress results add `Source`, `Destination`,
`ArchiveSize`, and `Checksum`.

---

## Repository structure

```
tools (included, no install needed)
  delphi-clean.ps1
  delphi-inspect.ps1
  delphi-msbuild.ps1
  delphi-dccbuild.ps1
  delphi-incver.ps1
  delphi-coverage.ps1
  delphi-callgraph.ps1
  delphi-format.ps1
source/                 PowerShell module source
  Delphi.PowerShell.CI.psm1
  bundled-tools/        Packaged standalone
  Private/              Internal helpers (not exported)
  Public/               Exported commands
Examples/               Integration test projects and example config
  ConsoleProjectGroup/  Simple Delphi console app and DUnitX test project
docs/                   Per-command reference documentation
  Get-DelphiCiConfig.md
  Invoke-DelphiClean.md
  Invoke-DelphiBuild.md
  Invoke-DelphiCi.md
  Invoke-DelphiCompress.md
  Invoke-DelphiCopy.md
  Invoke-DelphiCoverage.md
  Invoke-DelphiCallGraph.md
  Invoke-DelphiCodesign.md
  Invoke-DelphiFormat.md
  Invoke-DelphiIncVer.md
  Invoke-DelphiRun.md
tests/                  Pester test suite
  run-tests.ps1
  pwsh/
```

---

## Reference documentation

| Command | Description |
|---|---|
| `Invoke-DelphiCi` | Primary orchestration command |
| `Invoke-DelphiClean` | Clean step |
| `Invoke-DelphiBuild` | Build step |
| `Invoke-DelphiCompress` | Compress step (create .zip archives with optional SHA256 sidecar) |
| `Invoke-DelphiCopy` | Copy step (collect build outputs with glob, flatten, and checksum) |
| `Invoke-DelphiCoverage` | Coverage step (code coverage with threshold and badge generation) |
| `Invoke-DelphiFormat` | Format step (format Delphi source, or audit-only with `-FormatCheck`) |
| `Invoke-DelphiCallGraph` | CallGraph step (call graph and dependency graph analysis) |
| `Invoke-DelphiCodesign` | Codesign step (sign or verify binaries via Azure Trusted Signing) |
| `Invoke-DelphiIncVer` | IncVer step (increment version numbers in RC, DProj, or text files) |
| `Invoke-DelphiRun` | Run step (execute a command and check exit code) |
| `Get-DelphiCiConfig` | Inspect resolved configuration |

Full parameter reference and examples for each command are in `docs/`.

---

## Continuous-Delphi

This tool is part of the [Continuous-Delphi](https://github.com/continuous-delphi)
ecosystem, focused on strengthening Delphi's continued success

![continuous-delphi logo](https://continuous-delphi.github.io/assets/logos/continuous-delphi-480x270.png)
