# Invoke-DelphiCoverage

Runs Delphi code coverage analysis as a CI step using a pluggable
coverage engine. Returns a structured step result with coverage
percentage, line counts, threshold status, and optional badge output.

## Syntax

```powershell
Invoke-DelphiCoverage
    [-Execute <string>]
    [-MapFile <string>]
    [-CoverageDproj <string>]
    [-CoverageEngine <string>]
    [-CoverageEnginePath <string>]
    [-CoverageSourceDir <string[]>]
    [-CoverageUnits <string[]>]
    [-CoverageExcludeUnits <string[]>]
    [-CoverageOutputDir <string>]
    [-CoverageFormats <string[]>]
    [-CoverageThreshold <int>]
    [-CoverageArguments <string[]>]
    [-CoverageTimeoutSeconds <int>]
    [-CoverageBadge <string>]
    [-WhatIf]
```

## Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `-Execute` | string | | Path to the test executable. Required unless `-CoverageDproj` is used. |
| `-MapFile` | string | | Path to the detailed MAP file. Required unless `-CoverageDproj` is used. |
| `-CoverageDproj` | string | | Path to a `.dproj` file. The engine auto-discovers exe, map, units, and source paths. |
| `-CoverageEngine` | string | `DelphiCodeCoverage` | Which coverage engine to use. |
| `-CoverageEnginePath` | string | auto-detect | Explicit path to the engine executable. |
| `-CoverageSourceDir` | string[] | `@()` | Directories containing Delphi source files. Each path gets a separate `-sp` flag. |
| `-CoverageUnits` | string[] | `@()` | Unit name patterns to include (supports wildcards). |
| `-CoverageExcludeUnits` | string[] | `@()` | Unit name patterns to exclude. |
| `-CoverageOutputDir` | string | `coverage` | Directory for coverage reports. |
| `-CoverageFormats` | string[] | `@('html')` | Output formats: `html`, `xml`, `emma`, `lcov`, `cobertura`, `md`, `covdb`. |
| `-CoverageThreshold` | int | `0` | Minimum coverage %. Fails if below. 0 = disabled. |
| `-CoverageArguments` | string[] | `@()` | Extra arguments passed to the test executable. |
| `-CoverageTimeoutSeconds` | int | `300` | Maximum time before the engine process is killed. |
| `-CoverageBadge` | string | | Output path for a coverage badge (`.svg` or `.json`). |
| `-WhatIf` | switch | | Shows what would happen without running coverage. |

## Supported Engines

| Engine | Default Executable | Notes |
|--------|-------------------|-------|
| `DelphiCodeCoverage` | `CodeCoverage.exe` | Open source, MAP-file based, Win32/Win64 |
| `radCodeCoverage` | `radCodeCoverage.exe` | Shares DelphiCodeCoverage CLI conventions, adds markdown report |

Both engines share the same CLI parameter conventions and both support
`-dproj` for auto-discovery from a project file. `radCodeCoverage`
additionally supports the `md`, `lcov`, and `covdb` output formats for
markdown, LCOV, and SQLite coverage reports.

The engine must be on PATH or specified via `-CoverageEnginePath`.
Use `-CoverageEnginePath` for platform-specific variants (e.g.,
`CodeCoverage.x64.exe` or `radCodeCoverage.x64.exe`).

## MAP File Requirement

The MAP file must contain detailed line number information. This requires
the Delphi linker setting "Detailed" or "Full" (`DCC_MapFile=3` in the
.dproj). Segment-only MAP files are rejected with a clear error.

## Coverage Threshold

When `-CoverageThreshold` is greater than 0, the step fails if the
measured coverage percentage is below the threshold. This makes coverage
a quality gate in the pipeline.

```powershell
# Fail if coverage drops below 60%
Invoke-DelphiCoverage -Execute test.exe -MapFile test.map -CoverageThreshold 60
```

## Badge Generation

The `-CoverageBadge` parameter generates a coverage badge file:

- `.svg` -- self-contained SVG badge (commit to repo or host on GitHub Pages)
- `.json` -- Shields.io endpoint format (host and reference via dynamic URL)

Color thresholds: green >= 80%, yellow >= 60%, red < 60%.

```powershell
Invoke-DelphiCoverage -Execute test.exe -MapFile test.map -CoverageBadge docs/coverage.svg
```

## Return Value

Returns a `PSCustomObject` with these fields:

| Field | Type | Description |
|---|---|---|
| `StepName` | string | Always `'Coverage'` |
| `Success` | bool | `$true` if coverage ran and threshold was met |
| `ExitCode` | int | Exit code from the bundled tool |
| `Duration` | TimeSpan | Total time for this step |
| `Tool` | string | Always `'delphi-coverage.ps1'` |
| `Message` | string | Coverage summary or error description |
| `Execute` | string | Path to the test executable |
| `CoveragePercent` | double | Measured line coverage percentage |
| `LinesCovered` | int | Number of lines covered |
| `LinesTotal` | int | Total number of measurable lines |
| `ThresholdMet` | bool | Whether the threshold was met (or no threshold set) |
| `OutputDir` | string | Directory containing coverage reports |
| `Badge` | string | Path to generated badge file, or null |

## Usage Examples

### Basic coverage run

```powershell
Invoke-DelphiCoverage -Execute .\test\Win32\Debug\MyApp.Tests.exe `
    -MapFile .\test\Win32\Debug\MyApp.Tests.map `
    -CoverageSourceDir .\source
```

### With threshold and Cobertura output

```powershell
Invoke-DelphiCoverage -Execute .\test\Win32\Debug\MyApp.Tests.exe `
    -MapFile .\test\Win32\Debug\MyApp.Tests.map `
    -CoverageSourceDir .\source -CoverageUnits 'MyApp.*' `
    -CoverageFormats html,cobertura -CoverageThreshold 60
```

### With badge generation

```powershell
Invoke-DelphiCoverage -Execute .\test\Win32\Debug\MyApp.Tests.exe `
    -MapFile .\test\Win32\Debug\MyApp.Tests.map `
    -CoverageSourceDir .\source -CoverageBadge docs\coverage-badge.svg
```

### Using radCodeCoverage with markdown output

```powershell
Invoke-DelphiCoverage -Execute .\test\Win64\Debug\MyApp.Tests.exe `
    -MapFile .\test\Win64\Debug\MyApp.Tests.map `
    -CoverageEngine radCodeCoverage `
    -CoverageEnginePath radCodeCoverage.x64.exe `
    -CoverageSourceDir .\source -CoverageFormats html,md
```

### Using radCodeCoverage with covdb (SQLite) output

```powershell
Invoke-DelphiCoverage -Execute .\test\Win64\Debug\MyApp.Tests.exe `
    -MapFile .\test\Win64\Debug\MyApp.Tests.map `
    -CoverageEngine radCodeCoverage `
    -CoverageSourceDir .\source -CoverageFormats html,covdb
```

### Pipeline Coverage action in Invoke-DelphiCi config file

```json
{
  "pipeline": [
    { "action": "Build", "jobs": [
      { "name": "Test project",
        "projectFile": "test/MyApp.Tests.dproj",
        "platform": "Win32", "configuration": "Debug",
        "defines": ["CI"] }
    ]},
    { "action": "Coverage", "jobs": [
      { "name": "Unit test coverage",
        "execute": "test/Win32/Debug/MyApp.Tests.exe",
        "mapFile": "test/Win32/Debug/MyApp.Tests.map",
        "sourceDir": ["source/"],
        "units": ["MyApp.*"],
        "formats": ["html", "cobertura"],
        "threshold": 60,
        "badge": "docs/coverage-badge.svg" }
    ]}
  ]
}
```

## Default Coverage action options can be set by the `coverage` key in `defaults`

```json
{
  "defaults": {
    "coverage": {
      "engine": "DelphiCodeCoverage",
      "sourceDir": ["source/"],
      "outputDir": "coverage/",
      "formats": ["html"],
      "threshold": 0,
      "badge": "",
      "timeoutSeconds": 300
    }
  }
}
```

Each job inherits defaults through the three-level merge
(defaults > action-level > job-level) and can override them at any level.

## Notes

- Coverage replaces Run for test execution when coverage data is needed.
  A pipeline typically has either Run or Coverage for a given test project,
  not both.
- The Coverage action handles both running the tests and collecting
  coverage data in a single step.
- The engine executable must be installed separately. `DelphiCodeCoverage`
  is available at [github.com/DelphiCodeCoverage](https://github.com/DelphiCodeCoverage/DelphiCodeCoverage).
- `radCodeCoverage` shares DelphiCodeCoverage's CLI conventions and adds
  the `md` format for markdown reports and `covdb` for SQLite database
  output. Use `-CoverageEnginePath` to specify platform-specific variants
  like `radCodeCoverage.x64.exe`.
- Coverage reports are written to `-CoverageOutputDir`. The directory is
  created automatically if it does not exist.
- The standalone tool is maintained at
  [github.com/continuous-delphi/delphi-coverage](https://github.com/continuous-delphi/delphi-coverage).
