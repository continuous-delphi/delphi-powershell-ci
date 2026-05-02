@echo off
setlocal
pushd %~dp0

set "_DCI=%~dp0..\..\tools\delphi-ci.ps1"

echo.
echo ============================================================
echo  DELPHI-CI:  Step 1 of 2 -- Clean + Build: ConsoleProject
echo ============================================================
echo.

pwsh -NoProfile -ExecutionPolicy Bypass -File "%_DCI%" ^
     -Steps Clean,Build ^
     -CleanIncludeFilePattern *.res ^
     -ProjectFile Source\ConsoleProject.dpr

set "_EC=%ERRORLEVEL%"
if %_EC% neq 0 (
    echo.
    echo DELPHI-CI:  FAILED: ConsoleProject  ^(exit code %_EC%^) -- see output above.
    popd & endlocal & exit /b %_EC%
)

echo.
echo ============================================================
echo  DELPHI-CI:  Step 2 of 2 -- Build + Run: ConsoleProject.Tests
echo ============================================================
echo.

pwsh -NoProfile -ExecutionPolicy Bypass -File "%_DCI%" ^
     -Steps Build,Run ^
     -CleanIncludeFilePattern *.res ^
     -ProjectFile Tests\ConsoleProject.Tests.dpr ^
     -Defines CI ^
     -Execute Tests\Win32\Debug\ConsoleProject.Tests.exe

set "_EC=%ERRORLEVEL%"
if %_EC% neq 0 (
    echo.
    echo DELPHI-CI:  FAILED: ConsoleProject.Tests  ^(exit code %_EC%^) -- see output above.
    popd & endlocal & exit /b %_EC%
)

echo.
echo ============================================================
echo  DELPHI-CI:  All steps completed successfully.
echo ============================================================
echo.

popd & endlocal & exit /b 0
