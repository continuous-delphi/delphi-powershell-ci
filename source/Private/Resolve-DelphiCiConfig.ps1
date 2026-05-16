function Resolve-DelphiCiConfig {
    [CmdletBinding()]
    param(
        [string]$ConfigFile,
        [hashtable]$Overrides = @{}
    )

    # -------------------------------------------------------------------------
    # Built-in defaults (keyed by action type)
    # -------------------------------------------------------------------------
    $builtInDefaults = @{
        clean = @{
            level                   = 'basic'
            outputLevel             = 'detailed'
            includeFilePattern      = @()
            excludeDirectoryPattern = @()
            configFile              = ''
            recycleBin              = $false
            check                   = $false
        }
        build = @{
            engine         = 'MSBuild'
            toolchain      = @{ version = 'Latest' }
            platform       = 'Win32'
            configuration  = 'Debug'
            defines        = @()
            verbosity      = 'normal'
            target         = 'Build'
            exeOutputDir   = ''
            dcuOutputDir   = ''
            unitSearchPath = @()
            includePath    = @()
            namespace      = @()
        }
        run = @{
            timeoutSeconds = 10
            arguments      = @()
        }
        incver = @{
            target     = ''
            style      = ''
            part       = ''
            pattern    = ''
            dateformat = 'yyyy.mm.dd'
        }
        copy = @{
            flatten           = $false
            overwrite         = $true
            createDestination = $true
            checksum          = $false
        }
        compress = @{
            overwrite = $true
            checksum  = $false
        }
        coverage = @{
            engine         = 'DelphiCodeCoverage'
            enginePath     = ''
            dproj          = ''
            sourceDir      = @()
            units          = @()
            excludeUnits   = @()
            outputDir      = 'coverage'
            formats        = @('html')
            threshold      = 0
            arguments      = @()
            timeoutSeconds = 300
            badge          = ''
        }
        callgraph = @{
            path              = @()
            engine            = 'radCallGraph'
            enginePath        = ''
            outputDir         = 'callgraph'
            formats           = @('json')
            jsonFile          = ''
            dotFile           = ''
            summaryFile       = ''
            class             = ''
            annotations       = $true
            deterministic     = $true
            graphKind         = ''
            graphVizUses      = $false
            graphVizClasses   = $false
            pasDocOptions     = @()
            projectFile       = ''
            graphVizExclude   = @()
            engineArguments   = @()
            timeoutSeconds    = 300
        }
    }

    # -------------------------------------------------------------------------
    # Load JSON config file
    # -------------------------------------------------------------------------
    $root      = $null
    $json      = $null
    $configDir = $null

    if ($ConfigFile) {
        $cfgItem   = Get-Item -LiteralPath $ConfigFile -ErrorAction Stop
        $configDir = $cfgItem.DirectoryName
        $json      = Get-Content -LiteralPath $cfgItem.FullName -Raw -ErrorAction Stop |
                     ConvertFrom-Json

        if ($json.PSObject.Properties['root'] -and
            -not [string]::IsNullOrWhiteSpace($json.root)) {
            $root = Join-Path $configDir $json.root
        } else {
            $root = $configDir
        }
    }

    # -------------------------------------------------------------------------
    # Merge JSON "defaults" section onto built-in defaults
    # -------------------------------------------------------------------------
    $effectiveDefaults = @{}
    foreach ($actionType in $builtInDefaults.Keys) {
        $effectiveDefaults[$actionType] = $builtInDefaults[$actionType].Clone()
    }

    if ($null -ne $json -and $json.PSObject.Properties['defaults']) {
        $jsonDefaults = $json.defaults
        foreach ($actionType in $builtInDefaults.Keys) {
            if ($jsonDefaults.PSObject.Properties[$actionType]) {
                $layer = ConvertTo-Hashtable $jsonDefaults.$actionType
                $effectiveDefaults[$actionType] = Merge-ActionConfig `
                    -Base  $effectiveDefaults[$actionType] `
                    -Layer $layer
            }
        }
    }

    # -------------------------------------------------------------------------
    # Legacy format support: convert old "steps" + named sections to pipeline
    # -------------------------------------------------------------------------
    $pipeline = $null

    if ($null -ne $json -and $json.PSObject.Properties['pipeline']) {
        # New format: pipeline array
        $pipeline = @($json.pipeline)
    }
    elseif ($null -ne $json) {
        # Old format (or no pipeline key): named sections (clean/build/test)
        # Section properties become defaults (so CLI can override them);
        # only jobs go into the pipeline entries.
        # CLI -Steps overrides which steps are included.
        $legacySteps = $null
        if ($Overrides.ContainsKey('Steps') -and $null -ne $Overrides['Steps']) {
            $legacySteps = @($Overrides['Steps'] | ForEach-Object { $_ -split ',' } |
                            ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
        }
        $legacyResult = ConvertFrom-LegacyConfig -Json $json -StepsOverride $legacySteps
        $pipeline = $legacyResult.Pipeline
        foreach ($actionType in $legacyResult.SectionDefaults.Keys) {
            $layer = $legacyResult.SectionDefaults[$actionType]
            if ($layer.Count -gt 0) {
                $effectiveDefaults[$actionType] = Merge-ActionConfig `
                    -Base  $effectiveDefaults[$actionType] `
                    -Layer $layer
            }
        }
    }

    # -------------------------------------------------------------------------
    # Apply CLI overrides into effective defaults
    # -------------------------------------------------------------------------
    if ($Overrides.ContainsKey('Root') -and
        -not [string]::IsNullOrWhiteSpace($Overrides['Root'])) {
        $root = $Overrides['Root']
    }

    # Clean CLI overrides
    $cleanCliLayer = @{}
    if ($Overrides.ContainsKey('CleanLevel') -and
        -not [string]::IsNullOrWhiteSpace($Overrides['CleanLevel']))             { $cleanCliLayer['level']        = $Overrides['CleanLevel'] }
    if ($Overrides.ContainsKey('CleanOutputLevel') -and
        -not [string]::IsNullOrWhiteSpace($Overrides['CleanOutputLevel']))       { $cleanCliLayer['outputLevel']  = $Overrides['CleanOutputLevel'] }
    if ($Overrides.ContainsKey('CleanIncludeFilePattern') -and
        $null -ne $Overrides['CleanIncludeFilePattern'])                         { $cleanCliLayer['includeFilePattern!'] = @($Overrides['CleanIncludeFilePattern']) }
    if ($Overrides.ContainsKey('CleanExcludeDirectoryPattern') -and
        $null -ne $Overrides['CleanExcludeDirectoryPattern'])                    { $cleanCliLayer['excludeDirectoryPattern!'] = @($Overrides['CleanExcludeDirectoryPattern']) }
    if ($Overrides.ContainsKey('CleanConfigFile') -and
        -not [string]::IsNullOrWhiteSpace($Overrides['CleanConfigFile']))        { $cleanCliLayer['configFile']   = $Overrides['CleanConfigFile'] }
    if ($Overrides.ContainsKey('CleanRecycleBin') -and
        $null -ne $Overrides['CleanRecycleBin'])                                 { $cleanCliLayer['recycleBin']   = [bool]$Overrides['CleanRecycleBin'] }
    if ($Overrides.ContainsKey('CleanCheck') -and
        $null -ne $Overrides['CleanCheck'])                                      { $cleanCliLayer['check']        = [bool]$Overrides['CleanCheck'] }
    if ($cleanCliLayer.Count -gt 0) {
        $effectiveDefaults['clean'] = Merge-ActionConfig -Base $effectiveDefaults['clean'] -Layer $cleanCliLayer
    }

    # Build CLI overrides
    $buildCliLayer = @{}
    if ($Overrides.ContainsKey('BuildEngine') -and
        -not [string]::IsNullOrWhiteSpace($Overrides['BuildEngine']))            { $buildCliLayer['engine']       = $Overrides['BuildEngine'] }
    if ($Overrides.ContainsKey('Toolchain') -and
        -not [string]::IsNullOrWhiteSpace($Overrides['Toolchain']))              { $buildCliLayer['toolchain']    = @{ version = $Overrides['Toolchain'] } }
    if ($Overrides.ContainsKey('Platform') -and
        -not [string]::IsNullOrWhiteSpace($Overrides['Platform']))               { $buildCliLayer['platform']     = $Overrides['Platform'] }
    if ($Overrides.ContainsKey('Configuration') -and
        -not [string]::IsNullOrWhiteSpace($Overrides['Configuration']))          { $buildCliLayer['configuration'] = $Overrides['Configuration'] }
    if ($Overrides.ContainsKey('Defines') -and $null -ne $Overrides['Defines']) {
        $buildCliLayer['defines!'] = @($Overrides['Defines'] | ForEach-Object { $_ -split ',' } |
                                       ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
    }
    if ($Overrides.ContainsKey('BuildVerbosity') -and
        -not [string]::IsNullOrWhiteSpace($Overrides['BuildVerbosity']))         { $buildCliLayer['verbosity']    = $Overrides['BuildVerbosity'] }
    if ($Overrides.ContainsKey('BuildTarget') -and
        -not [string]::IsNullOrWhiteSpace($Overrides['BuildTarget']))            { $buildCliLayer['target']       = $Overrides['BuildTarget'] }
    if ($Overrides.ContainsKey('ExeOutputDir') -and
        -not [string]::IsNullOrWhiteSpace($Overrides['ExeOutputDir']))           { $buildCliLayer['exeOutputDir'] = $Overrides['ExeOutputDir'] }
    if ($Overrides.ContainsKey('DcuOutputDir') -and
        -not [string]::IsNullOrWhiteSpace($Overrides['DcuOutputDir']))           { $buildCliLayer['dcuOutputDir'] = $Overrides['DcuOutputDir'] }
    if ($Overrides.ContainsKey('UnitSearchPath') -and
        $null -ne $Overrides['UnitSearchPath'])                                  { $buildCliLayer['unitSearchPath!'] = @($Overrides['UnitSearchPath']) }
    if ($Overrides.ContainsKey('IncludePath') -and
        $null -ne $Overrides['IncludePath'])                                     { $buildCliLayer['includePath!'] = @($Overrides['IncludePath']) }
    if ($Overrides.ContainsKey('Namespace') -and
        $null -ne $Overrides['Namespace'])                                       { $buildCliLayer['namespace!']   = @($Overrides['Namespace']) }
    if ($buildCliLayer.Count -gt 0) {
        $effectiveDefaults['build'] = Merge-ActionConfig -Base $effectiveDefaults['build'] -Layer $buildCliLayer
    }

    # Run CLI overrides
    $runCliLayer = @{}
    if ($Overrides.ContainsKey('RunTimeoutSeconds') -and
        $null -ne $Overrides['RunTimeoutSeconds'])                               { $runCliLayer['timeoutSeconds'] = [int]$Overrides['RunTimeoutSeconds'] }
    if ($Overrides.ContainsKey('RunArguments') -and
        $null -ne $Overrides['RunArguments'])                                    { $runCliLayer['arguments!']    = @($Overrides['RunArguments']) }
    if ($runCliLayer.Count -gt 0) {
        $effectiveDefaults['run'] = Merge-ActionConfig -Base $effectiveDefaults['run'] -Layer $runCliLayer
    }

    # IncVer CLI overrides
    $incverCliLayer = @{}
    if ($Overrides.ContainsKey('IncverTarget') -and
        -not [string]::IsNullOrWhiteSpace($Overrides['IncverTarget']))     { $incverCliLayer['target']     = $Overrides['IncverTarget'] }
    if ($Overrides.ContainsKey('IncverStyle') -and
        -not [string]::IsNullOrWhiteSpace($Overrides['IncverStyle']))      { $incverCliLayer['style']      = $Overrides['IncverStyle'] }
    if ($Overrides.ContainsKey('IncverPart') -and
        -not [string]::IsNullOrWhiteSpace($Overrides['IncverPart']))       { $incverCliLayer['part']       = $Overrides['IncverPart'] }
    if ($Overrides.ContainsKey('IncverPattern') -and
        -not [string]::IsNullOrWhiteSpace($Overrides['IncverPattern']))    { $incverCliLayer['pattern']    = $Overrides['IncverPattern'] }
    if ($Overrides.ContainsKey('IncverDateformat') -and
        -not [string]::IsNullOrWhiteSpace($Overrides['IncverDateformat'])) { $incverCliLayer['dateformat'] = $Overrides['IncverDateformat'] }
    if ($incverCliLayer.Count -gt 0) {
        $effectiveDefaults['incver'] = Merge-ActionConfig -Base $effectiveDefaults['incver'] -Layer $incverCliLayer
    }

    # Copy CLI overrides
    $copyCliLayer = @{}
    if ($Overrides.ContainsKey('CopyFlatten') -and
        $null -ne $Overrides['CopyFlatten'])                             { $copyCliLayer['flatten']           = [bool]$Overrides['CopyFlatten'] }
    if ($Overrides.ContainsKey('CopyOverwrite') -and
        $null -ne $Overrides['CopyOverwrite'])                           { $copyCliLayer['overwrite']         = [bool]$Overrides['CopyOverwrite'] }
    if ($Overrides.ContainsKey('CopyCreateDestination') -and
        $null -ne $Overrides['CopyCreateDestination'])                   { $copyCliLayer['createDestination'] = [bool]$Overrides['CopyCreateDestination'] }
    if ($Overrides.ContainsKey('CopyChecksum') -and
        $null -ne $Overrides['CopyChecksum'])                            { $copyCliLayer['checksum']          = [bool]$Overrides['CopyChecksum'] }
    if ($copyCliLayer.Count -gt 0) {
        $effectiveDefaults['copy'] = Merge-ActionConfig -Base $effectiveDefaults['copy'] -Layer $copyCliLayer
    }

    # Compress CLI overrides
    $compressCliLayer = @{}
    if ($Overrides.ContainsKey('CompressOverwrite') -and
        $null -ne $Overrides['CompressOverwrite'])                       { $compressCliLayer['overwrite'] = [bool]$Overrides['CompressOverwrite'] }
    if ($Overrides.ContainsKey('CompressChecksum') -and
        $null -ne $Overrides['CompressChecksum'])                        { $compressCliLayer['checksum']  = [bool]$Overrides['CompressChecksum'] }
    if ($compressCliLayer.Count -gt 0) {
        $effectiveDefaults['compress'] = Merge-ActionConfig -Base $effectiveDefaults['compress'] -Layer $compressCliLayer
    }

    # Coverage CLI overrides
    $coverageCliLayer = @{}
    if ($Overrides.ContainsKey('CoverageEngine') -and
        -not [string]::IsNullOrWhiteSpace($Overrides['CoverageEngine']))           { $coverageCliLayer['engine']         = $Overrides['CoverageEngine'] }
    if ($Overrides.ContainsKey('CoverageEnginePath') -and
        -not [string]::IsNullOrWhiteSpace($Overrides['CoverageEnginePath']))       { $coverageCliLayer['enginePath']     = $Overrides['CoverageEnginePath'] }
    if ($Overrides.ContainsKey('CoverageDproj') -and
        -not [string]::IsNullOrWhiteSpace($Overrides['CoverageDproj']))            { $coverageCliLayer['dproj']          = $Overrides['CoverageDproj'] }
    if ($Overrides.ContainsKey('CoverageSourceDir') -and
        $null -ne $Overrides['CoverageSourceDir'])                                 { $coverageCliLayer['sourceDir!']     = @($Overrides['CoverageSourceDir']) }
    if ($Overrides.ContainsKey('CoverageUnits') -and
        $null -ne $Overrides['CoverageUnits'])                                     { $coverageCliLayer['units!']         = @($Overrides['CoverageUnits']) }
    if ($Overrides.ContainsKey('CoverageExcludeUnits') -and
        $null -ne $Overrides['CoverageExcludeUnits'])                              { $coverageCliLayer['excludeUnits!']  = @($Overrides['CoverageExcludeUnits']) }
    if ($Overrides.ContainsKey('CoverageOutputDir') -and
        -not [string]::IsNullOrWhiteSpace($Overrides['CoverageOutputDir']))        { $coverageCliLayer['outputDir']      = $Overrides['CoverageOutputDir'] }
    if ($Overrides.ContainsKey('CoverageFormats') -and
        $null -ne $Overrides['CoverageFormats'])                                   { $coverageCliLayer['formats!']       = @($Overrides['CoverageFormats']) }
    if ($Overrides.ContainsKey('CoverageThreshold') -and
        $null -ne $Overrides['CoverageThreshold'])                                 { $coverageCliLayer['threshold']      = [int]$Overrides['CoverageThreshold'] }
    if ($Overrides.ContainsKey('CoverageTimeoutSeconds') -and
        $null -ne $Overrides['CoverageTimeoutSeconds'])                            { $coverageCliLayer['timeoutSeconds'] = [int]$Overrides['CoverageTimeoutSeconds'] }
    if ($Overrides.ContainsKey('CoverageBadge') -and
        -not [string]::IsNullOrWhiteSpace($Overrides['CoverageBadge']))            { $coverageCliLayer['badge']          = $Overrides['CoverageBadge'] }
    if ($coverageCliLayer.Count -gt 0) {
        $effectiveDefaults['coverage'] = Merge-ActionConfig -Base $effectiveDefaults['coverage'] -Layer $coverageCliLayer
    }

    # CallGraph CLI overrides
    $callGraphCliLayer = @{}
    if ($Overrides.ContainsKey('CallGraphPath') -and
        $null -ne $Overrides['CallGraphPath'])                                      { $callGraphCliLayer['path!']            = @($Overrides['CallGraphPath']) }
    if ($Overrides.ContainsKey('CallGraphEngine') -and
        -not [string]::IsNullOrWhiteSpace($Overrides['CallGraphEngine']))           { $callGraphCliLayer['engine']           = $Overrides['CallGraphEngine'] }
    if ($Overrides.ContainsKey('CallGraphEnginePath') -and
        -not [string]::IsNullOrWhiteSpace($Overrides['CallGraphEnginePath']))       { $callGraphCliLayer['enginePath']       = $Overrides['CallGraphEnginePath'] }
    if ($Overrides.ContainsKey('CallGraphOutputDir') -and
        -not [string]::IsNullOrWhiteSpace($Overrides['CallGraphOutputDir']))        { $callGraphCliLayer['outputDir']        = $Overrides['CallGraphOutputDir'] }
    if ($Overrides.ContainsKey('CallGraphFormats') -and
        $null -ne $Overrides['CallGraphFormats'])                                   { $callGraphCliLayer['formats!']         = @($Overrides['CallGraphFormats']) }
    if ($Overrides.ContainsKey('CallGraphJsonFile') -and
        -not [string]::IsNullOrWhiteSpace($Overrides['CallGraphJsonFile']))         { $callGraphCliLayer['jsonFile']         = $Overrides['CallGraphJsonFile'] }
    if ($Overrides.ContainsKey('CallGraphDotFile') -and
        -not [string]::IsNullOrWhiteSpace($Overrides['CallGraphDotFile']))          { $callGraphCliLayer['dotFile']          = $Overrides['CallGraphDotFile'] }
    if ($Overrides.ContainsKey('CallGraphSummaryFile') -and
        -not [string]::IsNullOrWhiteSpace($Overrides['CallGraphSummaryFile']))      { $callGraphCliLayer['summaryFile']      = $Overrides['CallGraphSummaryFile'] }
    if ($Overrides.ContainsKey('CallGraphClass') -and
        -not [string]::IsNullOrWhiteSpace($Overrides['CallGraphClass']))            { $callGraphCliLayer['class']            = $Overrides['CallGraphClass'] }
    if ($Overrides.ContainsKey('CallGraphAnnotations') -and
        $null -ne $Overrides['CallGraphAnnotations'])                               { $callGraphCliLayer['annotations']      = [bool]$Overrides['CallGraphAnnotations'] }
    if ($Overrides.ContainsKey('CallGraphDeterministic') -and
        $null -ne $Overrides['CallGraphDeterministic'])                              { $callGraphCliLayer['deterministic']    = [bool]$Overrides['CallGraphDeterministic'] }
    if ($Overrides.ContainsKey('CallGraphGraphKind') -and
        -not [string]::IsNullOrWhiteSpace($Overrides['CallGraphGraphKind']))        { $callGraphCliLayer['graphKind']        = $Overrides['CallGraphGraphKind'] }
    if ($Overrides.ContainsKey('CallGraphGraphVizUses') -and
        $null -ne $Overrides['CallGraphGraphVizUses'])                              { $callGraphCliLayer['graphVizUses']     = [bool]$Overrides['CallGraphGraphVizUses'] }
    if ($Overrides.ContainsKey('CallGraphGraphVizClasses') -and
        $null -ne $Overrides['CallGraphGraphVizClasses'])                           { $callGraphCliLayer['graphVizClasses']  = [bool]$Overrides['CallGraphGraphVizClasses'] }
    if ($Overrides.ContainsKey('CallGraphPasDocOptions') -and
        $null -ne $Overrides['CallGraphPasDocOptions'])                             { $callGraphCliLayer['pasDocOptions!']   = @($Overrides['CallGraphPasDocOptions']) }
    if ($Overrides.ContainsKey('CallGraphProjectFile') -and
        -not [string]::IsNullOrWhiteSpace($Overrides['CallGraphProjectFile']))      { $callGraphCliLayer['projectFile']      = $Overrides['CallGraphProjectFile'] }
    if ($Overrides.ContainsKey('CallGraphGraphVizExclude') -and
        $null -ne $Overrides['CallGraphGraphVizExclude'])                           { $callGraphCliLayer['graphVizExclude!'] = @($Overrides['CallGraphGraphVizExclude']) }
    if ($Overrides.ContainsKey('CallGraphEngineArguments') -and
        $null -ne $Overrides['CallGraphEngineArguments'])                           { $callGraphCliLayer['engineArguments!'] = @($Overrides['CallGraphEngineArguments']) }
    if ($Overrides.ContainsKey('CallGraphTimeoutSeconds') -and
        $null -ne $Overrides['CallGraphTimeoutSeconds'])                            { $callGraphCliLayer['timeoutSeconds']   = [int]$Overrides['CallGraphTimeoutSeconds'] }
    if ($callGraphCliLayer.Count -gt 0) {
        $effectiveDefaults['callgraph'] = Merge-ActionConfig -Base $effectiveDefaults['callgraph'] -Layer $callGraphCliLayer
    }

    # -------------------------------------------------------------------------
    # Generate pipeline from CLI params if no pipeline was loaded from JSON
    # -------------------------------------------------------------------------
    if ($null -eq $pipeline) {
        $pipeline = Build-CliPipeline -Overrides $Overrides
    }

    # -------------------------------------------------------------------------
    # Resolve root to an absolute path
    # -------------------------------------------------------------------------
    if ($null -eq $root) {
        $root = (Get-Location).Path
    } elseif (-not [System.IO.Path]::IsPathRooted($root)) {
        $root = Join-Path (Get-Location).Path $root
    }
    $root = [System.IO.Path]::GetFullPath($root)

    # -------------------------------------------------------------------------
    # Resolve each pipeline entry: merge defaults -> action-level -> job-level
    # -------------------------------------------------------------------------
    $resolvedPipeline = [System.Collections.Generic.List[object]]::new()

    foreach ($entry in $pipeline) {
        $actionName = $entry.action
        if ([string]::IsNullOrWhiteSpace($actionName)) {
            throw "Pipeline entry missing 'action' property."
        }

        $actionType = $actionName.ToLower()
        $base = if ($effectiveDefaults.ContainsKey($actionType)) {
            $effectiveDefaults[$actionType]
        } else {
            @{}
        }

        # Extract action-level properties (everything except 'action' and 'jobs')
        $actionLayer = ConvertTo-ActionLayer $entry

        # Merge base + action-level to produce action defaults
        $actionDefaults = Merge-ActionConfig -Base $base -Layer $actionLayer

        # Validate action defaults for known action types
        switch ($actionType) {
            'clean'    { Assert-CleanConfig    $actionDefaults }
            'build'    { Assert-BuildConfig    $actionDefaults }
            'incver'   { Assert-IncverConfig   $actionDefaults }
            'copy'     { Assert-CopyConfig     $actionDefaults }
            'compress' { Assert-CompressConfig $actionDefaults }
            'coverage' { Assert-CoverageConfig $actionDefaults }
            'callgraph' { Assert-CallGraphConfig $actionDefaults }
        }

        # Resolve jobs
        $rawJobs = @()
        if ($entry.PSObject.Properties['jobs'] -and $null -ne $entry.jobs) {
            $rawJobs = @($entry.jobs)
        }

        $resolvedJobs = [System.Collections.Generic.List[object]]::new()
        foreach ($rawJob in $rawJobs) {
            $jobLayer = ConvertTo-Hashtable $rawJob
            # Remove 'name' from the merge layer -- it's metadata, not config
            $jobName = ''
            if ($jobLayer.ContainsKey('name')) {
                $jobName = $jobLayer['name']
                $jobLayer.Remove('name')
            }

            $resolved = Merge-ActionConfig -Base $actionDefaults -Layer $jobLayer
            $resolved['name'] = $jobName

            # Normalize platform/configuration to arrays for build jobs (matrix expansion)
            if ($actionType -eq 'build') {
                $resolved['platform']      = @($resolved['platform'])
                $resolved['configuration'] = @($resolved['configuration'])
            }

            $resolvedJobs.Add($resolved)
        }

        # Build the action defaults output object (for orchestrator fallback when no jobs)
        $actionDefaultsOutput = $actionDefaults.Clone()
        if ($actionType -eq 'clean' -and -not $actionDefaultsOutput.ContainsKey('root')) {
            $actionDefaultsOutput['root'] = $root
        }

        $resolvedPipeline.Add([PSCustomObject]@{
            Action   = $actionName
            Defaults = $actionDefaultsOutput
            Jobs     = $resolvedJobs.ToArray()
        })
    }

    # -------------------------------------------------------------------------
    # Return the resolved configuration
    # -------------------------------------------------------------------------
    return [PSCustomObject]@{
        Root     = $root
        Pipeline = $resolvedPipeline.ToArray()
    }
}

# =============================================================================
# Private helpers (scoped to this file, loaded into module scope)
# =============================================================================

function ConvertTo-Hashtable {
    <#
    .SYNOPSIS
        Converts a PSCustomObject (from ConvertFrom-Json) to a hashtable.
    #>
    param([Parameter(Mandatory)] $InputObject)

    if ($InputObject -is [hashtable]) { return $InputObject }

    $ht = @{}
    foreach ($prop in $InputObject.PSObject.Properties) {
        $val = $prop.Value
        if ($null -ne $val -and $val.GetType().Name -eq 'PSCustomObject') {
            $val = ConvertTo-Hashtable $val
        }
        elseif ($null -ne $val -and $val -is [object[]]) {
            # Normalize JSON arrays: convert any nested PSCustomObjects
            $val = @($val | ForEach-Object {
                if ($null -ne $_ -and $_.GetType().Name -eq 'PSCustomObject') {
                    ConvertTo-Hashtable $_
                } else { $_ }
            })
        }
        $ht[$prop.Name] = $val
    }
    return $ht
}

function ConvertTo-ActionLayer {
    <#
    .SYNOPSIS
        Extracts action-level config properties from a pipeline entry,
        excluding 'action' and 'jobs' metadata keys.
    #>
    param([Parameter(Mandatory)] $Entry)

    $ht = @{}
    foreach ($prop in $Entry.PSObject.Properties) {
        if ($prop.Name -eq 'action' -or $prop.Name -eq 'jobs') { continue }
        $val = $prop.Value
        if ($null -ne $val -and $val.GetType().Name -eq 'PSCustomObject') {
            $val = ConvertTo-Hashtable $val
        }
        elseif ($null -ne $val -and $val -is [object[]]) {
            $val = @($val | ForEach-Object {
                if ($null -ne $_ -and $_.GetType().Name -eq 'PSCustomObject') {
                    ConvertTo-Hashtable $_
                } else { $_ }
            })
        }
        $ht[$prop.Name] = $val
    }
    return $ht
}

function ConvertFrom-LegacyConfig {
    <#
    .SYNOPSIS
        Converts old-format JSON (with "steps" + named sections) to a
        pipeline array and extracted section defaults.
    .DESCRIPTION
        Returns a hashtable with:
        - Pipeline: array of action entries (action + jobs only)
        - SectionDefaults: hashtable keyed by action type with section
          properties (excluding jobs) to merge into effective defaults
    #>
    param(
        [Parameter(Mandatory)] $Json,
        [string[]]$StepsOverride = $null
    )

    $steps = @('Clean', 'Build')
    if ($null -ne $StepsOverride -and $StepsOverride.Count -gt 0) {
        $steps = $StepsOverride
    }
    elseif ($Json.PSObject.Properties['steps']) {
        $steps = @($Json.steps)
    }

    # Map legacy step/section names to current action types
    $legacyActionMap  = @{ test = 'Run' }
    $legacySectionMap = @{ test = 'run' }

    # Map legacy job property names to current names
    $legacyJobPropertyMap = @{ testExeFile = 'execute' }

    $pipeline        = [System.Collections.Generic.List[object]]::new()
    $sectionDefaults = @{}

    foreach ($stepName in $steps) {
        $sectionKey = $stepName.ToLower()
        $actionName = if ($legacyActionMap.ContainsKey($sectionKey)) { $legacyActionMap[$sectionKey] } else { $stepName }
        $defaultsKey = if ($legacySectionMap.ContainsKey($sectionKey)) { $legacySectionMap[$sectionKey] } else { $sectionKey }
        $entry = @{ action = $actionName }
        $sectionDefaults[$defaultsKey] = @{}

        if ($Json.PSObject.Properties[$sectionKey]) {
            $section = $Json.$sectionKey
            foreach ($prop in $section.PSObject.Properties) {
                if ($prop.Name -eq 'jobs') {
                    # Remap legacy job property names
                    $entry['jobs'] = @($prop.Value | ForEach-Object {
                        $job = $_
                        foreach ($oldName in $legacyJobPropertyMap.Keys) {
                            if ($job.PSObject.Properties[$oldName]) {
                                $newName = $legacyJobPropertyMap[$oldName]
                                $job | Add-Member -NotePropertyName $newName -NotePropertyValue $job.$oldName -Force
                                $job.PSObject.Properties.Remove($oldName)
                            }
                        }
                        $job
                    })
                } else {
                    $val = $prop.Value
                    if ($null -ne $val -and $val.GetType().Name -eq 'PSCustomObject') {
                        $val = ConvertTo-Hashtable $val
                    }
                    $sectionDefaults[$defaultsKey][$prop.Name] = $val
                }
            }
        }

        $pipeline.Add([PSCustomObject]$entry)
    }

    return @{
        Pipeline        = $pipeline.ToArray()
        SectionDefaults = $sectionDefaults
    }
}

function Build-CliPipeline {
    <#
    .SYNOPSIS
        Generates a pipeline array from CLI override parameters when no
        config file pipeline is present.
    #>
    param([hashtable]$Overrides)

    $pipeline = [System.Collections.Generic.List[object]]::new()

    # Determine which actions to include
    $steps = @('Clean', 'Build')
    if ($Overrides.ContainsKey('Steps') -and $null -ne $Overrides['Steps']) {
        $steps = @($Overrides['Steps'] | ForEach-Object { $_ -split ',' } |
                   ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
    }

    foreach ($stepName in $steps) {
        $entry = @{ action = $stepName }

        # If CLI provides a project file, inject it as a single build job
        if ($stepName -eq 'Build' -and $Overrides.ContainsKey('ProjectFile') -and
            -not [string]::IsNullOrWhiteSpace($Overrides['ProjectFile'])) {
            $entry['jobs'] = @([PSCustomObject]@{ projectFile = $Overrides['ProjectFile'] })
        }

        # If CLI provides an execute target, inject it as a single run job
        if ($stepName -eq 'Run' -and $Overrides.ContainsKey('Execute') -and
            -not [string]::IsNullOrWhiteSpace($Overrides['Execute'])) {
            $entry['jobs'] = @([PSCustomObject]@{ execute = $Overrides['Execute'] })
        }

        # If CLI provides a version file, inject it as a single incver job
        if ($stepName -eq 'IncVer' -and $Overrides.ContainsKey('IncverFile') -and
            -not [string]::IsNullOrWhiteSpace($Overrides['IncverFile'])) {
            $entry['jobs'] = @([PSCustomObject]@{ file = $Overrides['IncverFile'] })
        }

        # If CLI provides copy source/destination, inject as a single copy job
        if ($stepName -eq 'Copy' -and $Overrides.ContainsKey('CopySource') -and
            -not [string]::IsNullOrWhiteSpace($Overrides['CopySource'])) {
            $copyJob = @{ source = $Overrides['CopySource'] }
            if ($Overrides.ContainsKey('CopyDestination') -and
                -not [string]::IsNullOrWhiteSpace($Overrides['CopyDestination'])) {
                $copyJob['destination'] = $Overrides['CopyDestination']
            }
            $entry['jobs'] = @([PSCustomObject]$copyJob)
        }

        # If CLI provides compress source/destination, inject as a single compress job
        if ($stepName -eq 'Compress' -and $Overrides.ContainsKey('CompressSource') -and
            -not [string]::IsNullOrWhiteSpace($Overrides['CompressSource'])) {
            $compressJob = @{ source = $Overrides['CompressSource'] }
            if ($Overrides.ContainsKey('CompressDestination') -and
                -not [string]::IsNullOrWhiteSpace($Overrides['CompressDestination'])) {
                $compressJob['destination'] = $Overrides['CompressDestination']
            }
            $entry['jobs'] = @([PSCustomObject]$compressJob)
        }

        # If CLI provides coverage dproj or execute/mapfile, inject as a single coverage job
        if ($stepName -eq 'Coverage') {
            if ($Overrides.ContainsKey('CoverageDproj') -and
                -not [string]::IsNullOrWhiteSpace($Overrides['CoverageDproj'])) {
                $coverageJob = @{ dproj = $Overrides['CoverageDproj'] }
                $entry['jobs'] = @([PSCustomObject]$coverageJob)
            }
            elseif ($Overrides.ContainsKey('CoverageExecute') -and
                -not [string]::IsNullOrWhiteSpace($Overrides['CoverageExecute'])) {
                $coverageJob = @{ execute = $Overrides['CoverageExecute'] }
                if ($Overrides.ContainsKey('CoverageMapFile') -and
                    -not [string]::IsNullOrWhiteSpace($Overrides['CoverageMapFile'])) {
                    $coverageJob['mapFile'] = $Overrides['CoverageMapFile']
                }
                $entry['jobs'] = @([PSCustomObject]$coverageJob)
            }
        }

        # If CLI provides call graph path or project file, inject as a single callgraph job
        if ($stepName -eq 'CallGraph') {
            if ($Overrides.ContainsKey('CallGraphProjectFile') -and
                -not [string]::IsNullOrWhiteSpace($Overrides['CallGraphProjectFile'])) {
                $callGraphJob = @{ projectFile = $Overrides['CallGraphProjectFile'] }
                $entry['jobs'] = @([PSCustomObject]$callGraphJob)
            }
            elseif ($Overrides.ContainsKey('CallGraphPath') -and
                $null -ne $Overrides['CallGraphPath']) {
                $callGraphJob = @{ path = @($Overrides['CallGraphPath']) }
                $entry['jobs'] = @([PSCustomObject]$callGraphJob)
            }
        }

        $pipeline.Add([PSCustomObject]$entry)
    }

    return $pipeline.ToArray()
}

function Assert-CleanConfig {
    <#
    .SYNOPSIS
        Validates enum-like fields in a resolved clean configuration.
    #>
    param([hashtable]$Config)

    $validLevels = @('basic', 'standard', 'deep')
    $validOutputLevels = @('detailed', 'summary', 'quiet')

    if ($Config.ContainsKey('level') -and $Config['level'] -notin $validLevels) {
        throw "Invalid clean level '$($Config['level'])'. Valid values: $($validLevels -join ', ')"
    }
    if ($Config.ContainsKey('outputLevel') -and $Config['outputLevel'] -notin $validOutputLevels) {
        throw "Invalid clean output level '$($Config['outputLevel'])'. Valid values: $($validOutputLevels -join ', ')"
    }
}

function Assert-BuildConfig {
    <#
    .SYNOPSIS
        Validates enum-like fields in a resolved build configuration.
    #>
    param([hashtable]$Config)

    $validEngines     = @('MSBuild', 'DCCBuild')
    $validVerbosities = @('quiet', 'minimal', 'normal', 'detailed', 'diagnostic')
    $validTargets     = @('Build', 'Clean', 'Rebuild')

    if ($Config.ContainsKey('engine') -and $Config['engine'] -notin $validEngines) {
        throw "Invalid build engine '$($Config['engine'])'. Valid values: $($validEngines -join ', ')"
    }
    if ($Config.ContainsKey('verbosity') -and $Config['verbosity'] -notin $validVerbosities) {
        throw "Invalid build verbosity '$($Config['verbosity'])'. Valid values: $($validVerbosities -join ', ')"
    }
    if ($Config.ContainsKey('target') -and $Config['target'] -notin $validTargets) {
        throw "Invalid build target '$($Config['target'])'. Valid values: $($validTargets -join ', ')"
    }
}

function Assert-IncverConfig {
    <#
    .SYNOPSIS
        Validates fields in a resolved incver configuration.
    #>
    param([hashtable]$Config)

    $validTargets = @('', 'RC', 'DProj', 'Text')
    $validStyles  = @('', 'WinVer', 'SemVer')
    $validParts   = @('', 'major', 'minor', 'patch', 'build', 'pre-release')

    if ($Config.ContainsKey('target') -and $Config['target'] -notin $validTargets) {
        throw "Invalid incver target '$($Config['target'])'. Valid values: RC, DProj, Text"
    }
    if ($Config.ContainsKey('style') -and $Config['style'] -notin $validStyles) {
        throw "Invalid incver style '$($Config['style'])'. Valid values: WinVer, SemVer"
    }
    if ($Config.ContainsKey('part') -and $Config['part'] -notin $validParts) {
        throw "Invalid incver part '$($Config['part'])'. Valid values: major, minor, patch, build, pre-release"
    }
    # RC target cannot use SemVer style
    $effectiveTarget = if ($Config.ContainsKey('target')) { $Config['target'] } else { '' }
    $effectiveStyle  = if ($Config.ContainsKey('style'))  { $Config['style'] }  else { '' }
    if ($effectiveTarget -in @('RC', 'DProj') -and $effectiveStyle -eq 'SemVer') {
        throw "Invalid incver combination: $effectiveTarget target does not support SemVer style."
    }
    # pre-release part only valid for SemVer
    $effectivePart = if ($Config.ContainsKey('part')) { $Config['part'] } else { '' }
    if ($effectivePart -eq 'pre-release' -and $effectiveStyle -ne '' -and $effectiveStyle -ne 'SemVer') {
        throw "Invalid incver combination: part 'pre-release' is only valid with SemVer style."
    }
}

function Assert-CopyConfig {
    <#
    .SYNOPSIS
        Validates fields in a resolved copy configuration.
    #>
    param([hashtable]$Config)
    # No enum-like fields to validate. Boolean fields are type-coerced
    # during merge. Required fields (source, destination) are validated
    # by the pipeline orchestrator at dispatch time.
}

function Assert-CompressConfig {
    <#
    .SYNOPSIS
        Validates fields in a resolved compress configuration.
    #>
    param([hashtable]$Config)
    # No enum-like fields to validate.
}

function Assert-CoverageConfig {
    <#
    .SYNOPSIS
        Validates enum-like fields in a resolved coverage configuration.
    #>
    param([hashtable]$Config)

    $validEngines = @('DelphiCodeCoverage', 'radCodeCoverage')
    $validFormats = @('html', 'xml', 'emma', 'lcov', 'cobertura', 'md')

    if ($Config.ContainsKey('engine') -and $Config['engine'] -notin $validEngines) {
        throw "Invalid coverage engine '$($Config['engine'])'. Valid values: $($validEngines -join ', ')"
    }
    if ($Config.ContainsKey('formats')) {
        foreach ($fmt in $Config['formats']) {
            if ($fmt.ToLower() -notin $validFormats) {
                throw "Invalid coverage format '$fmt'. Valid values: $($validFormats -join ', ')"
            }
        }
    }
}

function Assert-CallGraphConfig {
    <#
    .SYNOPSIS
        Validates enum-like fields in a resolved call graph configuration.
    #>
    param([hashtable]$Config)

    $validEngines = @('radCallGraph', 'PasDoc', 'DCC')
    $validFormats = @('json', 'dot', 'txt')
    $validGraphKinds = @('', 'call', 'uses', 'classes', 'dependency', 'all')

    if ($Config.ContainsKey('engine') -and $Config['engine'] -notin $validEngines) {
        throw "Invalid callgraph engine '$($Config['engine'])'. Valid values: $($validEngines -join ', ')"
    }
    if ($Config.ContainsKey('formats')) {
        foreach ($fmt in $Config['formats']) {
            if ($fmt.ToLower() -notin $validFormats) {
                throw "Invalid callgraph format '$fmt'. Valid values: $($validFormats -join ', ')"
            }
        }
    }
    if ($Config.ContainsKey('graphKind') -and $Config['graphKind'] -notin $validGraphKinds) {
        throw "Invalid callgraph graphKind '$($Config['graphKind'])'. Valid values: call, uses, classes, dependency, all"
    }
}
