function Resolve-TestExecutable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TestProjectFile,

        [string]$Platform = 'Win32',

        [string]$Configuration = 'Debug'
    )

    $projectDir  = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($TestProjectFile))
    $projectBase = [System.IO.Path]::GetFileNameWithoutExtension($TestProjectFile)

    # Standard Delphi output layout: [ProjectDir]\[Platform]\[Configuration]\[Name].exe
    return [System.IO.Path]::Combine($projectDir, $Platform, $Configuration, "$projectBase.exe")
}
