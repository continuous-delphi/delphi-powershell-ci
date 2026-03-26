# delphi-powershell-ci

![delphi-powershell-ci logo](https://continuous-delphi.github.io/assets/logos/delphi-powershell-ci-480x270.png)

[![Delphi](https://img.shields.io/badge/delphi-red)](https://www.embarcadero.com/products/delphi)
[![CI](https://github.com/continuous-delphi/delphi-powershell-ci/actions/workflows/ci.yml/badge.svg)](https://github.com/continuous-delphi/delphi-powershell-ci/actions/workflows/ci.yml)
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

---

## v1 scope

v1 supports **Clean**, **Build**, and **Test** steps.

Not in v1: linting, coverage, SBOM, quality gates, GitHub Actions workflows,
PowerShell Gallery publication.

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

### Convention-based usage

If your repository has a single `.dproj` under `source\`:

```powershell
Invoke-DelphiCi
```

This cleans with the `lite` level, detects the latest Delphi installation,
and builds `Win32 Debug`.

### Explicit project

Clean + Build ConsoleProject:

```powershell
Invoke-DelphiCi -ProjectFile .\examples\ConsoleProjectGroup\Source\ConsoleProject.dproj
```

### Clean only

```powershell
Invoke-DelphiCi -Steps Clean -ProjectFile .\source\MyApp.dproj
```

### Build only

```powershell
Invoke-DelphiCi -Steps Build -ProjectFile .\source\MyApp.dproj
```

### Full pipeline: clean, build, and test

```powershell
Invoke-DelphiCi -Steps Clean,Build,Test `
    -ProjectFile .\source\MyApp.dproj `
    -TestProjectFile .\tests\MyApp.Tests.dproj `
    -TestDefines CI
```

The `CI` define switches DUnitX from the TestInsight IDE runner to the
headless console runner. It is not injected automatically.

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

## Two ways to use this module

### As a module function (scripted use)

Import the module and call `Invoke-DelphiCi` directly. The function always
returns a structured result object; your script decides what to do with it:

```powershell
Import-Module .\source\Delphi.PowerShell.CI.psd1

$run = Invoke-DelphiCi -ProjectFile .\source\MyApp.dproj
if (-not $run.Success) { exit 1 }
```

Use this when you want to inspect step details, branch on the result, or
compose `Invoke-DelphiCi` into a larger script.

### As a wrapper script (CI runner use)

`tools\delphi-ci.ps1` imports the module and owns the process exit code.
It exits 0 on success and 1 on failure. No result object is written to the
pipeline in run mode -- the exit code is the signal.

```powershell
# Clean and build
.\tools\delphi-ci.ps1 -ProjectFile .\source\MyApp.dproj

# Full pipeline with test
.\tools\delphi-ci.ps1 -Steps Clean,Build,Test `
    -ProjectFile .\source\MyApp.dproj `
    -TestProjectFile .\tests\MyApp.Tests.dproj `
    -TestDefines CI
```

Use this when a CI runner (GitHub Actions, GitLab CI, Jenkins, etc.) needs
to read a process exit code to determine pass or fail.

---

## Configuration

### Precedence (highest to lowest)

1. Explicit CLI parameters
2. JSON config file fields
3. Built-in defaults

For example, a `-Platform` supplied on the command line always wins over the same
field in the config file.

### Supported config file schema

```json
{
  "root": ".",
  "steps": ["Clean", "Build", "Test"],
  "clean": {
    "level": "lite"
  },
  "build": {
    "projectFile": "source/MyApp.dproj",
    "engine": "MSBuild",
    "toolchain": { "version": "Latest" },
    "platform": "Win32",
    "configuration": "Debug",
    "defines": []
  },
  "test": {
    "testProjectFile": "tests/MyApp.Tests.dproj",
    "defines": ["CI"],
    "timeoutSeconds": 10,
    "build": true,
    "run": true
  }
}
```

All fields are optional. Absent fields fall back to built-in defaults.

`root` is resolved relative to the config file's directory when it is a
relative path or `.`.

### Clean levels

| Level | What is removed |
|---|---|
| `lite` | Compiler caches, IDE state (`.dcu`, `.identcache`, `__history`, etc.) |
| `build` | Everything in `lite`, plus build outputs (`.exe`, `.dll`, `.bpl`, platform output folders, etc.) |
| `full` | Everything in `build`, plus user-local IDE files (`.~*`, FireDAC project cache, etc.) |

Default level is `lite`.

---

## Project discovery

When no `-ProjectFile` is given, discovery searches in order:

1. `<root>` -- if exactly one `.dproj` is present here
2. `<root>\source` -- fallback
3. `<root>\..\source` -- tools-folder convention fallback

Discovery stops at the first location that yields results. It fails with
a clear error if no `.dproj` is found, or if more than one is found and
no explicit file was given.

---

## Step commands

The step commands can also be called directly.

```powershell
# Clean only -- lite level against the current directory
Invoke-DelphiClean

# Clean with build level
Invoke-DelphiClean -Level build -Root .\source

# Build only -- latest Delphi, Win32 Debug
Invoke-DelphiBuild -ProjectFile .\source\MyApp.dproj

# Build with explicit options
Invoke-DelphiBuild -ProjectFile .\source\MyApp.dproj `
    -Platform Win64 -Configuration Release -Toolchain VER370

# Build and run a DUnitX test project
Invoke-DelphiTest -TestProjectFile .\tests\MyApp.Tests.dproj -Defines CI

# Build the test project without running it
Invoke-DelphiTest -TestProjectFile .\tests\MyApp.Tests.dproj -Defines CI -Run $false
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
| `Success` | Boolean | `$true` when every step succeeded |
| `Duration` | TimeSpan | Wall-clock time for the run |
| `ProjectFile` | String | Resolved project file path |
| `Steps` | Object[] | One result per step that ran |

Clean and Build step results have `StepName`, `Success`, `Duration`,
`ExitCode`, `Tool`, `Message`, and `ProjectFile`. Test step results
additionally have `TestProjectFile` and `TestExecutable` in place of
`ProjectFile`.

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
  Invoke-DelphiTest.md
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
| `Invoke-DelphiTest` | Test step (build and run a DUnitX test project) |
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

