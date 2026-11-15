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
    # (Hints/Warnings/Errors/ExeOutputDir/Output). The module runs under
    # Set-StrictMode -Version Latest, so a partial object would throw when
    # Invoke-DelphiBuild dereferences the missing properties.
    $newFailure = {
        param([int]$Code)
        [PSCustomObject]@{ ExitCode = $Code; Success = $false; Hints = 0; Warnings = 0; Errors = 0; ExeOutputDir = $null; Output = $null }
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

    # The child's stderr is captured to a file rather than left to flow into this process's
    # error stream, because a build that produced no result file is diagnosed from it below
    # (see the no-result guard) and the text has to be in hand to put in the error message --
    # a parameter-binding failure says which parameter, and discarding that leaves the caller
    # with nothing to act on. It is echoed to the host either way, so nothing the child wrote
    # stops being visible; the one cost is that stderr now lands as a block after the build
    # rather than interleaved with the streamed stdout.
    $stderrFile = [System.IO.Path]::GetTempFileName()

    try {
        & $script:PowerShellExe -NoProfile -NonInteractive -Command $childCommand 2>$stderrFile | Out-Host
        $buildExit = $LASTEXITCODE

        $childStderr = ''
        try {
            $childStderr = (Get-Content -LiteralPath $stderrFile -Raw -ErrorAction Stop)
            if ($null -eq $childStderr) { $childStderr = '' }
        }
        catch { $childStderr = '' }
        if (-not [string]::IsNullOrWhiteSpace($childStderr)) { $childStderr.TrimEnd() | Out-Host }

        $toolResult = $null
        try {
            $raw = Get-Content -LiteralPath $resultFile -Raw -ErrorAction Stop
            $toolResult = $raw | ConvertFrom-Json
        }
        catch { <# result file missing or malformed; handled by the no-result guard below #> }

        # A BUILD TOOL THAT WROTE NO RESULT IS A FAILURE, WHATEVER IT EXITED WITH (#26).
        # -OutputFile is passed on every invocation and both bundled tools write it before
        # returning, so a missing or unparseable result file means the tool did not reach
        # its end -- and the way it most often does not is a parameter the child cannot
        # bind. That failure used to be invisible: the child's binding error went to stderr,
        # the script body never ran, and a PowerShell script that exits without setting a
        # code exits 0, so this function returned Success with $null Output and zero
        # Hints/Warnings/Errors -- indistinguishable from a genuinely clean build, and
        # enough to pass a failOnWarning/failOnHint gate on a project nobody compiled.
        # Issue #26 measured it with -BuildVerbosity minimal under DCCBuild; the mapping in
        # Invoke-DelphiBuild fixes that particular argument, and this guard is what catches
        # the next one. Note this is deliberately NOT a test of whether .output is empty:
        # 'quiet' legitimately produces no build output (Invoke-TestBuild relies on it), so
        # emptiness is normal while a missing result file never is.
        if ($null -eq $toolResult) {
            $detail = if (-not [string]::IsNullOrWhiteSpace($childStderr)) { " Child process stderr: $($childStderr.Trim())" } else { ' The child process wrote nothing to stderr.' }
            Write-Error "$buildToolName produced no result file (exit code $buildExit), so no build can be assumed to have run.$detail"
            return & $newFailure $(if ($buildExit -ne 0) { $buildExit } else { 3 })
        }

        # Read result properties defensively: the two engines emit different
        # result shapes. Both carry warnings/errors, but only delphi-dccbuild
        # carries hints -- delphi-msbuild has no separate hint total to report
        # (see the Hints note below). Under Set-StrictMode a direct
        # $toolResult.hints dereference throws when the property is absent, so
        # probe for each property and fall back to a default when the engine (or
        # a malformed result file) omits it.
        $getProp = {
            param($Obj, [string]$Name, $Default)
            if ($null -ne $Obj -and $null -ne $Obj.PSObject.Properties[$Name]) { $Obj.PSObject.Properties[$Name].Value } else { $Default }
        }

        # HINTS IS 0 UNDER MSBUILD, AND THAT DOES NOT MEAN THERE WERE NONE.
        # delphi-msbuild reads msbuild's "N Warning(s)" summary, and for a Delphi
        # project that figure INCLUDES hints (an unused local reported as
        # "Hint: H2164" is counted there as a warning). So under MSBuild the
        # hints are already inside Warnings and there is no separate tally to
        # marshal; under DCCBuild the two are disjoint and Hints is its own
        # count. A caller gating "zero diagnostics" wants Warnings -eq 0 -and
        # Hints -eq 0, which is correct under both engines.
        return [PSCustomObject]@{
            ExitCode     = $buildExit
            Success      = ($buildExit -eq 0)
            Hints        = [int](& $getProp $toolResult 'hints' 0)
            Warnings     = [int](& $getProp $toolResult 'warnings' 0)
            Errors       = [int](& $getProp $toolResult 'errors' 0)
            ExeOutputDir = & $getProp $toolResult 'exeOutputDir' $null
            Output       = & $getProp $toolResult 'output' $null
        }
    }
    finally {
        Remove-Item -LiteralPath $resultFile -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $paramFile  -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $stderrFile -Force -ErrorAction SilentlyContinue
    }
}
