# Changelog

All notable changes to this project will be documented in this file.

---
## [0.3.0] - Unreleased
- Add `Codesign` pipeline action and `Invoke-DelphiCodesign`, bundling
  `delphi-codesign-azure.ps1` for Authenticode signing and verification
  via Azure Trusted Signing. Supports Sign and Verify actions with
  engine abstraction for future signing providers.
  [#12](https://github.com/continuous-delphi/delphi-powershell-ci/issues/12)

## [0.2.0] - Unreleased
- Add `schemas/delphi-ci.schema.json` for editor completion and validation of
  `delphi-ci.json` pipeline configuration files.
- Remove unreleased legacy JSON config support for top-level `"steps"` and
  named action sections; config files now use the ordered `"pipeline"` format.
- Extended pipeline redesign v2: replaced the fixed `"steps"`
and named-section config layout with an ordered `"pipeline"` array
of action objects. This enables repeatable and freely ordered actions
(Clean, Build, Run, Copy, Compress, etc.) without schema changes.
- Update `delphi-clean` to `0.10.0`. Clean settings (level, file patterns,
  directory exclusions) now live in `delphi-clean`'s own config file hierarchy
  (`delphi-clean.json` / `delphi-clean.local.json` / `$HOME/delphi-clean.json`)
  rather than in `delphi-ci.json`. `Invoke-DelphiClean` is now a thin wrapper
  that passes only `-RootPath` to `delphi-clean.ps1`.
- Total revamp/redesign of pipeline to support multiple jobs per step with matrix expansion
- Support more options in the external config file for delphi-clean, delphi-msbuild, delphi-dccbuild
- Support -Verbosity for delphi-msbuild and outputLevel for delphi-clean
- Add -ExeOutputDir+DcuOutputDir parameters to Invoke-DelphiBuild
- Add `CallGraph` pipeline action and `Invoke-DelphiCallGraph`, bundling
  `delphi-callgraph.ps1` for radCallGraph, PasDoc GraphViz, and DCC GraphViz output.
- Enable deterministic radCallGraph output by default and expose
  `CallGraphDeterministic` / `deterministic` opt-out controls.
- Add `covdb` coverage output format (SQLite) for radCodeCoverage engine
  [#10](https://github.com/continuous-delphi/delphi-powershell-ci/issues/10)

---

## [0.1.0] - Unreleased

- Update `delphi-clean` to `0.7.0` to use new clean levels (basic+standard+deep)
  [#5](https://github.com/continuous-delphi/delphi-powershell-ci/issues/5)

Initial commit of `delphi-powershell-ci`.

### Public commands

- `Invoke-DelphiCi` -- primary orchestration command; runs pipeline
  actions (Clean, IncVer, Build, Run, Coverage, CallGraph, Copy, Compress),
  `-VersionInfo` reports module and bundled tool versions
- `Invoke-DelphiClean` -- thin wrapper over `delphi-clean.ps1`; passes
  `-RootPath` and optional `-CleanConfigFile`; `-WhatIf` support;
  structured result object
- `Invoke-DelphiBuild` -- wraps `delphi-inspect.ps1` + `delphi-msbuild.ps1`;
  detect-latest or pinned toolchain, platform/configuration/defines
  forwarding, structured result object
- `Invoke-DelphiRun` -- executes a compiled binary (DUnitX test runner or
  other utility) with timeout, argument forwarding, and structured result
- `Invoke-DelphiIncVer` -- increments version numbers in RC or text files
  via `delphi-incver.ps1`; target/style/part/pattern controls
- `Invoke-DelphiCoverage` -- code coverage orchestrator via
  `delphi-coverage.ps1`; supports multiple coverage engines and output formats
- `Invoke-DelphiCallGraph` -- call graph and dependency analysis via
  `delphi-callgraph.ps1`; radCallGraph, PasDoc GraphViz, and DCC GraphViz output
- `Invoke-DelphiCopy` -- copies build artifacts to a destination directory
- `Invoke-DelphiCompress` -- compresses build artifacts into a zip archive
- `Get-DelphiCiConfig` -- returns the fully-resolved configuration object
  for inspection; supports JSON config files and CLI overrides

### Bundled tools

| Tool | Version |
|---|---|
| delphi-inspect | 1.1.0 |
| delphi-clean | 1.0.0 |
| delphi-msbuild | 0.7.0 |
| delphi-dccbuild | 0.3.0 |
| delphi-incver | 0.2.0 |
| delphi-coverage | 1.0.0 |
| delphi-callgraph | 0.1.0 |

### Module

- Module manifest (`Delphi.PowerShell.CI.psd1`) with explicit exports,
  PowerShell 5.1 minimum version requirement, and PowerShell Gallery
  metadata (Tags, ProjectUri, LicenseUri)
- Wrapper script (`tools/delphi-ci.ps1`) for script-style callers who
  prefer a single entry-point over managing module imports

### Other

- JSON configuration file support with CLI override precedence and
  ordered `pipeline` array of action objects
- CI-friendly console output with [INFO], [STEP], [OK], [ERROR] prefixes
- 332 Pester tests (unit and integration) -- all passing
- Reference documentation in `docs/` for all public commands

<br />
<br />

### `delphi-powershell-ci` - a developer tool from Continuous Delphi

![continuous-delphi logo](https://continuous-delphi.github.io/assets/logos/continuous-delphi-480x270.png)

https://github.com/continuous-delphi