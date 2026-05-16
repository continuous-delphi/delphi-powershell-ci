function Get-DelphiCiConfig {
    [CmdletBinding()]
    param(
        [string]$ConfigFile,
        [string]$Root,
        [string[]]$Steps,

        # Build defaults
        [string]$ProjectFile,
        [string]$Platform,
        [string]$Configuration,
        [string]$Toolchain,
        [string]$BuildEngine,
        [string[]]$Defines,
        [ValidateSet('quiet', 'minimal', 'normal', 'detailed', 'diagnostic')]
        [string]$BuildVerbosity,
        [ValidateSet('Build', 'Clean', 'Rebuild')]
        [string]$BuildTarget,
        [string]$ExeOutputDir,
        [string]$DcuOutputDir,
        [string[]]$UnitSearchPath,
        [string[]]$IncludePath,
        [string[]]$Namespace,

        # Clean defaults
        [ValidateSet('basic', 'standard', 'deep')]
        [string]$CleanLevel,
        [ValidateSet('detailed', 'summary', 'quiet')]
        [string]$CleanOutputLevel,
        [string[]]$CleanIncludeFilePattern,
        [string[]]$CleanExcludeDirectoryPattern,
        [string]$CleanConfigFile,
        [bool]$CleanRecycleBin,
        [bool]$CleanCheck,

        # Run defaults
        [string]$Execute,
        [string[]]$RunArguments,
        [int]$RunTimeoutSeconds,

        # IncVer defaults
        [string]$IncVerFile,
        [string]$IncVerTarget,
        [string]$IncVerStyle,
        [string]$IncVerPart,
        [string]$IncVerPattern,
        [string]$IncVerDateformat,

        # Copy defaults
        [string]$CopySource,
        [string]$CopyDestination,
        [bool]$CopyFlatten,
        [bool]$CopyOverwrite,
        [bool]$CopyCreateDestination,
        [bool]$CopyChecksum,

        # Compress defaults
        [string]$CompressSource,
        [string]$CompressDestination,
        [bool]$CompressOverwrite,
        [bool]$CompressChecksum,

        # Coverage defaults
        [string]$CoverageExecute,
        [string]$CoverageMapFile,
        [string]$CoverageDproj,
        [string]$CoverageEngine,
        [string]$CoverageEnginePath,
        [string[]]$CoverageSourceDir,
        [string[]]$CoverageUnits,
        [string[]]$CoverageExcludeUnits,
        [string]$CoverageOutputDir,
        [string[]]$CoverageFormats,
        [int]$CoverageThreshold,
        [int]$CoverageTimeoutSeconds,
        [string]$CoverageBadge,

        # CallGraph defaults
        [string[]]$CallGraphPath,
        [string]$CallGraphEngine,
        [string]$CallGraphEnginePath,
        [string]$CallGraphOutputDir,
        [string[]]$CallGraphFormats,
        [string]$CallGraphJsonFile,
        [string]$CallGraphDotFile,
        [string]$CallGraphSummaryFile,
        [string]$CallGraphClass,
        [bool]$CallGraphAnnotations,
        [bool]$CallGraphDeterministic,
        [string]$CallGraphGraphKind,
        [bool]$CallGraphGraphVizUses,
        [bool]$CallGraphGraphVizClasses,
        [string[]]$CallGraphPasDocOptions,
        [string]$CallGraphProjectFile,
        [string[]]$CallGraphGraphVizExclude,
        [string[]]$CallGraphEngineArguments,
        [int]$CallGraphTimeoutSeconds
    )

    $overrides = @{}
    if ($PSBoundParameters.ContainsKey('Root'))                          { $overrides['Root']                         = $Root }
    if ($PSBoundParameters.ContainsKey('Steps'))                         { $overrides['Steps']                        = $Steps }
    if ($PSBoundParameters.ContainsKey('ProjectFile'))                   { $overrides['ProjectFile']                  = $ProjectFile }
    if ($PSBoundParameters.ContainsKey('Platform'))                      { $overrides['Platform']                     = $Platform }
    if ($PSBoundParameters.ContainsKey('Configuration'))                 { $overrides['Configuration']                = $Configuration }
    if ($PSBoundParameters.ContainsKey('Toolchain'))                     { $overrides['Toolchain']                    = $Toolchain }
    if ($PSBoundParameters.ContainsKey('BuildEngine'))                   { $overrides['BuildEngine']                  = $BuildEngine }
    if ($PSBoundParameters.ContainsKey('Defines'))                       { $overrides['Defines']                      = $Defines }
    if ($PSBoundParameters.ContainsKey('BuildVerbosity'))                { $overrides['BuildVerbosity']               = $BuildVerbosity }
    if ($PSBoundParameters.ContainsKey('BuildTarget'))                   { $overrides['BuildTarget']                  = $BuildTarget }
    if ($PSBoundParameters.ContainsKey('ExeOutputDir'))                  { $overrides['ExeOutputDir']                 = $ExeOutputDir }
    if ($PSBoundParameters.ContainsKey('DcuOutputDir'))                  { $overrides['DcuOutputDir']                 = $DcuOutputDir }
    if ($PSBoundParameters.ContainsKey('UnitSearchPath'))                { $overrides['UnitSearchPath']               = $UnitSearchPath }
    if ($PSBoundParameters.ContainsKey('IncludePath'))                   { $overrides['IncludePath']                  = $IncludePath }
    if ($PSBoundParameters.ContainsKey('Namespace'))                     { $overrides['Namespace']                    = $Namespace }
    if ($PSBoundParameters.ContainsKey('CleanLevel'))                    { $overrides['CleanLevel']                   = $CleanLevel }
    if ($PSBoundParameters.ContainsKey('CleanOutputLevel'))              { $overrides['CleanOutputLevel']             = $CleanOutputLevel }
    if ($PSBoundParameters.ContainsKey('CleanIncludeFilePattern'))       { $overrides['CleanIncludeFilePattern']      = $CleanIncludeFilePattern }
    if ($PSBoundParameters.ContainsKey('CleanExcludeDirectoryPattern'))  { $overrides['CleanExcludeDirectoryPattern'] = $CleanExcludeDirectoryPattern }
    if ($PSBoundParameters.ContainsKey('CleanConfigFile'))               { $overrides['CleanConfigFile']              = $CleanConfigFile }
    if ($PSBoundParameters.ContainsKey('CleanRecycleBin'))               { $overrides['CleanRecycleBin']              = $CleanRecycleBin }
    if ($PSBoundParameters.ContainsKey('CleanCheck'))                    { $overrides['CleanCheck']                   = $CleanCheck }
    if ($PSBoundParameters.ContainsKey('Execute'))                        { $overrides['Execute']                      = $Execute }
    if ($PSBoundParameters.ContainsKey('RunArguments'))                  { $overrides['RunArguments']                 = $RunArguments }
    if ($PSBoundParameters.ContainsKey('RunTimeoutSeconds'))             { $overrides['RunTimeoutSeconds']            = $RunTimeoutSeconds }
    if ($PSBoundParameters.ContainsKey('IncVerFile'))                    { $overrides['IncVerFile']                   = $IncVerFile }
    if ($PSBoundParameters.ContainsKey('IncVerTarget'))                  { $overrides['IncVerTarget']                 = $IncVerTarget }
    if ($PSBoundParameters.ContainsKey('IncVerStyle'))                   { $overrides['IncVerStyle']                  = $IncVerStyle }
    if ($PSBoundParameters.ContainsKey('IncVerPart'))                    { $overrides['IncVerPart']                   = $IncVerPart }
    if ($PSBoundParameters.ContainsKey('IncVerPattern'))                 { $overrides['IncVerPattern']                = $IncVerPattern }
    if ($PSBoundParameters.ContainsKey('IncVerDateformat'))              { $overrides['IncVerDateformat']             = $IncVerDateformat }
    if ($PSBoundParameters.ContainsKey('CopySource'))                    { $overrides['CopySource']                   = $CopySource }
    if ($PSBoundParameters.ContainsKey('CopyDestination'))               { $overrides['CopyDestination']              = $CopyDestination }
    if ($PSBoundParameters.ContainsKey('CopyFlatten'))                   { $overrides['CopyFlatten']                  = $CopyFlatten }
    if ($PSBoundParameters.ContainsKey('CopyOverwrite'))                 { $overrides['CopyOverwrite']                = $CopyOverwrite }
    if ($PSBoundParameters.ContainsKey('CopyCreateDestination'))         { $overrides['CopyCreateDestination']        = $CopyCreateDestination }
    if ($PSBoundParameters.ContainsKey('CopyChecksum'))                  { $overrides['CopyChecksum']                 = $CopyChecksum }
    if ($PSBoundParameters.ContainsKey('CompressSource'))                { $overrides['CompressSource']               = $CompressSource }
    if ($PSBoundParameters.ContainsKey('CompressDestination'))           { $overrides['CompressDestination']          = $CompressDestination }
    if ($PSBoundParameters.ContainsKey('CompressOverwrite'))             { $overrides['CompressOverwrite']            = $CompressOverwrite }
    if ($PSBoundParameters.ContainsKey('CompressChecksum'))              { $overrides['CompressChecksum']             = $CompressChecksum }
    if ($PSBoundParameters.ContainsKey('CoverageExecute'))               { $overrides['CoverageExecute']              = $CoverageExecute }
    if ($PSBoundParameters.ContainsKey('CoverageMapFile'))               { $overrides['CoverageMapFile']              = $CoverageMapFile }
    if ($PSBoundParameters.ContainsKey('CoverageDproj'))                 { $overrides['CoverageDproj']                = $CoverageDproj }
    if ($PSBoundParameters.ContainsKey('CoverageEngine'))                { $overrides['CoverageEngine']               = $CoverageEngine }
    if ($PSBoundParameters.ContainsKey('CoverageEnginePath'))            { $overrides['CoverageEnginePath']           = $CoverageEnginePath }
    if ($PSBoundParameters.ContainsKey('CoverageSourceDir'))             { $overrides['CoverageSourceDir']            = $CoverageSourceDir }
    if ($PSBoundParameters.ContainsKey('CoverageUnits'))                 { $overrides['CoverageUnits']                = $CoverageUnits }
    if ($PSBoundParameters.ContainsKey('CoverageExcludeUnits'))          { $overrides['CoverageExcludeUnits']         = $CoverageExcludeUnits }
    if ($PSBoundParameters.ContainsKey('CoverageOutputDir'))             { $overrides['CoverageOutputDir']            = $CoverageOutputDir }
    if ($PSBoundParameters.ContainsKey('CoverageFormats'))               { $overrides['CoverageFormats']              = $CoverageFormats }
    if ($PSBoundParameters.ContainsKey('CoverageThreshold'))             { $overrides['CoverageThreshold']            = $CoverageThreshold }
    if ($PSBoundParameters.ContainsKey('CoverageTimeoutSeconds'))        { $overrides['CoverageTimeoutSeconds']       = $CoverageTimeoutSeconds }
    if ($PSBoundParameters.ContainsKey('CoverageBadge'))                 { $overrides['CoverageBadge']                = $CoverageBadge }
    if ($PSBoundParameters.ContainsKey('CallGraphPath'))                 { $overrides['CallGraphPath']                = $CallGraphPath }
    if ($PSBoundParameters.ContainsKey('CallGraphEngine'))               { $overrides['CallGraphEngine']              = $CallGraphEngine }
    if ($PSBoundParameters.ContainsKey('CallGraphEnginePath'))           { $overrides['CallGraphEnginePath']          = $CallGraphEnginePath }
    if ($PSBoundParameters.ContainsKey('CallGraphOutputDir'))            { $overrides['CallGraphOutputDir']           = $CallGraphOutputDir }
    if ($PSBoundParameters.ContainsKey('CallGraphFormats'))              { $overrides['CallGraphFormats']             = $CallGraphFormats }
    if ($PSBoundParameters.ContainsKey('CallGraphJsonFile'))             { $overrides['CallGraphJsonFile']            = $CallGraphJsonFile }
    if ($PSBoundParameters.ContainsKey('CallGraphDotFile'))              { $overrides['CallGraphDotFile']             = $CallGraphDotFile }
    if ($PSBoundParameters.ContainsKey('CallGraphSummaryFile'))          { $overrides['CallGraphSummaryFile']         = $CallGraphSummaryFile }
    if ($PSBoundParameters.ContainsKey('CallGraphClass'))                { $overrides['CallGraphClass']               = $CallGraphClass }
    if ($PSBoundParameters.ContainsKey('CallGraphAnnotations'))          { $overrides['CallGraphAnnotations']         = $CallGraphAnnotations }
    if ($PSBoundParameters.ContainsKey('CallGraphDeterministic'))        { $overrides['CallGraphDeterministic']       = $CallGraphDeterministic }
    if ($PSBoundParameters.ContainsKey('CallGraphGraphKind'))            { $overrides['CallGraphGraphKind']           = $CallGraphGraphKind }
    if ($PSBoundParameters.ContainsKey('CallGraphGraphVizUses'))         { $overrides['CallGraphGraphVizUses']        = $CallGraphGraphVizUses }
    if ($PSBoundParameters.ContainsKey('CallGraphGraphVizClasses'))      { $overrides['CallGraphGraphVizClasses']     = $CallGraphGraphVizClasses }
    if ($PSBoundParameters.ContainsKey('CallGraphPasDocOptions'))        { $overrides['CallGraphPasDocOptions']       = $CallGraphPasDocOptions }
    if ($PSBoundParameters.ContainsKey('CallGraphProjectFile'))          { $overrides['CallGraphProjectFile']         = $CallGraphProjectFile }
    if ($PSBoundParameters.ContainsKey('CallGraphGraphVizExclude'))      { $overrides['CallGraphGraphVizExclude']     = $CallGraphGraphVizExclude }
    if ($PSBoundParameters.ContainsKey('CallGraphEngineArguments'))      { $overrides['CallGraphEngineArguments']     = $CallGraphEngineArguments }
    if ($PSBoundParameters.ContainsKey('CallGraphTimeoutSeconds'))       { $overrides['CallGraphTimeoutSeconds']      = $CallGraphTimeoutSeconds }

    Resolve-DelphiCiConfig -ConfigFile $ConfigFile -Overrides $overrides
}
