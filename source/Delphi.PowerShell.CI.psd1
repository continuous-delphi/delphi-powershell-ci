#
# Module manifest for Delphi.PowerShell.CI
#

@{
    # Module identity
    RootModule        = 'Delphi.PowerShell.CI.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = '2cd8a9b8-b45b-44aa-9622-da80a9c1ac52'

    # Authorship
    Author            = 'Continuous Delphi'
    CompanyName       = 'Continuous Delphi'
    Copyright         = '(c) Continuous Delphi. All rights reserved.'

    # Description
    Description       = 'Bundled PowerShell CI orchestration layer for Delphi projects. Packages delphi-clean, delphi-inspect, and delphi-msbuild into a single opinionated command surface for local and CI use.'

    # PowerShell version requirement
    PowerShellVersion = '5.1'

    # Public surface -- only these names are exported
    FunctionsToExport = @(
        'Get-DelphiCiConfig'
        'Invoke-DelphiCi'
        'Invoke-DelphiClean'
        'Invoke-DelphiBuild'
        'Invoke-DelphiTest'
    )

    # Nothing else exported
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    # PowerShell Gallery metadata
    PrivateData = @{
        PSData = @{
            Tags       = @('Delphi', 'CI', 'Build', 'MSBuild', 'Clean', 'Embarcadero', 'DevTools')
            ProjectUri = 'https://github.com/continuous-delphi/delphi-powershell-ci'
            LicenseUri = 'https://github.com/continuous-delphi/delphi-powershell-ci/blob/main/LICENSE'
            # ReleaseNotes: see CHANGELOG.md in the repository root
        }
    }
}
