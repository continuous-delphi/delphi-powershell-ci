# Session Memory

This file preserves durable, cross-session insights about `delphi-powershell-ci`
that would otherwise live only in the per-machine Claude auto-memory folder
(`~/.claude/projects/.../memory/`). Because that folder is outside the repo, its
contents are lost when the development VM is retired or replaced. Anything worth
remembering across sessions belongs here, in the tracked repo, instead.

See the project `CLAUDE.md` for the policy: session memories go in `/docs`.

> These entries are point-in-time observations migrated from the auto-memory
> folder. Verify against current code before relying on any file/parameter
> claim.

---

## Invoke-DelphiClean parameter naming convention

_Type: feedback. Originally recorded ~2026-04 (verified accurate 2026-08-06)._

All parameters on `Invoke-DelphiClean` use the `Clean` prefix to match the
naming convention of the other Clean-related parameters (`CleanLevel`,
`CleanIncludeFilePattern`, `CleanExcludeDirectoryPattern`, `CleanConfigFile`).

**Why:** Consistent prefixing makes parameters unambiguous when splatted or
called from `Invoke-DelphiCi`, which also uses a `Clean` prefix on its own
corresponding parameters.

**How to apply:** The root path parameter is `-CleanRoot`, not `-Root`. When
updating callers or writing new tests, always use `-CleanRoot`. (Confirmed
present in `source/Public/Invoke-DelphiClean.ps1` and documented in
`docs/Invoke-DelphiClean.md` as of 2026-08-06.)

---

## Code coverage tool landscape

_Type: project. Originally recorded ~2026-05._

The user is building a code coverage tool called **radCodeCoverage**, which was
reaching its RC1 phase. It supports DelphiCodeCoverage-compatible command-line
parameters (a decision the user may revisit).

**Why:** DelphiCodeCoverage's CLI usability is poor -- too many odd parameters
and weak documentation. A `delphi-coverage` wrapper would simplify usage.

**How to apply:** When designing `delphi-coverage`, abstract the engine so
multiple tools can be supported (DelphiCodeCoverage first, radCodeCoverage
later, potentially Coverage Validator). Don't hardcode to one engine's CLI --
use an engine property similar to how `delphi-powershell-ci` uses an engine
selector (MSBuild / DCCBuild) for builds.

---

## New markdown/txt/bat docs are gitignored -- keep docs in tracked files

_Type: project. Recorded 2026-09-03 (during #17)._

The repo `.gitignore` ends with catch-all patterns `*.bat`, `*.txt`, `*.md`,
and `/.claude`. Files already tracked (README.md, CHANGELOG.md, CLAUDE.md,
`docs/*.md`, `tools/repo_tickets.txt`) are unaffected because gitignore does
not apply to tracked files -- but any NEW `.md`/`.txt`/`.bat` is invisible to
`git add -A`.

**Why:** The pattern exists to keep session commit bats and scratch
plan/notes out of the repo. The side effect is that a brand-new per-command
doc page (e.g. `docs/Invoke-DelphiFormat.md`) would be silently dropped by the
normal `git add -A` commit-bat flow.

**How to apply:** When adding a new command, document it INLINE in the existing
tracked `README.md` (bundled-tools table, step-command examples, repository
structure, reference table, result-shape note) rather than creating a new
`docs/<Command>.md`. If a dedicated doc page is genuinely wanted, it must be
`git add -f`'d explicitly. `Invoke-DelphiFormat` was documented inline in
README for this reason; no `docs/Invoke-DelphiFormat.md` was created.

---

## Adding a bundled tool: bump the hard-coded count assertion

_Type: project. Recorded 2026-09-03 (during #17)._

`Get-BundledToolInfo` (`source/Private/Get-BundledToolInfo.ps1`) holds the
authoritative `$toolDefs` list of bundled tools. `Invoke-DelphiCi.VersionInfo.Tests.ps1`
asserts the exact count of real tools (`@($info).Count | Should -Be N`) in the
`Get-BundledToolInfo -- unit` Describe.

**Why:** The count is hard-coded, so registering a new tool without updating the
assertion breaks the suite. (The separate `Should -Be 4` in the same file is
against a MOCKED `Get-BundledToolInfo` and is independent of the real count.)

**How to apply:** When adding an entry to `$toolDefs`, bump the real-count
assertion in `Invoke-DelphiCi.VersionInfo.Tests.ps1` to match, and add an
`includes <tool-name>` case. As of #17 the count is 9
(inspect, clean, msbuild, dccbuild, incver, coverage, callgraph,
codesign-azure, format).

## Adding a property to the build result: the mocks are part of the contract

_Type: project. Recorded 2026-11-14 (during #23)._

`Invoke-BuildPipeline` returns the build result and `Invoke-DelphiBuild`
re-publishes it. Under `Set-StrictMode -Version Latest` a property missing from
ANY of the places that construct that object throws where it is dereferenced,
not where it was forgotten -- so adding one (e.g. `Hints` in #23) means editing
four kinds of site, not one:

1. the marshalled return in `Invoke-BuildPipeline` (via the `$getProp` probe, so
   an engine that omits the field still works),
2. its `$newFailure` stand-in for pre-compiler failures,
3. `Invoke-DelphiBuild`'s `$toolResult` literal, used when `ShouldProcess`
   declines (`-WhatIf`) -- easy to miss because no build runs on that path,
4. **every `Mock Invoke-BuildPipeline` in `Invoke-DelphiBuild.Tests.ps1`** (7 of
   them at the time of #23). A mock returning the old shape fails the whole
   Describe, including tests that have nothing to do with the new property.

**Why:** measured by mutation during #23 -- dropping the property from site 2 or
3 reddened tests whose names mention neither the property nor StrictMode (e.g.
"does not invoke the pipeline when -WhatIf is set"), and the integration
Describes that run a real msbuild went red too. The failure is loud but points
at the wrong line, so knowing the four-site list is what makes it quick.

**How to apply:** when a mocked result object exists only to stand in for the
pipeline, give the NEW count a distinct non-zero value in the shared
`BeforeAll` mock. A surfacing test that asserts 0 passes just as well when the
value silently comes from the `-WhatIf` default object instead of the result.

## A Mock's script block cannot see a test helper's parameters

_Type: project. Recorded 2026-11-15 (during #24)._

Pester evaluates a `Mock`'s script block when the mock is INVOKED, not where it
is declared. So a helper function that takes parameters and sets up mocks from
them fails with "The variable '$X' cannot be retrieved because it has not been
set" -- the helper's locals are out of scope by then. This is why every mock in
`Invoke-DelphiCi.Tests.ps1` is either inlined in its `It` or reads a
`script:`-scoped variable.

**Why:** the failure looks like a test-logic bug rather than a scoping one, and
it only appears once a helper is introduced to remove duplication -- which is
exactly when a large test file tempts you into one.

**How to apply:** pass setup values through `$script:`-scoped variables (the
file's script scope is what a mock block can see), and have the mock BUILD its
return value each call rather than closing over one instance. The second half
matters here specifically: `Invoke-DelphiCi`'s diagnostic gate REWRITES
`.Success` and `.Message` on the result object it is handed, so a shared
instance would carry one call's mutation into the next.

## The psd1 version and the CHANGELOG heading are off by one on the remote

_Type: project. Recorded 2026-11-14 (during #23)._

`tools/hooks/pre-commit` runs `Invoke-DelphiIncVer` DURING `git commit` and
re-stages `source/Delphi.PowerShell.CI.psd1`, so the version that ships is the
working-tree value PLUS 1 on the patch. At HEAD (2026-11-14) `ModuleVersion` is
`0.4.28` while the newest CHANGELOG heading is `[0.4.27]` -- i.e. that entry was
authored from the pre-increment value and is one behind the commit that carries
it.

**Why:** it makes the CHANGELOG an unreliable way to infer the current version,
and it is self-perpetuating: reading the previous heading and adding one
reproduces the error.

**How to apply:** read `ModuleVersion` from the psd1 at authoring time and add 1
for the CHANGELOG heading, the commit-message version line, and the commit-bat
name. #23's entry is `[0.4.29]` on that basis (psd1 read `0.4.28`). Note
`delphi-dccbuild` does NOT have this drift -- its `$script:Version` and
CHANGELOG top agreed at `0.4.14`, and `tools/tag-release.ps1` there validates
that they match, which is why the error cannot accumulate in that repo.

## A child .ps1 whose parameters fail to bind exits 0, so the parent sees success

_Type: project. Recorded 2026-11-15 (during #26)._

`Invoke-BuildPipeline` runs the bundled build tools in a child `pwsh`. If an
argument fails the CHILD's parameter binding (a `ValidateSet` it is not in, a
parameter that does not exist), PowerShell writes the binding error to stderr
and never runs the script body -- so `$LASTEXITCODE` is never set and the child
process exits **0**. Measured directly: a fake tool given a `-Verbosity` outside
its set produced `child exit code: 0`, a zero-byte result file, and the binding
error on stderr only.

The parent therefore read exit 0 and reported `Success = $true` with `$null`
`Output` and zero `Hints`/`Warnings`/`Errors` -- byte-identical to a clean
build. That is how `-BuildEngine DCCBuild -BuildVerbosity minimal` passed a
`failOnWarning` gate on a project that was never compiled (#26).

**Why:** exit code is the only signal most of this code trusts across the
process boundary, and in this one case it is actively wrong rather than merely
uninformative. Every `[ValidateSet]` on a public parameter is a potential
instance: `Invoke-DelphiBuild` validates against msbuild's five verbosity levels
while `delphi-dccbuild.ps1` accepts two.

**How to apply:** two rules, both now in the code.
1. A parameter forwarded to a bundled tool must be checked against THAT tool's
   accepted set, not the module's. Map it in `Invoke-DelphiBuild` (as verbosity
   now is: `minimal`->`quiet`, `detailed`/`diagnostic`->`normal` for DCCBuild)
   or reject it the way `IncludePath`/`Namespace`/`NoConfig` are rejected for
   MSBuild. A test can read the tool's real set without hard-coding it:
   `(Get-Command <tool>.ps1).Parameters['X'].Attributes` filtered to
   `[ValidateSetAttribute]` and read via `.ValidValues`.
2. The general guard is RESULT-FILE PRESENCE, not exit code and not output
   emptiness. `-OutputFile` is passed on every invocation and both tools write
   it before returning, so a missing/unparseable result file means the tool
   never reached its end -- `Invoke-BuildPipeline` now fails on that whatever
   the child exited with, and surfaces the captured stderr so the binding error
   is readable. Do NOT gate on empty `.output`: `quiet` legitimately produces
   none and `Invoke-TestBuild` passes `-Verbosity quiet` on every test build.

Also measured, and contrary to its documentation: dcc32 `-Q` did NOT suppress
diagnostics on Delphi 13 (compiler 37.0) -- a project with one `W1036` and two
`H2164`s still reported `Hints=2 Warnings=1` under it. The suppression is
version-dependent, so do not rely on it in either direction; that is why #24's
refusal of a gate combined with `quiet`/`minimal` stays in place.

## A Pester discovery failure produces FailedCount = 0

_Type: project. Recorded 2026-11-15 (during #25). The runner was fixed the same
day in #28; the Pester behaviour below is permanent and still shapes how test
files should be written._

A DISCOVERY failure produces no failed TESTS -- it produces a failed CONTAINER
whose `TotalCount` is 0 -- so any gate written on `$result.FailedCount` stays
false while a whole file contributes nothing. `tests/run-tests.ps1` was gated
that way.

MEASURED, with a trailing comma in `schemas/delphi-ci.schema.json` while
`Schema.Tests.ps1` parsed it at discovery time:

    Invoke-Pester -PassThru  ->  FailedCount = 0, TotalCount = 0, Result = Failed
    tests/run-tests.ps1      ->  prints the discovery error in red, drops all 85
                                 of that file's tests, reports
                                 "Tests Passed: 477, Failed: 0", EXITS 0

The red error text scrolls past in the middle of several hundred lines. In CI
that is a green build. This applies to ANY test file: a syntax error, or
anything that throws while building `-ForEach` data, silently removes the file.

**Why:** it inverts the normal assumption that a visibly broken test run fails.
It also makes "I added a test file and the suite is green" worthless as evidence
the new tests ran at all.

**How to apply:** the runner now also gates on `$result.Result -eq 'Failed'` and
on any container with `TotalCount -eq 0`, naming the file (#28), so the exit code
can be trusted again. Two habits still matter, because they put the diagnosis in
the right place rather than relying on the runner to notice:
1. In a test file, do discovery-time work DEFENSIVELY -- `try`/`catch` the parse
   or file read, stash the error text, and assert on it in a run-time `It`.
   `Schema.Tests.ps1` does this deliberately; that is why its 'parses as JSON'
   test reads a captured string instead of calling `ConvertFrom-Json` in the
   script body.
2. Add an ANTI-VACUITY assertion whenever `-ForEach` data is computed rather
   than literal: assert the generated case count equals what it should be. An
   empty `-ForEach` collection generates zero `It`s and is perfectly "passing",
   so a Describe can contain nothing and never say so.

After adding a test file, confirm the suite's total test count ROSE by the
expected amount. 477 -> 565 for the 88 that #25 added. A green run at the old
count means the new file never executed.

## Verify a new test fails before trusting it -- perturb, do not reason

_Type: feedback. Recorded 2026-11-15 (during #25 and #26)._

Both of these sessions produced a test that passed for the wrong reason until it
was measured. #26's guard tests passed against fakes that happened not to
exercise the path; #25's 'parses as JSON' test reported SUCCESS on a file with a
trailing comma, because the failure arrived as a discovery crash instead of an
assertion (see [[a-pester-discovery-failure-produces-failedcount-0]] above) --
which is also how the runner's own gate (#28) turned out to be wrong.

**Why:** a new assertion's passing state is indistinguishable from a vacuous
one, and the vacuous version is what gets committed, because green looks done.

**How to apply:** for each new assertion, break the thing it guards and confirm
THAT assertion is the one that fails -- not merely that something failed. A
scripted harness is worth writing when there are more than two or three: back up
the file, apply one perturbation, run only the affected test file, assert the
failing test NAME matches the intended one, restore from backup, and `filecmp`
the restore. #25's run covered 13 perturbations that way and caught one
assertion that never fired. Delete the harness afterwards -- it is scaffolding,
not a test.

Prefer perturbing through a PARSER over text matching (load the JSON, mutate the
object, dump it) so a perturbation cannot silently no-op on a layout assumption;
the file is restored from backup afterwards, so reformatting does not matter.
Assert the perturbation actually changed the file.

## A clean lint/scan result and a scan that ran nothing look identical

_Type: feedback. Recorded 2026-11-15 (during #27)._

`PSScriptAnalyzer.Tests.ps1` asserted `$script:violations | Should
-BeNullOrEmpty` against a variable NOTHING in the suite ever assigned. It
evaluated `$null | Should -BeNullOrEmpty`, passed unconditionally in ~15ms, and
`Invoke-ScriptAnalyzer` was never invoked -- hiding 23 real violations in
`source/` for the gate's entire lifetime, while `tests/README.md` and `CLAUDE.md`
both described it as a working gate.

**Why:** this is the general shape behind #25, #27 and #28 in one day. Any check
whose "pass" state is an EMPTY RESULT passes just as convincingly when it
examined nothing -- an unassigned variable, a glob that matched no files, a
settings file that excluded every rule, a path typo, an `-ForEach` collection
that computed to nothing. Green is not evidence the check ran.

**How to apply:** for any gate shaped as "collect findings, assert the
collection is empty", add assertions that the COLLECTION STEP happened, and make
them name things:
1. Compute the subject inside the test. Never read an ambient variable another
   file is supposed to have set -- that is the exact defect here.
2. Assert specific KNOWN inputs were examined (one named file per directory the
   gate covers), not just a count. A path typo then fails by name instead of
   silently shrinking the scope.
3. Assert any deliberate carve-out is still scoped -- e.g. that no
   `bundled-tools` file is in the analysed set -- so an exclusion cannot widen
   unnoticed.
4. Add a PLANTED-DEFECT assertion: run the real tool over a temp file containing
   a known violation and assert it is still reported. That is the one check that
   fails if the tool silently stops working or the config over-excludes.
5. Verify every exclusion is LOAD-BEARING by removing it and confirming the gate
   fires. An exclusion that is no longer needed is indistinguishable from one
   that is, and it hides whatever drifts into its rule later.

Points 2-5 are all in `PSScriptAnalyzer.Tests.ps1` now; the same reasoning
produced the anti-vacuity assertion in `Schema.Tests.ps1`. See
[[verify-a-new-test-fails-before-trusting-it-perturb-do-not-reason]].
