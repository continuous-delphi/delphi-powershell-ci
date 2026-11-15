#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

<#
.SYNOPSIS
  Guards schemas/delphi-ci.schema.json against silent drift from Resolve-DelphiCiConfig.ps1.

.DESCRIPTION
  The schema is the EDITOR-facing contract and every $defs block sets
  "additionalProperties": false, so it REJECTS any key it does not know. The
  resolver's $builtInDefaults is the RUNTIME source of truth. Until this file
  existed nothing compared the two, and both directions of drift were silent:

    - a key in the resolver but not the schema works at runtime and shows up as
      a red squiggle on working config;
    - a key in the schema but not the resolver completes in the editor and is
      then ignored at runtime, which is the worse direction for anything
      gate-shaped (see #24's failOnWarning / failOnHint).

  What made it easy to miss is that one key has to be added in THREE schema
  places -- <action>Config's properties, plus the hand-maintained $ref lists in
  <action>Job and <action>Action -- and a forgotten $ref is invisible.

  Issue #25.
#>

# ---------------------------------------------------------------------------
# DISCOVERY-TIME DATA. Both sides of the contract are read here so the
# per-action cases can be generated with -ForEach. An It block cannot see a
# variable assigned in this script body (Pester runs discovery and execution in
# different scopes), so everything an assertion needs travels INSIDE the case
# hashtables as plain strings rather than as live JSON objects.
# ---------------------------------------------------------------------------

function Get-ResolverActionDefault {
    <#
    .SYNOPSIS
        Reads the $builtInDefaults hashtable literal out of Resolve-DelphiCiConfig.ps1.
    .DESCRIPTION
        Uses the PowerShell parser rather than a regex, and reads the literal
        rather than calling the resolver, so this test needs no production
        change to expose the defaults and cannot be fooled by formatting.

        Returns an ordered map of action name -> @{ Keys; Arrays }, where Arrays
        is the subset of Keys whose default is an array literal. That subset is
        what drives the 'key!' replacement-spelling checks below.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param([Parameter(Mandatory)][string]$Path)

    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)

    $assignments = @($ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $node.Left.Extent.Text -eq '$builtInDefaults'
    }, $true))

    if ($assignments.Count -ne 1) {
        throw "Expected exactly one assignment to `$builtInDefaults in $Path, found $($assignments.Count). This test reads that literal; update it if the resolver's shape changed."
    }

    $table = $assignments[0].Right.Expression
    if ($table -isnot [System.Management.Automation.Language.HashtableAst]) {
        throw "`$builtInDefaults in $Path is no longer a hashtable literal (found $($table.GetType().Name)). This test reads that literal; update it if the resolver's shape changed."
    }

    $map = [ordered]@{}
    foreach ($pair in $table.KeyValuePairs) {
        $action = $pair.Item1.Extent.Text

        # Pre-order search, so the first hashtable found is this action's own
        # block and not a nested one (build's `toolchain = @{ version = ... }`).
        $inner = $pair.Item2.Find({ param($node) $node -is [System.Management.Automation.Language.HashtableAst] }, $false)
        if ($null -eq $inner) {
            throw "Action '$action' in `$builtInDefaults has no hashtable value."
        }

        $keys   = [System.Collections.Generic.List[string]]::new()
        $arrays = [System.Collections.Generic.List[string]]::new()
        foreach ($kv in $inner.KeyValuePairs) {
            $key = $kv.Item1.Extent.Text
            $keys.Add($key)
            $arrayNode = $kv.Item2.Find({
                param($node)
                $node -is [System.Management.Automation.Language.ArrayExpressionAst] -or
                $node -is [System.Management.Automation.Language.ArrayLiteralAst]
            }, $false)
            if ($null -ne $arrayNode) { $arrays.Add($key) }
        }

        $map[$action] = @{ Keys = $keys.ToArray(); Arrays = $arrays.ToArray() }
    }

    return $map
}

function Get-SchemaPropertyName {
    <#
    .SYNOPSIS
        Property names declared by a $defs block, or $null when the block is absent.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]$Defs,
        [Parameter(Mandatory)][string]$DefName
    )

    # The [string[]] casts are what the declared OutputType claims, not decoration:
    # a bare @(...) is Object[], which PSUseOutputTypeCorrectly correctly flagged.
    $def = $Defs.PSObject.Properties[$DefName]
    if ($null -eq $def) { return $null }
    if ($null -eq $def.Value.PSObject.Properties['properties']) { return [string[]]@() }
    return [string[]]@($def.Value.properties.PSObject.Properties.Name)
}

$schemaFile   = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..' 'schemas' 'delphi-ci.schema.json'))
$resolverFile = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..' 'source' 'Private' 'Resolve-DelphiCiConfig.ps1'))

# BOTH SIDES ARE READ DEFENSIVELY, AND THAT IS NOT DEFENSIVENESS FOR ITS OWN SAKE.
# A throw at discovery time does NOT fail the suite. MEASURED: with a trailing comma
# in the schema, Pester reports the container as Result=Failed but FailedCount=0 and
# TotalCount=0, every test in this file silently disappears, and because
# tests/run-tests.ps1 gates on FailedCount the runner still exits 0 -- i.e. the
# malformed schema would ship, which is the exact failure mode this file exists to
# prevent. So each parse captures its error as TEXT and a run-time assertion reports
# it, where it counts as a real failure.
$schemaParseError   = ''
$resolverParseError = ''
$discoveryDefs      = $null
$discoveryParsed    = [ordered]@{}

try {
    $discoveryDefs = ((Get-Content -LiteralPath $schemaFile -Raw) | ConvertFrom-Json -ErrorAction Stop).'$defs'
}
catch {
    $schemaParseError = $_.Exception.Message
}

try {
    $discoveryParsed = Get-ResolverActionDefault -Path $resolverFile
}
catch {
    $resolverParseError = $_.Exception.Message
}

# PERMITTED DIFFERENCES -- an EXPLICIT list, so a new one has to be declared
# deliberately instead of being absorbed by a loose comparison.
#
# Every entry is a key the SCHEMA declares and the resolver's defaults omit ON
# PURPOSE: a required input with no sensible default -- a path or target the
# config author must supply. Defaulting one of these would turn a missing value
# into a silently wrong one, so the resolver leaves it absent and validates it
# where it is used. A key that is NOT on this list and NOT in the resolver's
# defaults is drift: valid in the editor, ignored at runtime.
#
# Adding a key here is a claim that the runtime deliberately ignores it as a
# default. If that is not true, add it to the resolver instead.
$schemaOnlyKeys = @{
    clean     = @('root')                          # the tree to clean; resolved against the config file's dir
    build     = @('projectFile')                   # the project to build
    run       = @('execute')                       # the command line to run
    incver    = @('file')                          # the version file to bump
    copy      = @('source', 'destination')         # what to copy, and where to
    compress  = @('source', 'destination')         # what to archive, and where to
    coverage  = @('execute', 'mapFile')            # the test exe and its .map
    callgraph = @()                                # none: the resolver defaults every callgraph key
    codesign  = @('files', 'filePath')             # what to sign
    format    = @('root')                          # the tree to format; as clean
}

# The structural keys the Job and Action wrappers add on top of their Config.
# 'name' labels a job; 'action'/'jobs' are the pipeline-entry metadata that
# ConvertTo-ActionLayer strips before merging, which is why they are never
# resolver defaults.
$jobOnlyKeys    = @('name')
$actionOnlyKeys = @('action', 'jobs')

$actionCases = @(
    foreach ($action in @(if ($null -ne $discoveryDefs) { $discoveryParsed.Keys } else { @() })) {
        $configProps = Get-SchemaPropertyName -Defs $discoveryDefs -DefName "${action}Config"
        @{
            Action         = $action
            ResolverKeys   = @($discoveryParsed[$action].Keys)
            ResolverArrays = @($discoveryParsed[$action].Arrays)
            ConfigProps    = @($configProps)
            ConfigBase     = @($configProps | Where-Object { -not $_.EndsWith('!') })
            ConfigBangs    = @($configProps | Where-Object { $_.EndsWith('!') } | ForEach-Object { $_.TrimEnd('!') })
            JobProps       = Get-SchemaPropertyName -Defs $discoveryDefs -DefName "${action}Job"
            ActionProps    = Get-SchemaPropertyName -Defs $discoveryDefs -DefName "${action}Action"
            SchemaOnly     = @($schemaOnlyKeys[$action])
            Discriminator  = @($discoveryDefs."${action}Action".properties.action.enum)
            JobOnly        = $jobOnlyKeys
            ActionOnly     = $actionOnlyKeys
        }
    }
)

# The file-level cases. Like the per-action ones these travel through -ForEach:
# a variable assigned in this script body is NOT visible inside an It or a
# BeforeAll, because Pester runs discovery and execution in separate scopes.
$fileCases = @(
    @{
        SchemaFile          = $schemaFile
        ResolverFile        = $resolverFile
        Actions             = @($discoveryParsed.Keys)
        SchemaParseError    = $schemaParseError
        ResolverParseError  = $resolverParseError
        ResolverActionCount = @($discoveryParsed.Keys).Count
        GeneratedCaseCount  = @($actionCases).Count
    }
)

Describe 'delphi-ci.schema.json -- the schema file itself' -ForEach $fileCases {

    It 'parses as JSON' {
        # A trailing-comma edit fails HERE, naming the file, rather than silently in
        # whichever editor opens it next. The error was captured at discovery (see
        # the note above) precisely so this reads as a failed assertion.
        $SchemaParseError | Should -BeNullOrEmpty -Because "schemas/delphi-ci.schema.json is not valid JSON: $SchemaParseError"
    }

    It 'still parses when re-read at run time' {
        $raw = Get-Content -LiteralPath $SchemaFile -Raw
        { $raw | ConvertFrom-Json -ErrorAction Stop } | Should -Not -Throw
    }

    It 'exposes the resolver defaults this file compares against' {
        # If the resolver's $builtInDefaults stops being a readable hashtable
        # literal, every per-action comparison below would generate ZERO cases and
        # the file would go quietly green. This is the assertion that refuses that.
        $ResolverParseError | Should -BeNullOrEmpty -Because "could not read `$builtInDefaults from $ResolverFile : $ResolverParseError"
        $ResolverActionCount | Should -BeGreaterThan 0 -Because 'the resolver must declare at least one action'
    }

    It 'generated a per-action comparison for every action the resolver declares' {
        # The anti-vacuity guard. A malformed schema or resolver makes $actionCases
        # empty, which would otherwise mean every Describe below contains no tests
        # at all -- a green suite that checked nothing.
        $GeneratedCaseCount | Should -Be $ResolverActionCount -Because "the resolver declares $ResolverActionCount actions but only $GeneratedCaseCount per-action comparisons were generated; the rest of this file is not running"
    }

    It 'resolves every local $ref to a node that exists' {
        # A typo'd pointer is not an error in JSON Schema -- it just never
        # validates anything, so the key it guards becomes unchecked. The Job and
        # Action blocks are built almost entirely out of these pointers.
        $raw    = Get-Content -LiteralPath $SchemaFile -Raw
        $schema = $raw | ConvertFrom-Json
        $refs   = [regex]::Matches($raw, '"\$ref"\s*:\s*"([^"]+)"') |
                    ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique

        @($refs).Count | Should -BeGreaterThan 100 -Because 'the Job/Action blocks are built from $refs; a collapse in this count means the regex stopped matching'

        $broken = foreach ($ref in $refs) {
            if ($ref -notlike '#/*') { "$ref (not a local pointer)"; continue }
            $node = $schema
            foreach ($segment in ($ref.Substring(2) -split '/')) {
                $decoded = $segment -replace '~1', '/' -replace '~0', '~'
                if ($null -eq $node -or $null -eq $node.PSObject.Properties[$decoded]) { $node = $null; break }
                $node = $node.PSObject.Properties[$decoded].Value
            }
            if ($null -eq $node) { $ref }
        }

        @($broken) | Should -BeNullOrEmpty -Because "these `$ref pointers resolve to nothing, so whatever they were meant to constrain is unvalidated: $(@($broken) -join ', ')"
    }

}

Describe 'delphi-ci.schema.json -- every action the resolver knows is reachable' -ForEach $fileCases {

    It 'declares a Config, Job and Action block for each one' {
        $schema  = (Get-Content -LiteralPath $SchemaFile -Raw) | ConvertFrom-Json
        $missing = foreach ($action in $Actions) {
            foreach ($suffix in @('Config', 'Job', 'Action')) {
                if ($null -eq $schema.'$defs'.PSObject.Properties["$action$suffix"]) { "$action$suffix" }
            }
        }
        @($missing) | Should -BeNullOrEmpty -Because "the resolver handles these actions but the schema has no block for them: $(@($missing) -join ', ')"
    }

    It 'lists each one under the defaults section' {
        # A missing entry here makes `defaults.<action>` an editor error even
        # though the resolver merges it.
        $schema   = (Get-Content -LiteralPath $SchemaFile -Raw) | ConvertFrom-Json
        $declared = @($schema.properties.defaults.properties.PSObject.Properties.Name)
        $missing  = @($Actions | Where-Object { $_ -notin $declared })
        $extra    = @($declared | Where-Object { $_ -notin $Actions })
        @($missing) | Should -BeNullOrEmpty -Because "absent from defaults: $(@($missing) -join ', ')"
        @($extra)   | Should -BeNullOrEmpty -Because "the schema offers a defaults section the resolver has no action for: $(@($extra) -join ', ')"
    }

    It 'includes each one in the pipelineAction dispatch list' {
        # pipelineAction's oneOf is what makes a pipeline entry validate at all.
        # An action left out of it is rejected outright by an editor.
        $schema   = (Get-Content -LiteralPath $SchemaFile -Raw) | ConvertFrom-Json
        $refs     = @($schema.'$defs'.pipelineAction.oneOf | ForEach-Object { $_.'$ref' })
        $expected = @($Actions | ForEach-Object { "#/`$defs/${_}Action" })
        $missing  = @($expected | Where-Object { $_ -notin $refs })
        $extra    = @($refs | Where-Object { $_ -notin $expected })
        @($missing) | Should -BeNullOrEmpty -Because "not dispatchable in a pipeline: $(@($missing) -join ', ')"
        @($extra)   | Should -BeNullOrEmpty -Because "dispatches an action the resolver does not handle: $(@($extra) -join ', ')"
    }

}

Describe 'delphi-ci.schema.json -- key sets match the resolver, per action' {

    It '<Action>: every resolver default key is declared in <Action>Config' -ForEach $actionCases {
        # The direction that puts a red squiggle on working config: the key is
        # honoured at runtime, and additionalProperties:false rejects it in the editor.
        @($ConfigProps) | Should -Not -BeNullOrEmpty -Because "there is no ${Action}Config block at all"
        $missing = @($ResolverKeys | Where-Object { $_ -notin $ConfigProps })
        @($missing) | Should -BeNullOrEmpty -Because "the resolver defaults these keys but the schema does not declare them, so an editor will flag working config as invalid: $(@($missing) -join ', ')"
    }

    It '<Action>: every <Action>Config property is a resolver default or a declared input key' -ForEach $actionCases {
        # The worse direction: the key completes in the editor and is then
        # ignored at runtime. See $schemaOnlyKeys for what is deliberately absent.
        $unexplained = @($ConfigBase | Where-Object { $_ -notin $ResolverKeys -and $_ -notin $SchemaOnly })
        @($unexplained) | Should -BeNullOrEmpty -Because "the schema accepts these keys but the resolver neither defaults nor declares them, so config using them silently does nothing. Add them to the resolver, or to this test's `$schemaOnlyKeys with a reason: $(@($unexplained) -join ', ')"
    }

    It '<Action>: every key declared schema-only is still in <Action>Config' -ForEach $actionCases {
        # Keeps the allow-list honest. A stale entry would mask a later removal.
        $stale = @($SchemaOnly | Where-Object { $_ -notin $ConfigBase })
        @($stale) | Should -BeNullOrEmpty -Because "this test's `$schemaOnlyKeys claims these are schema-only, but the schema no longer declares them: $(@($stale) -join ', ')"
    }

}

Describe 'delphi-ci.schema.json -- array-replacement spellings, per action' {

    # Merge-ActionConfig appends arrays and treats a 'key!' suffix as "replace
    # instead of append". The base hashtable defines the canonical types, so the
    # set of keys that CAN be appended is exactly the set whose resolver default
    # is an array -- which makes this an exact invariant in both directions, with
    # no exceptions to carve out.
    #
    # Note build's platform/configuration are stringOrStringArray for MATRIX
    # EXPANSION, not append semantics, and their resolver defaults are strings --
    # so they correctly need no '!' spelling, and the rule below excludes them
    # without a special case.

    It '<Action>: every array-valued resolver default has a matching key! spelling' -ForEach $actionCases {
        $missing = @($ResolverArrays | Where-Object { $_ -notin $ConfigBangs })
        @($missing) | Should -BeNullOrEmpty -Because "these keys append by default and the schema offers no way to spell the replacement: $(@($missing | ForEach-Object { "$_!" }) -join ', ')"
    }

    It '<Action>: every key! spelling corresponds to an array-valued resolver default' -ForEach $actionCases {
        $extra = @($ConfigBangs | Where-Object { $_ -notin $ResolverArrays })
        @($extra) | Should -BeNullOrEmpty -Because "the schema offers a replacement spelling for keys the resolver does not hold as arrays, where '!' does nothing useful: $(@($extra | ForEach-Object { "$_!" }) -join ', ')"
    }

}

Describe 'delphi-ci.schema.json -- the Job and Action $ref lists are complete' {

    # THE DEFECT #25 IS REALLY ABOUT. <action>Job and <action>Action do not
    # inherit from <action>Config -- they re-list every property as an explicit
    # $ref. A key added to Config and not to both lists is accepted in
    # defaults.<action> and rejected on the pipeline entry or job that actually
    # needs it, which reads as the schema being wrong about valid config.

    It '<Action>Job lists exactly <Action>Config plus name' -ForEach $actionCases {
        @($JobProps) | Should -Not -BeNullOrEmpty -Because "there is no ${Action}Job block at all"
        $expected = @($ConfigProps) + @($JobOnly)
        $missing  = @($expected | Where-Object { $_ -notin $JobProps })
        $extra    = @($JobProps | Where-Object { $_ -notin $expected })
        @($missing) | Should -BeNullOrEmpty -Because "${Action}Job is missing a `$ref for these, so a job cannot set them: $(@($missing) -join ', ')"
        @($extra)   | Should -BeNullOrEmpty -Because "${Action}Job accepts these but ${Action}Config does not declare them: $(@($extra) -join ', ')"
    }

    It '<Action>Action lists exactly <Action>Config plus action and jobs' -ForEach $actionCases {
        @($ActionProps) | Should -Not -BeNullOrEmpty -Because "there is no ${Action}Action block at all"
        $expected = @($ConfigProps) + @($ActionOnly)
        $missing  = @($expected | Where-Object { $_ -notin $ActionProps })
        $extra    = @($ActionProps | Where-Object { $_ -notin $expected })
        @($missing) | Should -BeNullOrEmpty -Because "${Action}Action is missing a `$ref for these, so an action-level default cannot set them: $(@($missing) -join ', ')"
        @($extra)   | Should -BeNullOrEmpty -Because "${Action}Action accepts these but ${Action}Config does not declare them: $(@($extra) -join ', ')"
    }

    It '<Action>Action.action is the pipeline discriminator' -ForEach $actionCases {
        # codesign is why this is checked: codesignConfig has its OWN 'action'
        # key (Sign/Verify), so the two meanings collide on exactly one block.
        # ConvertTo-ActionLayer strips 'action' before merging, so at the action
        # level it must be the pipeline name -- if it were wired to the Config
        # $ref instead, `{"action": "Codesign"}` would be invalid against its own
        # schema.
        @($Discriminator) | Should -Not -BeNullOrEmpty -Because "${Action}Action.action must be an enum of the pipeline action name, not a `$ref into ${Action}Config"
        @($Discriminator) | Should -Contain $Action -Because "the enum should accept the lowercase action name; got: $(@($Discriminator) -join ', ')"
    }

}
