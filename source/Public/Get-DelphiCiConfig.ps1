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
        [int]$RunTimeoutSeconds
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

    Resolve-DelphiCiConfig -ConfigFile $ConfigFile -Overrides $overrides
}
