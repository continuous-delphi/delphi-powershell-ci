function Resolve-TestProject {
    [CmdletBinding()]
    param(
        [string]$Root,
        [string]$TestProjectFile
    )

    # Returns unique project candidates from a directory.  Searches for both
    # .dproj and .dpr, then groups by BaseName so that a project which has both
    # files is counted once.  When both exist for the same base name, .dproj is
    # preferred (it is the richer MSBuild project file).
    function Get-UniqueProjectFiles {
        param(
            [string]$Directory,
            [scriptblock]$NameFilter
        )

        $all = @(
            Get-ChildItem -LiteralPath $Directory -Filter '*.dproj' -File -ErrorAction SilentlyContinue
            Get-ChildItem -LiteralPath $Directory -Filter '*.dpr'   -File -ErrorAction SilentlyContinue
        )

        if ($null -ne $NameFilter) {
            $all = @($all | Where-Object $NameFilter)
        }

        # Group by BaseName; within each group prefer .dproj over .dpr.
        return @(
            $all | Group-Object -Property BaseName | ForEach-Object {
                $_.Group | Sort-Object -Property Extension -Descending | Select-Object -First 1
            }
        )
    }

    # 1. Explicit path -- validate and return immediately.
    if (-not [string]::IsNullOrWhiteSpace($TestProjectFile)) {
        if (-not (Test-Path -LiteralPath $TestProjectFile)) {
            throw "Test project file not found: $TestProjectFile"
        }
        return [System.IO.Path]::GetFullPath($TestProjectFile)
    }

    # 2. Exactly one project in a tests/ subfolder.
    $testsDir = Join-Path $Root 'tests'
    if (Test-Path -LiteralPath $testsDir) {
        $found = @(Get-UniqueProjectFiles -Directory $testsDir)
        if ($found.Count -eq 1) { return $found[0].FullName }
        if ($found.Count -gt 1) {
            $names = ($found | ForEach-Object { $_.Name }) -join ', '
            throw "Multiple test project files found in '$testsDir'; use -TestProjectFile to select one. Found: $names"
        }
    }

    # 3. Exactly one project in root whose name starts or ends with 'Tests'.
    $testCandidates = @(Get-UniqueProjectFiles -Directory $Root -NameFilter {
        $_.BaseName -match '(?i)^(Tests.*|.*Tests)$'
    })
    if ($testCandidates.Count -eq 1) { return $testCandidates[0].FullName }
    if ($testCandidates.Count -gt 1) {
        $names = ($testCandidates | ForEach-Object { $_.Name }) -join ', '
        throw "Multiple test project files found in '$Root'; use -TestProjectFile to select one. Found: $names"
    }

    # Not found -- caller decides whether to throw.
    return $null
}
