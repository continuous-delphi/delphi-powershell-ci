# Changelog

All notable changes to this project will be documented in this file.

---

## [Unreleased]

- Update `delphi-clean` to `0.10.0`. Clean settings (level, file patterns,
  directory exclusions) now live in `delphi-clean`'s own config file hierarchy
  (`delphi-clean.json` / `delphi-clean.local.json` / `$HOME/delphi-clean.json`)
  rather than in `delphi-ci.json`. `Invoke-DelphiClean` is now a thin wrapper
  that passes only `-RootPath` to `delphi-clean.ps1`.

---

## [0.1.0] - Unreleased

- Update `delphi-clean` to `0.7.0` to use new clean levels (basic+standard+deep)
  [#5](https://github.com/continuous-delphi/delphi-powershell-ci/issues/5)

Initial commit of `delphi-powershell-ci`.

### Public commands

- `Invoke-DelphiCi` -- primary orchestration command; runs Clean, Build,
  and/or Test steps, supports convention-based project discovery and JSON
  config files; `-VersionInfo` reports module and bundled tool versions
- `Invoke-DelphiClean` -- thin wrapper over `delphi-clean.ps1`; passes
  `-RootPath` and optional `-CleanConfigFile`; `-WhatIf` support;
  structured result object
- `Invoke-DelphiBuild` -- wraps `delphi-inspect.ps1` + `delphi-msbuild.ps1`;
  detect-latest or pinned toolchain, platform/configuration/defines
  forwarding, structured result object
- `Invoke-DelphiTest` -- builds and runs a DUnitX test project as a CI step;
  `-Build`/`-Run` phase flags, `-TestExecutable` bypass, timeout with
  kill-on-breach, `-WhatIf` support, structured result object
- `Get-DelphiCiConfig` -- returns the fully-resolved configuration object
  for inspection; supports JSON config files and CLI overrides

### Bundled tools

| Tool | Version |
|---|---|
| delphi-clean | 0.4.0 |
| delphi-inspect | 0.6.0 |
| delphi-msbuild | 0.5.0 |
| delphi-dccbuild | 0.3.0 |

### Module

- Module manifest (`Delphi.PowerShell.CI.psd1`) with explicit exports,
  PowerShell 7.0 minimum version requirement, and PowerShell Gallery
  metadata (Tags, ProjectUri, LicenseUri)
- Wrapper script (`tools/delphi-ci.ps1`) for script-style callers who
  prefer a single entry-point over managing module imports

### Other

- Convention-based project discovery for both build and test projects;
  test discovery searches `<root>\tests\` then `<root>` for a project
  whose name starts or ends with `Tests`
- JSON configuration file support with CLI override precedence; full
  `test` section support (`testProjectFile`, `testExecutable`, `defines`,
  `arguments`, `timeoutSeconds`, `build`, `run`)
- CI-friendly console output with [INFO], [STEP], [OK], [ERROR] prefixes
- 269 Pester tests (unit and integration) -- all passing
- Reference documentation in `docs/` for all public commands

<br />
<br />

### `delphi-powershell-ci` - a developer tool from Continuous Delphi

![continuous-delphi logo](https://continuous-delphi.github.io/assets/logos/continuous-delphi-480x270.png)

https://github.com/continuous-delphi
