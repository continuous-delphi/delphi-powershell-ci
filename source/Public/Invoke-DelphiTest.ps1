function Invoke-DelphiTest {
    <#
    .SYNOPSIS
        Builds and runs a DUnitX test project as a CI step.

    .DESCRIPTION
        Resolves the test project file, optionally builds it, derives the expected
        test executable path, and optionally runs the executable with a timeout.
        Returns a structured step result.

        This step is self-contained: it does not depend on Invoke-DelphiBuild having
        already run. -Steps Test works standalone.

        The CI define is NOT injected automatically. Pass it via -Defines when using
        a DUnitX project that requires it for headless console execution.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        # Working root used for test project discovery when TestProjectFile is not specified.
        [string]$Root = (Get-Location).Path,

        # Explicit path to the test .dproj or .dpr file.
        # If omitted, discovery searches Root\tests\ then Root for a Tests*.dproj / *Tests.dproj.
        [string]$TestProjectFile = '',

        [string]$Platform = '',

        [string]$Configuration = 'Debug',

        [string]$Toolchain = 'Latest',

        [ValidateSet('MSBuild', 'DCCBuild')]
        [string]$BuildEngine = 'MSBuild',

        # Conditional-compilation defines passed to the test build.
        # DUnitX projects typically require CI to use the console runner instead of
        # the TestInsight IDE runner. Include it here: -Defines CI
        [string[]]$Defines = @(),

        # Extra command-line arguments forwarded to the test executable at runtime.
        [string[]]$Arguments = @(),

        # Maximum seconds the test process is allowed to run before it is killed.
        # Default is 10 seconds -- test suites should be fast.
        [int]$TimeoutSeconds = 10,

        # Set to $false to skip building the test project (run only).
        [bool]$Build = $true,

        # Set to $false to skip running the test executable (build only).
        [bool]$Run = $true,

        # Explicit path to the test executable.  When supplied, skips the
        # Resolve-TestExecutable derivation entirely.  Use this when the project
        # overrides DCC_ExeOutput or places output in a non-default location.
        [string]$TestExecutable = ''
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    # Resolve the test project file via the discovery precedence chain.
    $resolvedTestProject = Resolve-TestProject -Root $Root -TestProjectFile $TestProjectFile
    if ([string]::IsNullOrWhiteSpace($resolvedTestProject)) {
        throw "No test project found under '$Root'. Use -TestProjectFile or ensure a .dproj exists in a tests/ folder."
    }

    # Resolve platform: explicit value wins; otherwise read from the test project (MSBuild)
    # or default to Win32 (DCCBuild, which does not embed platform metadata).
    $resolvedPlatform = if (-not [string]::IsNullOrWhiteSpace($Platform)) {
        $Platform
    } elseif ($BuildEngine -ne 'DCCBuild') {
        Resolve-DefaultPlatform -ProjectFile ([System.IO.Path]::ChangeExtension($resolvedTestProject, '.dproj'))
    } else {
        'Win32'
    }

    Write-DelphiCiMessage -Level 'STEP' -Message "Test ($resolvedPlatform|$Configuration) -- $resolvedTestProject"

    # Phase 1: build the test project.
    $buildResult = [PSCustomObject]@{ ExitCode = 0; Success = $true }
    if ($Build) {
        if ($PSCmdlet.ShouldProcess($resolvedTestProject, "Build test project ($resolvedPlatform|$Configuration)")) {
            $buildResult = Invoke-TestBuild `
                -TestProjectFile $resolvedTestProject `
                -Platform        $resolvedPlatform `
                -Configuration   $Configuration `
                -Toolchain       $Toolchain `
                -BuildEngine     $BuildEngine `
                -Defines         $Defines
        }
    }

    if (-not $buildResult.Success) {
        $stopwatch.Stop()
        Write-DelphiCiMessage -Level 'ERROR' -Message "Test build failed (exit code $($buildResult.ExitCode))"
        return [PSCustomObject]@{
            StepName        = 'Test'
            Success         = $false
            Duration        = $stopwatch.Elapsed
            ExitCode        = $buildResult.ExitCode
            Tool            = 'test runner'
            Message         = "Build failed (exit code $($buildResult.ExitCode))"
            TestProjectFile = $resolvedTestProject
            TestExecutable  = $null
        }
    }

    # Phase 2: derive the expected executable path.
    $resolvedExe = if (-not [string]::IsNullOrWhiteSpace($TestExecutable)) {
        $TestExecutable
    } else {
        Resolve-TestExecutable `
            -TestProjectFile $resolvedTestProject `
            -Platform        $resolvedPlatform `
            -Configuration   $Configuration
    }

    # Phase 3: run the test executable.
    $runResult = [PSCustomObject]@{ ExitCode = 0; Success = $true; Message = 'Tests passed (run skipped)' }
    if ($Run) {
        if ($PSCmdlet.ShouldProcess($resolvedExe, "Run tests")) {
            $runResult = Invoke-TestRunner `
                -TestExecutable $resolvedExe `
                -Arguments      $Arguments `
                -TimeoutSeconds $TimeoutSeconds
        }
    }

    $stopwatch.Stop()

    if ($runResult.Success) {
        Write-DelphiCiMessage -Level 'OK' -Message 'Tests passed'
    }
    else {
        Write-DelphiCiMessage -Level 'ERROR' -Message "Tests failed -- $($runResult.Message)"
    }

    return [PSCustomObject]@{
        StepName        = 'Test'
        Success         = $runResult.Success
        Duration        = $stopwatch.Elapsed
        ExitCode        = $runResult.ExitCode
        Tool            = 'test runner'
        Message         = $runResult.Message
        TestProjectFile = $resolvedTestProject
        TestExecutable  = $resolvedExe
    }
}
