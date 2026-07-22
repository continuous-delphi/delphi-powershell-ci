# Get-DelphiCiConfig

Loads and normalizes configuration for a Delphi CI run.

Merges configuration through multiple levels:

1. Built-in defaults
2. JSON config file `defaults` section
3. CLI parameters (highest priority for defaults)
4. Action-level properties in the pipeline
5. Job-level properties (highest priority per job)

Returns a single `PSCustomObject` that all downstream commands consume.

## Syntax

```powershell
Get-DelphiCiConfig
    [-ConfigFile <string>]
    [-Root <string>]
    [-Steps <string[]>]
    [-ProjectFile <string>]
    [-Platform <string>]
    [-Configuration <string>]
    [-Toolchain <string>]
    [-BuildEngine <string>]
    [-Defines <string[]>]
    [-BuildVerbosity <string>]
    [-BuildTarget <string>]
    [-ExeOutputDir <string>]
    [-DcuOutputDir <string>]
    [-UnitSearchPath <string[]>]
    [-IncludePath <string[]>]
    [-Namespace <string[]>]
    [-NoConfig]
    [-CleanLevel <string>]
    [-CleanOutputLevel <string>]
    [-CleanIncludeFilePattern <string[]>]
    [-CleanExcludeDirectoryPattern <string[]>]
    [-CleanConfigFile <string>]
    [-CleanRecycleBin <bool>]
    [-CleanCheck <bool>]
    [-Execute <string>]
    [-RunArguments <string[]>]
    [-RunTimeoutSeconds <int>]
```

## Return value

```
Root       string     Resolved absolute path to the working root
Pipeline   object[]   Ordered array of resolved action entries

Each Pipeline entry:
  Action     string      Action type (Clean, Build, Run, ...)
  Defaults   hashtable   Merged defaults for this action (base + action-level)
  Jobs       hashtable[] Fully resolved jobs (base + action-level + job-level)
```

### Defaults keys by action type

**Clean:**
`level`, `outputLevel`, `includeFilePattern`, `excludeDirectoryPattern`,
`configFile`, `recycleBin`, `check`, `root`

**Build:**
`engine`, `toolchain` (with nested `version`), `platform`, `configuration`,
`defines`, `verbosity`, `target`, `exeOutputDir`, `dcuOutputDir`,
`unitSearchPath`, `includePath`, `namespace`

**Run:**
`timeoutSeconds`, `arguments`

**CallGraph:**
`path`, `engine`, `enginePath`, `outputDir`, `formats`, `jsonFile`,
`dotFile`, `summaryFile`, `class`, `annotations`, `deterministic`,
`graphKind`, `graphVizUses`, `graphVizClasses`, `pasDocOptions`,
`projectFile`, `graphVizExclude`, `engineArguments`, `timeoutSeconds`

### Job keys

Jobs are hashtables containing all resolved keys from the merge chain plus
`name` (metadata). Build jobs also have `platform` and `configuration`
normalized to arrays for matrix expansion.

## Merge semantics

| Type | Behavior |
|------|----------|
| Scalar | Last writer wins (child overrides parent) |
| Array | Append (child concatenated after parent) |
| `key!` suffix | Replace array instead of appending |
| Nested object | Shallow merge (child keys overwrite parent keys) |

## JSON config file format

### Pipeline format

```json
{
  "root": ".",
  "defaults": {
    "clean": { "level": "standard", "includeFilePattern": ["*.res"] },
    "build": {
      "engine": "MSBuild",
      "toolchain": { "version": "Latest" },
      "platform": "Win32",
      "configuration": "Debug"
    },
    "run": { "timeoutSeconds": 10, "arguments": [] }
  },
  "pipeline": [
    { "action": "Clean", "level": "deep" },
    { "action": "Build",
      "platform": "Win64",
      "jobs": [
        { "name": "App", "projectFile": "source/MyApp.dproj" },
        { "name": "Tests", "projectFile": "test/MyApp.Tests.dproj",
          "platform": "Win32", "defines": ["CI"] }
      ]
    },
    { "action": "Run",
      "jobs": [
        { "name": "Unit tests",
          "execute": "test/Win32/Debug/MyApp.Tests.exe" }
      ]
    }
  ]
}
```

## Notes

- When `-ConfigFile` is used, the JSON file must define a `pipeline` array.
- Without a config file, `-Steps` generates an in-memory pipeline, or the
  resolver uses the default `Clean, Build` steps.
- Absent action and job fields use built-in defaults.
- `root` is resolved relative to the config file's directory.
- CLI parameters override defaults but not action-level or job-level values
  in the pipeline config.
- Without a config file, `-ProjectFile` creates a single-entry build jobs list.
- Without a config file, `-Execute` creates a single-entry run jobs list.
- Validation errors (invalid level, engine, verbosity, target) throw
  immediately before any work begins.
- Build job `platform` and `configuration` are always normalized to arrays
  for matrix expansion.
