# PSScriptAnalyzer settings for delphi-powershell-ci.
#
# Used by tests/pwsh/PSScriptAnalyzer.Tests.ps1 (passed explicitly via -Settings) and
# picked up automatically by the VS Code PowerShell extension, so an editor warns about
# the same things CI fails on.
#
# EVERY EXCLUSION BELOW IS A RECORDED DECISION, not a way to reach green (#27). The rule
# the suite previously "passed" was an assertion against a variable nothing assigned, so
# the analyzer had never run at all and 23 real violations in source/ went unreported --
# the point of this file is that the remaining silence is deliberate and auditable.
#
# Counts are from the triage on 2026-11-15 at module v0.4.32.
#
# NOT excluded, and fixed instead: PSAvoidUsingEmptyCatchBlock (6 -- each now logs the
# swallowed error with Write-Verbose, which is strictly better than hiding it and is the
# lesson of #26, where a discarded child-process error cost real debugging time),
# PSUseOutputTypeCorrectly (4 -- declarations corrected) and PSAvoidTrailingWhitespace (1).
#
# Also NOT excluded but suppressed at the four specific sites that need it, each with a
# Justification in the source: PSReviewUnusedParameter on the two deliberately-uniform
# Assert-*Config validators, and PSUseShouldProcessForStateChangingFunctions on the two
# interactive symlink helpers in tools/.
#
# The analyzed file set is built in the test, which also EXCLUDES source/bundled-tools/:
# those nine scripts are vendored verbatim from their own standalone Continuous-Delphi
# repos, where they have their own CI. Linting them here would either cause drift from
# upstream or produce violations nobody in this repo may fix. All 8 of their violations
# are PSAvoidUsingPositionalParameters on one internal helper in delphi-codesign-azure.ps1.

@{
    ExcludeRules = @(

        # 41 sites. CONSOLE OUTPUT IS THE PRODUCT HERE. This is a CI/CLI tool:
        # Write-DelphiCiMessage IS the module's user-facing output channel (its entire
        # body is one Write-Host), tests/run-tests.ps1 prints progress and now names
        # containers that failed discovery, and the tools/ dev scripts are interactive.
        # The rule's rationale -- "might not work in all hosts, cannot be captured" -- is
        # exactly the intent: this text is for a human watching a build, and the
        # structured result objects are the capturable channel. Write-Information would
        # need -InformationAction Continue at every call site to behave the same way.
        'PSAvoidUsingWriteHost'

        # 24 sites, and EVERY ONE is `Join-Path $a $b $c`. Join-Path takes only -Path and
        # -ChildPath by name; a third or later segment can only bind positionally through
        # -AdditionalChildPath, so the rule asks for something that cannot be written for
        # the construct it is flagging. Pure noise in this codebase.
        'PSAvoidUsingPositionalParameters'

        # 3 sites, all PRIVATE helpers that genuinely return collections:
        # Find-DelphiProjects, Invoke-CopyFiles, Invoke-CompressFiles. The singular form
        # would describe them less accurately -- Find-DelphiProject reads as "find one" --
        # and none is exported, so no caller-facing convention is at stake.
        'PSUseSingularNouns'
    )
}
