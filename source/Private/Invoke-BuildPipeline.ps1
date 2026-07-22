function Invoke-BuildPipeline {
    [CmdletBinding()]
    param(
        # Inspect args drive registry-based toolchain detection. Not required
        # when an explicit root is supplied via -ExplicitRootDir.
        [string[]]$InspectArgs = @(),

        [Parameter(Mandatory)]
        [string[]]$BuildArgs,

        [Parameter(Mandatory)]
        [ValidateSet('MSBuild', 'DCCBuild')]
        [string]$Engine,

        # Explicit Delphi installation root. When non-empty, delphi-inspect is
        # not run at all -- registry detection (and its readiness gating) is
        # bypassed and this path is passed straight to the build tool's -RootDir.
        [string]$ExplicitRootDir
    )

    $buildToolName = if ($Engine -eq 'DCCBuild') { 'delphi-dccbuild.ps1' } else { 'delphi-msbuild.ps1' }
    $buildToolPath = Join-Path $script:BundledToolsDir $buildToolName

    # Failure results must carry the full property set the caller reads
    # (Warnings/Errors/ExeOutputDir/Output). The module runs under
    # Set-StrictMode -Version Latest, so a partial object would throw when
    # Invoke-DelphiBuild dereferences the missing properties.
    $newFailure = {
        param([int]$Code)
        [PSCustomObject]@{ ExitCode = $Code; Success = $false; Warnings = 0; Errors = 0; ExeOutputDir = $null; Output = $null }
    }

    if (-not [string]::IsNullOrWhiteSpace($ExplicitRootDir)) {
        # Explicit root: skip the inspect subprocess entirely. Fail fast with a
        # clear error if the caller-supplied path does not exist.
        if (-not (Test-Path -LiteralPath $ExplicitRootDir -PathType Container)) {
            Write-Error "Toolchain rootDir does not exist: $ExplicitRootDir"
            return & $newFailure 3
        }
        $rootDir = $ExplicitRootDir
    }
    else {
        $inspectPath = Join-Path $script:BundledToolsDir 'delphi-inspect.ps1'

        # Run inspect with JSON output so we can extract rootDir from it
        $jsonArgs    = $InspectArgs + @('-Format', 'json')
        $jsonOutput  = & $script:PowerShellExe -NoProfile -NonInteractive -File $inspectPath @jsonArgs 2>&1
        $inspectExit = $LASTEXITCODE

        if ($inspectExit -ne 0) {
            Write-Error "delphi-inspect.ps1 exited with code $inspectExit"
            return & $newFailure $inspectExit
        }

        try {
            $parsed  = ($jsonOutput -join '') | ConvertFrom-Json
            $rootDir = $parsed.result.installation.rootDir
        }
        catch {
            Write-Error "Failed to parse delphi-inspect.ps1 output as JSON: $($_.Exception.Message)"
            return & $newFailure 3
        }

        if ([string]::IsNullOrWhiteSpace($rootDir)) {
            Write-Error 'delphi-inspect.ps1 returned an empty rootDir'
            return & $newFailure 3
        }
    }

    # Run the build tool with | Out-Host so build output streams to the terminal
    # in real time.  A temp file carries the structured JSON result back to the
    # caller without interfering with the streamed output.
    $resultFile   = [System.IO.Path]::GetTempFileName()
    $allBuildArgs = @('-RootDir', $rootDir, '-OutputFile', $resultFile) + $BuildArgs

    # Convert the flat -Name/value token list into a splat hashtable so array
    # parameters survive the child-process boundary. Invoking the tool via
    # `-File @flatArgs` cannot carry a multi-value [string[]] param: a repeated
    # -Namespace fails to bind ("specified more than once") and a single
    # delimited string is not split. We coalesce repeated names into real arrays
    # and splat them in the child, which binds -Namespace / -UnitSearchPath /
    # -IncludePath / -Define as genuine multi-element arrays (see issue #15).
    #
    # In this argument set a value never begins with '-', so a token that starts
    # with '-' and is followed by another '-' token (or the end of the list) is a
    # valueless switch (e.g. -ShowOutput); anything else is a -Name value pair.
    $paramTable = @{}
    for ($i = 0; $i -lt $allBuildArgs.Count; $i++) {
        $token = $allBuildArgs[$i]
        if ($token -notlike '-*') { continue }   # defensive: skip a stray value
        $name     = $token.Substring(1)
        $hasValue = ($i + 1 -lt $allBuildArgs.Count) -and ($allBuildArgs[$i + 1] -notlike '-*')
        if (-not $hasValue) {
            $paramTable[$name] = $true            # switch parameter
            continue
        }
        $value = $allBuildArgs[$i + 1]
        $i++
        if ($paramTable.ContainsKey($name)) {
            $paramTable[$name] = @($paramTable[$name]) + $value   # repeated -> array
        }
        else {
            $paramTable[$name] = $value
        }
    }

    # Serialise the params to a temp file and splat them in the child. Only our
    # own generated paths are embedded in the command string (single-quote
    # escaped); every caller/user value travels as data inside the Clixml file,
    # never as executable code.
    $paramFile = [System.IO.Path]::GetTempFileName()
    $paramTable | Export-Clixml -LiteralPath $paramFile

    $toolPathLiteral  = "'" + ($buildToolPath -replace "'", "''") + "'"
    $paramFileLiteral = "'" + ($paramFile     -replace "'", "''") + "'"
    $childCommand = "`$p = Import-Clixml -LiteralPath $paramFileLiteral; & $toolPathLiteral @p; exit `$LASTEXITCODE"

    try {
        & $script:PowerShellExe -NoProfile -NonInteractive -Command $childCommand | Out-Host
        $buildExit = $LASTEXITCODE

        $toolResult = $null
        try {
            $raw = Get-Content -LiteralPath $resultFile -Raw -ErrorAction Stop
            $toolResult = $raw | ConvertFrom-Json
        }
        catch { <# result file missing or malformed; fall back to exit-code only #> }

        # Read result properties defensively: the two engines emit different
        # result shapes -- delphi-msbuild carries warnings/errors, delphi-dccbuild
        # does not. Under Set-StrictMode a direct $toolResult.warnings dereference
        # throws when the property is absent, so probe for each property and fall
        # back to a default when the engine (or a malformed file) omits it.
        $getProp = {
            param($Obj, [string]$Name, $Default)
            if ($null -ne $Obj -and $null -ne $Obj.PSObject.Properties[$Name]) { $Obj.PSObject.Properties[$Name].Value } else { $Default }
        }

        return [PSCustomObject]@{
            ExitCode     = $buildExit
            Success      = ($buildExit -eq 0)
            Warnings     = [int](& $getProp $toolResult 'warnings' 0)
            Errors       = [int](& $getProp $toolResult 'errors' 0)
            ExeOutputDir = & $getProp $toolResult 'exeOutputDir' $null
            Output       = & $getProp $toolResult 'output' $null
        }
    }
    finally {
        Remove-Item -LiteralPath $resultFile -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $paramFile  -Force -ErrorAction SilentlyContinue
    }
}
