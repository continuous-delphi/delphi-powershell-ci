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
            'clean' { Assert-CleanConfig $actionDefaults }
            'build' { Assert-BuildConfig $actionDefaults }
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

    $pipeline        = [System.Collections.Generic.List[object]]::new()
    $sectionDefaults = @{}

    foreach ($stepName in $steps) {
        $sectionKey = $stepName.ToLower()
        $entry = @{ action = $stepName }
        $sectionDefaults[$sectionKey] = @{}

        if ($Json.PSObject.Properties[$sectionKey]) {
            $section = $Json.$sectionKey
            foreach ($prop in $section.PSObject.Properties) {
                if ($prop.Name -eq 'jobs') {
                    $entry['jobs'] = @($prop.Value)
                } else {
                    $val = $prop.Value
                    if ($null -ne $val -and $val.GetType().Name -eq 'PSCustomObject') {
                        $val = ConvertTo-Hashtable $val
                    }
                    $sectionDefaults[$sectionKey][$prop.Name] = $val
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
