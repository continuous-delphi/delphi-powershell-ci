# Invoke-DelphiCallGraph

Runs Delphi call graph or dependency graph analysis as a CI step. The default
engine is `radCallGraph`; PasDoc and Delphi compiler GraphViz modes are also
available for DOT dependency/class graphs.

## Syntax

```powershell
Invoke-DelphiCallGraph
    [-CallGraphPath <string[]>]
    [-CallGraphEngine <string>]
    [-CallGraphEnginePath <string>]
    [-CallGraphOutputDir <string>]
    [-CallGraphFormats <string[]>]
    [-CallGraphJsonFile <string>]
    [-CallGraphDotFile <string>]
    [-CallGraphSummaryFile <string>]
    [-CallGraphClass <string>]
    [-CallGraphAnnotations <bool>]
    [-CallGraphDeterministic <bool>]
    [-CallGraphGraphKind <string>]
    [-CallGraphGraphVizUses <bool>]
    [-CallGraphGraphVizClasses <bool>]
    [-CallGraphPasDocOptions <string[]>]
    [-CallGraphProjectFile <string>]
    [-CallGraphGraphVizExclude <string[]>]
    [-CallGraphEngineArguments <string[]>]
    [-CallGraphTimeoutSeconds <int>]
    [-WhatIf]
```

## Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `-CallGraphPath` | string[] | `@()` | Source files or directories to analyze. |
| `-CallGraphEngine` | string | `radCallGraph` | Engine: `radCallGraph`, `PasDoc`, or `DCC`. |
| `-CallGraphEnginePath` | string | auto-detect | Explicit path to the engine executable. |
| `-CallGraphOutputDir` | string | `callgraph` | Directory for generated graph files. |
| `-CallGraphFormats` | string[] | `@('json')` | Output formats: `json`, `dot`, `txt`. PasDoc/DCC support `dot`. |
| `-CallGraphJsonFile` | string | | Explicit JSON output path. |
| `-CallGraphDotFile` | string | | Explicit DOT/GV output path. |
| `-CallGraphSummaryFile` | string | | Explicit text summary path. |
| `-CallGraphClass` | string | | radCallGraph class filter. |
| `-CallGraphAnnotations` | bool | `$true` | Include radCallGraph `{cg:...}` annotation data. |
| `-CallGraphDeterministic` | bool | `$true` | Pass radCallGraph `--deterministic` for reproducible output without timestamps. |
| `-CallGraphGraphKind` | string | | `call`, `uses`, `classes`, `dependency`, or `all`. |
| `-CallGraphGraphVizUses` | bool | `$false` | PasDoc `--graphviz-uses`. |
| `-CallGraphGraphVizClasses` | bool | `$false` | PasDoc `--graphviz-classes`. |
| `-CallGraphPasDocOptions` | string[] | `@()` | Extra PasDoc options. |
| `-CallGraphProjectFile` | string | | DCC project file for compiler GraphViz output. |
| `-CallGraphGraphVizExclude` | string[] | `@()` | DCC `--graphviz-exclude` unit patterns. |
| `-CallGraphEngineArguments` | string[] | `@()` | Extra arguments passed to the selected engine. |
| `-CallGraphTimeoutSeconds` | int | `300` | Maximum runtime before failure. |

## Examples

### radCallGraph

```powershell
Invoke-DelphiCallGraph -CallGraphPath .\source `
    -CallGraphFormats json,dot,txt `
    -CallGraphOutputDir .\artifacts\callgraph
```

### PasDoc GraphViz

```powershell
Invoke-DelphiCallGraph -CallGraphPath .\source `
    -CallGraphEngine PasDoc `
    -CallGraphGraphKind all `
    -CallGraphFormats dot
```

### Delphi Compiler GraphViz

```powershell
Invoke-DelphiCallGraph -CallGraphEngine DCC `
    -CallGraphProjectFile .\source\MyApp.dpr `
    -CallGraphGraphVizExclude System.*,Vcl.*,Winapi.* `
    -CallGraphFormats dot
```

### Pipeline Action

```json
{
  "pipeline": [
    {
      "action": "CallGraph",
      "jobs": [
        {
          "name": "Source call graph",
          "path": ["source"],
          "engine": "radCallGraph",
          "formats": ["json", "dot", "txt"],
          "outputDir": "artifacts/callgraph"
        }
      ]
    }
  ]
}
```

## Return Value

Returns a `PSCustomObject` with these fields:

| Field | Type | Description |
|---|---|---|
| `StepName` | string | Always `CallGraph`. |
| `Success` | bool | `$true` when the bundled tool exits 0. |
| `ExitCode` | int | Exit code from `delphi-callgraph.ps1`. |
| `Duration` | TimeSpan | Total step duration. |
| `Tool` | string | Always `delphi-callgraph.ps1`. |
| `Message` | string | Completion or exit-code summary. |
| `Engine` | string | Selected engine. |
| `Inputs` | string[] | Resolved source inputs from the tool result. |
| `OutputDir` | string | Output directory. |
| `Formats` | string[] | Generated formats. |
| `Files` | object | Generated output files from the tool result. |
| `Summary` | object | Call graph metrics when available: `files`, `nodes`, `classes`, `standalone`, and `edges`. |

## Notes

- `radCallGraph` supports `json`, `dot`, and `txt`.
- radCallGraph deterministic output is enabled by default. Set
  `-CallGraphDeterministic $false` or `"deterministic": false` to keep
  engine timestamps.
- PasDoc and DCC modes are DOT/GV graph generators.
- Extra engine and PasDoc options are passed through environment variables so
  option values beginning with `-` are not misparsed by PowerShell `-File`.
