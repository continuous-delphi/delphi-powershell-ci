function Get-DelphiCiConfig {
    [CmdletBinding()]
    param(
        [string]$ConfigFile,
        [string]$Root,
        [string]$ProjectFile,
        [string[]]$Steps,
        [string]$Platform,
        [string]$Configuration,
        [string]$Toolchain,
        [string]$BuildEngine,
        [string[]]$Defines,
        [ValidateSet('basic', 'standard', 'deep')]
        [string]$CleanLevel,
        [string[]]$CleanIncludeFilePattern,
        [string[]]$CleanExcludeDirectoryPattern,
        [string]$CleanConfigFile,
        [string]$TestProjectFile,
        [string]$TestExecutable,
        [string[]]$TestDefines,
        [string[]]$TestArguments,
        [int]$TestTimeoutSeconds,
        [bool]$TestBuild,
        [bool]$TestRun
    )

    $overrides = @{}
    if ($PSBoundParameters.ContainsKey('Root'))                         { $overrides['Root']                         = $Root }
    if ($PSBoundParameters.ContainsKey('ProjectFile'))                  { $overrides['ProjectFile']                  = $ProjectFile }
    if ($PSBoundParameters.ContainsKey('Steps'))                        { $overrides['Steps']                        = $Steps }
    if ($PSBoundParameters.ContainsKey('Platform'))                     { $overrides['Platform']                     = $Platform }
    if ($PSBoundParameters.ContainsKey('Configuration'))                { $overrides['Configuration']                = $Configuration }
    if ($PSBoundParameters.ContainsKey('Toolchain'))                    { $overrides['Toolchain']                    = $Toolchain }
    if ($PSBoundParameters.ContainsKey('BuildEngine'))                  { $overrides['BuildEngine']                  = $BuildEngine }
    if ($PSBoundParameters.ContainsKey('Defines'))                      { $overrides['Defines']                      = $Defines }
    if ($PSBoundParameters.ContainsKey('CleanLevel'))                   { $overrides['CleanLevel']                   = $CleanLevel }
    if ($PSBoundParameters.ContainsKey('CleanIncludeFilePattern'))      { $overrides['CleanIncludeFilePattern']      = $CleanIncludeFilePattern }
    if ($PSBoundParameters.ContainsKey('CleanExcludeDirectoryPattern')) { $overrides['CleanExcludeDirectoryPattern'] = $CleanExcludeDirectoryPattern }
    if ($PSBoundParameters.ContainsKey('CleanConfigFile'))              { $overrides['CleanConfigFile']              = $CleanConfigFile }
    if ($PSBoundParameters.ContainsKey('TestProjectFile'))              { $overrides['TestProjectFile']              = $TestProjectFile }
    if ($PSBoundParameters.ContainsKey('TestExecutable'))               { $overrides['TestExecutable']               = $TestExecutable }
    if ($PSBoundParameters.ContainsKey('TestDefines'))                  { $overrides['TestDefines']                  = $TestDefines }
    if ($PSBoundParameters.ContainsKey('TestArguments'))                { $overrides['TestArguments']                = $TestArguments }
    if ($PSBoundParameters.ContainsKey('TestTimeoutSeconds'))           { $overrides['TestTimeoutSeconds']           = $TestTimeoutSeconds }
    if ($PSBoundParameters.ContainsKey('TestBuild'))                    { $overrides['TestBuild']                    = $TestBuild }
    if ($PSBoundParameters.ContainsKey('TestRun'))                      { $overrides['TestRun']                      = $TestRun }

    Resolve-DelphiCiConfig -ConfigFile $ConfigFile -Overrides $overrides
}
