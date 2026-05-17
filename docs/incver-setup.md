# Automated Version Numbering with IncVer

This document describes how delphi-parser uses `Invoke-DelphiIncVer` from
delphi-powershell-ci to maintain an automatically incrementing version number
that stays synchronized with the git commit count.

## Version Scheme

```
Major.Minor.Sequence.Build
  0  .  8  .  444   .  3
```

| Part | Meaning | When it changes |
|------|---------|-----------------|
| Major | Breaking API change | Manual bump |
| Minor | Feature milestone | Manual bump |
| Sequence | Commit count (monotonic, never resets) | Pre-commit hook |
| Build | Local CI build counter | `Invoke-DelphiCi` pipeline |

The sequence number matches the total commit count on main. This means
`git log --oneline | wc -l` always equals the 3rd version part. Baselines
and conversation can reference just "444" as a unique identifier for a
specific committed state.

## File Layout

```
source/Delphi.Parser.Info.pas    -- contains the version constant
tools/hooks/pre-commit           -- git hook that bumps sequence on commit
tools/configure-hooks.bat        -- one-time setup for new clones
delphici-tests.json              -- CI pipeline (bumps build number)
```

### Version File

```pascal
unit Delphi.Parser.Info;

interface

const
  Version = '0.8.444.0';

implementation

end.
```

A standalone unit with a single constant. Referenced as
`Delphi.Parser.Info.Version` in code.

## How It Works

### Local builds (4th number)

The `delphici-tests.json` pipeline includes an IncVer step that bumps the
4th part (build) on every `Invoke-DelphiCi` run:

```json
{
  "action": "IncVer",
  "jobs": [{
    "name": "Build version",
    "file": "source/Delphi.Parser.Info.pas",
    "target": "Text",
    "style": "WinVer",
    "part": "build",
    "pattern": "(\\d+\\.\\d+\\.\\d+\\.\\d+)"
  }]
}
```

This tracks iterations during development. If a bug appears between
builds, "444.2 works but 444.3 doesn't" pinpoints it to one edit.

### Commits (3rd number)

A pre-commit hook bumps the 3rd part (sequence) and zeros the 4th:

```bash
#!/bin/sh
pwsh -NoProfile -Command '
  $result = Invoke-DelphiIncVer \
    -File "source/Delphi.Parser.Info.pas" \
    -IncverTarget "Text" \
    -IncverStyle "WinVer" \
    -IncverPart "patch" \
    -IncverPattern "(\d+\.\d+\.\d+\.\d+)"
  if (-not $result.Success) { exit 1 }
'
git add source/Delphi.Parser.Info.pas
```

The hook stages the updated file so it's part of the commit. No separate
version-bump commit is needed.

### Setup for new clones

After cloning the repo, run:

```
tools\configure-hooks.bat
```

This executes `git config core.hooksPath tools/hooks` to point git at the
committed hooks directory. Without this, the pre-commit hook won't fire
and the sequence number won't auto-increment.

## Design Decisions

**Why not a post-commit hook?**
A post-commit hook would require either amending the commit (causing
recursion) or creating a separate version-bump commit (cluttering history
and requiring pulls after pushing).

**Why not a GitHub Action?**
A server-side bump would push a commit back to main, forcing the developer
to pull before continuing. The pre-commit hook keeps everything local and
self-contained.

**Why does the sequence number never reset?**
If it reset on minor version bumps, "444" would be ambiguous -- was it in
the 0.8 series or 0.9? A monotonic sequence means every number is globally
unique and always sortable.

**Linear development required**
This scheme only works cleanly for trunk-based linear development. 
The moment you branch, the 3rd number becomes branch-local and loses its "globally unique" property.

If you start branching regularly, one fix is: only count commits on main for the sequence number.
The hook would need to check `git rev-list --count main` instead of total commits.
Feature branches don't bump the sequence -- they use only the 4th number for tracking.
When merged to main, the hook on main bumps the sequence once.

## Applying This Pattern to Other Repos

To replicate this setup in another Delphi project:

1. Create a version unit (e.g. `MyProject.Info.pas`) with a `Version` constant.

2. Add an IncVer step to your `delphici-*.json` pipeline for local builds:
   ```json
   {
     "action": "IncVer",
     "jobs": [{
       "name": "Build version",
       "file": "source/MyProject.Info.pas",
       "target": "Text",
       "style": "WinVer",
       "part": "build",
       "pattern": "(\\d+\\.\\d+\\.\\d+\\.\\d+)"
     }]
   }
   ```

3. Create `tools/hooks/pre-commit` that bumps "patch" (3rd part) and
   stages the version file.

4. Create `tools/configure-hooks.bat` with:
   ```bat
   git config core.hooksPath tools/hooks
   ```

5. Document that new clones must run `tools\configure-hooks.bat` once.

The pattern works for any project where you want commit-synchronized
versioning without manual intervention or remote-side automation.
