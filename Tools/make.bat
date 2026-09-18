@echo off
setlocal EnableDelayedExpansion
rem ===========================================================================
rem  MilRP build script - compiles MilRP\Classes\*.uc into System\MilRP.u
rem
rem  Usage:
rem    make.bat                 (uses POSTAL2_DIR env var or the default below)
rem    make.bat "D:\Games\Postal 2"
rem
rem  Requirements:
rem    - Postal 2 (Steam build 5025+) with the POSTed SDK installed, so that
rem      <Postal2>\System\ucc.exe exists.
rem    - The base script packages are already compiled (.u files in System).
rem
rem  How it works:
rem    1. Mirrors MilRP\Classes into <Postal2>\MilRP\Classes (ucc only compiles
rem       from the game tree).
rem    2. Generates System\MilRP_Make.ini from the live Postal2.ini so the
rem       EditPackages chain always matches the installed game, then appends
rem       EditPackages=MilRP. The live Postal2.ini is never modified.
rem    3. Runs "ucc make" and installs MilRP.u / MilRP.int / MilRP.ini.
rem ===========================================================================

set "REPO=%~dp0.."
if not "%~1"=="" set "POSTAL2_DIR=%~1"
if "%POSTAL2_DIR%"=="" set "POSTAL2_DIR=C:\Program Files (x86)\Steam\steamapps\common\Postal 2"

set "P2SYS=%POSTAL2_DIR%\System"
set "UCC=%P2SYS%\ucc.exe"
set "PKG=MilRP"
set "MAKEINI=%PKG%_Make.ini"

if not exist "%UCC%" (
    echo [MilRP] ucc.exe not found at "%UCC%".
    echo [MilRP] Set POSTAL2_DIR or pass the Postal 2 install folder as the first argument.
    exit /b 1
)

echo [MilRP] Postal 2 dir : %POSTAL2_DIR%
echo [MilRP] Repo dir     : %REPO%

rem --- 1. Sync sources into the game tree ---
if not exist "%POSTAL2_DIR%\%PKG%\Classes" mkdir "%POSTAL2_DIR%\%PKG%\Classes"
robocopy "%REPO%\%PKG%\Classes" "%POSTAL2_DIR%\%PKG%\Classes" *.uc *.upkg /MIR /NJH /NJS /NDL /NFL >nul
if errorlevel 8 (
    echo [MilRP] robocopy failed while syncing sources.
    exit /b 1
)

rem --- 2. Generate the build ini from the game's own ini ---
set "SRCINI=%P2SYS%\Postal2.ini"
if not exist "%SRCINI%" set "SRCINI=%P2SYS%\Default.ini"
if not exist "%SRCINI%" (
    echo [MilRP] Neither Postal2.ini nor Default.ini found in "%P2SYS%".
    exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%REPO%\Tools\gen-makeini.ps1" -SourceIni "%SRCINI%" -OutIni "%P2SYS%\%MAKEINI%" -Package "%PKG%"
if errorlevel 1 (
    echo [MilRP] Failed to generate %MAKEINI%.
    exit /b 1
)

rem --- 3. Remove stale binary so ucc rebuilds the package ---
if exist "%P2SYS%\%PKG%.u" del /q "%P2SYS%\%PKG%.u"

rem --- 4. Compile ---
pushd "%P2SYS%"
ucc.exe make -ini=%MAKEINI% -nobind
set "RC=%ERRORLEVEL%"
popd

if not "%RC%"=="0" (
    echo [MilRP] BUILD FAILED ^(ucc exit code %RC%^). Check "%P2SYS%\ucc.log".
    exit /b %RC%
)
if not exist "%P2SYS%\%PKG%.u" (
    echo [MilRP] BUILD FAILED: "%P2SYS%\%PKG%.u" was not produced. Check "%P2SYS%\ucc.log".
    exit /b 1
)

rem --- 5. Install runtime config/localization next to the compiled package ---
copy /y "%REPO%\System\%PKG%.int" "%P2SYS%\%PKG%.int" >nul
if not exist "%P2SYS%\%PKG%.ini" copy /y "%REPO%\System\%PKG%.ini" "%P2SYS%\%PKG%.ini" >nul

rem --- 6. Copy the artifact back into the repo for distribution ---
copy /y "%P2SYS%\%PKG%.u" "%REPO%\System\%PKG%.u" >nul

echo [MilRP] BUILD OK -^> "%P2SYS%\%PKG%.u"
exit /b 0
