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

The standalone tools remain individually usable and separately versioned.
This repo packages compatible versions together and provides a simpler
public interface for day-to-day CI workflows.

Additional functionlity include `Invoke-DelphiRun` for executing DUnitX test projects or other utilities as needed.


---

## v1 scope

v1 supports **Clean**, **Build**, and **Run** steps.

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
    "run": { "timeoutSeconds": 10 }
  },
  "pipeline": [
    { "action": "Clean", "level": "deep" },
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

`includePath` and `namespace` are DCCBuild-only and are ignored when `engine`
is `MSBuild`.

All fields are optional. Absent fields fall back to built-in defaults.

`root` is resolved relative to the config file's directory when it is a
relative path or `.`.

The legacy format (with `"steps"` and named sections) is still supported and
automatically converted internally.

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

# Build only -- latest Delphi, Win32 Debug
Invoke-DelphiBuild -ProjectFile .\source\MyApp.dproj

# Build with explicit options
Invoke-DelphiBuild -ProjectFile .\source\MyApp.dproj `
    -Platform Win64 -Configuration Release -Toolchain VER370

# Run a pre-built DUnitX test executable
Invoke-DelphiRun -Execute .\tests\Win32\Debug\MyApp.Tests.exe
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

Result shape:

| Field | Type | Notes |
|---|---|---|
| `Success` | Boolean | `$true` when every job succeeded |
| `Duration` | TimeSpan | Wall-clock time for the run |
| `Steps` | Object[] | One result per job that ran |

Clean step results have `StepName`, `Success`, `Duration`, `ExitCode`,
`Tool`, and `Message`. Build results add `ProjectFile`, `Warnings`,
`Errors`, `ExeOutputDir`, and `Output`. Run results have `Execute`
instead of `ProjectFile`.

---

## Repository structure

```
tools (included, no install needed)
  delphi-clean.ps1
  delphi-inspect.ps1
  delphi-msbuild.ps1
  delphi-dccbuild.ps1
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
| `Invoke-DelphiRun` | Run step (execute a command and check exit code) |
| `Get-DelphiCiConfig` | Inspect resolved configuration |

Full parameter reference and examples for each command are in `docs/`.

---

## Maturity

This repository is currently `incubator`. Both implementations are under active development.
It will graduate to `stable` once:

- At least one downstream consumer exists.

Until graduation, breaking changes may occur

![continuous-delphi logo](https://continuous-delphi.github.io/assets/logos/continuous-delphi-480x270.png)

## Part of the Continuous Delphi Organization

This repository follows the Continuous Delphi organization taxonomy. See
[cd-meta-org](https://github.com/continuous-delphi/cd-meta-org) for navigation and governance.

- `docs/org-taxonomy.md` -- naming and tagging conventions
- `docs/versioning-policy.md` -- release and versioning rules
- `docs/repo-lifecycle.md` -- lifecycle states and graduation criteria

